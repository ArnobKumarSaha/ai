// Convert a multi-diagram Mermaid file into a single native .excalidraw scene.
// Usage: node convert.mjs <input.mmd> [output.excalidraw]
// Diagrams in the input are separated by a banner line starting with "%% ===".
// Each diagram should be wrapped in a titled `subgraph` so it renders as a labeled panel.
// Requires puppeteer-core (installed locally in this skill dir) and Google Chrome.
import puppeteer from "puppeteer-core";
import { readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";

const input = process.argv[2];
if (!input) { console.error("usage: node convert.mjs <input.mmd> [output.excalidraw]"); process.exit(1); }
const output = process.argv[3] || input.replace(/\.[^.]+$/, "") + ".excalidraw";
const CHROME = process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// Split on banner lines ("%% ===..."); keep chunks that contain a diagram.
const raw = readFileSync(input, "utf8");
const diagrams = raw
  .split(/^%%\s*=+.*$/m)
  .map((c) => c.split("\n").filter((l) => !/^\s*%%/.test(l) || /init:/.test(l)).join("\n").trim())
  .filter((c) => /\b(graph|flowchart|sequenceDiagram|classDiagram)\b/.test(c));
if (!diagrams.length) { console.error("no diagrams found in", input); process.exit(1); }

// Headless Chrome lacks Excalidraw's handwriting font, so mermaid under-measures
// text width (labels clip) and leaves <br> literal. Fix both: <br> -> newline, then
// recompute text size with a generous factor and grow containers (center kept, so
// bound arrows re-anchor on load).
function fixText(els) {
  const byId = new Map(els.map((e) => [e.id, e]));
  const CHARW = 0.64, LH = 1.25, PAD = 18;
  for (const e of els) {
    if (e.type !== "text") continue;
    const clean = (s) => (s || "").replace(/<br\s*\/?>/gi, "\n");
    e.text = clean(e.text);
    e.originalText = clean(e.originalText);
    e.lineHeight = e.lineHeight || LH;
    const lines = e.text.split("\n");
    const tw = Math.max(...lines.map((l) => l.trim().length)) * e.fontSize * CHARW;
    const th = lines.length * e.fontSize * e.lineHeight;
    const oldW = e.width, oldH = e.height;
    e.width = tw; e.height = th;
    const c = e.containerId && byId.get(e.containerId);
    if (c && e.verticalAlign === "top") {
      // subgraph frame title: keep at the top, horizontally centered; never resize the frame
      e.x = c.x + (c.width - tw) / 2; e.y = c.y + 8;
    } else if (c) {
      // node label: grow container to fit, keep its center so bound arrows re-anchor
      const nw = Math.max(c.width, tw + 2 * PAD), nh = Math.max(c.height, th + 2 * PAD);
      c.x -= (nw - c.width) / 2; c.y -= (nh - c.height) / 2;
      c.width = nw; c.height = nh;
      e.x = c.x + (c.width - tw) / 2; e.y = c.y + (c.height - th) / 2;
    } else {
      e.x -= (tw - oldW) / 2; e.y -= (th - oldH) / 2;
    }
  }
  return els;
}

function remap(elements, i) {
  const idMap = new Map(), gMap = new Map();
  const nid = (id) => id == null ? id : (idMap.has(id) ? idMap.get(id) : idMap.set(id, `${id}_p${i}`).get(id));
  const ngid = (g) => gMap.has(g) ? gMap.get(g) : gMap.set(g, `${g}_p${i}`).get(g);
  for (const e of elements) nid(e.id);
  for (const e of elements) {
    e.id = nid(e.id);
    if (e.containerId) e.containerId = nid(e.containerId);
    if (e.frameId) e.frameId = nid(e.frameId);
    if (Array.isArray(e.groupIds)) e.groupIds = e.groupIds.map(ngid);
    if (Array.isArray(e.boundElements)) e.boundElements = e.boundElements.map((b) => ({ ...b, id: nid(b.id) }));
    if (e.startBinding?.elementId) e.startBinding.elementId = nid(e.startBinding.elementId);
    if (e.endBinding?.elementId) e.endBinding.elementId = nid(e.endBinding.elementId);
  }
  return elements;
}
function bbox(els) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const e of els) {
    minX = Math.min(minX, e.x); minY = Math.min(minY, e.y);
    maxX = Math.max(maxX, e.x + (e.width || 0)); maxY = Math.max(maxY, e.y + (e.height || 0));
  }
  return { minX, minY, w: maxX - minX, h: maxY - minY };
}

const browser = await puppeteer.launch({ executablePath: CHROME, headless: "new" });
const page = await browser.newPage();
page.on("pageerror", (e) => console.error("[page]", e.message));
await page.goto("https://esm.sh/", { waitUntil: "domcontentloaded" });

const converted = [];
for (const def of diagrams) {
  const els = await page.evaluate(async (d) => {
    const mmMod = await import("https://esm.sh/@excalidraw/mermaid-to-excalidraw@1.1.2");
    const exMod = await import("https://esm.sh/@excalidraw/excalidraw@0.17.6");
    const mm = mmMod.parseMermaidToExcalidraw ? mmMod : mmMod.default;
    const ex = exMod.convertToExcalidrawElements ? exMod : exMod.default;
    const { elements } = await mm.parseMermaidToExcalidraw(d, { flowchart: { curve: "linear" } });
    return JSON.parse(JSON.stringify(ex.convertToExcalidrawElements(elements)));
  }, def);
  converted.push(els);
}
await browser.close();

const GAPX = 160, GAPY = 140, cols = 2;
const norm = converted.map((els, i) => {
  fixText(els);
  const b = bbox(els);
  for (const e of els) { e.x -= b.minX; e.y -= b.minY; }
  return { els: remap(els, i), w: b.w, h: b.h };
});
const colW = Math.max(...norm.map((n) => n.w));
const rowH = [];
for (let r = 0; r * cols < norm.length; r++)
  rowH[r] = Math.max(...norm.slice(r * cols, r * cols + cols).map((n) => n.h));
const all = [];
norm.forEach((n, i) => {
  const ox = (i % cols) * (colW + GAPX);
  const oy = rowH.slice(0, Math.floor(i / cols)).reduce((s, h) => s + h + GAPY, 0);
  for (const e of n.els) { e.x += ox; e.y += oy; }
  all.push(...n.els);
});

writeFileSync(output, JSON.stringify({
  type: "excalidraw", version: 2, source: "mmd2excal",
  elements: all, appState: { gridSize: null, viewBackgroundColor: "#ffffff" }, files: {},
}, null, 2));
console.log(`wrote ${all.length} elements (${diagrams.length} panels) to ${output}`);
