---
allowed-tools: Bash
description: Fetch, reset, and clean all kubedb.dev database repos to a clean remote state. Usage: /fetch-db-repo [branch]
---

Run this bash script exactly as written. Do not explain, do not summarize — just execute it and print its output.

```bash
#!/usr/bin/env bash
set -uo pipefail

BASE="$HOME/go/src/kubedb.dev"
BRANCH="$ARGUMENTS"
BRANCH="${BRANCH// /}"
[[ -z "$BRANCH" ]] && BRANCH="master"

REPOS=(
  aerospike cassandra clickhouse db2 documentdb druid elasticsearch hanadb
  hazelcast ignite kafka mariadb memcached milvus mongodb mssqlserver mysql
  neo4j oracle percona-xtradb pgbouncer pgpool postgres proxysql qdrant
  rabbitmq redis singlestore solr weaviate zookeeper
)

printf '%-20s %-10s %s\n' "REPO" "BRANCH" "OUTCOME"
printf '%-20s %-10s %s\n' "----" "------" "-------"

for REPO in "${REPOS[@]}"; do
  REPO_DIR="$BASE/$REPO"
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    printf '%-20s %-10s %s\n' "$REPO" "$BRANCH" "SKIPPED (not found: $REPO_DIR)"
    continue
  fi

  cd "$REPO_DIR"

  DIRTY=$(git status --short 2>/dev/null)

  if ! git fetch --all --prune -q 2>&1; then
    printf '%-20s %-10s %s\n' "$REPO" "$BRANCH" "ERROR: git fetch failed"
    continue
  fi

  if ! git checkout "$BRANCH" -q 2>/dev/null; then
    printf '%-20s %-10s %s\n' "$REPO" "$BRANCH" "ERROR: checkout $BRANCH failed"
    continue
  fi

  git reset --hard "origin/$BRANCH" -q
  git clean -fdq 2>/dev/null || true

  # Delete all local branches except master and the checked-out branch
  git branch --format='%(refname:short)' \
    | grep -vxE "master|$BRANCH" \
    | xargs -r git branch -D -q 2>/dev/null || true

  if [[ -n "$DIRTY" ]]; then
    printf '%-20s %-10s %s\n' "$REPO" "$BRANCH" "OK (local changes discarded)"
  else
    printf '%-20s %-10s %s\n' "$REPO" "$BRANCH" "OK"
  fi
done
```
