# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubestash.dev/kubestash` is the KubeStash operator — a Kubernetes controller that orchestrates backup and restore of applications using restic, WAL-G, CSI snapshots, and other drivers. The binary is `kubestash` and serves two roles: `operator` (reconciliation loops) and `webhook` (admission webhooks). It also has a rich set of `cmds` subcommands used as entrypoints for backup/restore Jobs.

## Commands

All build/lint/test commands run inside Docker via Make.

```bash
# Build binary
make build

# Format code
make fmt

# Run unit tests (inside Docker)
make unit-tests

# Run unit tests directly (no Docker)
GOFLAGS="-mod=vendor" go test ./pkg/... ./tests/...

# Run a single test
GOFLAGS="-mod=vendor" go test ./pkg/controllers/core/... -run TestBackupConfiguration

# Lint
make lint

# Verify modules and generated files
make verify
```

The `kubestash` binary subcommands (used in Jobs, not just operator):
```bash
kubestash operator           # run the operator
kubestash webhook            # run admission webhooks
kubestash trigger-backup     # create a BackupSession manually
kubestash create-restoresession
kubestash upload-snapshot    # upload a completed snapshot's metadata
kubestash initialize-storage / cleanup-storage
kubestash initialize-repository / cleanup-repository
kubestash prune-snapshot     # apply retention policy
kubestash populate-volume
```

## Architecture

### Entry Points

`main.go` → `pkg/cmds/root.go` wires all Cobra subcommands. `run_operator.go` sets up the `controller-runtime` Manager, registers all controllers, and starts webhooks.

### Controllers (`pkg/controllers/`)

Organized by API group:

**`core/`** — reconciles KubeStash core CRs:
- `BackupConfigurationReconciler` — validates target/addon/storage readiness, manages CronJobs (via `pkg/scheduler/`), ensures RBAC
- `BackupSessionReconciler` — the hot path: creates backup Jobs via `pkg/executor/`, tracks per-component status, updates Snapshot CRs
- `RestoreSessionReconciler` — creates restore Jobs via `pkg/executor/`, tracks status
- `BackupBlueprintReconciler` — watches BackupBlueprints, no-op for reconcile (template validation)
- `BackupBatchReconciler` — orchestrates multi-target backups

**`storage/`** — reconciles storage CRs:
- `BackupStorageReconciler` — validates bucket connectivity, updates total size
- `RepositoryReconciler` — manages restic repository initialization, tracks snapshots
- `SnapshotReconciler` — manages snapshot lifecycle, triggers retention policy

**`app/`** — watches workload resources (AppBinding, Deployment, StatefulSet, DaemonSet, PVC) to auto-trigger backup via `pkg/auto-backup/`

**`batch/`** — `JobReconciler`: watches backup/restore Jobs created by the executor and updates BackupSession/RestoreSession status when Jobs complete

### Backup Execution Flow

```
BackupConfiguration + CronJob fires
    → creates BackupSession CR
    → BackupSessionReconciler.Reconcile()
        → pkg/executor/backup.go: BackupJobExecutor
            → pkg/rbac/: ensure ServiceAccount + RoleBindings
            → pkg/resolver/: resolve addon params, template variables
            → pkg/executor/job.go: create Kubernetes Job
                → job runs addon container (e.g. mongodb-restic-plugin backup)
    → batch/JobReconciler watches Job completion
    → updates Snapshot, BackupSession status
    → pkg/snapshot/ uploads snapshot metadata to blob storage
    → RetentionPolicy applied via prune-snapshot subcommand
```

### Key Packages

- **`pkg/executor/`** — builds Kubernetes Job specs for backup (`backup.go`), restore (`restore.go`), retention policy pruning (`retentionpolicy.go`), snapshot upload (`snapshot_uploader.go`), storage/repository init/cleanup, volume population
- **`pkg/scheduler/`** — `InstantScheduler` (creates BackupSession immediately) and `PeriodicScheduler` (manages CronJob for a BackupConfiguration session)
- **`pkg/resolver/`** — resolves BackupConfiguration session parameters and fills addon template variables (image registry, namespace, invoker, etc.)
- **`pkg/rbac/`** — creates ServiceAccounts, ClusterRoles, RoleBindings for backup/restore Jobs
- **`pkg/auto-backup/`** — reads `kubestash.com/backup-blueprint-name` annotation from target objects, auto-creates BackupConfiguration from a BackupBlueprint
- **`pkg/backend/`** — interacts with restic repositories and blob storage for snapshot listing, integrity checks
- **`pkg/addon/`** — resolves Addon CRs and their backup/restore task definitions
- **`pkg/target/`** — determines target readiness and extracts connection info
- **`pkg/hook/`** — executes pre/post backup/restore HookTemplates

### Controller Interface Pattern

Each controller (e.g. `BackupConfigurationReconciler`) creates a private per-reconcile struct (e.g. `bcReconciler`) with interface fields for its dependencies (`targetChecker`, `addonValidator`, `storagePhaseGetter`, etc.). This allows unit testing by mocking those interfaces — see `backupconfiguration_controller_test.go` for the pattern.
