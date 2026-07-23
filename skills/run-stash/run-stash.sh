#!/usr/bin/env bash
# Bootstrap a Stash backup demo end-to-end:
#   license-proxyserver -> MinIO -> Stash enterprise -> demo ns -> bucket -> secret -> manifest.
# Only externals: kubectl access to the cluster and the MongoDB AppBinding ('mm').
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MANIFEST="${1:-$SKILL_DIR/stash.yaml}"
NS="${NS:-demo}"
MINIO_NS="${MINIO_NS:-minio}"
MINIO_SVC="${MINIO_SVC:-minio}"
MINIO_PORT="${MINIO_PORT:-9000}"
LOCAL_PORT="${LOCAL_PORT:-9000}"
BUCKET="${BUCKET:-arnob}"
ACCESS_KEY="${ACCESS_KEY:-rootuser}"
SECRET_KEY="${SECRET_KEY:-rootpass123}"
RESTIC_PASSWORD="${RESTIC_PASSWORD:-123456}"
SECRET_NAME="${SECRET_NAME:-minio-secret}"

# install toggles / versions
INSTALL="${INSTALL:-1}"
PROXY_VERSION="${PROXY_VERSION:-v2026.2.16}"
STASH_VERSION="${STASH_VERSION:-v2025.10.17}"
MINIO_REPLICAS="${MINIO_REPLICAS:-1}"
MINIO_MEM="${MINIO_MEM:-4Gi}"
LICENSE_BASE_URL="${LICENSE_BASE_URL:-https://appscode.com}"

# license token: never hardcoded here — sourced from ~/.claude/secrets/appscode.env
SECRETS_ENV="${SECRETS_ENV:-$HOME/.claude/secrets/appscode.env}"
[[ -f "$SECRETS_ENV" ]] && source "$SECRETS_ENV"
LICENSE_TOKEN="${LICENSE_TOKEN:-${LICENSE_PROXY_TOKEN:-}}"

PF_PID=""
cleanup() {
  [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

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

  if release_exists minio "$MINIO_NS"; then
    log "MinIO already present in $MINIO_NS — skipping"
  else
    log "Installing MinIO ($MINIO_NS, replicas=$MINIO_REPLICAS)"
    helm upgrade --install minio minio-comm/minio \
      --namespace "$MINIO_NS" --create-namespace \
      --set rootUser="$ACCESS_KEY" --set rootPassword="$SECRET_KEY" \
      --set replicas="$MINIO_REPLICAS" --set mode=standalone \
      --set resources.requests.memory="$MINIO_MEM" --wait
  fi

  log "Installing Stash enterprise ($STASH_VERSION, stash ns)"
  helm upgrade --install stash oci://ghcr.io/appscode-charts/stash \
    --version "$STASH_VERSION" --namespace stash --create-namespace \
    --set features.enterprise=true --wait --burst-limit=10000 --debug
else
  log "INSTALL=0 — skipping license-proxyserver / MinIO / Stash installs"
fi

log "Creating namespace '$NS'"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

log "Port-forwarding svc/$MINIO_SVC ($MINIO_NS) $LOCAL_PORT->$MINIO_PORT"
kubectl port-forward -n "$MINIO_NS" "svc/$MINIO_SVC" "$LOCAL_PORT:$MINIO_PORT" >/dev/null 2>&1 &
PF_PID=$!

# wait for the tunnel
for i in {1..20}; do
  if nc -z 127.0.0.1 "$LOCAL_PORT" 2>/dev/null; then break; fi
  [[ $i -eq 20 ]] && { echo "port-forward did not come up" >&2; exit 1; }
  sleep 0.5
done

ENDPOINT="http://127.0.0.1:$LOCAL_PORT"
log "Creating bucket '$BUCKET' at $ENDPOINT"
if command -v mc >/dev/null 2>&1; then
  mc alias set run-stash "$ENDPOINT" "$ACCESS_KEY" "$SECRET_KEY" >/dev/null
  mc mb --ignore-existing "run-stash/$BUCKET"
elif command -v aws >/dev/null 2>&1; then
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    aws --endpoint-url "$ENDPOINT" s3 mb "s3://$BUCKET" 2>/dev/null \
    || echo "  (bucket may already exist, continuing)"
else
  echo "neither 'mc' nor 'aws' found on PATH" >&2
  exit 1
fi

log "Creating secret '$SECRET_NAME' in '$NS'"
kubectl create secret generic "$SECRET_NAME" -n "$NS" \
  --from-literal=AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
  --from-literal=RESTIC_PASSWORD="$RESTIC_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Applying manifest: $MANIFEST"
kubectl apply -f "$MANIFEST"

log "Done. Resources in '$NS':"
kubectl get repository,backupconfiguration -n "$NS" 2>/dev/null || true
