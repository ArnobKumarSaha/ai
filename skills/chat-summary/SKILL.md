---
name: chat-summary
description: >
  Summarize a Google Chat space over a time period using the chat-export binary.
  Fetches messages since a start time, then produces either a categorized alert
  digest (categories, counts, still-unresolved via FIRING/RESOLVED pairing) when
  the space is an alert feed, or a general prose summary otherwise.
  Triggers on: "summarize google chat", "chat summary", "summarize ace-prod-notifications",
  "alert digest", "summarize the alerts since ...".
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
---

# chat-summary

Wraps the globally-installed `chat-export` binary: fetch messages → classify the
feed → write a markdown summary (alert digest or prose).

## Constants

```
CRED=~/.claude/secrets/chat-export-oauth.json   # OAuth client (client_id + client_secret)
DEFAULT_SPACE=spaces/AAQAeVUIeeE                 # ace-prod-notifications
```

`$CRED` is the Google OAuth client-secret JSON, kept in `~/.claude/secrets/`
(outside version control). If missing, ask me for its location.

Dhaka tz is `+06:00`. The binary filters only on `--after` (no upper bound), so
summaries are always open-to-now.

## Step 1 — Inputs

- **Space**: default `$DEFAULT_SPACE`. For another space whose ID you don't know,
  run `chat-export --credentials "$CRED" --list-spaces` (tab-separated
  `name<TAB>type<TAB>displayName`) and pick the match.
- **`--after`** (required): convert relative periods to RFC3339 `+06:00` via BSD
  `date`, e.g. `date -v-3d "+%Y-%m-%dT%H:%M:%S+06:00"`. If none given, ask.

## Step 2 — Export

```bash
OUT=~/yamls/chat-$(echo "$SPACE" | tr '/' '-')-$(date +%Y%m%d-%H%M%S).jsonl
chat-export --credentials "$CRED" --space "$SPACE" --after "$AFTER" --format jsonl --out "$OUT"
wc -l "$OUT"
```

On auth errors (`invalid_grant`, revoked/expired token, or a hang waiting for the
browser), `rm ~/.config/chat-export/token.json` and rerun to retrigger OAuth — the
first run on a machine always needs this. Surface it; don't silently retry.

If `wc -l` is 0, report "no messages in this period" and stop.

## Step 3 — Classify

Read the JSONL. **Alert feed** if most messages are app/webhook posts (empty
`sender.displayName`, `sender.name` like `users/...`) or `text` has
`[FIRING]`/`[RESOLVED]`/label blocks (`alertname=`, `severity=`, `namespace=`).
Else **general chat**. Triage: `jq -r '.text' "$OUT" | grep -cE '\[(FIRING|RESOLVED)\]'`
vs total lines. State the verdict in one line.

## Step 4a — Alert feed → digest

Run the bundled parser — it handles the message shape (multiple `Status:`/`Labels:`
sub-blocks per message split on dashed lines), so don't re-derive it:

```bash
python3 "$(dirname "$0")/alert_digest.py" "$OUT" \
  ~/yamls/summary-<spaceid>-$(date +%Y%m%d).md \
  "<after> → now (Dhaka +06:00)"
```

(`$0` won't resolve in this skill context — use the absolute path
`~/.claude/skills/chat-summary/alert_digest.py`.)

Key facts the script encodes, in case you parse manually:
- **Re-sends**: Alertmanager resends `FIRING` every interval, so event counts ≫
  incidents. Group by fingerprint = (alertname, namespace, responsible component)
  and treat an incident as **open** when its *latest* event is FIRING — never
  `count(firing) - count(resolved)`.
- **Responsible component**: pick the most-specific workload label present, in
  order `statefulset > deployment > daemonset > cronjob > job_name >
  persistentvolumeclaim > pod > service > instance`. `pod`/`instance` are last
  because for kube-state-metrics-sourced alerts the `pod` label is the KSM
  exporter, not the workload at fault.

Output sections: header (counts, open count), By-alert table (instances/firing/
resolved/open + up to 5 responsible components), severity breakdown, open-incidents
table, noisiest instances. Edit `alert_digest.py` to adjust — don't reinvent inline.

## Step 4b — General chat → prose

Group by thread/topic. Bullets: key points & decisions, open questions, action
items (owner if known), participants.

## Step 5 — Output

Write `~/yamls/summary-<spaceid>-<YYYYMMDD>.md` (spaceid = part after `spaces/`). Print
the path and a short preview (counts table or top bullets). `createTime` values
are UTC — note that in the file.
