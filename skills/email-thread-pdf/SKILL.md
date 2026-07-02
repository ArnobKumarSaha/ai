---
name: email-thread-pdf
description: >
  Extract the unique top-level messages from a Gmail-print email-thread PDF,
  discarding the quoted history that Gmail repeats under every message. Turns a
  hundreds-of-pages "print all" export of an N-message thread back into N messages,
  each with sender, date, and only its new content. Use this whenever asked to read,
  summarize, or pull replies/issues out of an exported email-thread PDF.
  Triggers on: "email thread pdf", "extract messages from this email pdf",
  "gmail thread export", "too many repeated/quoted messages in the pdf",
  "top-level messages", "deduplicate the email pdf".
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
---

# email-thread-pdf

Gmail's "print all" export quotes the entire prior thread under every message, so a
small thread becomes hundreds of pages of near-duplicate text — too big and too noisy
to read directly. The bundled `extract_thread.py` keeps only each message's **new
content** (the part above its first quoted block) plus the sender and date.

This skill is generic: it does not know or care about any specific people, companies,
or subjects.

## Step 1 — Ensure PyMuPDF is available

The script needs `fitz` (PyMuPDF). On a managed Python, install into a throwaway venv
in the scratchpad (never `--break-system-packages` the system Python):

```bash
VENV=<scratchpad>/venv
python3 -m venv "$VENV" && "$VENV/bin/pip" install -q pymupdf
PY="$VENV/bin/python"
```

If a venv already exists, reuse it. If `python3 -c "import fitz"` already works, just
use `PY=python3`.

## Step 2 — Run the extractor

```bash
$PY ~/.claude/skills/email-thread-pdf/extract_thread.py "<thread.pdf>" \
    --format md -o "<scratchpad>/thread.md"
```

- `--format md` (default): one `## [i] Author — date` section per message — best for
  reading/skimming.
- `--format json`: list of `{index, author, email, date, text}` — best when you then
  need to filter (e.g. "only messages from X and the replies to them") or post-process.
- `--format txt`: compact `===== [i] Author <email> | date =====` blocks.

It prints a per-author message count to stderr. Skim that first to sanity-check the
parse (e.g. message totals look right, expected senders present).

## Step 3 — Use the result

Read the output file (it is small now) and do whatever was asked — summarize, filter
by sender, build an issue/reply table, etc. Quote messages faithfully; do not invent
replies that the thread doesn't contain.

## How detection works (for when a PDF doesn't parse)

Each top-level Gmail message header is three lines (blank lines may be interleaved):

```
<Name> <email>
<Weekday, Mon D, YYYY [at H:MM AM/PM]>
To: ...
```

The script anchors on the `To:` line and walks up (skipping blanks) to the date and
sender. It rejects quoted Outlook blocks (a `To:` whose sender line is itself preceded
by a `Sent:` line). A message's new content ends at the first quote marker below it —
a `From:`/`Sent:` block or an `On <date> ... wrote:` line — and trailing signature /
contact blocks plus `[Quoted text hidden]` markers are stripped.

**Truncated/empty dates are reconstructed automatically.** Gmail's layout can clip
late-thread header dates to `Mon, Ju`, `Th`, or even empty, which would otherwise be
missed or undated. The script rebuilds them from the full dates surviving in the quoted
history (`On <date> at <time> ... wrote:` and Outlook `Sent: <date>` blocks), auto-
detecting the recipient/sender timezone offset by matching messages that carry both
forms. Exact times appear only when known from a Gmail `On ... wrote:` line; otherwise
the calendar date alone is shown. Always skim the stderr per-author counts and the tail
dates to confirm nothing looks off.

Known limitations — if the output looks wrong, inspect the raw extracted text and
adjust the script (`find_headers`, `extract_body`, or the chrome filters in
`clean_lines`):

- **Recipient lists leaking into the body.** Wrapped `Cc:` lines that lead a message
  are skipped heuristically; a body that genuinely opens with an email address may
  lose its first line.
- **Non-Gmail layouts** (Outlook, mbox-to-PDF, scanned mail) use different headers and
  won't match — the script exits telling you to adjust `find_headers`.
- This relies on the PDF having a real text layer. Scanned/image-only PDFs need OCR
  first.
