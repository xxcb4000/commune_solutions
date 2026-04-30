// Charge l'agrégat de manifests, rend la grille, gère les filtres officiel/communauté.
const grid = document.getElementById("catalog-grid");
const filters = document.querySelectorAll(".filter");

let modules = [];
let activeFilter = "all";

async function load() {
  try {
    const res = await fetch("/marketplace/data/manifests.json", { cache: "no-cache" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const payload = await res.json();
    modules = payload.modules || [];
    render();
  } catch (err) {
    grid.innerHTML = `<p class="loading">Impossible de charger le catalogue (${err.message}).</p>`;
  }
}

function render() {
  grid.removeAttribute("aria-busy");
  const filtered = modules.filter((m) => {
    if (activeFilter === "all") return true;
    if (activeFilter === "official") return m.official === true;
    if (activeFilter === "community") return m.official === false;
    return true;
  });

  if (filtered.length === 0) {
    grid.innerHTML = `<p class="loading">Aucun module dans cette catégorie pour le moment.</p>`;
    return;
  }

  grid.innerHTML = filtered.map(card).join("");
}

function card(m) {
  const tags = (m.tags || []).slice(0, 2).map((t) => `<span class="tag">${escape(t)}</span>`).join("");
  const badge = m.official
    ? `<span class="badge badge-official">officiel</span>`
    : `<span class="badge badge-community">communauté</span>`;
  return `
    <a class="card" href="/marketplace/module?id=${encodeURIComponent(m.id)}">
      <div class="card-head">
        <h3 class="card-title">${escape(m.displayName || m.id)}</h3>
        ${badge}
      </div>
      <p class="card-desc">${escape(m.description || "")}</p>
      <div class="card-foot">
        <div class="card-tags">${tags}</div>
        <span>v${escape(m.version || "?")}</span>
      </div>
    </a>
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

filters.forEach((btn) => {
  btn.addEventListener("click", () => {
    filters.forEach((b) => {
      b.classList.toggle("active", b === btn);
      b.setAttribute("aria-selected", b === btn ? "true" : "false");
    });
    activeFilter = btn.dataset.filter;
    render();
  });
});

load();
