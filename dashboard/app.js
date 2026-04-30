// Commune Solutions — dashboard admin (Phase 10).
// Pure ES modules + Firebase Web SDK from CDN, no build step.
// Reads tenant Firestore (read-only) after auth, mirrors the mobile shell's
// per-tenant model (one Firebase project per commune).

import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.0/firebase-app.js";
import {
    getAuth,
    signInWithEmailAndPassword,
    signOut,
    onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/11.0.0/firebase-auth.js";
import {
    getFirestore,
    collection,
    getDocs,
    doc,
    getDoc,
    setDoc,
    serverTimestamp,
} from "https://www.gstatic.com/firebasejs/11.0.0/firebase-firestore.js";

const MARKETPLACE_CATALOG_URL = "https://communesolutions.be/marketplace/data/manifests.json";

const TENANT_LABELS = {
    "spike-1": "Démo A",
    "spike-2": "Démo B",
};

const root = document.getElementById("root");
let app = null;
let auth = null;
let db = null;
let currentTenant = null;

// Pre-bound for back-button
const renderPicker = () => {
    if (auth) {
        signOut(auth).catch(() => {});
        auth = null;
        db = null;
        app = null;
    }
    currentTenant = null;
    root.innerHTML = "";
    root.appendChild(document.getElementById("picker-template").content.cloneNode(true));
    root.querySelectorAll("button[data-tenant]").forEach((b) => {
        b.addEventListener("click", () => onPickTenant(b.dataset.tenant));
    });
};

async function onPickTenant(tenantId) {
    currentTenant = tenantId;
    let config;
    try {
        const resp = await fetch(`firebase-config-${tenantId}.json`);
        if (!resp.ok) throw new Error(`config introuvable (${resp.status})`);
        config = await resp.json();
    } catch (e) {
        alert(`Impossible de charger la config Firebase : ${e.message}\n\nPlace les fichiers firebase-config-spike-1.json et firebase-config-spike-2.json dans dashboard/.`);
        return;
    }
    app = initializeApp(config, tenantId);
    auth = getAuth(app);
    db = getFirestore(app);

    // If a session is already cached for this Firebase app, jump straight to the dashboard.
    onAuthStateChanged(auth, (user) => {
        if (user) renderDashboard(user);
        else renderLogin();
    });
}

function renderLogin() {
    root.innerHTML = "";
    const node = document.getElementById("login-template").content.cloneNode(true);
    node.querySelector("[data-slot='tenant-label']").textContent = TENANT_LABELS[currentTenant];
    const form = node.querySelector("#login-form");
    const errorEl = node.querySelector("[data-slot='error']");
    form.addEventListener("submit", async (e) => {
        e.preventDefault();
        errorEl.textContent = "";
        const submitBtn = form.querySelector("button[type='submit']");
        submitBtn.disabled = true;
        submitBtn.textContent = "Connexion…";
        try {
            const data = new FormData(form);
            await signInWithEmailAndPassword(auth, data.get("email"), data.get("password"));
            // onAuthStateChanged → renderDashboard
        } catch (err) {
            errorEl.textContent = err?.message ?? "Erreur de connexion";
            submitBtn.disabled = false;
            submitBtn.textContent = "Se connecter";
        }
    });
    node.querySelector("#back-to-picker").addEventListener("click", renderPicker);
    root.appendChild(node);
}

async function renderDashboard(user) {
    root.innerHTML = "";
    const node = document.getElementById("dashboard-template").content.cloneNode(true);
    node.querySelector("[data-slot='tenant-label']").textContent = TENANT_LABELS[currentTenant];
    node.querySelector("[data-slot='user-email']").textContent = user.email ?? user.uid;
    const tabs = node.querySelectorAll(".tabs button");
    const content = node.querySelector("#content");
    node.querySelector("#logout-btn").addEventListener("click", () => signOut(auth).then(renderPicker));
    root.appendChild(node);

    let activeTab = "modules";
    const showTab = async (name) => {
        activeTab = name;
        tabs.forEach((b) => b.classList.toggle("active", b.dataset.tab === name));
        content.innerHTML = `<p class="empty">Chargement…</p>`;
        if (name === "modules") {
            await renderModules(content, user);
        } else {
            content.innerHTML = await renderSection(name);
        }
    };
    tabs.forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));
    showTab(activeTab);
}

