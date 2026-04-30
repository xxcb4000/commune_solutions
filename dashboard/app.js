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
} from "https://www.gstatic.com/firebasejs/11.0.0/firebase-firestore.js";

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

    let activeTab = "polls";
    const showTab = async (name) => {
        activeTab = name;
        tabs.forEach((b) => b.classList.toggle("active", b.dataset.tab === name));
        content.innerHTML = `<p class="empty">Chargement…</p>`;
        content.innerHTML = await renderSection(name);
    };
    tabs.forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));
    showTab(activeTab);
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
