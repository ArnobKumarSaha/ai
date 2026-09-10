#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-}"
VM="${2:-}"
IP="${3:-}"
CPU_ARG="${4:-}"
MEMORY_ARG="${5:-}"
DISK_ARG="${6:-}"

if [ -z "$NAMESPACE" ] || [ -z "$VM" ] || [ -z "$IP" ]; then
  echo "Usage: $0 <namespace> <vm-name> <ip> [cpu] [memory] [disk]" >&2
  echo "  e.g.: $0 devops kubeadm-cp 10.2.200.10 3 6Gi 30Gi" >&2
  echo "  env: VM_CPU=2 VM_MEMORY=2Gi VM_DISK=20Gi VM_IMAGE=default/image-6nwz7" >&2
  echo "       VM_PREFIX=16 VM_GATEWAY=10.2.0.1 VM_DNS=1.1.1.1,1.0.0.1 VM_IFACE=enp1s0" >&2
  echo "       VM_SSH_KEYPAIR=default/arnob-mac  VM_FORCE=1 (skip IP-in-use check)" >&2
  exit 1
fi

export KUBECONFIG="${KUBECONFIG:-$HOME/Downloads/configs/harvester-core.yaml}"

CPU="${CPU_ARG:-${VM_CPU:-2}}"
MEMORY="${MEMORY_ARG:-${VM_MEMORY:-2Gi}}"
DISK="${DISK_ARG:-${VM_DISK:-20Gi}}"

[[ "$CPU" =~ ^[0-9]+$ ]] || { echo "cpu must be a whole number of cores: $CPU" >&2; exit 1; }
# bare numbers mean GiB, so `6` and `6Gi` both work
[[ "$MEMORY" =~ ^[0-9]+$ ]] && MEMORY="${MEMORY}Gi"
[[ "$MEMORY" =~ ^[0-9]+(Mi|Gi)$ ]] || { echo "memory must look like 6Gi or 512Mi: $MEMORY" >&2; exit 1; }
[[ "$DISK" =~ ^[0-9]+$ ]] && DISK="${DISK}Gi"
[[ "$DISK" =~ ^[0-9]+(Gi|Ti)$ ]] || { echo "disk must look like 30Gi or 1Ti: $DISK" >&2; exit 1; }
IMAGE="${VM_IMAGE:-default/image-6nwz7}"
PREFIX="${VM_PREFIX:-16}"
GATEWAY="${VM_GATEWAY:-10.2.0.1}"
DNS="${VM_DNS:-1.1.1.1,1.0.0.1}"
IFACE="${VM_IFACE:-enp1s0}"
KEYPAIR="${VM_SSH_KEYPAIR:-default/arnob-mac}"
NETWORK="${VM_NETWORK:-default/vmnet}"