async function renderModules(container, user) {
    let catalog = [];
    let runtime = { modules: [], view: { type: "tabbar", tabs: [] } };
    try {
        const [catalogRes, runtimeSnap] = await Promise.all([
            fetch(MARKETPLACE_CATALOG_URL, { cache: "no-cache" }),
            getDoc(doc(db, "_config", "modules")),
        ]);
        if (catalogRes.ok) catalog = (await catalogRes.json()).modules || [];
        if (runtimeSnap.exists()) runtime = { ...runtime, ...runtimeSnap.data() };
    } catch (e) {
        container.innerHTML = `<p class="empty">Erreur chargement modules : ${esc(e.message)}</p>`;
        return;
    }

    const officials = catalog.filter((m) => m.official === true);
    if (officials.length === 0) {
        container.innerHTML = `<p class="empty">Aucun module officiel disponible.</p>`;
        return;
    }

    const activeIds = new Set((runtime.modules ?? []).map((m) => m.id));

    container.innerHTML = `
        <div class="modules-pane">
            <p class="modules-intro">Activez/désactivez les modules officiels pour cette commune. Les changements prennent effet au prochain démarrage de l'app citoyenne.</p>
            <div class="modules-list">
                ${officials.map((m) => `
                    <label class="module-row">
                        <input type="checkbox" data-module-id="${esc(m.id)}" ${activeIds.has(m.id) ? "checked" : ""}>
                        <div class="module-row-text">
                            <strong>${esc(m.displayName)}</strong>
                            <span>${esc(m.description ?? "")}</span>
                            <span class="module-row-meta">v${esc(m.version)} · ${esc((m.capabilities ?? []).length)} capability(ies)</span>
                        </div>
                    </label>
                `).join("")}
            </div>
            <div class="modules-actions">
                <button id="modules-save" class="primary">Enregistrer</button>
                <p class="modules-status" data-slot="status"></p>
            </div>
        </div>
    `;

    const status = container.querySelector("[data-slot='status']");
    container.querySelector("#modules-save").addEventListener("click", async () => {
        const checked = Array.from(container.querySelectorAll("input[data-module-id]:checked")).map(
            (i) => i.dataset.moduleId
        );
        const newModules = checked.map((id) => ({
            id,
            version: officials.find((m) => m.id === id)?.version ?? "0.1.0",
        }));
        const newTabs = (runtime.view?.tabs ?? []).filter((t) => {
            const mod = String(t.screen ?? "").split(":")[0];
            return checked.includes(mod);
        });
        // Ajoute un onglet par défaut pour les modules nouvellement activés.
        const tabModuleIds = new Set(newTabs.map((t) => String(t.screen ?? "").split(":")[0]));
        for (const id of checked) {
            if (!tabModuleIds.has(id)) {
                const m = officials.find((x) => x.id === id);
                if (!m) continue;
                const firstScreen = Object.keys(m.screens ?? {})[0] ?? "main";
                newTabs.push({
                    title: m.displayName,
                    icon: m.icon ?? "info.circle",
                    screen: `${id}:${firstScreen}`,
                });
            }
        }

        status.textContent = "Enregistrement…";
        status.classList.remove("error", "success");
        try {
            await setDoc(doc(db, "_config", "modules"), {
                modules: newModules,
                view: { type: "tabbar", tabs: newTabs },
                updatedAt: serverTimestamp(),
                updatedBy: user.uid,
            });
            status.textContent = "✓ Enregistré. L'app citoyenne reflètera la nouvelle config au prochain démarrage.";
            status.classList.add("success");
        } catch (e) {
            const msg = e?.code === "permission-denied"
                ? "Permission refusée — votre compte n'a pas le claim `admin`. Contactez un mainteneur."
                : `Erreur : ${e.message}`;
            status.textContent = msg;
            status.classList.add("error");
        }
    });
}

async function renderSection(name) {
    try {
        switch (name) {
            case "polls": return await listCollection("polls", (p) => `
                <h3>${esc(p.title)}</h3>
                <p class="meta">${esc(p.description ?? "")}</p>
                <p class="body"><strong>Question :</strong> ${esc(p.question ?? "")}</p>
                ${(p.options ?? []).length ? `<ul>${p.options.map((o) => `<li>${esc(o.label)} <small>(${esc(o.id)})</small></li>`).join("")}</ul>` : ""}
            `);
            case "events": return await listCollection("events", (e) => `
                <h3>${esc(e.title)}</h3>
                <p class="meta">${esc(e.date ?? "")} — ${esc(e.location ?? "")}</p>
                <p class="body">${esc(e.description ?? "")}</p>
            `);
            case "articles": return await listCollection("articles", (a) => `
                <h3>${esc(a.title)}</h3>
                <p class="meta">${esc(a.date ?? "")}${a.isNew ? " · NOUVEAU" : ""}</p>
                <p class="body">${esc(a.excerpt ?? "")}</p>
            `);
            case "info": {
                const snap = await getDoc(doc(db, "info", "main"));
                if (!snap.exists()) return `<p class="empty">Aucun document <code>info/main</code>.</p>`;
                const d = snap.data();
                return `<div class="item">
                    <h3>${esc(d.communeName ?? "")}</h3>
                    <p class="meta">${esc(d.address ?? "").replace(/\n/g, "<br>")}</p>
                    <p class="body">${esc(d.contactMd ?? "")}</p>
                </div>`;
            }
        }
    } catch (e) {
        return `<p class="empty">Erreur : ${esc(e.message)}</p>`;
    }
    return "";
}

async function listCollection(name, render) {
    const snap = await getDocs(collection(db, name));
    if (snap.empty) return `<p class="empty">Aucun document.</p>`;
    return snap.docs.map((d) => `<div class="item">${render(d.data())}</div>`).join("");
}

function esc(s) {
    return String(s ?? "").replace(/[&<>"']/g, (c) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[c]));
}

// Boot
renderPicker();
