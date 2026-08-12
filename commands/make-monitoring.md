Run guide.md steps 3-5 (MinIO, telemetry bucket, TelemetryStack) on the CURRENT cluster.

Assumes the current kubectl context points at an ACE-imported Observability cluster where the
TelemetryStack + MinIO CRDs/operators already exist (guide steps 1-2 done). This command does NOT
provision k3s.

Arguments: `$ARGUMENTS` — optionally a path to a TelemetryStack manifest. If omitted, the script
uses `$HOME/yamls/store/telemetry-stack.yaml`.

Before running, confirm the active context is the intended observability cluster:

```bash
kubectl config current-context
```

Run the script (do not re-implement its logic):

```bash
bash ~/.claude/scripts/make-monitoring.bash [MANIFEST]
```

The script, all steps idempotent:
- **Step 3** — creates the `minio` and `monitoring` namespaces, the `tls-ssl-minio` secret in both
  (from `private.key` + `public.crt` in the otel-o11y repo), adds the `minio-comm` helm repo, and
  `helm upgrade -i minio` with `minio/minio-values.yaml` (TLS-enabled), `--wait`.
- **Step 4** — port-forwards `svc/minio` and creates the `telemetry` bucket over HTTPS via
  `mc --insecure` (fallback `aws --no-verify-ssl`). Port-forward is torn down on exit.
- **Step 5** — strips runtime metadata (`resourceVersion`, `uid`, `creationTimestamp`,
  `generation`, `status`) from the manifest with `yq`, then `kubectl apply`s it.

Asset locations (overridable env vars):
- `OTEL_REPO` (default `$HOME/go/src/opnpulse/otel-o11y`) — source of `private.key`, `public.crt`,
  `minio/minio-values.yaml`. The private key is referenced in place, never copied.
- Other overrides: `MINIO_NS`, `MONITORING_NS`, `BUCKET` (telemetry), `ACCESS_KEY` (rootuser),
  `SECRET_KEY` (rootpass123), `LOCAL_PORT` (9000), `INSTALL` (1; set 0 to skip the helm install on
  repeat runs).

Use a long timeout — `helm ... --wait` can take a few minutes (set the Bash timeout to its max,
600000 ms). Report output verbatim; on non-zero exit show me the error — do not retry blindly.
