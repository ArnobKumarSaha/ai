# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubestash.dev/pvc` is a KubeStash addon plugin binary (`pvc`) that performs backup and restore of PersistentVolumeClaims using restic. It runs as a Job inside Kubernetes, reads KubeStash CRs (`BackupSession`, `RestoreSession`, `Snapshot`) from the API server, and drives restic to back up or restore PVC data.

## Commands

All build/test commands run inside Docker via Make.

```bash
# Build the binary
make build              # outputs to bin/pvc-<os>-<arch>

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
pvc backup  --backupsession <name> --namespace <ns> --paths <path,...>
pvc restore --restoresession <name> --namespace <ns> --snapshot <name>
```

## Architecture

This is a small, focused codebase. All logic lives in the `pkg` package (5 files).

### `pkg/` Package Structure

| File | Role |
|---|---|
| `root.go` | Cobra root command; registers `backup`, `restore`, `version` subcommands |
| `backup.go` | `NewCmdBackup()` + `performBackup()` — full backup flow |
| `restore.go` | `NewCmdRestore()` + `performRestore()` — full restore flow |
| `status.go` | Kubernetes status update helpers for `Snapshot` and `RestoreSession` |
| `utils.go` | `options` struct, `newRuntimeClient()`, `getResticWrapperForSnapshots()`, `getComponentName()` |

### Core `options` Struct (`utils.go`)

All state is carried in a single `options` struct per command invocation:
```go
type options struct {
    client              client.Client
    namespace, backupSessionName, restoreSessionName, snapshotName string
    setupOptions        restic.SetupOptions
    backupOptions       restic.BackupOptions
    restoreOptions      restic.RestoreOptions
    backupConfiguration *coreapi.BackupConfiguration
    backupSession       *coreapi.BackupSession
    restoreSession      *coreapi.RestoreSession
    snapshots           []storageapi.Snapshot
}
```

### Component Name

The component name (used as the key in `Snapshot.Status.Components`) comes from the `KUBESTASH_COMPONENT_NAME` env var set by the KubeStash operator when launching the Job.

### Backup Flow (`backup.go`)

1. Resolve `BackupSession` → `BackupConfiguration` → `Snapshot` list from Kubernetes
2. Mark each Snapshot component as `Running` in status
3. `getResticWrapperForSnapshots()` — resolves backend credentials/TLS from `BackupStorage` Secrets
4. `w.EnsureNoExclusiveLock()` — check no other restic process holds an exclusive lock
5. `w.RunBackup(backupOptions)` — runs restic backup for specified `--paths`
6. `w.VerifyRepositoryIntegrity()` — checks repo integrity post-backup
7. Update `Snapshot.Status.Components` with restic snapshot IDs, size, duration

### Restore Flow (`restore.go`)

1. Resolve `RestoreSession` → `Snapshot` from Kubernetes
2. Mark RestoreSession component as `Running`
3. Extract restic snapshot IDs from `Snapshot.Status.Components`
4. `getResticWrapperForSnapshots()` — resolves backend credentials/TLS
5. `w.RunRestore()` — runs restic restore
6. `handleRestoreError()` — silences expected FUSE filesystem errors (`lchown`/`chmod` "operation not supported") that occur on some cloud storage mounts
7. Update `RestoreSession.Status.Components` with result

### Key External Dependency

`gomodules.xyz/restic` wraps the restic binary. `restic.ResticWrapper` manages backend configuration, env var setup, and subprocess execution. `restic.SetupOptions` / `BackupOptions` / `RestoreOptions` configure each run.
