---
name: run-stash
description: Bootstrap a Stash backup demo end-to-end. Installs license-proxyserver, MinIO, and the Stash enterprise operator (each skipped if already present), then creates the demo namespace, port-forwards MinIO, creates the "arnob" bucket and minio-secret, and applies the Stash Repository + BackupConfiguration manifest. Only cluster access and the MongoDB AppBinding are external. Triggers on "run stash", "run-stash", "set up the stash demo", "bootstrap stash backup".
---

# run-stash

Bootstraps the Stash MongoDB backup demo. Runs `run-stash.sh`, which performs, in order:

1. Install `license-proxyserver` (`kubeops` ns) — skipped if the release already exists.
2. Install MinIO (`minio` ns, standalone, `replicas=1`) — skipped if the release already exists.
3. Install Stash enterprise (`stash` ns) — no license file needed; the proxyserver supplies it.
4. Create the `demo` namespace (idempotent).
5. Port-forward `svc/minio` in the `minio` namespace (`9000:9000`), waiting for the tunnel.
6. Create the `arnob` bucket in MinIO via `mc` (preferred) or `aws` cli.
7. Create the `minio-secret` in `demo` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `RESTIC_PASSWORD`).
8. `kubectl apply` the bundled manifest (default `stash.yaml` next to the script).
9. Print the created `Repository` / `BackupConfiguration`, then tear down the port-forward.

Set `INSTALL=0` to skip steps 1–3 on repeat runs.

## Prerequisites (not handled by this skill)

Only these are external:
- kubectl access to the target cluster.
- The target MongoDB `AppBinding` (`mm`) referenced by the `BackupConfiguration`.
- helm repo `minio-comm` (`https://charts.min.io/`) added.
- `LICENSE_PROXY_TOKEN` present in `~/.claude/secrets/appscode.env` (only needed the first
  time, when license-proxyserver is not yet installed).

## Usage

Default (installs everything, applies the bundled `stash.yaml`):

```bash
bash ~/.claude/skills/run-stash/run-stash.sh
```

Custom manifest:

```bash
bash ~/.claude/skills/run-stash/run-stash.sh /path/to/manifest.yaml
```

## Overridable env vars

`NS` (demo), `MINIO_NS` (minio), `MINIO_SVC` (minio), `MINIO_PORT`/`LOCAL_PORT` (9000),
`BUCKET` (arnob), `ACCESS_KEY` (rootuser), `SECRET_KEY` (rootpass123),
`RESTIC_PASSWORD` (123456), `SECRET_NAME` (minio-secret).

Install-related: `INSTALL` (1; set 0 to skip installs), `PROXY_VERSION` (v2026.2.16),
`STASH_VERSION` (v2025.10.17), `MINIO_REPLICAS` (1), `MINIO_MEM` (4Gi),
`LICENSE_BASE_URL` (https://appscode.com), `SECRETS_ENV` (`~/.claude/secrets/appscode.env`).
The license token is read as `LICENSE_PROXY_TOKEN` from `SECRETS_ENV` — never hardcoded.

Example:

```bash
BUCKET=demo-bucket NS=test bash ~/.claude/skills/run-stash/run-stash.sh
```

## Notes

- The port-forward runs only for the duration of the script (killed on exit via a trap).
- Bucket creation is idempotent (`mc mb --ignore-existing` / `aws mb` swallows exists errors).
- If neither `mc` nor `aws` is on PATH, the script fails fast with a clear message.
