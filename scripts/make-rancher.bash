#!/usr/bin/env bash
set -euo pipefail

IP="${1:-}"
NAME="${2:-}"
SSH_USER="${SSH_USER:-ubuntu}"
K3S_VERSION="${K3S_VERSION:-v1.35.6+k3s1}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.18.6}"
RANCHER_VERSION="${RANCHER_VERSION:-2.14.3}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-}"
SKIP_K3S="${SKIP_K3S:-0}"

if [ -z "$IP" ]; then
  echo "Usage: $0 <ip> [name]" >&2
  echo "  env: SSH_USER K3S_VERSION CERT_MANAGER_VERSION RANCHER_VERSION RANCHER_HOSTNAME SKIP_K3S" >&2
  exit 1
fi
[ -n "$RANCHER_HOSTNAME" ] || RANCHER_HOSTNAME="$IP.sslip.io"

if [ -z "$NAME" ]; then
  NAME=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$IP" uname -n)
  echo "No name given; using remote hostname: $NAME"
fi

ssh -o StrictHostKeyChecking=no "$SSH_USER@$IP" 'sudo bash -s' \
  "$IP" "$K3S_VERSION" "$CERT_MANAGER_VERSION" "$RANCHER_VERSION" "$RANCHER_HOSTNAME" "$SKIP_K3S" <<'EOF'
set -euo pipefail
IP="$1"
K3S_VERSION="$2"
CERT_MANAGER_VERSION="$3"
RANCHER_VERSION="$4"
RANCHER_HOSTNAME="$5"
SKIP_K3S="$6"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ "$SKIP_K3S" != "1" ]; then
  echo "=== installing k3s $K3S_VERSION ==="
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - --tls-san "$IP"
fi
kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl get nodes

if ! command -v helm >/dev/null 2>&1; then
  echo "=== installing helm ==="
  curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 /tmp/get_helm.sh
  /tmp/get_helm.sh
fi

echo "=== installing cert-manager $CERT_MANAGER_VERSION ==="
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
helm upgrade -i cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true \
  --wait --timeout 10m
kubectl get pods --namespace cert-manager

echo "=== installing rancher $RANCHER_VERSION at $RANCHER_HOSTNAME ==="
helm upgrade -i rancher rancher-stable/rancher \
  --namespace cattle-system --create-namespace \
  --version "$RANCHER_VERSION" \
  --set hostname="$RANCHER_HOSTNAME" \
  --set ingress.ingressClassName=traefik \
  --set replicas=1 \
  --wait --timeout 15m
kubectl -n cattle-system rollout status deploy/rancher --timeout=900s
kubectl -n cattle-system get deploy rancher

echo "=== bootstrap password ==="
if kubectl -n cattle-system get secret bootstrap-secret >/dev/null 2>&1; then
  kubectl -n cattle-system get secret bootstrap-secret \
    -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'
else
  echo "bootstrap-secret not found in cattle-system; reset with:" >&2
  echo "  kubectl -n cattle-system exec deploy/rancher -- reset-password" >&2
  exit 1
fi
EOF

mkdir -p "$HOME/Downloads/configs"
OUT="$HOME/Downloads/configs/$NAME.yaml"
ssh -o StrictHostKeyChecking=no "$SSH_USER@$IP" 'sudo cat /etc/rancher/k3s/k3s.yaml' > "$OUT"
kubectl --kubeconfig "$OUT" config set-cluster default --server="https://$IP:6443"
kubectl --kubeconfig "$OUT" config rename-context default "$NAME"

echo
echo "=== Rancher deployed on $IP ==="
echo "URL: https://$RANCHER_HOSTNAME  (self-signed cert - open in unsafe mode)"
echo "Username: admin, password printed above"
echo "Kubeconfig: $OUT (context: $NAME)"
