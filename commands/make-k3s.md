Provision a fresh k3s single-node cluster on a remote VM, with resource reservations
so the host (sshd etc.) never starves.

Arguments: `$ARGUMENTS` — the target IP, optionally followed by a VM/context name,
optionally followed by the flag `build`.
- First token = IP (required). If absent, stop and ask me.
- Second token = name for the kubeconfig context/file (optional). If omitted, the script
  uses the remote hostname.
- `build` flag (optional) = this VM is also used for Go image builds; use the
  build-VM reservation profile regardless of size.

SSH for the Step 1 detection as `ubuntu` (`ssh ubuntu@<IP>`); if that fails auth, fall
back to `root`, then `arnobkumarsaha`. The Step 3 script always connects as `ubuntu@$IP`
(hardcoded) — if only a non-`ubuntu` user works, tell me so I can adjust the script, don't
edit it silently.

## Step 1 — Detect VM resources

```bash
ssh ubuntu@<IP> 'nproc; free -g | awk "/Mem:/{print \$2}"'
```

## Step 2 — Pick the profile

Decide the reservation profile from Step 1's numbers — you pass it to the script in
Step 3 as `K3S_PROFILE` (the `build` flag maps to `K3S_PROFILE=build`):

- **small** — CPU ≤ 8 AND Mem ≤ 16Gi
- **large** — anything bigger
- **build** — if the `build` flag was passed (overrides size check)

Profiles:

| profile | system-reserved            | kube-reserved              | eviction-hard              |
|---------|----------------------------|----------------------------|----------------------------|
| small   | cpu=250m,memory=512Mi      | cpu=250m,memory=512Mi      | memory.available<500Mi     |
| large   | cpu=500m,memory=1Gi        | cpu=1000m,memory=2Gi       | memory.available<1Gi       |
| build   | cpu=4000m,memory=6Gi       | cpu=1000m,memory=2Gi       | memory.available<1Gi       |

Tell me which profile was selected and why before proceeding.

## Step 3 — Run the provisioning script (do not re-implement its logic)

Pass the Step 2 profile as `K3S_PROFILE` (defaults to `large` if unset):

```bash
K3S_PROFILE=<small|large|build> bash ~/.claude/scripts/make-k3s.bash <IP> [NAME]
```

First it checks whether the target already runs a **pristine** cluster — k3s active and
`coredns` + `local-path-provisioner` the only deployments cluster-wide, ignoring anything in
`cert-manager` and `flux-system` (leftovers from a `make-hub` run that died at the ACE
precheck). If so it skips the
recreate entirely (just refreshes the kubeconfig) and says so, because reinstalling mints a
new cluster ID and invalidates any selfhost license pinned to the old one. A profile
different from the running cluster's is warned about, not applied. Pass `K3S_FORCE=1` to
recreate anyway.

Otherwise it uninstalls any existing k3s, sets inotify limits, **writes `/etc/rancher/k3s/config.yaml`
for the chosen profile**, installs k3s (`--disable=traefik --disable=metrics-server
--tls-san <IP>`), waits for coredns, then runs `copy-kubeconfig.bash` to write
`$HOME/Downloads/configs/<NAME>.yaml`. Because the config is written *after* the uninstall
and *before* the install, k3s applies it at first start — no restart needed.
Use a long timeout (the install + coredns wait can take a few minutes). Report the script's
output verbatim; if it exits non-zero, show me the error — do not retry blindly.

## Step 4 — Verify reservations took effect

```bash
kubectl --kubeconfig $HOME/Downloads/configs/<NAME>.yaml describe node | grep -A6 'Capacity\|Allocatable'
```

Allocatable should be less than capacity by the reserved amounts. If it equals capacity,
the config.yaml wasn't picked up — show me, don't fix silently.
