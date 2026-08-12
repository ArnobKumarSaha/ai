#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
ITEMS=(scripts commands skills CLAUDE.md settings.json)

MODE="${1:-}"
case "${MODE}" in
  pull) SRC="${CLAUDE_DIR}"; DST="${REPO_DIR}" ;;
  push) SRC="${REPO_DIR}"; DST="${CLAUDE_DIR}" ;;
  *)
    echo "Usage: $(basename "$0") pull|push"
    echo "  pull: ${CLAUDE_DIR} -> ${REPO_DIR}"
    echo "  push: ${REPO_DIR} -> ${CLAUDE_DIR}"
    exit 1
    ;;
esac

for item in "${ITEMS[@]}"; do
  if [[ ! -e "${SRC}/${item}" ]]; then
    echo "skip: ${SRC}/${item} (not found)"
    continue
  fi
  if [[ -d "${SRC}/${item}" ]]; then
    rsync -a --delete "${SRC}/${item}/" "${DST}/${item}/"
  else
    cp "${SRC}/${item}" "${DST}/${item}"
  fi
  echo "synced: ${item}"
done

echo "Done: ${MODE} (${SRC} -> ${DST})"
