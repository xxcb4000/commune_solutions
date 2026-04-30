// Mapping SF Symbols → SVG inline pour la marketplace web.
// Reflète la table iOS (SF Symbols natifs) et Android (`Renderer.kt:iconForName`).
// En v0, couvre uniquement les icônes utilisées par les modules officiels.
// Phase 11.5 : faire de cette table la source de vérité, branchée à un check CI
// qui refuse une PR module utilisant une icône hors-table.

const ICONS = {
  newspaper: {
    body: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 9h6M7 13h6M7 17h6M16 9h2M16 13h2M16 17h2"/>',
    fill: false,
  },
  calendar: {
    body: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 11h18"/>',
    fill: false,
  },
  "info.circle": {
    body: '<circle cx="12" cy="12" r="9"/><path d="M12 8h.01M11 12h1v5h1"/>',
    fill: false,
  },
  "chart.bar.fill": {
    body: '<rect x="4" y="13" width="3.5" height="8" rx="0.5"/><rect x="10.25" y="7" width="3.5" height="14" rx="0.5"/><rect x="16.5" y="10" width="3.5" height="11" rx="0.5"/>',
    fill: true,
  },
  // Fallback générique : un carré arrondi (= "module").
  __fallback: {
    body: '<rect x="4" y="4" width="16" height="16" rx="3"/>',
    fill: false,
  },
};

export function iconSvg(name, { size = 24, className = "" } = {}) {
  const icon = ICONS[name] ?? ICONS.__fallback;
  const stroke = icon.fill ? "none" : "currentColor";
  const fill = icon.fill ? "currentColor" : "none";
  return `<svg class="${className}" width="${size}" height="${size}" viewBox="0 0 24 24" fill="${fill}" stroke="${stroke}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icon.body}</svg>`;
}
