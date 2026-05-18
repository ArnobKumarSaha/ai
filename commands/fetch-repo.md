---
allowed-tools: Bash
description: Fetch and reset repos to a clean remote state. Usage: /fetch-repo <org> <repo1> [repo2 ...] [--branch <branch>]
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
ORG="${ARGS[0]}"
BRANCH="master"
REPOS=()

for arg in "${ARGS[@]:1}"; do
  if [[ "$arg" == "--branch" ]]; then
    NEXT_IS_BRANCH=1
  elif [[ "${NEXT_IS_BRANCH:-0}" == "1" ]]; then
    BRANCH="$arg"
    NEXT_IS_BRANCH=0
  else
    REPOS+=("$arg")
  fi
done

if [[ -z "$ORG" ]] || [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "Usage: /fetch-repo <org> <repo1> [repo2 ...] [--branch <branch>]"
  exit 1
fi

ORG_PATH="${ORG_MAP[$ORG]:-}"
if [[ -z "$ORG_PATH" ]]; then
  ORG_PATH=$(find ~/go/src -maxdepth 1 -type d -iname "*${ORG}*" -printf '%f\n' 2>/dev/null | head -1)
  if [[ -z "$ORG_PATH" ]]; then
    echo "ERROR: org '$ORG' not found. Add it to ORG_MAP or check ~/go/src/"
    exit 1
  fi
fi

BASE="$HOME/go/src/$ORG_PATH"

printf '%-30s %-15s %s\n' "REPO" "BRANCH" "OUTCOME"
printf '%-30s %-15s %s\n' "----" "------" "-------"

for REPO in "${REPOS[@]}"; do
  REPO_DIR="$BASE/$REPO"
  if [[ ! -d "$REPO_DIR" ]]; then
    printf '%-30s %-15s %s\n' "$REPO" "$BRANCH" "SKIPPED (dir not found: $REPO_DIR)"
    continue
  fi

  cd "$REPO_DIR"

  DIRTY=$(git status --short 2>/dev/null)
  if [[ -n "$DIRTY" ]]; then
    printf '%-30s %-15s %s\n' "$REPO" "$BRANCH" "WARN: local changes discarded"
  fi

  if ! git fetch --all --prune -q 2>&1; then
    printf '%-30s %-15s %s\n' "$REPO" "$BRANCH" "ERROR: git fetch failed"
    continue
  fi

  git checkout master -q 2>/dev/null || { printf '%-30s %-15s %s\n' "$REPO" "$BRANCH" "ERROR: checkout master failed"; continue; }
  git reset --hard origin/master -q

  git branch | grep -v '^\* master$' | grep -v '^  master$' | xargs -r git branch -D -q 2>/dev/null || true

  if [[ "$BRANCH" != "master" ]]; then
    if git checkout "$BRANCH" -q 2>/dev/null; then
      printf '%-30s %-15s %s\n' "$REPO" "$BRANCH" "OK"
    else
      printf '%-30s %-15s %s\n' "$REPO" "$BRANCH" "ERROR: branch '$BRANCH' not found, left on master"
    fi
  else
    printf '%-30s %-15s %s\n' "$REPO" "$BRANCH" "OK"
  fi
done
```
