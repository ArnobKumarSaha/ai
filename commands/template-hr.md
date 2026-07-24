---
description: Extract a Flux HelmRelease's .spec.values and helm-template the chart
argument-hint: <path-to-helmrelease.yaml>
allowed-tools: Bash(yq:*), Bash(helm:*), Bash(mkdir:*), Bash(cat:*), Read
---

Given the Flux `HelmRelease` file `$ARGUMENTS` (always located in `~/yamls`), run the following. Do not improvise — run exactly this and report the output verbatim.

```bash
set -euo pipefail

HR=~/yamls/"$ARGUMENTS"
[ -f "$HR" ] || { echo "HelmRelease file not found: $HR" >&2; exit 1; }

REL=$(yq -r '.spec.releaseName' "$HR")
CHART=$(yq -r '.spec.chart.spec.chart' "$HR")
VER=$(yq -r '.spec.chart.spec.version' "$HR")
NS=$(yq -r '.spec.targetNamespace' "$HR")

for v in REL CHART VER NS; do
  [ "${!v}" != "null" ] && [ -n "${!v}" ] || { echo "missing .spec value for $v" >&2; exit 1; }
done

mkdir -p ~/yamls
VALUES=~/yamls/"$REL"-values.yaml

# 1) Extract .spec.values
yq -y '.spec.values' "$HR" > "$VALUES"
echo "wrote $VALUES"

# 2) Template the chart
helm template "$REL" \
  oci://ghcr.io/appscode-charts/"$CHART" \
  --version "$VER" \
  --namespace "$NS" \
  -f "$VALUES" > ~/yamls/tpl.yaml

echo "wrote ~/yamls/tpl.yaml ($(wc -l < ~/yamls/tpl.yaml) lines)"
```

If either `yq` or `helm` fails, stop and show the error verbatim.
