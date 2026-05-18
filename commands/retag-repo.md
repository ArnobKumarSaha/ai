---
allowed-tools: Bash
description: Force-retag repos at HEAD of master. Usage: /retag-repo <org> <tag> <repo1> [repo2 ...]
---

Run this bash script exactly as written. Do not explain, do not summarize — just execute it and print its output.

```bash
#!/usr/bin/env bash
set -euo pipefail

declare -A ORG_MAP=(
  [bytebuilders]="go.bytebuilders.dev"
  [appscode]="go.appscode.dev"
  [kubedb]="kubedb.dev"
  [opscenter]="go.opscenter.dev"
  [kubeops]="kubeops.dev"
  [kmodules]="kmodules.xyz"
  [gomodules]="gomodules.xyz"
)

ARGS=($ARGUMENTS)

if [[ ${#ARGS[@]} -lt 3 ]]; then
  echo "Usage: /retag-repo <org> <tag> <repo1> [repo2 ...]"
  exit 1
fi

ORG="${ARGS[0]}"
TAG="${ARGS[1]}"
REPOS=("${ARGS[@]:2}")

ORG_PATH="${ORG_MAP[$ORG]:-}"
if [[ -z "$ORG_PATH" ]]; then
  ORG_PATH=$(find ~/go/src -maxdepth 1 -type d -iname "*${ORG}*" -printf '%f\n' 2>/dev/null | head -1)
  if [[ -z "$ORG_PATH" ]]; then
    echo "ERROR: org '$ORG' not found. Add it to ORG_MAP or check ~/go/src/"
    exit 1
  fi
fi

BASE="$HOME/go/src/$ORG_PATH"

printf '%-30s %s\n' "REPO" "OUTCOME"
printf '%-30s %s\n' "----" "-------"

for REPO in "${REPOS[@]}"; do
  REPO_DIR="$BASE/$REPO"
  if [[ ! -d "$REPO_DIR" ]]; then
    printf '%-30s %s\n' "$REPO" "SKIPPED (dir not found: $REPO_DIR)"
    continue
  fi

  cd "$REPO_DIR"

  if ! git checkout master -q 2>&1; then
    printf '%-30s %s\n' "$REPO" "ERROR: checkout master failed"
    continue
  fi

  if ! git pull origin master -q 2>&1; then
    printf '%-30s %s\n' "$REPO" "ERROR: git pull failed"
    continue
  fi

  git tag -fa "$TAG" -m "$TAG"

  if git push origin "$TAG" -f; then
    printf '%-30s %s\n' "$REPO" "Retagged → $TAG"
  else
    printf '%-30s %s\n' "$REPO" "ERROR: push failed"
  fi
done
```