[[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "not an IPv4 address: $IP" >&2; exit 1; }

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || {
  echo "namespace '$NAMESPACE' does not exist" >&2; exit 1; }
kubectl get vm -n "$NAMESPACE" "$VM" >/dev/null 2>&1 && {
  echo "VM '$VM' already exists in namespace '$NAMESPACE'" >&2; exit 1; }

# The vmnet NAD has empty ipam, so nothing in-cluster tracks addresses: a static IP
# colliding with a live VM or a DHCP lease is only discoverable by looking.
if [ -z "${VM_FORCE:-}" ]; then
  INUSE=$(kubectl get vmi -A -o jsonpath="{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.interfaces[0].ipAddress}{'\n'}{end}" |
    awk -v ip="$IP" '$2 == ip { print $1 }')
  [ -z "$INUSE" ] || { echo "$IP is already assigned to VMI $INUSE" >&2; exit 1; }
  if ping -c1 -W 1000 "$IP" >/dev/null 2>&1; then
    echo "$IP answers ping - something already holds it (VM_FORCE=1 to override)" >&2
    exit 1
  fi
fi

IMAGE_NS="${IMAGE%%/*}"
IMAGE_NAME="${IMAGE##*/}"
SC=$(kubectl get virtualmachineimages.harvesterhci.io -n "$IMAGE_NS" "$IMAGE_NAME" \
  -o jsonpath='{.status.storageClassName}')
[ -n "$SC" ] || { echo "no storageClassName on image $IMAGE" >&2; exit 1; }

KEYPAIR_NS="${KEYPAIR%%/*}"
KEYPAIR_NAME="${KEYPAIR##*/}"
PUBKEY="${VM_SSH_PUBKEY:-$(kubectl get keypairs.harvesterhci.io -n "$KEYPAIR_NS" "$KEYPAIR_NAME" \
  -o jsonpath='{.spec.publicKey}')}"
[ -n "$PUBKEY" ] || { echo "no public key from keypair $KEYPAIR" >&2; exit 1; }

PVC="${VM}-disk-0"
DNS_YAML=$(printf '%s' "$DNS" | tr ',' '\n' | sed 's/^/              - /')

echo "creating $NAMESPACE/$VM  ip=$IP/$PREFIX gw=$GATEWAY  image=$IMAGE (sc=$SC)  ${CPU}cpu/${MEMORY}/${DISK}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${VM}-cloudinit
  namespace: ${NAMESPACE}
stringData:
  userdata: |
    #cloud-config
    package_update: true
    packages:
      - qemu-guest-agent
    runcmd:
      - - systemctl
        - enable
        - --now
        - qemu-guest-agent.service
    ssh_authorized_keys:
      - ${PUBKEY}
  networkdata: |
    version: 2
    ethernets:
      ${IFACE}:
        dhcp4: false
        addresses:
          - ${IP}/${PREFIX}
        routes:
          - to: default
            via: ${GATEWAY}
        nameservers:
          addresses:
${DNS_YAML}
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${VM}
  namespace: ${NAMESPACE}
  annotations:
    harvesterhci.io/vmRunStrategy: RerunOnFailure
    harvesterhci.io/volumeClaimTemplates: '[{"metadata":{"name":"${PVC}","annotations":{"harvesterhci.io/imageId":"${IMAGE}"}},"spec":{"accessModes":["ReadWriteMany"],"resources":{"requests":{"storage":"${DISK}"}},"volumeMode":"Block","storageClassName":"${SC}"}}]'
    network.harvesterhci.io/ips: '[]'
  labels:
    harvesterhci.io/creator: harvester
    harvesterhci.io/os: ubuntu
spec:
  runStrategy: RerunOnFailure
  template:
    metadata:
      labels:
        harvesterhci.io/vmName: ${VM}
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: network.harvesterhci.io/mgmt
                    operator: In
                    values:
                      - "true"
      architecture: amd64
      domain:
        cpu:
          cores: ${CPU}
          sockets: 1
          threads: 1
        devices:
          disks:
            - bootOrder: 1
              disk:
                bus: virtio
              name: disk-0
            - disk:
                bus: virtio
              name: cloudinitdisk
          interfaces:
            - bridge: {}
              model: virtio
              name: default
        features:
          acpi:
            enabled: true
        machine:
          type: q35
        memory:
          guest: ${MEMORY}
        resources:
          limits:
            cpu: "${CPU}"
            memory: ${MEMORY}
      evictionStrategy: LiveMigrateIfPossible
      networks:
        - multus:
            networkName: ${NETWORK}
          name: default
      terminationGracePeriodSeconds: 120
      volumes:
        - name: disk-0
          persistentVolumeClaim:
            claimName: ${PVC}
        - cloudInitNoCloud:
            networkDataSecretRef:
              name: ${VM}-cloudinit
            secretRef:
              name: ${VM}-cloudinit
          name: cloudinitdisk
EOF

echo "waiting for $VM to boot and answer on $IP ..."
for i in $(seq 1 60); do
  PHASE=$(kubectl get vmi -n "$NAMESPACE" "$VM" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$PHASE" = "Running" ] && ping -c1 -W 1000 "$IP" >/dev/null 2>&1; then
    echo "$VM is up at $IP after ~$((i * 10))s"
    echo "ssh ubuntu@$IP"
    exit 0
  fi
  sleep 10
done

echo "timed out after 10m; last phase='${PHASE:-<none>}'" >&2
kubectl get vm,vmi,pvc -n "$NAMESPACE" 2>&1 | grep -E "NAME|$VM" >&2
exit 1
