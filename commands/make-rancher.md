---
description: Provision a k3s cluster on a remote VM and install Rancher (cert-manager + rancher-stable) on it
argument-hint: <ip> [name]
allowed-tools: Bash(bash ~/.claude/scripts/make-rancher.bash:*)
---

Set up a single-node Rancher management cluster on a remote VM, per
`testplan/rancher-provider.md` section 1 ("Rancher Cluster Creation") in
appscode-cloud/launchpad. Only that section — importing an existing cluster into Rancher
and importing the Rancher cluster into ByteBuilders are manual/API steps, not covered here.

Arguments: `$ARGUMENTS` — the target VM IP, optionally followed by a context name.
Examples:
- "make a rancher on 74.207.230.106"
- "/make-rancher 10.2.0.180 rancher-mgmt"

Parse `IP` = the IPv4 address (required; if missing, stop and ask me) and `NAME` = the
kubeconfig context/file name (optional, defaults to the remote hostname).

Run the script (do not re-implement its logic, and do not run the steps by hand over ssh):

```
bash ~/.claude/scripts/make-rancher.bash <IP> [NAME]
```

The script SSHes in once as `ubuntu` (`sudo bash -s`) and, with
`KUBECONFIG=/etc/rancher/k3s/k3s.yaml`:
- installs k3s `v1.35.6+k3s1` via `get.k3s.io` with `--tls-san <IP>`. This is not
  `make-k3s.bash`: **traefik stays enabled** and serves the Rancher ingress, and there are no
  resource reservations.
- installs helm via `get-helm-3`, only if `helm` is missing.
- installs cert-manager `v1.18.6` as one chart with `--set crds.enabled=true`. The doc applies
  v1.0.4 CRDs and then chart v1.7.1; that mismatch fails, so the versions are made consistent.
- installs rancher `2.14.3` from `rancher-stable` with `hostname=<IP>.sslip.io`,
  `ingress.ingressClassName=traefik`, and `replicas=1` (single node; chart default is 3), then
  waits on the `rancher` deployment rollout. The doc's `global.cattle.psp.enabled=false` is
  dropped: PodSecurityPolicy is gone from k8s 1.25+ and from Rancher 2.9+, so the flag is dead.
- prints the `bootstrap-secret` password.
- then, locally, writes `~/Downloads/configs/<NAME>.yaml` — the remote k3s kubeconfig with the
  server rewritten to `https://<IP>:6443` (valid thanks to `--tls-san`) and the context renamed
  to `<NAME>`. The cluster/user entries stay named `default`.

Version pins are a matched set: rancher 2.14.3 declares `kubeVersion: < 1.36.0-0`, so k8s must
stay on 1.35.x. If I ask for a different combination, override with env vars rather than editing
the script: `K3S_VERSION`, `CERT_MANAGER_VERSION`, `RANCHER_VERSION`, `RANCHER_HOSTNAME`
(default `<IP>.sslip.io`), `SSH_USER` (default `ubuntu`), `SKIP_K3S=1` (reuse the k3s already on
the VM — use this for re-runs).

Everything is `helm upgrade -i --create-namespace`, so re-running with `SKIP_K3S=1` is safe.

Use an extended timeout — the two `helm --wait` calls plus the rollout can take ~15 minutes
(set the Bash timeout to its max, 600000 ms; if it still times out, tell me rather than
re-running from the top).

Report the script's output verbatim. At the end give me the URL `https://<IP>.sslip.io`
(self-signed — must be opened in unsafe mode), the username `admin`, the bootstrap password,
and the kubeconfig path. On non-zero exit show me the error — do not retry blindly.
