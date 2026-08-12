#!/usr/bin/env bash
set -euo pipefail

IP="${1:-}"
URL="${2:-}"
SSH_USER="${SSH_USER:-ubuntu}"

if [ -z "$IP" ] || [ -z "$URL" ]; then
  echo "Usage: $0 <ip> <selfhost-url>" >&2
  echo "  selfhost-url: https://<host>/selfhost/<org>/<name>/<id>" >&2
  exit 1
fi

# Parse selfhost URL: https://<host>/selfhost/<org>/<name>/<id>
if [[ "$URL" =~ ^https?://([^/]+)/selfhost/([^/]+)/([^/]+)/([^/?#]+) ]]; then
  HOST="${BASH_REMATCH[1]}"
  ORG="${BASH_REMATCH[2]}"
  NAME="${BASH_REMATCH[3]}"
  ID="${BASH_REMATCH[4]}"
else
  echo "Bad selfhost URL: $URL" >&2
  exit 1
fi

# Pick creds by host
# shellcheck source=/dev/null
source ~/.claude/secrets/appscode.env
if [ "$HOST" = "appscode.ninja" ]; then
  CRED_USER="$APPSCODE_NINJA_USERNAME"; CRED_PASS="$APPSCODE_NINJA_PASSWORD"
else
  CRED_USER="$APPSCODE_PROD_USERNAME"; CRED_PASS="$APPSCODE_PROD_PASSWORD"
fi

# Fetch + decode readme (validates creds before provisioning)
README=$(curl -fsS -u "$CRED_USER:$CRED_PASS" \
  "https://$HOST/api/v1/ace-installer/installers/$NAME/$ID?org=$ORG" \
  | jq -r '.readme' | base64 -d)
if [ -z "$README" ]; then
  echo "Empty readme from API" >&2
  exit 1
fi

# Extract the cert-manager apply line
CERT_LINE=$(printf '%s\n' "$README" | grep -E 'kubectl apply -f .*cert-manager\.yaml' | head -1)
if [ -z "$CERT_LINE" ]; then
  echo "Could not find cert-manager apply line in readme" >&2
  exit 1
fi

# Extract the fenced code block under "## Deploy ACE", minus the trailing interactive watch
DEPLOY=$(printf '%s\n' "$README" | awk '
  /^## Deploy ACE/ { found=1; next }
  found && /^```/  { if (!started) { started=1; next } else { exit } }
  found && started { print }
' | grep -v '^watch ')

# Strip prose lines and the single-node-skippable LoadBalancer Service heredoc
# (make-k3s.bash always creates a single-node cluster, so that svc is never needed).
# The namespace create is the one non-idempotent step, and it aborts a retry against a
# cluster the guard kept alive, so it is rewritten to an apply.
DEPLOY=$(printf '%s\n' "$DEPLOY" | awk '
  /^Note:/ { next }
  /^Wait for/ { next }
  /^kubectl create namespace / { print $0 " --dry-run=client -o yaml | kubectl apply -f -"; next }
  /^cat <<EOF \| kubectl apply -f -$/ { in_heredoc=1; next }
  in_heredoc { if ($0 == "EOF") { in_heredoc=0 }; next }
  { print }
')
if [ -z "$DEPLOY" ]; then
  echo "Could not extract Deploy ACE block from readme" >&2
  exit 1
fi

# Create the k3s cluster
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_USER="$SSH_USER" bash "$SCRIPT_DIR/make-k3s.bash" "$IP"

# Deploy ACE on the VM
ssh -o StrictHostKeyChecking=no "$SSH_USER@$IP" 'sudo bash -s' <<EOF
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

$CERT_LINE

mkdir -p ~/ace && cd ~/ace

$DEPLOY
EOF

echo
echo "=== ACE deployed on $IP ==="
printf '%s\n' "$README" | awk '
  /## Site Admin Credentials/ { f=1; next }
  f && /username:/ { print }
  f && /password:/ { print; exit }
'
echo "Access: https://$IP (self-signed cert)"
