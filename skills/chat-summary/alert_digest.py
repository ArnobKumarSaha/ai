#!/usr/bin/env python3
"""Parse a chat-export JSONL of Alertmanager-style Google Chat posts into a
markdown alert digest. Usage: alert_digest.py <in.jsonl> <out.md> "<period>"

JSONL line shape: {createTime, name, sender, text, thread}. Each `text` holds one
or more alert sub-blocks separated by a dashed line; each sub-block has a
`Status: 🔥 FIRING|✅ RESOLVED` line, an optional `Started At:`, and a fenced
`Labels:` block of `key: value` pairs. Alertmanager re-sends FIRING every
interval, so event counts >> incident counts — incidents are grouped by a label
fingerprint and considered OPEN when their latest event is FIRING.
"""
import sys, json, re
from collections import defaultdict, Counter

# Label that identifies the workload actually at fault, most-specific first.
# `pod`/`instance` are deprioritized: for kube-state-metrics-sourced alerts the
# `pod` label is the KSM exporter, not the affected workload.
COMPONENT_KEYS = ("statefulset", "deployment", "daemonset", "cronjob", "job_name",
                  "persistentvolumeclaim", "pod", "service", "instance")

def parse(path):
    blocks = []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        m = json.loads(line)
        text = m.get("text", "") or ""
        for part in re.split(r'\n-{10,}\n', text):
            st = re.search(r'Status:\s*\S*\s*(FIRING|RESOLVED)', part)
            if not st:
                continue
            labs = {}
            lb = re.search(r'Labels:\s*```(.*?)```', part, re.S)
            if lb:
                for ln in lb.group(1).strip().splitlines():
                    if ':' in ln:
                        k, v = ln.split(':', 1)
                        labs[k.strip()] = v.strip()
            ts = re.search(r'Started At:\s*(\S+)', part)
            blocks.append({"status": st.group(1),
                           "alertname": labs.get("alertname", "?"),
                           "ts": ts.group(1) if ts else "",
                           "recv": m.get("createTime", ""),
                           "labels": labs})
    return blocks

def component(labs):
    for k in COMPONENT_KEYS:
        if labs.get(k):
            return f"{k}={labs[k]}"
    return ""

def fingerprint(b):
    return (b["alertname"], b["labels"].get("namespace", ""), component(b["labels"]))

def main():
    path, out_path, period = sys.argv[1], sys.argv[2], sys.argv[3]
    blocks = parse(path)
    if not blocks:
        open(out_path, "w").write(f"# alert digest\n\nNo parseable alert blocks in {path}.\n")
        print("no alert blocks"); return

    fire = [b for b in blocks if b["status"] == "FIRING"]
    res  = [b for b in blocks if b["status"] == "RESOLVED"]
    groups = defaultdict(list)
    for b in blocks:
        groups[fingerprint(b)].append(b)
    latest = lambda g: sorted(g, key=lambda x: (x["recv"], x["ts"]))[-1]
    first_fire = lambda g: min((x["ts"] for x in g if x["status"] == "FIRING" and x["ts"]), default="?")
    open_inc = [(k, g) for k, g in groups.items() if latest(g)["status"] == "FIRING"]

    names = sorted({b["alertname"] for b in blocks})
    cnt = lambda n, s: sum(1 for b in blocks if b["alertname"] == n and b["status"] == s)
    inst_by = {n: sum(1 for k in groups if k[0] == n) for n in names}
    open_by = Counter(k[0] for k, _ in open_inc)
    def comps_for(n, limit=5):
        seen, ordered = set(), []
        for b in blocks:
            if b["alertname"] != n:
                continue
            c = component(b["labels"])
            if c and c not in seen:
                seen.add(c); ordered.append(c)
        extra = len(ordered) - limit
        shown = ordered[:limit]
        return ", ".join(shown) + (f" (+{extra} more)" if extra > 0 else "") if shown else "-"

    o = []
    o.append("# ace-prod-notifications — alert digest\n")
    o.append(f"**Period:** {period} · **Chat messages:** ~{sum(1 for _ in open(path))} · "
             f"**Alert events (incl. re-sends):** {len(blocks)} — {len(fire)} firing / {len(res)} resolved · times UTC\n")
    o.append(f"- Distinct alert instances: **{len(groups)}** · Currently open (last event = FIRING): **{len(open_inc)}**")
    o.append("- Alertmanager re-sends FIRING each interval, so event counts ≫ incident counts.\n")

    o.append("## By alert\n")
    o.append("| Alert | Instances | Firing | Resolved | Open | Responsible component(s) |")
    o.append("|---|--:|--:|--:|--:|---|")
    for n in sorted(names, key=lambda x: -cnt(x, "FIRING")):
        o.append(f"| {n} | {inst_by[n]} | {cnt(n,'FIRING')} | {cnt(n,'RESOLVED')} | {open_by.get(n,0)} | {comps_for(n)} |")

    o.append("\n## By severity (firing events)\n")
    for s, c in Counter(b['labels'].get('severity', '(none)') for b in fire).most_common():
        o.append(f"- {s}: {c}")

    o.append("\n## Currently open incidents\n")
    if open_inc:
        o.append("| Alert | Severity | Namespace | Component | First fired (UTC) | Re-sends |")
        o.append("|---|---|---|---|---|--:|")
        for (an, ns, comp), g in sorted(open_inc, key=lambda x: (x[0][0], x[0][1])):
            sev = latest(g)["labels"].get("severity", "")
            nf = sum(1 for x in g if x["status"] == "FIRING")
            o.append(f"| {an} | {sev} | {ns or '-'} | {comp or '-'} | {first_fire(g)} | {nf} |")
    else:
        o.append("_None open._")

    o.append("\n## Noisiest instances (most firing events)\n")
    for k, g in sorted(groups.items(), key=lambda x: -sum(1 for b in x[1] if b['status'] == 'FIRING'))[:10]:
        an, ns, comp = k
        nf = sum(1 for b in g if b['status'] == 'FIRING')
        state = "OPEN" if latest(g)["status"] == "FIRING" else "resolved"
        o.append(f"- {an} ({ns or '-'} · {comp or '-'}): {nf}× — {state}")

    open(out_path, "w").write("\n".join(o) + "\n")
    print(f"instances={len(groups)} open={len(open_inc)} events={len(blocks)} -> {out_path}")

if __name__ == "__main__":
    main()
