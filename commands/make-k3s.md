Provision a fresh k3s single-node cluster on a remote VM.

Arguments: `$ARGUMENTS` — the target IP, optionally followed by a VM/context name.
- First token = IP (required). If absent, stop and ask me.
- Second token = name for the kubeconfig context/file (optional). If omitted, the script
  uses the remote hostname.

Run the script (do not re-implement its logic):

```bash
bash $HOME/yamls/scripts/machine/make-k3s.bash <IP> [NAME]
```

It uninstalls any existing k3s, sets inotify limits, installs k3s
(`--disable=traefik --disable=metrics-server --tls-san <IP>`), waits for coredns, then
runs `copy-kubeconfig.bash` to write `$HOME/Downloads/configs/<NAME>.yaml`.

Use a long timeout (the install + coredns wait can take a few minutes). Report the script's
output verbatim; if it exits non-zero, show me the error — do not retry blindly.
