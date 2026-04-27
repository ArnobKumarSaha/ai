#!/bin/bash
set -euo pipefail

 
CURRENT_DIR="$(pwd)" # Expected path pattern: ~/go/src/<org>/<repo>
GO_SRC="${HOME}/go/src/"
if [[ "${CURRENT_DIR}" != ${GO_SRC}* ]]; then
  echo "Error: Not inside ${GO_SRC}"
  exit 1
fi

RELATIVE="${CURRENT_DIR#${GO_SRC}}"
ORG="$(echo "${RELATIVE}" | cut -d'/' -f1)"
REPO="$(echo "${RELATIVE}" | cut -d'/' -f2)"

if [[ -z "${ORG}" || -z "${REPO}" ]]; then
  echo "Error: Could not parse org/repo from path: ${CURRENT_DIR}"
  exit 1
fi

SOURCE_DIR="${HOME}/go/src/github.com/Arnobkumarsaha/ai/repo/${ORG}/${REPO}"

# echo "Org  : ${ORG}"
# echo "Repo : ${REPO}"
# echo "From : ${SOURCE_DIR}"
# echo "To   : ${CURRENT_DIR}"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "Error: Source directory does not exist: ${SOURCE_DIR}"
  exit 1
fi

cp -v "${SOURCE_DIR}"/* "${CURRENT_DIR}/"
echo "Done."