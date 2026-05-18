---
allowed-tools: Bash
description: "Update Go module deps, tidy, vendor, commit, push. Usage: /update-deps <org> <repo> <dep-org/dep-repo>@<ref> [...]"
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
  [kubestash]="kubestash.dev"
  [kubevault]="kubevault.dev"
  [voyagermesh]="voyagermesh.dev"
)

ARGS=($ARGUMENTS)

if [[ ${#ARGS[@]} -lt 3 ]]; then
  echo "Usage: /update-deps <org> <repo> <dep-org/dep-repo>@<ref> [...]"
  echo "Example: /update-deps kubedb installer kubedb.dev/apimachinery@master kubestash.dev/apimachinery@master"
  exit 1
fi

ORG="${ARGS[0]}"
REPO="${ARGS[1]}"
DEPS=("${ARGS[@]:2}")

ORG_PATH="${ORG_MAP[$ORG]:-}"
if [[ -z "$ORG_PATH" ]]; then
  ORG_PATH=$(find ~/go/src -maxdepth 1 -type d -iname "*${ORG}*" -printf '%f\n' 2>/dev/null | head -1)
  if [[ -z "$ORG_PATH" ]]; then
    echo "ERROR: org '$ORG' not found. Add it to ORG_MAP or check ~/go/src/"
    exit 1
  fi
fi

REPO_DIR="$HOME/go/src/$ORG_PATH/$REPO"
if [[ ! -d "$REPO_DIR" ]]; then
  echo "ERROR: repo not found: $REPO_DIR"
  exit 1
fi

cd "$REPO_DIR"

CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" == "master" ]]; then
  echo "ERROR: currently on 'master'. Checkout a working branch first."
  exit 1
fi

echo "Repo:   $REPO_DIR"
echo "Branch: $CURRENT_BRANCH"
echo ""

printf '%-45s %-20s %s\n' "MODULE" "REF" "RESULT"
printf '%-45s %-20s %s\n' "------" "---" "------"

FAILED=0
for DEP_SPEC in "${DEPS[@]}"; do
  DEP_PATH="${DEP_SPEC%%@*}"
  DEP_REF="${DEP_SPEC##*@}"
  DEP_ORG="${DEP_PATH%%/*}"
  DEP_REPO_NAME="${DEP_PATH##*/}"

  DEP_ORG_PATH="${ORG_MAP[$DEP_ORG]:-}"
  if [[ -n "$DEP_ORG_PATH" ]]; then
    MODULE_PATH="$DEP_ORG_PATH/$DEP_REPO_NAME"
  else
    MODULE_PATH="github.com/$DEP_PATH"
  fi

  if ! grep -q "$MODULE_PATH" go.mod; then
    printf '%-45s %-20s %s\n' "$MODULE_PATH" "$DEP_REF" "SKIPPED (not in go.mod)"
    continue
  fi

  if go get "$MODULE_PATH@$DEP_REF" 2>&1; then
    printf '%-45s %-20s %s\n' "$MODULE_PATH" "$DEP_REF" "OK"
  else
    printf '%-45s %-20s %s\n' "$MODULE_PATH" "$DEP_REF" "FAILED"
    FAILED=1
    break
  fi
done

if [[ "$FAILED" == "1" ]]; then
  echo ""
  echo "ERROR: go get failed. go.mod may be partially modified. Aborting."
  exit 1
fi

echo ""
echo "Running go mod tidy && go mod vendor..."
go mod tidy && go mod vendor

echo ""
git add go.mod go.sum vendor/
git commit -m "Update deps" -s

echo ""
if ! git push origin HEAD 2>&1; then
  git push --set-upstream origin "$CURRENT_BRANCH"
fi

echo ""
echo "Done. Pushed to $CURRENT_BRANCH."
```
