#!/usr/bin/env bash
# Guide steps 3-5 against the CURRENT kubectl context (assumed: ACE Observability
# cluster with TelemetryStack + MinIO CRDs already present).
#   Step 3: MinIO (ns + tls-ssl-minio secret + helm install)
#   Step 4: create the 'telemetry' bucket (port-forward + mc/aws, TLS-aware)
#   Step 5: apply the TelemetryStack manifest
set -euo pipefail

OTEL_REPO="${OTEL_REPO:-$HOME/go/src/opnpulse/otel-o11y}"
MANIFEST="${1:-$HOME/yamls/store/telemetry-stack.yaml}"

MINIO_NS="${MINIO_NS:-minio}"
MONITORING_NS="${MONITORING_NS:-monitoring}"
MINIO_SVC="${MINIO_SVC:-minio}"
MINIO_PORT="${MINIO_PORT:-9000}"
LOCAL_PORT="${LOCAL_PORT:-9000}"
BUCKET="${BUCKET:-telemetry}"
ACCESS_KEY="${ACCESS_KEY:-rootuser}"
SECRET_KEY="${SECRET_KEY:-rootpass123}"
INSTALL="${INSTALL:-1}"

TLS_SECRET="${TLS_SECRET:-tls-ssl-minio}"
PRIVATE_KEY="$OTEL_REPO/private.key"
PUBLIC_CRT="$OTEL_REPO/public.crt"
MINIO_VALUES="$OTEL_REPO/minio/minio-values.yaml"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

PF_PID=""
cleanup() { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null || true; }
trap cleanup EXIT

for f in "$PRIVATE_KEY" "$PUBLIC_CRT" "$MINIO_VALUES" "$MANIFEST"; do
  [[ -f "$f" ]] || { echo "required file not found: $f" >&2; exit 1; }
done

release_exists() { helm status "$1" -n "$2" >/dev/null 2>&1; }

# ---------------------------------------------------------------- Step 3: MinIO
log "Step 3: MinIO"

kubectl create namespace "$MINIO_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$MONITORING_NS" --dry-run=client -o yaml | kubectl apply -f -

for ns in "$MINIO_NS" "$MONITORING_NS"; do
  log "Creating secret '$TLS_SECRET' in '$ns'"
  kubectl create secret generic "$TLS_SECRET" -n "$ns" \
    --from-file=private.key="$PRIVATE_KEY" \
    --from-file=public.crt="$PUBLIC_CRT" \
    --dry-run=client -o yaml | kubectl apply -f -
done

if [[ "$INSTALL" == "1" ]]; then
  helm repo add minio-comm https://charts.min.io/ >/dev/null 2>&1 || true
  helm repo update minio-comm >/dev/null 2>&1 || true
  if release_exists minio "$MINIO_NS"; then
    log "MinIO release already present in $MINIO_NS — upgrading"
  fi
  log "helm upgrade -i minio ($MINIO_NS)"
  helm upgrade -i minio minio-comm/minio \
    --namespace "$MINIO_NS" --create-namespace \
    --set rootUser="$ACCESS_KEY" --set rootPassword="$SECRET_KEY" \
    -f "$MINIO_VALUES" --wait
else
  log "INSTALL=0 — skipping MinIO helm install"
fi

# --------------------------------------------------------- Step 4: bucket
log "Step 4: bucket '$BUCKET'"

kubectl rollout status deploy/minio -n "$MINIO_NS" --timeout=300s 2>/dev/null || true

log "Port-forwarding svc/$MINIO_SVC ($MINIO_NS) $LOCAL_PORT->$MINIO_PORT"
kubectl port-forward -n "$MINIO_NS" "svc/$MINIO_SVC" "$LOCAL_PORT:$MINIO_PORT" >/dev/null 2>&1 &
PF_PID=$!

for i in {1..20}; do
  nc -z 127.0.0.1 "$LOCAL_PORT" 2>/dev/null && break
  [[ $i -eq 20 ]] && { echo "port-forward did not come up" >&2; exit 1; }
  sleep 0.5
done

ENDPOINT="https://127.0.0.1:$LOCAL_PORT"
log "Creating bucket '$BUCKET' at $ENDPOINT (TLS, insecure)"
if command -v mc >/dev/null 2>&1; then
  mc alias set make-monitoring "$ENDPOINT" "$ACCESS_KEY" "$SECRET_KEY" --insecure >/dev/null
  mc mb --ignore-existing --insecure "make-monitoring/$BUCKET"
elif command -v aws >/dev/null 2>&1; then
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    aws --endpoint-url "$ENDPOINT" --no-verify-ssl s3 mb "s3://$BUCKET" 2>/dev/null \
    || echo "  (bucket may already exist, continuing)"
else
  echo "neither 'mc' nor 'aws' found on PATH" >&2
  exit 1
fi

# --------------------------------------------------- Step 5: TelemetryStack
log "Step 5: apply TelemetryStack ($MANIFEST)"

CLEANED="$(mktemp)"
trap 'cleanup; rm -f "$CLEANED"' EXIT
if command -v yq >/dev/null 2>&1; then
  yq -y 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation, .metadata.managedFields, .status)' \
    "$MANIFEST" > "$CLEANED"
else
  echo "yq not found — applying manifest as-is" >&2
  cp "$MANIFEST" "$CLEANED"
fi
kubectl apply -f "$CLEANED"

log "Done. TelemetryStack:"
kubectl get telemetrystack 2>/dev/null || true
