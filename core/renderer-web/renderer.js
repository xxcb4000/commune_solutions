// Commune Solutions — renderer web (3ème renderer après iOS/Android).
//
// Pure ES module, vanilla JS. Pas de dépendances ni de build step.
// Interprète le même DSL JSON que les renderers natifs et rend en HTML.
// Les modules dont les data sources sont 100% `@<name>` (bundlée) sont
// rendus fidèlement. Sources `firestore:` / `cf:` sont mockées (vide en
// MVP — la marketplace web preview sert à valider la STRUCTURE et le
// design des écrans, pas le runtime data).
//
// Mapping primitives → HTML (MVP scope) :
//   scroll, vstack, hstack, card, image, text, markdown, for, if, header
// Phase 16.2 : tabbar, segmented, calendar, map, field, button.

import { renderMarkdown as md } from "./markdown.js";

// MARK: - Scope (binding lookup, parsé identique à iOS DSLScope)

export class Scope {
    constructor(bindings = {}) { this.bindings = { ...bindings }; }

    lookup(path) {
        const parts = String(path ?? "").split(".").filter(Boolean);
        if (parts.length === 0) return null;
        let curr = this.bindings[parts[0]];
        for (let i = 1; i < parts.length; i++) {
            if (curr == null) return null;
            const part = parts[i];
            if (Array.isArray(curr)) {
                const idx = parseInt(part, 10);
                if (Number.isNaN(idx)) return null;
                curr = curr[idx];
            } else if (typeof curr === "object") {
                curr = curr[part];
            } else {
                return null;
            }
        }
        return curr ?? null;
    }

    adding(key, value) {
        return new Scope({ ...this.bindings, [key]: value });
    }
}

// MARK: - Templating (Mustache-like, mêmes règles que iOS Template.swift)

export function resolve(str, scope) {
    return String(str ?? "").replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, key) => {
        const v = scope.lookup(key.trim());
        if (v == null) return "";
        if (typeof v === "object") return JSON.stringify(v);
        return String(v);
    });
}

/// Si `str` est exactement `{{ x }}`, retourne la valeur native (objet,
/// array). Sinon, stringifie. Mirror de iOS Template.resolveValue.
export function resolveValue(str, scope) {
    const trimmed = String(str ?? "").trim();
    const m = /^\{\{\s*([^}]+?)\s*\}\}$/.exec(trimmed);
    if (m) return scope.lookup(m[1].trim());
    return resolve(str, scope);
}

// MARK: - render entry point

/// Rend un noeud DSL en élément DOM.
/// `scope` : bindings pour résolution `{{ ... }}`
/// `ctx`   : contexte global (manifest, module id, navigate handler, etc.)
export function render(node, scope, ctx) {
    if (!node || !node.type) return document.createComment("(empty)");
    const fn = PRIMITIVES[node.type];
    if (!fn) {
        const el = document.createElement("div");
        el.className = "ds-unknown";
        el.textContent = `[${node.type}] non rendu en preview web (cf renderer iOS/Android)`;
        return el;
    }
    return fn(node, scope, ctx);
}

const PRIMITIVES = {
    scroll: renderScroll,
    vstack: renderVStack,
    hstack: renderHStack,
    card: renderCard,
    image: renderImage,
    text: renderText,
    markdown: renderMarkdownBlock,
    for: renderFor,
    if: renderIf,
    header: renderHeader,
    // 16.2 (stub gracieux pour l'instant)
    segmented: renderSegmented,
    tabbar: renderTabBar,
    calendar: renderCalendar,
    map: renderMap,
    field: renderUnsupported("Champ formulaire — preview natif uniquement"),
    button: renderButton,
};

// MARK: - Layout

function renderScroll(node, scope, ctx) {
    const div = document.createElement("div");
    div.className = "ds-scroll";
    for (const child of node.children ?? []) {
        div.appendChild(render(child, scope, ctx));
    }
    return div;
}

function renderVStack(node, scope, ctx) {
    const div = document.createElement("div");
    div.className = "ds-vstack";
    if (node.spacing != null) div.style.gap = `${node.spacing}px`;
    if (node.padding != null) div.style.padding = `${node.padding}px`;
    if (node.fill) div.classList.add("ds-fill");
    for (const child of node.children ?? []) {
        div.appendChild(render(child, scope, ctx));
    }
    return div;
}

