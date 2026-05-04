# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubestash.dev/workload` is a KubeStash addon plugin binary (`workload`) that performs backup and restore of Kubernetes workload volumes (Deployments, StatefulSets, DaemonSets) using restic. It runs as a Job inside Kubernetes, reads KubeStash CRs from the API server, and drives restic to back up or restore volume data.

## Commands

All build/test commands run inside Docker via Make.

```bash
# Build the binary
make build              # outputs to bin/workload-<os>-<arch>

# Format code
make fmt

# Run unit tests (inside Docker)
make unit-tests

# Run unit tests directly (no Docker)
GOFLAGS="-mod=vendor" go test ./cmd/... ./pkg/...

# Lint
make lint

# Verify modules and generated files
make verify
```

The binary is invoked by KubeStash with subcommands:
```bash
workload backup  --backupsession <name> --namespace <ns> --paths <path,...>
workload restore --restoresession <name> --namespace <ns> --snapshot <name> \
                 [--exclude <pattern,...>] [--include <pattern,...>]
```

## Architecture

This codebase is structurally identical to `kubestash.dev/pvc`. All logic lives in the `pkg` package (5 files).

### `pkg/` Package Structure

| File | Role |
|---|---|
| `root.go` | Cobra root command; registers `backup`, `restore`, `version` subcommands |
| `backup.go` | `NewCmdBackup()` + `performBackup()` — full backup flow |
| `restore.go` | `NewCmdRestore()` + `performRestore()` — full restore flow |
| `status.go` | Kubernetes status update helpers for `Snapshot` and `RestoreSession` |
| `utils.go` | `options` struct, `newRuntimeClient()`, `getResticWrapperForSnapshots()`, `getComponentName()` |

### Differences from `kubestash.dev/pvc`

- Binary name is `workload` (not `pvc`)
- Restore command adds two extra flags:
  - `--exclude` — list of glob patterns for paths to skip during restore
  - `--include` — list of glob patterns to selectively restore
- No FUSE filesystem error handling (`handleRestoreError` silencing `lchown`/`chmod` errors is absent — not needed for regular filesystem mounts)
- Scheme registration does not include `kubedbapi` (kubedb v1alpha2 types)

### Backup/Restore Flow

Identical to `kubestash.dev/pvc`:

1. Resolve `BackupSession` → `BackupConfiguration` → `Snapshot` list from Kubernetes
2. Mark Snapshot component as `Running`
3. `getResticWrapperForSnapshots()` — resolves backend credentials/TLS from `BackupStorage` Secrets
4. `w.EnsureNoExclusiveLock()` → `w.RunBackup(backupOptions)` → `w.VerifyRepositoryIntegrity()`
5. Update `Snapshot.Status.Components` with restic snapshot IDs, size, duration

Restore mirrors backup: resolves `RestoreSession` → `Snapshot`, extracts restic snapshot IDs, calls `w.RunRestore()`, updates status.

### Component Name

From `KUBESTASH_COMPONENT_NAME` env var set by the KubeStash operator when launching the Job.
