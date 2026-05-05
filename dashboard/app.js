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
        } else if (name === "branding") {
            await renderBranding(content, user);
        } else if (name === "moderation") {
            await renderModeration(content, user);
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

    if (catalog.length === 0) {
        container.innerHTML = `<p class="empty">Aucun module disponible dans le catalogue.</p>`;
        return;
    }

    // Tri : officiels en haut, communauté en bas, alpha dans chaque groupe
    const sortedCatalog = [...catalog].sort((a, b) => {
        if (!!a.official !== !!b.official) return a.official ? -1 : 1;
        return (a.displayName || "").localeCompare(b.displayName || "");
    });

    const activeIds = new Set((runtime.modules ?? []).map((m) => m.id));

    const moduleRowHTML = (m) => `
        <label class="module-row">
            <input type="checkbox" data-module-id="${esc(m.id)}" ${activeIds.has(m.id) ? "checked" : ""}>
            <div class="module-row-text">
                <strong>${esc(m.displayName)}${m.official ? "" : ` <span class="module-badge community">Communauté</span>`}</strong>
                <span>${esc(m.description ?? "")}</span>
                <span class="module-row-meta">v${esc(m.version)} · ${esc((m.capabilities ?? []).length)} capability(ies) · par ${esc(m.author ?? "?")} · ${esc(m.licence ?? "?")}</span>
            </div>
        </label>
    `;

    container.innerHTML = `
        <div class="modules-pane">
            <p class="modules-intro">Activez/désactivez les modules disponibles pour cette commune. Officiels en haut, communautaires en bas. Les changements prennent effet au prochain démarrage de l'app citoyenne.</p>
            <div class="modules-list">
                ${sortedCatalog.map(moduleRowHTML).join("")}
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
            version: catalog.find((m) => m.id === id)?.version ?? "0.1.0",
        }));
        const newTabs = (runtime.view?.tabs ?? []).filter((t) => {
            const mod = String(t.screen ?? "").split(":")[0];
            return checked.includes(mod);
        });
        // Ajoute un onglet par défaut pour les modules nouvellement activés.
        const tabModuleIds = new Set(newTabs.map((t) => String(t.screen ?? "").split(":")[0]));
        for (const id of checked) {
            if (!tabModuleIds.has(id)) {
                const m = catalog.find((x) => x.id === id);
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
// et le rendu de la liste.
//   - `singleton: true` = un doc fixe (pas de + Nouveau, pas de Supprimer)
//   - `image` field type → upload Firebase Storage (14.2)
//   - `number` field type → input numérique (lat/lng pour places)
//   - `options` field type → liste dynamique d'objets {id,label} (polls)
const PLACE_CATEGORIES = [
    { value: "services", label: "Services communaux" },
    { value: "ecole", label: "Écoles" },
    { value: "sport", label: "Sport" },
    { value: "culture", label: "Culture" },
    { value: "nature", label: "Nature" },
];

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
            { key: "imageUrl", label: "Image (1.6:1 conseillé)", type: "image", folder: "articles" },
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
            { key: "imageUrl", label: "Image (1.78:1 conseillé)", type: "image", folder: "events" },
            { key: "description", label: "Description (Markdown)", type: "markdown" },
        ],
    },
    polls: {
        label: "Sondage",
        labelPlural: "Sondages",
        renderItem: (p) => `
            <h3>${esc(p.title)}</h3>
            <p class="meta">${esc(p.description ?? "")}</p>
            <p class="body"><strong>Question :</strong> ${esc(p.question ?? "")}</p>
            ${(p.options ?? []).length ? `<ul>${p.options.map((o) => `<li>${esc(o.label)} <small>(${esc(o.id)})</small></li>`).join("")}</ul>` : ""}
        `,
        fields: [
            { key: "title", label: "Titre interne (visible dans la liste app)", type: "text", required: true },
            { key: "description", label: "Description courte", type: "textarea", maxLength: 200 },
            { key: "question", label: "Question posée à l'utilisateur", type: "text", required: true },
            { key: "options", label: "Réponses possibles (id technique + label affiché)", type: "options" },
        ],
    },
    places: {
        label: "Lieu",
        labelPlural: "Lieux",
        renderItem: (p) => `
            <h3>${esc(p.name)}</h3>
            <p class="meta">${esc(p.categoryLabel ?? p.category ?? "")} — ${esc(p.address ?? "")}</p>
            <p class="body">${esc(p.meta ?? "")}</p>
        `,
        fields: [
            { key: "name", label: "Nom du lieu", type: "text", required: true },
            { key: "category", label: "Catégorie (id technique pour la couleur du pin)", type: "select", options: PLACE_CATEGORIES.map((c) => c.value), required: true },
            { key: "categoryLabel", label: "Catégorie (libellé affiché)", type: "text", placeholder: "Services communaux" },
            { key: "address", label: "Adresse", type: "text" },
            { key: "meta", label: "Sous-titre liste (ex. « Place 1 · ouvert jusqu'à 12h »)", type: "text" },
            { key: "lat", label: "Latitude (ex. 50.6695)", type: "number", required: true },
            { key: "lng", label: "Longitude (ex. 5.4762)", type: "number", required: true },
            { key: "hours", label: "Horaires (multi-ligne)", type: "textarea" },
            { key: "body", label: "Description (Markdown)", type: "markdown" },
        ],
    },
    info: {
        label: "Infos pratiques",
        labelPlural: "Infos pratiques",
        singleton: true,        // 1 doc fixe = info/main
        singletonDocId: "main",
        renderItem: (d) => `
            <h3>${esc(d.communeName ?? "")}</h3>
            <p class="meta">${esc(d.address ?? "").replace(/\n/g, " · ")}</p>
            <p class="body">${esc(d.tagline ?? "")}</p>
        `,
        fields: [
            { key: "communeName", label: "Nom de la commune (affiché en hero)", type: "text", required: true },
            { key: "tagline", label: "Tagline (italic, sous le nom)", type: "text", placeholder: "à votre service depuis 1830" },
            { key: "address", label: "Adresse postale (multi-ligne)", type: "textarea" },
            { key: "hours", label: "Horaires (multi-ligne)", type: "textarea" },
            { key: "phone", label: "Téléphone", type: "text" },
            { key: "email", label: "Email", type: "text" },
        ],
    },
};

// MARK: - Modération UGC (14.8)
//
// Pattern :
//   - Les CFs des modules officiels écrivent les soumissions citoyennes
//     dans `_moderation_queue/<auto-id>` (Admin SDK bypasse les rules)
//     avec le shape : { targetCollection, payload, moduleId,
//     submittedBy, submittedAt }
//   - Le dashboard lit la queue, propose Approuver / Rejeter par item
//   - Approuver : `addDoc(targetCollection, payload + approvedAt + approvedBy)`
//                 puis `deleteDoc(_moderation_queue/<id>)`
//   - Rejeter : juste `deleteDoc(_moderation_queue/<id>)` (audit log =
//                 phase ultérieure si besoin)
//
// Aucun module officiel ne produit d'UGC en v0 — la queue restera vide
// tant qu'un module n'aura pas implémenté le côté soumission. Le contrat
// + l'UI sont prêts pour quand ce cas arrivera.

async function renderModeration(container, user) {
    let pending = [];
    try {
        const snap = await getDocs(collection(db, "_moderation_queue"));
        pending = snap.docs.map((d) => ({ _docId: d.id, ...d.data() }));
    } catch (e) {
        if (e?.code === "permission-denied") {
            container.innerHTML = `<p class="empty">Permission refusée — votre compte n'a pas le claim admin.</p>`;
        } else {
            container.innerHTML = `<p class="empty">Erreur : ${esc(e.message)}</p>`;
        }
        return;
    }

    if (pending.length === 0) {
        container.innerHTML = `
            <div class="moderation-pane">
                <p class="modules-intro">
                    File de modération unifiée. Les contenus citoyens en attente
                    (suggestions, signalements, commentaires…) y apparaissent
                    avant publication. Aucun module officiel ne produit d'UGC
                    en v0 — cette file reste vide tant qu'un module n'a pas
                    déclaré la capability <code>moderation</code>.
                </p>
                <p class="empty">Aucun contenu en attente.</p>
            </div>
        `;
        return;
    }

    // Tri par date de soumission ascendante (les plus anciennes d'abord)
    pending.sort((a, b) => {
        const ta = a.submittedAt?.seconds ?? 0;
        const tb = b.submittedAt?.seconds ?? 0;
        return ta - tb;
    });

    container.innerHTML = `
        <div class="moderation-pane">
            <p class="modules-intro">
                ${esc(pending.length)} contenu${pending.length > 1 ? "s" : ""} en attente de validation.
            </p>
            <div class="moderation-list">
                ${pending.map((item) => moderationCardHTML(item)).join("")}
            </div>
        </div>
    `;

    container.querySelectorAll("[data-mod-action]").forEach((btn) => {
        btn.addEventListener("click", async () => {
            const action = btn.dataset.modAction;
            const docId = btn.dataset.docId;
            const item = pending.find((p) => p._docId === docId);
            if (!item) return;
            await handleModerationAction(action, item, user, container);
        });
    });
}