function renderHStack(node, scope, ctx) {
    const div = document.createElement("div");
    div.className = "ds-hstack";
    if (node.spacing != null) div.style.gap = `${node.spacing}px`;
    if (node.padding != null) div.style.padding = `${node.padding}px`;
    const align = node.align;
    if (align === "top") div.style.alignItems = "flex-start";
    else if (align === "bottom") div.style.alignItems = "flex-end";
    else div.style.alignItems = "center";
    for (const child of node.children ?? []) {
        div.appendChild(render(child, scope, ctx));
    }
    return div;
}

// MARK: - Card

function renderCard(node, scope, ctx) {
    const article = document.createElement("article");
    article.className = "ds-card";
    if (node.action?.type === "navigate" && node.action.to) {
        article.classList.add("ds-card-tappable");
        const a = document.createElement("a");
        a.className = "ds-card-link";
        a.href = navigateHref(node.action, scope, ctx);
        if (node.child) a.appendChild(render(node.child, scope, ctx));
        article.appendChild(a);

        const chev = document.createElement("span");
        chev.className = "ds-card-chevron";
        chev.textContent = "›";
        article.appendChild(chev);
    } else if (node.child) {
        article.appendChild(render(node.child, scope, ctx));
    }
    return article;
}

// MARK: - Image

function renderImage(node, scope, ctx) {
    // Mode SF Symbol (icon dans une box) — on rend une approximation Unicode
    if (node.systemName) {
        return renderSymbol(node, scope);
    }
    const url = resolve(node.url ?? "", scope);
    const wrapper = document.createElement("div");
    wrapper.className = "ds-image";
    if (node.cornerRadius != null) wrapper.style.borderRadius = `${node.cornerRadius}px`;
    const w = node.width;
    const h = node.height;
    const aspect = node.aspectRatio;
    if (w && h) {
        wrapper.style.width = `${w}px`;
        wrapper.style.height = `${h}px`;
        wrapper.style.flex = "0 0 auto";
    } else if (h) {
        wrapper.style.height = `${h}px`;
    } else if (aspect) {
        wrapper.style.aspectRatio = `${aspect}`;
    }
    if (url) {
        const img = document.createElement("img");
        img.src = url;
        img.alt = "";
        img.loading = "lazy";
        wrapper.appendChild(img);
    }
    return wrapper;
}

function renderSymbol(node, scope) {
    const wrapper = document.createElement("span");
    wrapper.className = "ds-symbol";
    const inner = document.createElement("span");
    inner.className = "ds-symbol-inner";
    // Approximation : on utilise un mapping minimal SF Symbol → emoji/glyph.
    // Le but est l'aperçu, pas le pixel-perfect.
    inner.textContent = SF_SYMBOL_GLYPH[node.systemName] ?? "●";
    inner.style.color = colorVar(node.color);
    if (node.height) inner.style.fontSize = `${node.height}px`;
    if (node.bg) {
        wrapper.classList.add("ds-symbol-boxed");
        wrapper.style.background = bgVar(node.bg);
    }
    wrapper.appendChild(inner);
    return wrapper;
}

const SF_SYMBOL_GLYPH = {
    "envelope": "✉",
    "phone": "☎",
    "globe": "🌐",
    "mappin": "📍",
    "mappin.and.ellipse": "📍",
    "mappin.circle.fill": "📍",
    "clock": "🕒",
    "info.circle": "ℹ",
    "info.circle.fill": "ℹ",
    "newspaper": "📰",
    "calendar": "📅",
    "map": "🗺",
    "chart.bar.fill": "📊",
    "person.3": "👥",
    "person.3.fill": "👥",
    "fork.knife": "🍴",
    "plus.circle.fill": "+",
    "plus": "+",
    "checkmark": "✓",
    "checkmark.circle.fill": "✓",
    "xmark": "×",
    "magnifyingglass": "🔍",
};

// MARK: - Text

function renderText(node, scope) {
    const span = document.createElement("span");
    span.className = `ds-text ds-text-${node.style ?? "body"}`;
    if (node.color) span.style.color = colorVar(node.color);
    if (node.align) span.style.textAlign = node.align;
    span.textContent = resolve(node.value ?? "", scope);
    return span;
}

function renderMarkdownBlock(node, scope) {
    const div = document.createElement("div");
    div.className = "ds-markdown";
    div.innerHTML = md(resolve(node.value ?? "", scope));
    return div;
}

// MARK: - For / If

