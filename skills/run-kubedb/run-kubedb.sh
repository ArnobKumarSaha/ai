#!/usr/bin/env bash
# Bootstrap a KubeDB MongoDB demo end-to-end:
#   license-proxyserver -> KubeDB -> demo ns -> MongoDB manifest.
# The kubestash-catalog is disabled when Stash is already installed (helm ls -n stash stash),
# enabled otherwise. Only external: kubectl access to the cluster.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MANIFEST="${1:-$SKILL_DIR/mongodb.yaml}"
NS="${NS:-demo}"

# install toggles / versions
INSTALL="${INSTALL:-1}"
PROXY_VERSION="${PROXY_VERSION:-v2026.2.16}"
KUBEDB_VERSION="${KUBEDB_VERSION:-v2026.6.19}"
LICENSE_BASE_URL="${LICENSE_BASE_URL:-https://appscode.com}"

# license token: never hardcoded here — sourced from ~/.claude/secrets/appscode.env
SECRETS_ENV="${SECRETS_ENV:-$HOME/.claude/secrets/appscode.env}"
[[ -f "$SECRETS_ENV" ]] && source "$SECRETS_ENV"
LICENSE_TOKEN="${LICENSE_TOKEN:-${LICENSE_PROXY_TOKEN:-}}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# helm release present in a namespace?
release_exists() { helm status "$1" -n "$2" >/dev/null 2>&1; }

[[ -f "$MANIFEST" ]] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

if [[ "$INSTALL" == "1" ]]; then
  if release_exists license-proxyserver kubeops; then
    log "license-proxyserver already present in kubeops — skipping"
  else
    [[ -n "$LICENSE_TOKEN" ]] || {
      echo "LICENSE_PROXY_TOKEN not set (expected in $SECRETS_ENV). Set INSTALL=0 to skip installs." >&2
      exit 1
    }
    log "Installing license-proxyserver (kubeops)"
    helm upgrade --install license-proxyserver \
      oci://ghcr.io/appscode-charts/license-proxyserver --version "$PROXY_VERSION" \
      --namespace kubeops --create-namespace --wait --debug --burst-limit=1000 \
      --set platform.baseURL="$LICENSE_BASE_URL" \
      --set platform.token="$LICENSE_TOKEN"
  fi

  # Stash present? -> don't install the kubestash catalog (avoid conflict). Absent -> install it.
  if release_exists stash stash; then
    CATALOG="false"
    log "Stash detected (helm ls -n stash stash) — kubedb-kubestash-catalog=false"
  else
    CATALOG="true"
    log "Stash not found — kubedb-kubestash-catalog=true"
  fi

  log "Installing KubeDB ($KUBEDB_VERSION, kubedb ns)"
  helm upgrade --install kubedb oci://ghcr.io/appscode-charts/kubedb \
    --version "$KUBEDB_VERSION" --namespace kubedb --create-namespace \
    --wait --timeout=15m --burst-limit=10000 --debug \
    --set kubedb-kubestash-catalog.enabled="$CATALOG"
else
  log "INSTALL=0 — skipping license-proxyserver / KubeDB installs"
fi

log "Creating namespace '$NS'"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

log "Applying manifest: $MANIFEST"
kubectl apply -f "$MANIFEST"

log "Done. Resources in '$NS':"
kubectl get mongodb -n "$NS" 2>/dev/null || true
