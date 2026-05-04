# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubestash.dev/apimachinery` is the shared API library for KubeStash — a Kubernetes-native backup/restore operator. It defines all CRDs, Go types, helper methods, and utility packages consumed by the KubeStash operator and addon plugins (e.g. `mongodb-restic-plugin`).

## Commands

```bash
# Format code (inside Docker)
make fmt

# Run tests (requires envtest — downloads kubebuilder binaries automatically)
make test
# or directly without manifests/generate prerequisite:
GOFLAGS="-mod=vendor" go test ./... -coverprofile cover.out

# Run a single test
GOFLAGS="-mod=vendor" go test ./apis/core/v1alpha1/... -run TestFunctionName

# Lint
make lint

# Regenerate deepcopy methods (requires controller-gen in PATH)
make generate

# Regenerate CRD YAML files from kubebuilder markers
make manifests

# Verify modules are tidy
make verify-modules
```

## Architecture

### API Groups (`apis/`)

| Package | Group | Key CRDs |
|---|---|---|
| `apis/core/v1alpha1` | `core.kubestash.com/v1alpha1` | BackupConfiguration, BackupSession, RestoreSession, BackupBatch, BackupBlueprint, BackupVerifier, HookTemplate |
| `apis/storage/v1alpha1` | `storage.kubestash.com/v1alpha1` | BackupStorage, Repository, Snapshot, RetentionPolicy |
| `apis/addons/v1alpha1` | `addons.kubestash.com/v1alpha1` | Addon (cluster-scoped), Function |
| `apis/config/v1alpha1` | `config.kubestash.com/v1alpha1` | KubeStashConfig, BackendMeta (operator config) |

Top-level `apis/` package (`apis/types.go`, `apis/variables.go`, `apis/constant.go`) holds shared types and constants used across all groups: `Driver`, `UsagePolicy`, `VolumeSource`, `ParameterDefinition`, and template variable names.

### Core Concepts and Relationships

```
BackupBlueprint          ← template; auto-creates BackupConfigurations via annotations
BackupConfiguration      ← references target app + BackupStorage backends + Sessions
    ↓  triggers (CronJob)
BackupSession            ← one run; created by the operator per session schedule
    ↓  creates
Snapshot                 ← records what was backed up; lives in same namespace as Repository
    ↓  stored in
Repository               ← references BackupStorage; one per (target, storage) pair
    ↓  backed by
BackupStorage            ← bucket representation (S3, GCS, Azure, NFS…)

RestoreSession           ← one restore run; references a Snapshot as data source
Addon                    ← cluster-scoped; declares backup/restore tasks for a DB type
```

**BackupConfiguration** is the primary user-facing resource. Each `Session` inside it specifies a schedule (cron), addon, and which backends to use.

**Snapshot** is operator-managed (never user-created). It tracks per-component backup status and holds restic/WAL-G snapshot IDs.

### Drivers

The `Driver` type (`apis/types.go`) specifies the underlying backup tool:
- `Restic` — used by most DB addons (MongoDB, Postgres, etc.)
- `WalG` — WAL archiving for Postgres/MongoDB continuous backup
- `VolumeSnapshotter` — CSI VolumeSnapshot based
- `Medusa` — Cassandra
- `Solr`, `ClickHouseBackup` — DB-specific drivers

### File Naming Conventions

Within each API version package:
- `{resource}_types.go` — struct definitions with kubebuilder markers
- `{resource}_helpers.go` — methods on the types (condition helpers, phase transitions, defaults)
- `zz_generated.deepcopy.go` — generated; do not edit

### Utility Packages (`pkg/`)

- `pkg/blob/` — cloud storage client (wraps AWS S3, Azure Blob, GCS via `gocloud.dev/blob`); used to read/write data directly from addon plugins
- `pkg/resolver/` — resolves BackupConfiguration session parameters, fills template variables
- `pkg/snapshot/` — snapshot I/O helpers
- `pkg/resourceops/` — Kubernetes resource operation utilities
- `pkg/retry/` — retry helpers for backup/restore operations
- `pkg/workerpool/` — worker pool for parallel blob operations
- `pkg/cloud/` — cloud provider credential helpers
- `pkg/version.go` — semver utilities

### Webhooks (`webhooks/`)

Admission webhooks for the CRDs live in `webhooks/`. Split into `core/` and `storage/` sub-packages mirroring the API groups.

### Code Generation

This repo uses `controller-gen` (not the gengo-based generators used in `kubedb.dev/apimachinery`):
- `make generate` → runs `controller-gen object:...` to regenerate `zz_generated.deepcopy.go`
- `make manifests` → runs `controller-gen crd rbac webhook` to regenerate `crds/` YAML
- Tests require `envtest` (`make test` downloads it automatically via `setup-envtest`)
