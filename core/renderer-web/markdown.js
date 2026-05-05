// Mini renderer markdown — couvre le sous-ensemble utilisé par les modules
// officiels et communautaires : titres `## `, gras `**...**`, italique `*...*`,
// listes `- ` ou `* `, paragraphes séparés par lignes vides, retours à la
// ligne. Pas de tableaux, pas de code blocks, pas d'images inline (les
// modules utilisent la primitive `image` à la place).
//
// Pourquoi pas markdown-it / marked en CDN ? Pas de dépendance externe pour
// la preview. Le sous-ensemble suffit (vérifié sur les modules existants).

export function renderMarkdown(src) {
    if (!src) return "";
    const escaped = escapeHtml(src);
    const blocks = escaped.split(/\n{2,}/);
    return blocks.map(renderBlock).join("\n");
}

function renderBlock(block) {
    const lines = block.split(/\n/).map((l) => l.trimEnd());
    if (lines.every((l) => /^\s*[-*]\s+/.test(l))) {
        return "<ul>" + lines.map((l) => `<li>${inline(l.replace(/^\s*[-*]\s+/, ""))}</li>`).join("") + "</ul>";
    }
    const h3 = /^###\s+(.+)/.exec(lines[0]);
    if (h3) return `<h3>${inline(h3[1])}</h3>`;
    const h2 = /^##\s+(.+)/.exec(lines[0]);
    if (h2) return `<h2>${inline(h2[1])}</h2>`;
    return "<p>" + lines.map(inline).join("<br>") + "</p>";
}

function inline(s) {
    return s
        .replace(/\*\*([^*]+?)\*\*/g, "<strong>$1</strong>")
        .replace(/\*([^*]+?)\*/g, "<em>$1</em>")
        .replace(/`([^`]+?)`/g, "<code>$1</code>");
}

function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[c]));
}
