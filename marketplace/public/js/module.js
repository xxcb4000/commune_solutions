// Page détail d'un module. Lit l'id depuis ?id=, retrouve le manifest dans
// l'agrégat, rend les sections : description, capabilities, écrans, infos.
import { iconSvg } from "./icons.js";

const root = document.getElementById("module-root");
const params = new URLSearchParams(window.location.search);
const id = params.get("id");

async function load() {
  if (!id) return showError("Aucun module spécifié.");
  try {
    const res = await fetch("/marketplace/data/manifests.json", { cache: "no-cache" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const payload = await res.json();
    const mod = (payload.modules || []).find((m) => m.id === id);
    if (!mod) return showError(`Module « ${id} » introuvable.`);
    render(mod);
  } catch (err) {
    showError(`Impossible de charger le module (${err.message}).`);
  }
}

function showError(msg) {
  root.removeAttribute("aria-busy");
  root.innerHTML = `<p class="loading">${escape(msg)}</p>`;
}

function render(m) {
  document.title = `${m.displayName || m.id} — Marketplace Commune Solutions`;
  root.removeAttribute("aria-busy");

  const badge = m.official
    ? `<span class="badge badge-official">officiel</span>`
    : `<span class="badge badge-community">communauté</span>`;

  const screens = Object.keys(m.screens || {});
  const dataKeys = Object.keys(m.data || {});

  root.innerHTML = `
    <div class="module-head">
      <div class="module-icon">${iconSvg(m.icon, { size: 32 })}</div>
      <div class="module-head-text">
        <h1>${escape(m.displayName || m.id)}</h1>
        <p class="module-meta">
          ${badge}
          <span>v${escape(m.version || "?")}</span>
          <span>par ${escape(m.author || "—")}</span>
        </p>
      </div>
    </div>

    <section class="module-section">
      <h2>Description</h2>
      <p class="module-description">${escape(m.longDescription || m.description || "")}</p>
    </section>

    <section class="module-section">
      <h2>Capabilities demandées</h2>
      ${renderCapabilities(m.capabilities || [])}
    </section>

    <section class="module-section">
      <h2>Écrans (${screens.length})</h2>
      <div class="screens-list">
        ${screens.map((s) => `<div class="screen-pill">${escape(s)}</div>`).join("")}
      </div>
    </section>

    <section class="module-section">
      <h2>Informations</h2>
      <div class="facts">
        <div>
          <div class="fact-label">Identifiant</div>
          <div class="fact-value"><code>${escape(m.id)}</code></div>
        </div>
        <div>
          <div class="fact-label">Version</div>
          <div class="fact-value">${escape(m.version || "—")}</div>
        </div>
        <div>
          <div class="fact-label">Licence</div>
          <div class="fact-value">${escape(m.licence || "—")}</div>
        </div>
        <div>
          <div class="fact-label">Sources de données</div>
          <div class="fact-value">${dataKeys.length || "—"}</div>
        </div>
      </div>
    </section>
  `;
}

function renderCapabilities(caps) {
  if (caps.length === 0) {
    return `<p class="module-description" style="color: var(--text-soft);">Ce module ne demande aucune capacité.</p>`;
  }
  return `<ul class="cap-list">${caps.map(capItem).join("")}</ul>`;
}

function capItem(c) {
  const isWrite = (c.type || "").includes("write");
  const isRead = (c.type || "").includes("read");
  const klass = isWrite ? "write" : isRead ? "read" : "";
  const glyph = isWrite ? "✎" : isRead ? "⟲" : "·";
  return `
    <li class="cap-item">
      <div class="cap-icon ${klass}">${glyph}</div>
      <div class="cap-text">
        <div class="cap-target">${escape(c.target || "")}</div>
        <div class="cap-desc">${escape(c.description || "")}</div>
      </div>
      <span class="cap-type">${escape(c.type || "")}</span>
    </li>
  `;
}

function escape(str) {
  return String(str).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[c]);
}

load();
