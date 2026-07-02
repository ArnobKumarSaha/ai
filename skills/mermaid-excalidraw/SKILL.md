---
name: mermaid-excalidraw
description: Produce Excalidraw diagrams from Mermaid. Default output is a single native .excalidraw file the user just opens (no pasting), built by a bundled headless converter; falls back to a paste-ready .mmd. Use when the user wants diagrams in Excalidraw. Triggers on "mermaid for excalidraw", "excalidraw diagram", "make a diagram to insert in excalidraw", ".excalidraw file", ".mmd for excalidraw".
---

# Mermaid for Excalidraw

Two delivery modes. Default to the **.excalidraw file** (zero pasting); use the **.mmd** mode only if the converter cannot run (no Chrome / no network).

- **.excalidraw file (default)**: author the diagrams, then run the bundled `convert.mjs` to produce one native scene file the user opens with File -> Open (or drag-drop). All panels arrive at once in a grid.
- **.mmd (fallback)**: write a paste-ready `.mmd` the user pastes into the "Mermaid to Excalidraw" dialog, one diagram block at a time.

Either way, the Mermaid you author must follow the readability and compatibility rules below, because the converter uses Excalidraw's own `@excalidraw/mermaid-to-excalidraw` (identical to the dialog), so the same limits apply.

## Readability first (the diagram must be understandable at a glance)

Layout is done by dagre; too many nodes or edges produce **overlapping arrows** and an unreadable result. Optimize for clarity, not completeness:

- **Cap complexity**: aim for <= ~8 nodes and <= ~10 edges per diagram. If a concept needs more, make it a separate panel.
- **Collapse detail into node text, not into more nodes/edges.** e.g. list 5 related types as lines inside ONE node instead of 5 nodes with an arrow each. Fewer edges = far less overlap.
- **Short labels**: node title a few words; at most ~3-4 short `<br/>` lines. No sentences.
- **Short, sparse edge labels**: one or two words (`embeds`, `Clone`) or none.
- **Breathing room** via a layout init at the top of each diagram:
  `%%{init: {'flowchart': {'nodeSpacing': 60, 'rankSpacing': 90}}}%%`
  Spacing only; it is the one `%%{init}%%` allowed. Avoid `theme`/color init.
- **Minimize crossing edges**: declare nodes so arrows flow one direction; avoid back-edges to far-declared nodes.
- **Titled panels**: wrap each diagram in one `subgraph TITLE["1. Type model"] ... end` so it renders as a labeled frame. The converter grids panels by their diagram order.

## Compatibility rules (non-negotiable)

1. **Diagram type**: only `graph`/`flowchart`, `sequenceDiagram`, or `classDiagram`. Never `gantt`, `pie`, `mindmap`, `journey`, `erDiagram`, `stateDiagram`.
2. **No styling directives**: drop `classDef`, `class`, `style`, `linkStyle`, and color/theme `%%{init}%%`. The spacing init above is the only allowed init. Recolor in Excalidraw after import.
3. **No HTML formatting tags**: `<b>`, `<i>`, `<u>`, `<font>`, emoji-as-markup render literally. Keep `<br/>` only.
4. **Quote every label** with spaces, parentheses, `:`, `|`, `-`, `>`, `/`, or `<br/>`. Example: `A["Migration CR<br/>source: RDS"]`.
5. **ASCII arrows in labels**: write `->` not unicode arrows inside node text.
6. **Fan-out edges one per line**: never `A --> B & C`; write each edge on its own line.
7. **Simple node IDs**: alphanumeric/underscore, no spaces. IDs must be unique WITHIN a diagram; the converter namespaces per panel so reuse across panels is fine.

## Input file format (what convert.mjs consumes)

Write ONE `.mmd` file to `~/yamls/<kebab-name>.mmd`. Separate panels with a banner line beginning `%% ===`. The converter splits on that banner, strips `%%` comment lines (keeping the spacing `init:` line), and converts each block. Example:

```
%% ======================================================================
%% DIAGRAM 1: Type model
%% ======================================================================
%%{init: {'flowchart': {'nodeSpacing': 60, 'rankSpacing': 90}}}%%
graph TB
 subgraph P["1. Type model"]
  a1["Shared value types<br/>Endpoint, Schedule, MovementStatus"]
  a2["Migration (mv)"]
  a2 -->|embeds| a1
 end

%% ======================================================================
%% DIAGRAM 2: Runtime flow
%% ======================================================================
%%{init: {'flowchart': {'nodeSpacing': 60, 'rankSpacing': 90}}}%%
graph TB
 subgraph P["2. Runtime flow"]
  ...
 end
```

This same file also works for manual pasting (one block at a time) if the converter is unavailable.

## Procedure (default: emit .excalidraw)

1. Derive the diagrams from the source the user points at; apply the readability + compatibility rules; wrap each in a titled `subgraph`.
2. Write the `.mmd` input to `~/yamls/<kebab-name>.mmd` with banner-delimited panels.
3. Ensure the converter deps exist (one time):
   - Chrome at `/Applications/Google Chrome.app/...` (override with `CHROME_PATH`). Needs network (pulls the Excalidraw libs from esm.sh at runtime).
   - Install `puppeteer-core` into the skill dir if missing:
     `cd ~/.claude/skills/mermaid-excalidraw && [ -d node_modules/puppeteer-core ] || npm i puppeteer-core@23`
4. Run the converter:
   `node ~/.claude/skills/mermaid-excalidraw/convert.mjs ~/yamls/<kebab-name>.mmd ~/yamls/<kebab-name>.excalidraw`
5. Sanity-check the output (well-formed, no dup ids / dangling bindings), then tell the user the path and: open excalidraw.com -> hamburger menu -> Open (or drag-drop the file). Note colors are applied after import since styling was stripped.
6. If the converter fails (no Chrome / no network), fall back: tell the user the `.mmd` is paste-ready and give the dialog steps (Mermaid to Excalidraw -> paste one block -> Insert -> repeat).

## Self-check before running

- [ ] Diagram type is flowchart/sequence/class only
- [ ] <= ~8 nodes and <= ~10 edges per panel; detail inside nodes, not extra nodes/edges
- [ ] Spacing init present; no color/theme init or `classDef`/`style`
- [ ] Labels short; edge labels one or two words or none
- [ ] No `<b>`/`<i>`/emoji-markup; only `<br/>`
- [ ] Every spaced/punctuated label is quoted; no `&` fan-out
- [ ] Each panel wrapped in a titled `subgraph`; panels banner-delimited in one `~/yamls/*.mmd`
- [ ] Validate the emitted `.excalidraw`: parses as JSON, 0 duplicate ids, 0 dangling bindings