function renderFor(node, scope, ctx) {
    // Note : les clés JSON sont `in` / `as` (mots réservés Swift mappés via
    // CodingKeys en iOS, on utilise les noms bruts en JS).
    const items = scope.lookup(node.in ?? "") ?? [];
    const alias = node.as ?? "item";
    const div = document.createElement("div");
    div.className = "ds-for";
    if (node.spacing != null) div.style.gap = `${node.spacing}px`;
    if (Array.isArray(items)) {
        for (const item of items) {
            if (node.child) {
                div.appendChild(render(node.child, scope.adding(alias, item), ctx));
            }
        }
    }
    return div;
}

function renderIf(node, scope, ctx) {
    const cond = scope.lookup(node.condition ?? "");
    const truthy = cond != null && cond !== false && cond !== "" && cond !== 0
        && !(Array.isArray(cond) && cond.length === 0);
    const branch = truthy ? node.then : node.else;
    if (!branch) return document.createComment("(if-empty)");
    return render(branch, scope, ctx);
}

// MARK: - Header (hero)

function renderHeader(node, scope, ctx) {
    const wrapper = document.createElement("div");
    wrapper.className = "ds-header";
    if (node.cornerRadius) wrapper.style.borderRadius = `${node.cornerRadius}px`;
    const aspect = node.aspectRatio;
    const height = node.height;
    if (aspect) wrapper.style.aspectRatio = `${aspect}`;
    else if (height) wrapper.style.height = `${height}px`;
    else wrapper.style.aspectRatio = "1.78";

    const url = resolve(node.imageUrl ?? "", scope);
    if (url) {
        const img = document.createElement("img");
        img.src = url;
        img.alt = "";
        img.loading = "lazy";
        wrapper.appendChild(img);
    }
    const overlay = document.createElement("div");
    overlay.className = "ds-header-overlay";
    wrapper.appendChild(overlay);

    const text = document.createElement("div");
    text.className = "ds-header-text";
    const eyebrow = resolve(node.eyebrow ?? "", scope);
    if (eyebrow) {
        const e = document.createElement("span");
        e.className = "ds-header-eyebrow";
        e.textContent = eyebrow;
        text.appendChild(e);
    }
    const title = resolve(node.title ?? "", scope);
    if (title) {
        const t = document.createElement("span");
        t.className = "ds-header-title";
        t.textContent = title;
        text.appendChild(t);
    }
    wrapper.appendChild(text);

    if (node.action?.type === "navigate" && node.action.to) {
        wrapper.classList.add("ds-card-tappable");
        const a = document.createElement("a");
        a.className = "ds-header-link";
        a.href = navigateHref(node.action, scope, ctx);
        a.setAttribute("aria-label", title || "détail");
        wrapper.appendChild(a);
    }
    return wrapper;
}

// MARK: - Segmented (interactive, mirror du SegmentedBlock iOS)

function renderSegmented(node, scope, ctx) {
    const wrapper = document.createElement("div");
    wrapper.className = "ds-segmented";

    const options = node.options ?? [];
    let selectedId = node.default ?? options[0]?.id;

    const tabs = document.createElement("div");
    tabs.className = "ds-segmented-tabs";

    const content = document.createElement("div");
    content.className = "ds-segmented-content";

    function rebuild() {
        tabs.innerHTML = "";
        content.innerHTML = "";
        for (const opt of options) {
            const btn = document.createElement("button");
            btn.className = "ds-segmented-tab";
            if (opt.id === selectedId) btn.classList.add("active");
            btn.textContent = opt.label ?? opt.id;
            btn.onclick = () => {
                selectedId = opt.id;
                rebuild();
            };
            tabs.appendChild(btn);
        }
        const caseNode = node.cases?.[selectedId];
        if (caseNode) content.appendChild(render(caseNode, scope, ctx));
    }
    rebuild();

    wrapper.appendChild(tabs);
    wrapper.appendChild(content);
    return wrapper;
}

function renderTabBar(node, scope, ctx) {
    // En preview web, la tabbar = un tableau d'écrans cliquables qui recharge
    // la page sur le screen choisi. Sert au navigation entre les screens
    // déclarés dans le manifest du module.
    const wrapper = document.createElement("nav");
    wrapper.className = "ds-tabbar";
    for (const tab of node.tabs ?? []) {
        const a = document.createElement("a");
        a.className = "ds-tab";
        a.textContent = tab.title;
        a.href = "#";
        a.addEventListener("click", (e) => {
            e.preventDefault();
            ctx?.onNavigate?.(tab.screen, {});
        });
        wrapper.appendChild(a);
    }
    return wrapper;
}

