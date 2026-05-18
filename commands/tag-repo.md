---
allowed-tools: Bash
description: Tag repos with a new semver tag. Usage: /tag-repo <org> <tag> <repo1> [repo2 ...]
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
  echo "Usage: /tag-repo <org> <tag> <repo1> [repo2 ...]"
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
BRANCH="arnob-${TAG}"

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

  if [[ -f "$REPO_DIR/package.json" ]]; then
    VERSION="${TAG#v}"

    git checkout -b "$BRANCH"

    tmp=$(mktemp)
    jq --arg v "$VERSION" '.version = $v' package.json > "$tmp" && mv "$tmp" package.json

    if ! npm i; then
      printf '%-30s %s\n' "$REPO" "ERROR: npm i failed"
      git checkout master -q
      git branch -D "$BRANCH" 2>/dev/null || true
      continue
    fi

    git add package.json package-lock.json 2>/dev/null || git add package.json
    git commit -s -m "Update to ${TAG}"
    git push origin "$BRANCH"

    PR_URL=$(gh pr create \
      --title "Update to ${TAG}" \
      --body "Bump version to ${TAG}" \
      --base master \
      --head "$BRANCH" 2>&1) && \
      printf '%-30s %s\n' "$REPO" "PR: $PR_URL" || \
      printf '%-30s %s\n' "$REPO" "ERROR: pr create failed — branch: $BRANCH"

  else
    if git tag "$TAG" -m "$TAG" 2>/dev/null; then
      if git push origin "$TAG"; then
        printf '%-30s %s\n' "$REPO" "Tagged → $TAG"
      else
        printf '%-30s %s\n' "$REPO" "ERROR: push failed"
      fi
    else
      printf '%-30s %s\n' "$REPO" "ERROR: tag exists — use /retag-repo"
    fi
  fi
done
```
