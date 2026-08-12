#!/usr/bin/env bash
set -euo pipefail

IP="${1:-}"
NAME="${2:-}"
PROFILE="${K3S_PROFILE:-large}"
SSH_USER="${SSH_USER:-ubuntu}"

if [ -z "$IP" ]; then
  echo "Usage: $0 <ip> [name]   (K3S_PROFILE=small|large|build, default large)" >&2
  exit 1
fi

case "$PROFILE" in small|large|build) ;; *)
  echo "Invalid K3S_PROFILE=$PROFILE (want small|large|build)" >&2; exit 1 ;;
esac

if [ -z "$NAME" ]; then
  NAME=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$IP" uname -n)
  echo "No name given; using remote hostname: $NAME"
fi

COPY_KUBECONFIG="$HOME/yamls/scripts/machine/copy-kubeconfig.bash"

# Reinstalling mints a new kube-system UID, and selfhost licenses are pinned to it.
# So an already-running cluster carrying nothing but the k3s built-ins is left alone.
# cert-manager and flux-system are ignored too: a make-hub run that dies at the ACE
# precheck leaves them behind, and wiping on the retry would void the fresh license.
if [ -z "${K3S_FORCE:-}" ]; then
  PRISTINE=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$IP" 'sudo bash -s' <<'EOF' || true
set -uo pipefail
systemctl is-active --quiet k3s || exit 0
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
DEPLOYS=$(kubectl get deploy -A --no-headers -o custom-columns=:metadata.namespace,:metadata.name 2>/dev/null |
  awk '$1 != "cert-manager" && $1 != "flux-system" { print $2 }' | sort | tr '\n' ' ')
[ "$DEPLOYS" = "coredns local-path-provisioner " ] || exit 0
echo "pristine $(sed -n 's/^ *# \([a-z]*\):.*/\1/p' /etc/rancher/k3s/config.yaml 2>/dev/null | head -1)"
EOF
)
  if [ "${PRISTINE%% *}" = pristine ]; then
    INSTALLED="${PRISTINE#pristine}"; INSTALLED="${INSTALLED# }"
    if [ -n "$INSTALLED" ] && [ "$INSTALLED" != "$PROFILE" ]; then
      echo "Warning: running cluster uses profile '$INSTALLED', requested '$PROFILE'; keeping existing reservations" >&2
    fi
    echo "k3s already running and pristine on $IP; skipping recreate (K3S_FORCE=1 to override)"
    REMOTE_USER="$SSH_USER" "$COPY_KUBECONFIG" "$IP" "$NAME"
    echo "k3s ready on $IP (context: $NAME)"
    exit 0
  fi
fi

ssh -o StrictHostKeyChecking=no "$SSH_USER@$IP" 'sudo bash -s' "$IP" "$PROFILE" <<'EOF'
set -euo pipefail
IP="$1"
PROFILE="$2"

/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true

grep -q 'fs.inotify.max_user_instances=100000' /etc/sysctl.conf || \
  echo 'fs.inotify.max_user_instances=100000' >> /etc/sysctl.conf
grep -q 'fs.inotify.max_user_watches=100000' /etc/sysctl.conf || \
  echo 'fs.inotify.max_user_watches=100000' >> /etc/sysctl.conf

# Caps how much acknowledged-but-unwritten data a hard VM power-off can lose.
# Defaults (20% dirty_ratio, 30s expiry) leave GBs of the kine SQLite store in
# page cache; a Harvester force-off can then bring the datastore back corrupt.
# Skipped on build VMs, where bursty image-build writes want the wider window.
if [ "$PROFILE" != build ]; then
  grep -q 'vm.dirty_background_bytes=' /etc/sysctl.conf || \
    echo 'vm.dirty_background_bytes=268435456' >> /etc/sysctl.conf
  grep -q 'vm.dirty_bytes=' /etc/sysctl.conf || \
    echo 'vm.dirty_bytes=1073741824' >> /etc/sysctl.conf
  grep -q 'vm.dirty_expire_centisecs=' /etc/sysctl.conf || \
    echo 'vm.dirty_expire_centisecs=500' >> /etc/sysctl.conf
fi
sysctl -p

case "$PROFILE" in
  small) SYS="cpu=250m,memory=512Mi";  KUBE="cpu=250m,memory=512Mi";  EVICT="memory.available<500Mi" ;;
  large) SYS="cpu=500m,memory=1Gi";    KUBE="cpu=1000m,memory=2Gi";   EVICT="memory.available<1Gi" ;;
  build) SYS="cpu=4000m,memory=6Gi";   KUBE="cpu=1000m,memory=2Gi";   EVICT="memory.available<1Gi" ;;
esac
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<CFG
kubelet-arg:
  # $PROFILE:
  - "system-reserved=$SYS"
  - "kube-reserved=$KUBE"
  - "eviction-hard=$EVICT"
CFG

# Written before the install so the k3s installer's daemon-reload picks it up.
# The 90s default can SIGKILL k3s mid-write to the datastore on a normal reboot.
mkdir -p /etc/systemd/system/k3s.service.d
cat > /etc/systemd/system/k3s.service.d/shutdown.conf <<'DROPIN'
[Service]
TimeoutStopSec=300
DROPIN

cat > /usr/local/bin/k3s-safe-shutdown <<'SHUT'
#!/usr/bin/env bash
set -euo pipefail
systemctl stop k3s
/usr/local/bin/k3s-killall.sh 2>/dev/null || true
sync
echo "k3s stopped and disks flushed; safe to power off the VM"
SHUT
chmod +x /usr/local/bin/k3s-safe-shutdown

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--disable=traefik --disable=metrics-server" sh -s - --tls-san "$IP"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl wait --for=create -n kube-system deploy/coredns --timeout=60s
kubectl -n kube-system rollout status deploy/coredns --timeout=300s
EOF

REMOTE_USER="$SSH_USER" "$COPY_KUBECONFIG" "$IP" "$NAME"

echo "k3s ready on $IP (context: $NAME)"