function moderationCardHTML(item) {
    const summary = renderModerationPayload(item.payload ?? {});
    const submittedAt = item.submittedAt?.seconds
        ? new Date(item.submittedAt.seconds * 1000).toLocaleString("fr-BE")
        : "—";
    return `
        <div class="moderation-item" data-doc-id="${esc(item._docId)}">
            <div class="moderation-meta">
                <span class="moderation-badge">${esc(item.moduleId ?? "?")}</span>
                <span>→ <code>${esc(item.targetCollection ?? "?")}</code></span>
                <span class="moderation-when">soumis ${esc(submittedAt)}</span>
            </div>
            <div class="moderation-payload">${summary}</div>
            <div class="moderation-actions">
                <button type="button" class="approve" data-mod-action="approve" data-doc-id="${esc(item._docId)}">Approuver</button>
                <button type="button" class="danger" data-mod-action="reject" data-doc-id="${esc(item._docId)}">Rejeter</button>
            </div>
        </div>
    `;
}

function renderModerationPayload(payload) {
    // Affiche les champs du payload de manière générique. Les modules peuvent
    // pré-formater leur payload avec un champ `_summary` qu'on privilégie.
    if (typeof payload._summary === "string") return esc(payload._summary);
    return Object.entries(payload)
        .filter(([k]) => !k.startsWith("_"))
        .slice(0, 4)
        .map(([k, v]) => `<div><strong>${esc(k)}</strong> : ${esc(typeof v === "object" ? JSON.stringify(v) : v)}</div>`)
        .join("");
}

