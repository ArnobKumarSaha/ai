#!/usr/bin/env python3
"""Map the practice-test sections of a Cambridge IELTS book PDF. Zero tokens.

Two routes, chosen per book by probing for a text layer:

  text  -- extract_text() finds the LISTENING/READING/WRITING/SPEAKING headings.
  scan  -- no text layer, so find the printed banner box by pixel geometry: a
           solid dark centred rectangle with the section name knocked out of it
           in white. What separates it from a centred bold title is ink DENSITY
           (>0.55 inside its bounding box); a title is thin strokes on white.

Either way the four sections appear in the fixed order L, R, W, S, so their
positions alone label them -- no OCR and no vision needed.
"""
import argparse, io, json, re, sys
import numpy as np
import pdfplumber
from PIL import Image
from pypdf import PdfReader

SECTIONS = ["listening", "reading", "writing", "speaking"]
HEADING = re.compile(r"^\s*(LISTENING|READING|WRITING|SPEAKING)\s*$", re.M)

THR = 140                    # grey level below which a pixel counts as ink
TOP_FRAC = 0.45              # banners live in the upper part of the page
MIN_W, MAX_W = 0.08, 0.32    # banner width, fraction of page width
MIN_H, MAX_H = 0.012, 0.040  # banner height, fraction of page height
CENTRE_TOL = 0.06
MIN_DENSITY = 0.55           # ink fraction inside the banner's bounding box


# ---------------------------------------------------------------- route probe

def probe_route(pdf_path):
    """Return ('text'|'scan', page_count). Samples across the whole book."""
    with pdfplumber.open(pdf_path) as pdf:
        n = len(pdf.pages)
        sample = {max(0, int(n * f)) for f in (0.05, 0.2, 0.4, 0.6, 0.8)}
        textual = any(len(pdf.pages[i].chars) > 100 for i in sorted(sample))
    return ("text" if textual else "scan"), n


# ------------------------------------------------------------------ text mode

def sections_text(pdf_path):
    hits = []
    with pdfplumber.open(pdf_path) as pdf:
        for i, page in enumerate(pdf.pages, 1):
            for name in HEADING.findall(page.extract_text() or ""):
                hits.append({"physical": i, "banner": name})
    return hits


# ------------------------------------------------------------------ scan mode

def page_gray(page):
    for im in page.images:
        return np.asarray(Image.open(io.BytesIO(im.data)).convert("L"), dtype=np.uint8)
    return None


def banner(gray):
    h, w = gray.shape
    x0, x1 = int(w * 0.20), int(w * 0.80)          # a centred box lives here
    region = gray[int(h * 0.02):int(h * TOP_FRAC), x0:x1] < THR
    counts = region.sum(axis=1)
    need = w * MIN_W * 0.6                          # a filled row is mostly ink
    bands, start = [], None
    for y, c in enumerate(counts):
        if c >= need and start is None:
            start = y
        elif c < need and start is not None:
            bands.append((start, y)); start = None
    if start is not None:
        bands.append((start, len(counts)))

    for top, bot in bands:
        height = bot - top
        if not (h * MIN_H <= height <= h * MAX_H):
            continue
        block = region[top:bot]
        cols = np.flatnonzero(block.any(axis=0))
        if cols.size == 0:
            continue
        bw = cols[-1] - cols[0] + 1
        if not (w * MIN_W <= bw <= w * MAX_W):
            continue
        if abs((x0 + cols[0] + bw / 2) / w - 0.5) > CENTRE_TOL:
            continue
        density = block[:, cols[0]:cols[-1] + 1].mean()
        if density < MIN_DENSITY:
            continue
        return {"y": round((int(h * 0.02) + top) / h, 3), "w": round(bw / w, 3),
                "density": round(float(density), 2)}
    return None


def sections_scan(pdf_path, n):
    reader = PdfReader(pdf_path)
    hits = []
    for i in range(1, n + 1):
        gray = page_gray(reader.pages[i - 1])
        if gray is None:
            print(f"page {i}: no embedded image", file=sys.stderr)
            continue
        b = banner(gray)
        if b:
            b["physical"] = i
            hits.append(b)
    return hits


# --------------------------------------------------------------------- shared

def label(hits, tests, last_page):
    """Assign test/section to raw banner hits, drop back matter, close ranges."""
    for n, hit in enumerate(hits):
        hit["section"] = SECTIONS[n % 4]
        hit["test"] = n // 4 + 1
    kept = [h for h in hits if h["test"] <= tests]
    tail = [h for h in hits if h["test"] > tests]
    for n, hit in enumerate(kept):
        nxt = kept[n + 1]["physical"] if n + 1 < len(kept) else None
        if nxt is None:
            nxt = tail[0]["physical"] if tail else last_page + 1
        hit["end"] = nxt - 1
        hit["pages"] = hit["end"] - hit["physical"] + 1
    return kept, len(hits) - len(kept)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("--test", type=int, help="report only this test")
    ap.add_argument("--tests", type=int, default=4,
                    help="practice tests in the book (default 4); later banners are "
                         "back matter -- audioscripts, answer keys, sample answers")
    ap.add_argument("--printed-start", type=int,
                    help="printed folio of the selected test's first page; sets the offset")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    route, n = probe_route(args.pdf)
    raw = sections_text(args.pdf) if route == "text" else sections_scan(args.pdf, n)
    hits, dropped = label(raw, args.tests, n)
    sel = [h for h in hits if h["test"] == args.test] if args.test else hits

    offset = None
    if args.printed_start and sel:
        offset = args.printed_start - min(h["physical"] for h in sel)
        for h in sel:
            h["printed"], h["printed_end"] = h["physical"] + offset, h["end"] + offset

    if args.json:
        print(json.dumps({"pdf": args.pdf, "route": route, "pages": n,
                          "offset": offset, "sections": sel}, indent=2))
        return

    print(f"{args.pdf}: {n} pages, route={route}, {len(hits)} test banners"
          + (f" (+{dropped} back-matter ignored)" if dropped else "")
          + (f", printed offset {offset:+d}" if offset is not None else ""))
    for h in sel:
        pr = f"  printed {h['printed']:>3}-{h['printed_end']:<3}" if offset is not None else ""
        print(f"  test {h['test']:>2}  {h['section']:<10} physical {h['physical']:>3}-{h['end']:<3}"
              f"{pr}  ({h['pages']:>2} pp)")


if __name__ == "__main__":
    main()
