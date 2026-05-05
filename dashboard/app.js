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
    addDoc,
    deleteDoc,
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
            await renderSection(name, content);
        }
    };
    tabs.forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));
    showTab(activeTab);

    // Expose pour que les handlers d'éditeur puissent re-rendre après save/delete
    window.__refreshActiveTab = () => showTab(activeTab);
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
            // Préserve les autres champs du view (e.g. brand) qui ne sont pas
            // édités depuis cet écran — ne pas écraser tout le doc.
            const preservedView = { ...(runtime.view ?? {}) };
            preservedView.type = "tabbar";
            preservedView.tabs = newTabs;
            await setDoc(doc(db, "_config", "modules"), {
                modules: newModules,
                view: preservedView,
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

// Schémas par collection — pilotent la génération du formulaire d'édition
// et le rendu de la liste. Articles + events ont CRUD ; polls + info gardent
// le rendu read-only en attendant les phases 14.4 / 14.6.
const SCHEMAS = {
    articles: {
        label: "Article",
        labelPlural: "Actualités",
        renderItem: (a) => `
            <h3>${esc(a.title)}</h3>
            <p class="meta">${esc(a.dateEyebrow ?? a.date ?? "")}${a.isNew ? " · NOUVEAU" : ""}</p>
            <p class="body">${esc(a.excerpt ?? "")}</p>
        `,
        fields: [
            { key: "title", label: "Titre", type: "text", required: true },
            { key: "excerpt", label: "Extrait (max 200 chars, affiché dans le feed)", type: "textarea", maxLength: 200 },
            { key: "imageUrl", label: "URL image (1.6:1 conseillé)", type: "url" },
            { key: "date", label: "Date affichée (long)", type: "text", placeholder: "30 avril 2026" },
            { key: "dateEyebrow", label: "Eyebrow (compact)", type: "text", placeholder: "30 avril · Travaux" },
            { key: "category", label: "Catégorie", type: "select", options: ["Travaux", "Loisirs", "Environnement", "Vie communale", "Culture", "Mobilité"] },
            { key: "isNew", label: "Marquer comme nouveau", type: "checkbox" },
            { key: "body", label: "Corps (Markdown)", type: "markdown" },
        ],
    },
    events: {
        label: "Événement",
        labelPlural: "Événements",
        renderItem: (e) => `
            <h3>${esc(e.title)}</h3>
            <p class="meta">${esc(e.date ?? "")} — ${esc(e.location ?? "")}</p>
            <p class="body">${esc(e.description ?? "")}</p>
        `,
        fields: [
            { key: "title", label: "Titre", type: "text", required: true },
            { key: "date", label: "Date affichée", type: "text", placeholder: "samedi 3 mai · 9h–17h" },
            { key: "dateStart", label: "Date ISO (utilisée par le calendrier)", type: "date", placeholder: "2026-05-03" },
            { key: "location", label: "Lieu", type: "text" },
            { key: "imageUrl", label: "URL image (1.78:1 conseillé)", type: "url" },
            { key: "description", label: "Description (Markdown)", type: "markdown" },
        ],
    },
};

async function renderSection(name, container) {
    try {
        if (SCHEMAS[name]) {
            await renderEditableList(name, container);
            return;
        }
        // Read-only fallbacks (CRUD à venir en 14.4 / 14.6)
        if (name === "polls") {
            const html = await listCollectionHTML("polls", (p) => `
                <h3>${esc(p.title)}</h3>
                <p class="meta">${esc(p.description ?? "")}</p>
                <p class="body"><strong>Question :</strong> ${esc(p.question ?? "")}</p>
                ${(p.options ?? []).length ? `<ul>${p.options.map((o) => `<li>${esc(o.label)} <small>(${esc(o.id)})</small></li>`).join("")}</ul>` : ""}
            `);
            container.innerHTML = html;
            return;
        }
        if (name === "info") {
            const snap = await getDoc(doc(db, "info", "main"));
            if (!snap.exists()) {
                container.innerHTML = `<p class="empty">Aucun document <code>info/main</code>.</p>`;
                return;
            }
            const d = snap.data();
            container.innerHTML = `<div class="item">
                <h3>${esc(d.communeName ?? "")}</h3>
                <p class="meta">${esc(d.address ?? "").replace(/\n/g, "<br>")}</p>
                <p class="body">${esc(d.contactMd ?? "")}</p>
            </div>`;
            return;
        }
    } catch (e) {
        container.innerHTML = `<p class="empty">Erreur : ${esc(e.message)}</p>`;
    }
}

async function renderEditableList(collectionName, container) {
    const schema = SCHEMAS[collectionName];
    const snap = await getDocs(collection(db, collectionName));
    const items = snap.docs.map((d) => ({ _docId: d.id, ...d.data() }));

    const itemsHTML = items.length
        ? items.map((it) => `
            <div class="item" data-doc-id="${esc(it._docId)}">
                ${schema.renderItem(it)}
                <button type="button" class="edit" data-doc-id="${esc(it._docId)}">Éditer</button>
            </div>
        `).join("")
        : `<p class="empty">Aucun ${schema.label.toLowerCase()} pour l'instant. Cliquez sur « + Nouveau » pour en créer un.</p>`;

    container.innerHTML = `
        <div class="section-toolbar">
            <h2>${esc(items.length)} ${esc(items.length > 1 ? schema.labelPlural.toLowerCase() : schema.label.toLowerCase())}</h2>
            <button type="button" class="new" data-collection="${esc(collectionName)}">+ Nouveau</button>
        </div>
        ${itemsHTML}
    `;

    container.querySelector(".new").addEventListener("click", () => openEditor(collectionName, null));
    container.querySelectorAll(".item .edit").forEach((btn) => {
        btn.addEventListener("click", () => {
            const docId = btn.dataset.docId;
            const item = items.find((i) => i._docId === docId);
            if (item) openEditor(collectionName, { _docId: docId, ...item });
        });
    });
}

async function listCollectionHTML(name, render) {
    const snap = await getDocs(collection(db, name));
    if (snap.empty) return `<p class="empty">Aucun document.</p>`;
    return snap.docs.map((d) => `<div class="item">${render(d.data())}</div>`).join("");
}

// MARK: - Editor modal

function openEditor(collectionName, existingDoc) {
    const schema = SCHEMAS[collectionName];
    const dialog = document.getElementById("editor-dialog");
    const form = dialog.querySelector("#editor-form");
    const titleEl = dialog.querySelector("[data-slot='title']");
    const fieldsEl = dialog.querySelector("[data-slot='fields']");
    const statusEl = dialog.querySelector("[data-slot='status']");
    const closeBtn = dialog.querySelector("[data-slot='close']");
    const deleteBtn = dialog.querySelector("[data-slot='delete']");

    const isNew = !existingDoc;
    titleEl.textContent = isNew ? `Nouveau ${schema.label.toLowerCase()}` : `Éditer ${schema.label.toLowerCase()}`;
    deleteBtn.hidden = isNew;
    statusEl.textContent = "";
    statusEl.className = "editor-status";

    fieldsEl.innerHTML = schema.fields.map((f) => fieldHTML(f, existingDoc?.[f.key])).join("");

    closeBtn.onclick = () => dialog.close();
    dialog.addEventListener("cancel", (e) => { e.preventDefault(); dialog.close(); }, { once: true });

    deleteBtn.onclick = async () => {
        if (!existingDoc) return;
        if (!confirm(`Supprimer ce ${schema.label.toLowerCase()} ? Cette action est irréversible.`)) return;
        statusEl.textContent = "Suppression…";
        statusEl.className = "editor-status";
        try {
            await deleteDoc(doc(db, collectionName, existingDoc._docId));
            dialog.close();
            window.__refreshActiveTab?.();
        } catch (e) {
            statusEl.textContent = e?.code === "permission-denied"
                ? "Permission refusée — claim admin manquant."
                : `Erreur : ${e.message}`;
            statusEl.className = "editor-status error";
        }
    };

    form.onsubmit = async (e) => {
        e.preventDefault();
        const data = collectFormData(schema.fields, fieldsEl);
        statusEl.textContent = "Enregistrement…";
        statusEl.className = "editor-status";
        try {
            if (isNew) {
                const ref = await addDoc(collection(db, collectionName), {
                    ...data,
                    id: "", // placeholder, sync below
                    createdAt: serverTimestamp(),
                    updatedAt: serverTimestamp(),
                });
                // Sync `id` field with Firestore-generated doc ID pour rester
                // cohérent avec les data seed (qui ont id == doc.id).
                await setDoc(ref, { id: ref.id }, { merge: true });
            } else {
                await setDoc(doc(db, collectionName, existingDoc._docId), {
                    ...data,
                    updatedAt: serverTimestamp(),
                }, { merge: true });
            }
            dialog.close();
            window.__refreshActiveTab?.();
        } catch (err) {
            statusEl.textContent = err?.code === "permission-denied"
                ? "Permission refusée — claim admin manquant."
                : `Erreur : ${err.message}`;
            statusEl.className = "editor-status error";
        }
    };

    dialog.showModal();
}

function fieldHTML(f, value) {
    const v = value ?? "";
    const required = f.required ? "required" : "";
    switch (f.type) {
        case "textarea":
            return `<label class="field"><span>${esc(f.label)}${f.required ? " *" : ""}</span>
                <textarea name="${esc(f.key)}" ${f.maxLength ? `maxlength="${f.maxLength}"` : ""} ${required}>${esc(v)}</textarea></label>`;
        case "markdown":
            return `<label class="field"><span>${esc(f.label)}${f.required ? " *" : ""}</span>
                <textarea name="${esc(f.key)}" data-tall ${required}>${esc(v)}</textarea></label>`;
        case "checkbox":
            return `<label class="checkbox">
                <input type="checkbox" name="${esc(f.key)}" ${v ? "checked" : ""}>
                <span>${esc(f.label)}</span></label>`;
        case "select":
            return `<label class="field"><span>${esc(f.label)}${f.required ? " *" : ""}</span>
                <select name="${esc(f.key)}" ${required}>
                    <option value="">—</option>
                    ${f.options.map((o) => `<option value="${esc(o)}" ${v === o ? "selected" : ""}>${esc(o)}</option>`).join("")}
                </select></label>`;
        case "date":
            return `<label class="field"><span>${esc(f.label)}${f.required ? " *" : ""}</span>
                <input type="date" name="${esc(f.key)}" value="${esc(v)}" ${required}></label>`;
        case "url":
            return `<label class="field"><span>${esc(f.label)}${f.required ? " *" : ""}</span>
                <input type="url" name="${esc(f.key)}" value="${esc(v)}" ${f.placeholder ? `placeholder="${esc(f.placeholder)}"` : ""} ${required}></label>`;
        case "text":
        default:
            return `<label class="field"><span>${esc(f.label)}${f.required ? " *" : ""}</span>
                <input type="text" name="${esc(f.key)}" value="${esc(v)}" ${f.placeholder ? `placeholder="${esc(f.placeholder)}"` : ""} ${required}></label>`;
    }
}

function collectFormData(fields, container) {
    const data = {};
    for (const f of fields) {
        const el = container.querySelector(`[name="${f.key}"]`);
        if (!el) continue;
        if (f.type === "checkbox") {
            data[f.key] = el.checked;
        } else if (f.type === "select" && el.value === "") {
            // skip empty selects to avoid storing literal ""
            continue;
        } else {
            data[f.key] = el.value;
        }
    }
    return data;
}

function esc(s) {
    return String(s ?? "").replace(/[&<>"']/g, (c) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[c]));
}

// Boot
renderPicker();