async function handleModerationAction(action, item, user, container) {
    const card = container.querySelector(`[data-doc-id="${item._docId}"]`);
    const actions = card?.querySelector(".moderation-actions");
    if (actions) actions.innerHTML = `<span class="muted">Traitement…</span>`;
    try {
        if (action === "approve") {
            await addDoc(collection(db, item.targetCollection), {
                ...item.payload,
                approvedAt: serverTimestamp(),
                approvedBy: user.uid,
                originalSubmittedBy: item.submittedBy ?? null,
            });
        }
        // Dans tous les cas (approve OU reject) on supprime l'entrée queue.
        // Audit/log des rejets = phase ultérieure si besoin.
        await deleteDoc(doc(db, "_moderation_queue", item._docId));
        if (card) card.remove();
        // Re-render si la liste devient vide
        if (container.querySelectorAll(".moderation-item").length === 0) {
            window.__refreshActiveTab?.();
        }
    } catch (e) {
        if (actions) {
            actions.innerHTML = `<span class="error">${esc(e?.code === "permission-denied" ? "Permission refusée" : e.message)}</span>`;
        }
    }
}

// MARK: - Branding editor (14.7 — onboarding admin partiel)

async function renderBranding(container, user) {
    let runtime = { view: { brand: {} } };
    try {
        const snap = await getDoc(doc(db, "_config", "modules"));
        if (snap.exists()) runtime = { ...runtime, ...snap.data() };
    } catch (e) {
        container.innerHTML = `<p class="empty">Erreur chargement : ${esc(e.message)}</p>`;
        return;
    }

    const brand = runtime.view?.brand ?? {};
    const dots = Array.isArray(brand.dots) && brand.dots.length === 6
        ? brand.dots
        : ["#1976d2", "#26a69a", "#ffa000", "#ec407a", "#7e57c2", "#26c6da"];

    container.innerHTML = `
        <div class="branding-pane">
            <p class="modules-intro">Personnalisez l'identité visuelle de l'app citoyenne. Le label apparaît en haut de chaque écran ; les 6 ronds colorés sont la signature visuelle de la commune (sous le label).</p>
            <div class="branding-form">
                <label class="field">
                    <span>Label affiché en haut de l'app *</span>
                    <input type="text" name="label" value="${esc(brand.label ?? "")}" placeholder="Ex: AWANS" required>
                </label>
                <label class="field">
                    <span>Couleur du texte (hex)</span>
                    <input type="text" name="textColor" value="${esc(brand.textColor ?? "#0f172a")}" placeholder="#0f172a">
                </label>
                <div class="field">
                    <span>Ronds colorés (signature)</span>
                    <div class="dots-row">
                        ${dots.map((d, i) => `<input type="color" data-dot-index="${i}" value="${esc(d)}">`).join("")}
                    </div>
                </div>
                <div class="branding-preview">
                    <span class="branding-preview-label" data-preview-label>${esc(brand.label ?? "DÉMO")}</span>
                    <div class="branding-preview-dots">
                        ${dots.map((d, i) => `<span class="branding-preview-dot" data-preview-dot="${i}" style="background:${esc(d)}"></span>`).join("")}
                    </div>
                </div>
            </div>
            <div class="modules-actions">
                <button id="branding-save" class="primary">Enregistrer</button>
                <p class="modules-status" data-slot="status"></p>
            </div>
        </div>
    `;

    // Live preview en tapant
    const labelInput = container.querySelector("input[name='label']");
    const previewLabel = container.querySelector("[data-preview-label]");
    labelInput.addEventListener("input", () => {
        previewLabel.textContent = labelInput.value || "DÉMO";
    });
    container.querySelectorAll("input[data-dot-index]").forEach((dotInput) => {
        dotInput.addEventListener("input", () => {
            const i = parseInt(dotInput.dataset.dotIndex, 10);
            const previewDot = container.querySelector(`[data-preview-dot="${i}"]`);
            if (previewDot) previewDot.style.background = dotInput.value;
        });
    });

    const status = container.querySelector("[data-slot='status']");
    container.querySelector("#branding-save").addEventListener("click", async () => {
        const newDots = Array.from(container.querySelectorAll("input[data-dot-index]"))
            .sort((a, b) => parseInt(a.dataset.dotIndex, 10) - parseInt(b.dataset.dotIndex, 10))
            .map((i) => i.value);
        const newBrand = {
            label: labelInput.value.trim(),
            textColor: container.querySelector("input[name='textColor']").value.trim() || "#0f172a",
            dots: newDots,
        };
        status.textContent = "Enregistrement…";
        status.className = "modules-status";
        try {
            // Préserve modules + tabs ; ne touche QUE view.brand
            const preservedView = { ...(runtime.view ?? {}) };
            preservedView.brand = newBrand;
            preservedView.type = preservedView.type ?? "tabbar";
            await setDoc(doc(db, "_config", "modules"), {
                ...runtime,
                view: preservedView,
                updatedAt: serverTimestamp(),
                updatedBy: user.uid,
            }, { merge: true });
            status.textContent = "✓ Branding enregistré. L'app citoyenne reflètera la nouvelle identité au prochain démarrage.";
            status.className = "modules-status success";
        } catch (e) {
            status.textContent = e?.code === "permission-denied"
                ? "Permission refusée — claim admin manquant."
                : `Erreur : ${e.message}`;
            status.className = "modules-status error";
        }
    });
}

