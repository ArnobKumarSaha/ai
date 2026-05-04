# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubedb.dev/mongodb-restic-plugin` is a KubeStash addon binary that implements MongoDB backup and restore via `mongodump`/`mongorestore` + restic. It runs as a sidecar/job inside Kubernetes, reads KubeStash CRs (`BackupSession`, `RestoreSession`, `Snapshot`), and orchestrates the dump/restore process.

## Commands

All build/test/lint commands run inside Docker via Make.

```bash
# Build the binary
make build              # outputs to bin/mongodb-restic-plugin-<os>-<arch>

# Format code
make fmt

# Lint
make lint

# Run unit tests (inside Docker)
make unit-tests

# Run unit tests directly (no Docker)
GOFLAGS="-mod=vendor" go test ./cmd/... ./pkg/...

# Verify modules and generated files
make verify
```

The binary is invoked by KubeStash with subcommands:
```bash
mongodb-restic-plugin backup  --backupsession <name> --namespace <ns> --db-version <ver>
mongodb-restic-plugin restore --restoresession <name> --namespace <ns> --db-version <ver>
```

## Architecture

### Version Dispatch (`pkg/mapper.go`)

The central design pattern: `--db-version` selects a versioned implementation at runtime. `initializeAddonImplementer()` switches on the version string and instantiates the matching `pkg/v{version}/` package. Each versioned package implements the `common.VersionedAddon` interface.

### The VersionedAddon Interface (`pkg/common/interface.go`)

```go
type VersionedAddon interface {
    SetupCredsForBackup(authSecret, tlsSecret *corev1.Secret) error
    SetupBackupOptions(hostname string, port int32) error
    GetBackupCleanerFunctions() []database.CleanupFunc

    SetupCredsForRestore(authSecret, tlsSecret *corev1.Secret) error
    SetupDumpOptions(hostname string, port int32) error
    GetRestoreCleanerFunctions() []func() error
}
```

Every versioned package (`v4.2.3`, `v4.4.6`, `v5.0.3`, `v5.0.15`, `v6.0.5`, `v8.0.3`) implements this.

### Versioned Package Structure (`pkg/v{ver}/`)

Each versioned package has the same three files:
- `types.go` — defines the struct embedding `*common.Options` + `database.DBOptions`, wired with version-specific constants (which CLI tool: `mongosh` vs `mongo`, which balancer check command, etc.)
- `backup.go` — implements `SetupCredsForBackup()` and `SetupBackupOptions()`
- `restore.go` — implements `SetupCredsForRestore()` and `SetupDumpOptions()`

**Key differences across versions:**
- `v4.2.3`/`v4.4.6` use `MongoCMD` (`/usr/bin/mongo`) and `SlaveOk`/`BalancerCheckWithoutMode`
- `v5.0.3`+ use `MongoshCMD` (`/usr/bin/mongosh`) and `SecondaryReadPref`/`BalancerCheckWithMode`
- `v8.0.3` sharded backup creates a temporary super-user for the dump

### Shared Logic (`pkg/common/database/`)

`database.DBOptions` holds the shared implementation of:
- `WaitForDBPingable()` — polls until the DB accepts connections
- `SetupBackupOptions()` / `SetupDumpOptions()` — builds `restic.BackupOptions`/`restic.DumpOptions` with correct `mongodump`/`mongorestore` command arguments
- `WorkOnSuperUser()` — creates/drops a temporary privileged user for sharded cluster backup
- Lock/unlock balancer, stop/start secondaries — via `database/lock.go`
- Role management — via `database/role.go`

### Backup/Restore Flow

**Backup** (`pkg/backup.go`):
1. Resolve KubeStash CRs + AppBinding via Kubernetes API
2. Wait for DB ready
3. `initializeAddonImplementer()` — select versioned impl
4. `SetupCredsForBackup()` — parse auth/TLS secrets, optionally create super-user
5. `SetupBackupOptions()` — wait for ping, handle resharding workaround (v8), configure per-replicaset backup targets
6. `w.RunParallelBackup()` — drive restic in parallel across replicasets
7. Cleanup via `GetBackupCleanerFunctions()` — ordered: unlock secondaries (order=0) before other steps

**Restore** (`pkg/restore.go`):
1. Resolve KubeStash CRs + AppBinding
2. Wait for DB ready
3. `initializeAddonImplementer()` — select versioned impl
4. `SetupCredsForRestore()` — parse auth/TLS secrets
5. `SetupDumpOptions()` — configure mongorestore targets
6. `w.ParallelDump()` — restore in parallel via restic

### Adding a New MongoDB Version

1. Create `pkg/v{ver}/` with `types.go`, `backup.go`, `restore.go` following an existing version as template.
2. Set `DatabaseCommand`, `SecondaryAllowCommand`, `BalancerCheckCommand` in `types.go` to the appropriate constants from `pkg/common/constant.go`.
3. Add a `case "{ver}":` in `initializeAddonImplementer()` in `pkg/mapper.go`.
