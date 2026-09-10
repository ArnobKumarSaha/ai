Create a Harvester VM with a pinned static IPv4, on the `harvester-core` cluster.

Arguments: `$ARGUMENTS` — `<namespace> <vm-name> <ip> [cpu] [memory] [disk]`, in that order.
- The first three are required. If any is missing, stop and ask me — do not invent a name
  or pick an IP on my behalf.
- The IP must be one I gave you. Never guess a free address.
- `cpu` (whole cores), `memory` (`6Gi`, or a bare `6` meaning GiB) and `disk` (`30Gi`, or
  a bare `30`) are optional and default to `2` / `2Gi` / `20Gi`. Those defaults are
  deliberately small — fine for a scratch box, too small for anything real. If the VM name
  suggests a Kubernetes node, a database, or another workload that will not fit and I did
  not pass sizes, say so and ask before creating. All three are fixed at creation:
  changing any of them means deleting and recreating the VM.

## Step 1 — Sanity-check the IP before creating anything

The `default/vmnet` NAD is a plain L2 bridge with `"ipam":{}` — nothing in the cluster
assigns or tracks addresses, so a static IP that collides with a live VM or an existing
DHCP lease will only show up as a duplicate-address problem later.

```bash
export KUBECONFIG=$HOME/Downloads/configs/harvester-core.yaml
kubectl get vmi -A -o 'custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IP:.status.interfaces[0].ipAddress' --no-headers | sort -t. -k3,3n -k4,4n
```

Every DHCP-assigned address observed so far sits in `10.2.0.x`–`10.2.1.x`. If the IP I
gave you falls inside that span, warn me before proceeding — it is inside the DHCP pool's
working range and will eventually collide. Addresses well above it (e.g. `10.2.200.x`) are
outside where the DHCP server has been handing out leases.

The script repeats this check itself (VMI list + ping) and refuses to run on a taken
address unless `VM_FORCE=1`. Do not set `VM_FORCE` unless I tell you to.

## Step 2 — Run the script (do not re-implement its logic)

```bash
bash ~/.claude/scripts/make-vm.bash <namespace> <vm-name> <ip> [cpu] [memory] [disk]
```

It exports `KUBECONFIG=$HOME/Downloads/configs/harvester-core.yaml` itself, then:

1. validates the IP, that the namespace exists, and that the VM name is free
2. looks up the image's storage class and my ssh public key from the Harvester keypair
3. applies a Secret (cloud-init) + VirtualMachine
4. waits up to 10 minutes for the VM to reach `Running` **and** answer ping on the IP

Defaults, override with env vars:

| var | default | |
|---|---|---|
| `VM_CPU` | `2` | the `cpu` argument wins over this |
| `VM_MEMORY` | `2Gi` | the `memory` argument wins over this |
| `VM_DISK` | `20Gi` | the `disk` argument wins over this |
| `VM_IMAGE` | `default/image-6nwz7` | ubuntu-24; storage class is derived from it |
| `VM_PREFIX` | `16` | |
| `VM_GATEWAY` | `10.2.0.1` | |
| `VM_DNS` | `1.1.1.1,1.0.0.1` | comma-separated |
| `VM_IFACE` | `enp1s0` | guest interface name the static config binds to |
| `VM_SSH_KEYPAIR` | `default/arnob-mac` | `VM_SSH_PUBKEY` overrides with a literal key |
| `VM_NETWORK` | `default/vmnet` | |

Use a long timeout — first boot plus the `qemu-guest-agent` install takes a few minutes.
Report the script's output verbatim. If it exits non-zero, show me the error; do not retry
blindly and do not fall back to creating the VM by hand.

## Step 3 — Verify

```bash
~/yamls/scripts/machine/vmip.bash <namespace> <vm-name>
ssh ubuntu@<ip> 'ip -4 -br addr show enp1s0; ip route | grep default'
```

`vmip.bash` asks the QEMU guest agent, so it only answers once cloud-init has installed
the agent — a failure here in the first couple of minutes means "not ready yet", not
"broken". The route must read `proto static`; `proto dhcp` means the network-data was
ignored and the IP is not actually pinned.

## Notes

- The VM carries `harvesterhci.io/volumeClaimTemplates`, so Harvester creates the PVC as a
  child of the VM and its cleanup finalizer removes it on delete. `kubectl delete vm` is
  enough; the cloud-init Secret is standalone and must be deleted separately.
- Static IPs only re-apply cleanly on a **new** VM. Changing the IP of an already-booted
  guest by editing its cloud-init Secret generally will not take effect — cloud-init does
  not re-render network config for an unchanged instance-id. Edit netplan in the guest.