function renderButton(node, scope, ctx) {
    const btn = document.createElement("button");
    btn.className = "ds-button";
    btn.textContent = resolve(node.label ?? "OK", scope);
    btn.addEventListener("click", () => {
        if (node.action?.type === "navigate" && node.action.to) {
            ctx?.onNavigate?.(node.action.to, resolveActionWith(node.action, scope));
        } else {
            alert(`Action « ${node.action?.type ?? "?"} » non simulée en preview web.`);
        }
    });
    return btn;
}

function renderUnsupported(label) {
    return () => {
        const el = document.createElement("div");
        el.className = "ds-unsupported";
        el.textContent = `(${label})`;
        return el;
    };
}

// MARK: - Calendar (mirror du CalendarBlock iOS — month grid)

function renderCalendar(node, scope, ctx) {
    const events = scope.lookup(node.in ?? "") ?? [];
    const dateField = node.dateField ?? "date";
    const exposes = node.exposes ?? "selectedEvents";

    const eventDates = new Set(
        (Array.isArray(events) ? events : [])
            .map((e) => e?.[dateField])
            .filter(Boolean)
    );

    const wrapper = document.createElement("div");
    wrapper.className = "ds-calendar";

    const today = new Date();
    let visible = new Date(today.getFullYear(), today.getMonth(), 1);
    let selected = isoDate(today);

    const chrome = document.createElement("div");
    chrome.className = "ds-calendar-chrome";
    wrapper.appendChild(chrome);

    const childWrap = document.createElement("div");
    childWrap.className = "ds-calendar-child";
    wrapper.appendChild(childWrap);

    function rebuild() {
        chrome.innerHTML = "";
        childWrap.innerHTML = "";

        // Month nav
        const head = document.createElement("div");
        head.className = "ds-calendar-head";
        const prev = document.createElement("button");
        prev.className = "ds-calendar-nav";
        prev.textContent = "‹";
        prev.onclick = () => {
            visible = new Date(visible.getFullYear(), visible.getMonth() - 1, 1);
            rebuild();
        };
        const monthLabel = document.createElement("span");
        monthLabel.className = "ds-calendar-month";
        monthLabel.textContent = visible.toLocaleDateString("fr-BE", { month: "long", year: "numeric" });
        const next = document.createElement("button");
        next.className = "ds-calendar-nav";
        next.textContent = "›";
        next.onclick = () => {
            visible = new Date(visible.getFullYear(), visible.getMonth() + 1, 1);
            rebuild();
        };
        head.appendChild(prev);
        head.appendChild(monthLabel);
        head.appendChild(next);
        chrome.appendChild(head);

        // Day-of-week headers (lundi = first, FR convention)
        const dows = document.createElement("div");
        dows.className = "ds-calendar-dows";
        for (const d of ["L", "M", "M", "J", "V", "S", "D"]) {
            const cell = document.createElement("span");
            cell.textContent = d;
            dows.appendChild(cell);
        }
        chrome.appendChild(dows);

        // Day grid
        const grid = document.createElement("div");
        grid.className = "ds-calendar-grid";
        const monthStart = new Date(visible.getFullYear(), visible.getMonth(), 1);
        // Lundi-first : JS Date.getDay() retourne 0=Dim, 6=Sam ; on convertit
        const startWeekday = (monthStart.getDay() + 6) % 7;
        const monthEnd = new Date(visible.getFullYear(), visible.getMonth() + 1, 0);
        const totalDays = monthEnd.getDate();
        // Padding gauche
        for (let i = 0; i < startWeekday; i++) {
            const empty = document.createElement("span");
            empty.className = "ds-calendar-cell empty";
            grid.appendChild(empty);
        }
        for (let day = 1; day <= totalDays; day++) {
            const date = new Date(visible.getFullYear(), visible.getMonth(), day);
            const iso = isoDate(date);
            const cell = document.createElement("button");
            cell.className = "ds-calendar-cell";
            cell.textContent = String(day);
            if (eventDates.has(iso)) cell.classList.add("has-event");
            if (iso === isoDate(today)) cell.classList.add("today");
            if (iso === selected) cell.classList.add("selected");
            cell.onclick = () => {
                selected = iso;
                rebuild();
            };
            grid.appendChild(cell);
        }
        chrome.appendChild(grid);

        // Render child with selectedEvents binding
        if (node.child) {
            const filtered = (Array.isArray(events) ? events : []).filter(
                (e) => e?.[dateField] === selected
            );
            const augmented = scope
                .adding(exposes, filtered)
                .adding(`${exposes}Count`, filtered.length)
                .adding(`${exposes}DayLabel`, longDayLabel(selected))
                .adding(`${exposes}Pre`, isoDate(today) === selected ? "Aujourd'hui" : "");
            childWrap.appendChild(render(node.child, augmented, ctx));
        }
    }
    rebuild();
    return wrapper;
}

