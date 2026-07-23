---
name: run-kubedb
description: Bootstrap a KubeDB MongoDB demo end-to-end. Installs license-proxyserver and the KubeDB operator (each skipped if already present), then creates the demo namespace and applies a MongoDB manifest. The kubedb-kubestash-catalog is auto-disabled when Stash is already installed and enabled otherwise. Only cluster access is external. Triggers on "run kubedb", "run-kubedb", "set up the kubedb demo", "bootstrap kubedb mongodb".
---

# run-kubedb

Bootstraps the KubeDB MongoDB demo. Runs `run-kubedb.sh`, which performs, in order:

1. Install `license-proxyserver` (`kubeops` ns) — skipped if the release already exists.
2. Detect Stash via `helm ls -n stash stash`:
   - present → install KubeDB with `--set kubedb-kubestash-catalog=false`
   - absent  → install KubeDB with `--set kubedb-kubestash-catalog=true`
3. Install KubeDB (`kubedb` ns) — `--wait --burst-limit=10000`.
4. Create the `demo` namespace (idempotent).
5. `kubectl apply` the bundled manifest (default `mongodb.yaml` next to the script).
6. Print the created `MongoDB`.

Set `INSTALL=0` to skip steps 1–3 on repeat runs.

## Prerequisites (not handled by this skill)

Only these are external:
- kubectl access to the target cluster.
- `LICENSE_PROXY_TOKEN` present in `~/.claude/secrets/appscode.env` (only needed the first
  time, when license-proxyserver is not yet installed).

## Usage

Default (installs everything, applies the bundled `mongodb.yaml`):

```bash
bash ~/.claude/skills/run-kubedb/run-kubedb.sh
```

Custom manifest:

```bash
bash ~/.claude/skills/run-kubedb/run-kubedb.sh /path/to/manifest.yaml
```

## Overridable env vars

`NS` (demo), `INSTALL` (1; set 0 to skip installs), `PROXY_VERSION` (v2026.2.16),
`KUBEDB_VERSION` (v2026.6.19), `LICENSE_BASE_URL` (https://appscode.com),
`SECRETS_ENV` (`~/.claude/secrets/appscode.env`).
The license token is read as `LICENSE_PROXY_TOKEN` from `SECRETS_ENV` — never hardcoded.

Example:

```bash
NS=test KUBEDB_VERSION=v2026.6.19 bash ~/.claude/skills/run-kubedb/run-kubedb.sh
```

## Notes

- The kubestash-catalog toggle is decided automatically from the Stash release state; no flag needed.
- The bundled `mongodb.yaml` creates a single-replica MongoDB `mm` in `demo` (version 6.0.24,
  2Gi storage, `WipeOut` termination) — the same `mm` the run-stash BackupConfiguration targets.