async function renderSection(name, container) {
    try {
        if (!SCHEMAS[name]) {
            container.innerHTML = `<p class="empty">Onglet « ${esc(name)} » sans schéma.</p>`;
            return;
        }
        if (SCHEMAS[name].singleton) {
            await renderSingleton(name, container);
        } else {
            await renderEditableList(name, container);
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

async function renderSingleton(collectionName, container) {
    const schema = SCHEMAS[collectionName];
    const docId = schema.singletonDocId;
    const snap = await getDoc(doc(db, collectionName, docId));
    const data = snap.exists() ? { _docId: docId, ...snap.data() } : { _docId: docId };

    container.innerHTML = `
        <div class="section-toolbar">
            <h2>${esc(schema.label)}</h2>
            <button type="button" class="new" id="singleton-edit">Éditer</button>
        </div>
        <div class="item">
            ${snap.exists() ? schema.renderItem(data) : `<p class="empty">Aucun document <code>${esc(collectionName)}/${esc(docId)}</code> pour l'instant. Cliquez sur Éditer pour le créer.</p>`}
        </div>
    `;
    container.querySelector("#singleton-edit").addEventListener("click", () => {
        openEditor(collectionName, data);
    });
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

    // Singletons : on traite TOUJOURS comme "existingDoc" (le doc id est fixe),
    // même quand le doc n'existe pas encore en Firestore — pas de "+ Nouveau",
    // pas de bouton Supprimer.
    const isSingleton = !!schema.singleton;
    const isNew = !isSingleton && !existingDoc;
    titleEl.textContent = isNew
        ? `Nouveau ${schema.label.toLowerCase()}`
        : `Éditer ${schema.label.toLowerCase()}`;
    deleteBtn.hidden = isNew || isSingleton;
    statusEl.textContent = "";
    statusEl.className = "editor-status";

    fieldsEl.innerHTML = schema.fields.map((f) => fieldHTML(f, existingDoc?.[f.key])).join("");
    attachFieldHandlers(fieldsEl, schema, collectionName);

    closeBtn.onclick = () => dialog.close();
    dialog.addEventListener("cancel", (e) => { e.preventDefault(); dialog.close(); }, { once: true });

    deleteBtn.onclick = async () => {
        if (!existingDoc || isSingleton) return;
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
            if (isSingleton) {
                await setDoc(doc(db, collectionName, schema.singletonDocId), {
                    ...data,
                    updatedAt: serverTimestamp(),
                }, { merge: true });
            } else if (isNew) {
                const ref = await addDoc(collection(db, collectionName), {
                    ...data,
                    id: "",
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
    const labelHTML = `<span>${esc(f.label)}${f.required ? " *" : ""}</span>`;
    switch (f.type) {
        case "textarea":
            return `<label class="field">${labelHTML}
                <textarea name="${esc(f.key)}" ${f.maxLength ? `maxlength="${f.maxLength}"` : ""} ${required}>${esc(v)}</textarea></label>`;
        case "markdown":
            return `<label class="field">${labelHTML}
                <textarea name="${esc(f.key)}" data-tall ${required}>${esc(v)}</textarea></label>`;
        case "checkbox":
            return `<label class="checkbox">
                <input type="checkbox" name="${esc(f.key)}" ${v ? "checked" : ""}>
                <span>${esc(f.label)}</span></label>`;
        case "select":
            return `<label class="field">${labelHTML}
                <select name="${esc(f.key)}" ${required}>
                    <option value="">—</option>
                    ${f.options.map((o) => `<option value="${esc(o)}" ${v === o ? "selected" : ""}>${esc(o)}</option>`).join("")}
                </select></label>`;
        case "date":
            return `<label class="field">${labelHTML}
                <input type="date" name="${esc(f.key)}" value="${esc(v)}" ${required}></label>`;
        case "number":
            return `<label class="field">${labelHTML}
                <input type="number" step="any" name="${esc(f.key)}" value="${esc(v)}" ${f.placeholder ? `placeholder="${esc(f.placeholder)}"` : ""} ${required}></label>`;
        case "url":
            return `<label class="field">${labelHTML}
                <input type="url" name="${esc(f.key)}" value="${esc(v)}" ${f.placeholder ? `placeholder="${esc(f.placeholder)}"` : ""} ${required}></label>`;
        case "image":
            // Image upload : URL stockée comme string ; preview + bouton upload.
            // Si l'URL existe déjà, on l'affiche en preview ; un nouveau upload
            // remplace. Storage path = uploads/<folder>/<random>.
            return `<div class="field">${labelHTML}
                <div class="image-field">
                    <img class="image-preview" data-preview-for="${esc(f.key)}"
                         src="${esc(v)}" ${v ? "" : "hidden"}>
                    <input type="hidden" name="${esc(f.key)}" value="${esc(v)}">
                    <input type="file" accept="image/*" data-upload-for="${esc(f.key)}" data-folder="${esc(f.folder ?? "uploads")}">
                    <span class="image-status" data-upload-status="${esc(f.key)}"></span>
                </div></div>`;
        case "options": {
            // Tableau dynamique d'objets {id,label} pour les sondages.
            // Chaque ligne : input id (technique) + input label (affiché).
            // Bouton + Ajouter en bas. Bouton × supprime la ligne.
            // La valeur initiale est sérialisée en data-initial pour que
            // attachFieldHandlers puisse la lire après injection HTML.
            const initialOpts = Array.isArray(value) ? value : [];
            const serialized = esc(JSON.stringify(initialOpts));
            return `<div class="field">${labelHTML}
                <div class="options-field" data-options-for="${esc(f.key)}" data-initial="${serialized}">
                    <div class="options-rows" data-rows></div>
                    <button type="button" class="options-add" data-add-option="${esc(f.key)}">+ Ajouter une option</button>
                </div></div>`;
        }
        case "text":
        default:
            return `<label class="field">${labelHTML}
                <input type="text" name="${esc(f.key)}" value="${esc(v)}" ${f.placeholder ? `placeholder="${esc(f.placeholder)}"` : ""} ${required}></label>`;
    }
}

function attachFieldHandlers(container, schema, collectionName) {
    // Image upload : sur changement de fichier, upload vers Storage, met
    // l'URL dans le hidden input + preview.
    container.querySelectorAll("input[type='file'][data-upload-for]").forEach((input) => {
        input.addEventListener("change", async (e) => {
            const key = input.dataset.uploadFor;
            const folder = input.dataset.folder || "uploads";
            const file = input.files?.[0];
            if (!file) return;
            const status = container.querySelector(`[data-upload-status="${key}"]`);
            const preview = container.querySelector(`[data-preview-for="${key}"]`);
            const hidden = container.querySelector(`input[type="hidden"][name="${key}"]`);
            status.textContent = "Upload…";
            status.className = "image-status";
            try {
                const url = await uploadImage(file, folder);
                hidden.value = url;
                preview.src = url;
                preview.hidden = false;
                status.textContent = "✓ Image envoyée.";
                status.className = "image-status success";
            } catch (err) {
                status.textContent = err?.code === "storage/unauthorized"
                    ? "Permission refusée (claim admin manquant)."
                    : `Erreur upload : ${err.message}`;
                status.className = "image-status error";
            }
        });
    });

    // Options dynamiques (polls) : init avec la valeur existante (sérialisée
    // en data-initial par fieldHTML) + bouton add.
    container.querySelectorAll("[data-options-for]").forEach((wrapper) => {
        const rowsEl = wrapper.querySelector("[data-rows]");
        const initialJson = wrapper.dataset.initial || "[]";
        let parsed;
        try { parsed = JSON.parse(initialJson); } catch { parsed = []; }
        for (const opt of parsed) {
            rowsEl.appendChild(buildOptionRow(opt));
        }
        if (parsed.length === 0) {
            rowsEl.appendChild(buildOptionRow({ id: "", label: "" }));
        }
        wrapper.querySelector("[data-add-option]").addEventListener("click", () => {
            rowsEl.appendChild(buildOptionRow({ id: "", label: "" }));
        });
    });
}

function buildOptionRow(opt) {
    const row = document.createElement("div");
    row.className = "options-row";
    row.innerHTML = `
        <input type="text" data-opt-id placeholder="id (yes, no, …)" value="${esc(opt.id ?? "")}">
        <input type="text" data-opt-label placeholder="Label affiché" value="${esc(opt.label ?? "")}">
        <button type="button" class="options-remove" aria-label="Supprimer">×</button>
    `;
    row.querySelector(".options-remove").addEventListener("click", () => row.remove());
    return row;
}

function collectFormData(fields, container) {
    const data = {};
    for (const f of fields) {
        if (f.type === "options") {
            const wrapper = container.querySelector(`[data-options-for="${f.key}"]`);
            if (!wrapper) continue;
            const rows = wrapper.querySelectorAll(".options-row");
            const opts = Array.from(rows).map((r) => ({
                id: r.querySelector("[data-opt-id]").value.trim(),
                label: r.querySelector("[data-opt-label]").value.trim(),
            })).filter((o) => o.id && o.label);
            data[f.key] = opts;
            continue;
        }
        const el = container.querySelector(`[name="${f.key}"]`);
        if (!el) continue;
        if (f.type === "checkbox") {
            data[f.key] = el.checked;
        } else if (f.type === "select" && el.value === "") {
            continue;
        } else if (f.type === "number") {
            const num = parseFloat(el.value);
            data[f.key] = Number.isFinite(num) ? num : 0;
        } else {
            data[f.key] = el.value;
        }
    }
    return data;
}

// MARK: - Image upload (Firebase Storage)

let storage = null;
async function uploadImage(file, folder) {
    if (!storage) {
        const mod = await import("https://www.gstatic.com/firebasejs/11.0.0/firebase-storage.js");
        storage = mod.getStorage(app);
        // Cache mod pour réutilisation
        uploadImage._mod = mod;
    }
    const mod = uploadImage._mod;
    // Random suffix pour éviter les collisions et faciliter le cache busting
    const ext = (file.name.match(/\.[^.]+$/)?.[0] || ".bin").toLowerCase();
    const filename = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}${ext}`;
    // Préfixe `uploads/` pour matcher les Storage rules
    // (`match /uploads/{folder}/{filename}` dans core/firebase/storage.rules).
    const path = `uploads/${folder}/${filename}`;
    const ref = mod.ref(storage, path);
    await mod.uploadBytes(ref, file, { contentType: file.type });
    return await mod.getDownloadURL(ref);
}

function esc(s) {
    return String(s ?? "").replace(/[&<>"']/g, (c) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[c]));
}

// Boot
renderPicker();