function isoDate(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
}

function longDayLabel(iso) {
    const [y, m, d] = iso.split("-").map(Number);
    const date = new Date(y, m - 1, d);
    return date.toLocaleDateString("fr-BE", {
        weekday: "long", day: "numeric", month: "long",
    });
}

// MARK: - Map (Leaflet — preview natif iOS = MapKit, Android = stub)

let leafletPromise = null;
function ensureLeaflet() {
    if (leafletPromise) return leafletPromise;
    leafletPromise = new Promise((resolve) => {
        // CSS
        const css = document.createElement("link");
        css.rel = "stylesheet";
        css.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
        document.head.appendChild(css);
        // JS
        const script = document.createElement("script");
        script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
        script.onload = () => resolve(window.L);
        document.head.appendChild(script);
    });
    return leafletPromise;
}

function renderMap(node, scope, ctx) {
    const wrapper = document.createElement("div");
    wrapper.className = "ds-map";
    wrapper.style.height = `${node.height ?? 280}px`;
    wrapper.style.width = "100%";
    wrapper.style.borderRadius = "18px";
    wrapper.style.overflow = "hidden";

    let places = [];
    if (node.from) {
        const single = scope.lookup(node.from);
        if (single) places = [single];
    } else {
        places = scope.lookup(node.in ?? "") ?? [];
    }
    const latKey = node.latField ?? "lat";
    const lngKey = node.lngField ?? "lng";
    const catKey = node.categoryField;

    ensureLeaflet().then((L) => {
        const items = (Array.isArray(places) ? places : [])
            .map((p) => p && { lat: p[latKey], lng: p[lngKey], category: catKey ? p[catKey] : null, place: p })
            .filter((p) => p && Number.isFinite(p.lat) && Number.isFinite(p.lng));

        const center = items.length ? [items[0].lat, items[0].lng] : [50.5, 5.5];
        const map = L.map(wrapper, { zoomControl: false, attributionControl: true })
            .setView(center, 14);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            maxZoom: 19,
            attribution: "© OpenStreetMap",
        }).addTo(map);
        const bounds = [];
        for (const item of items) {
            const color = mapPinColor(item.category);
            const marker = L.circleMarker([item.lat, item.lng], {
                radius: 9,
                fillColor: color,
                color: "white",
                weight: 3,
                fillOpacity: 1,
            }).addTo(map);
            bounds.push([item.lat, item.lng]);
        }
        if (bounds.length > 1) {
            map.fitBounds(bounds, { padding: [40, 40] });
        }
        // L'init du map peut nécessiter un invalidateSize après attachement
        setTimeout(() => map.invalidateSize(), 100);
    });

    return wrapper;
}

function mapPinColor(category) {
    switch (category) {
        case "sport": return "#6B7A3D";
        case "culture": return "#C8451B";
        case "ecole": return "#6B4F8B";
        case "services": return "#2C4A6B";
        case "nature": return "#4F7B5A";
        default: return "#2C4A6B";
    }
}

// MARK: - Helpers

function navigateHref(action, scope, ctx) {
    const target = action.to;
    const args = resolveActionWith(action, scope);
    return ctx?.makeNavigateHref?.(target, args) ?? "#";
}

function resolveActionWith(action, scope) {
    const out = {};
    for (const [k, v] of Object.entries(action.with ?? {})) {
        if (typeof v === "string") out[k] = resolveValue(v, scope);
        else out[k] = v;
    }
    return out;
}

function colorVar(name) {
    switch (name) {
        case "civic": return "var(--civic-accent)";
        case "terra": return "var(--civic-terra)";
        case "secondary": return "var(--ink-2)";
        case "tertiary": return "var(--ink-3)";
        case "white": return "#fff";
        case "primary":
        default: return "var(--ink)";
    }
}

function bgVar(name) {
    switch (name) {
        case "civic-soft": return "var(--civic-accent-soft)";
        case "terra-soft": return "var(--civic-terra-soft)";
        case "civic": return "var(--civic-accent)";
        case "terra": return "var(--civic-terra)";
        case "paper": return "var(--paper)";
        case "paper-deep": return "var(--paper-deep)";
        default: return "var(--paper-deep)";
    }
}
