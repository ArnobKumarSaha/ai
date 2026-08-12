Provision a k3s cluster and deploy ACE (hub) onto a remote VM.

Arguments: `$ARGUMENTS` — the target IP and a selfhost URL. Examples:
- "make a ace with 10.2.0.180 here is the selfhost https://appscode.com/selfhost/appscode-ops/platform-demo/d909vsakifds73blnc0g-cnvzhd542q"
- "make a hub in 10.2.0.235 , with selfhost https://appscode.ninja/selfhost/appscode-ops/platform-demo/d909vsakifds73blnc0g-cnvzhd542q"

Parse from the message:
- `IP` = the IPv4 address.
- `URL` = the selfhost URL, form `https://<host>/selfhost/<org>/<name>/<id>` where `<host>`
  is `appscode.com` (prod) or `appscode.ninja` (staging).

If either is missing, stop and ask me.

Run the script (do not re-implement its logic):

```bash
bash ~/.claude/scripts/make-hub.bash <IP> "<URL>"
```

The script: parses the URL, picks prod/ninja creds from `~/.claude/secrets/appscode.env`,
fetches + base64-decodes the installer readme (fails fast on bad creds), extracts the
cert-manager apply line and the `## Deploy ACE` block (no helm-install, no openshifter),
runs `make-k3s.bash` (which reuses an already-running pristine cluster instead of recreating
it, so a cluster-ID-pinned selfhost license stays valid — cert-manager/flux leftovers from a
previous failed run still count as pristine), then over one root SSH session
applies cert-manager and the Deploy ACE
block in `~/ace`. It prints the site-admin creds and the `https://<IP>` URL at the end.

Use an extended timeout — the `helm upgrade ... --wait` calls can take up to ~10 minutes
(set the Bash timeout to its max, 600000 ms). Report output verbatim; on non-zero exit show
me the error — do not retry blindly.
