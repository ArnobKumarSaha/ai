# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubedb.dev/mongodb` is the KubeDB MongoDB operator — a Kubernetes controller that manages the full lifecycle of MongoDB databases (standalone, replica set, sharded clusters). The operator binary is `mg-operator` and serves dual roles: provisioner (day-1 operations) and OpsRequest handler (day-2 operations).

## Commands

All build/test commands run inside Docker containers via Make targets.

```bash
# Build the operator binary
make build

# Format code
make fmt

# Run unit tests (inside Docker)
make unit-tests

# Run unit tests directly (no Docker)
GOFLAGS="-mod=vendor" go test ./cmd/... ./pkg/...

# Run a single test
GOFLAGS="-mod=vendor" go test ./pkg/... -run TestFunctionName

# Lint
make lint

# Run e2e tests against a live cluster
make e2e-tests TEST_ARGS="--selfhosted-operator=false --storageclass=standard"

# Verify generated files and modules
make verify
```

## Architecture

### Binary Entry Points

- `cmd/mg-operator/main.go` → `pkg/cmds/root.go` — root Cobra command
- `pkg/cmds/operator.go` — `operator` subcommand: starts the provisioner controller
- `pkg/cmds/webhook.go` — `webhook` subcommand: starts admission webhooks
- `pkg/cmds/server/` — `OperatorOptions`, wires all clients and starts the manager

### Controller Flow (Provisioner)

```
pkg/controller/controller.go   Controller struct — holds all informers, listers, queues
       ↓
pkg/controller/dormant.go      watches MongoDB CRs, enqueues to mgQueue
       ↓
pkg/controller/worker/         Reconciler — main reconcile loop
  mongodb.go                   Reconcile() entry: validates, calls EnsureXxx methods
  petset.go / petset_replicaset.go / petset_sharded.go   builds PetSet specs
  service.go / secret.go / rbac.go / certificate.go      reconcile supporting resources
  health.go                    health check integration
  appbinding.go / monitor.go   AppBinding and Prometheus monitor
```

`Controller` (in `pkg/controller/`) sets up informers/watches. The actual reconciliation delegates to `worker.Reconciler`, which is a thin wrapper over `utils.BaseReconciler` embedding `amc.Controller` from `kubedb.dev/apimachinery/pkg/controller`.

### OpsRequest Flow (Day-2 Operations)

```
pkg/ops/controller.go          mongoOpsReqController — watches MongoDBOpsRequest CRs
pkg/ops/ops_request.go         main dispatch: routes by OpsRequest type
pkg/ops/mongodb.go             per-operation handlers (restart, reconfigure, etc.)
pkg/ops/horizontal_scaling*.go horizontal scaling for standalone/replicaset/shard/mongos
pkg/ops/vertical_scaling.go    vertical scaling
pkg/ops/update_version.go / upgrade.go   version upgrades
pkg/ops/reconfigure_tls.go     TLS cert rotation
pkg/ops/volume_expansion.go / offline_volume_expansion.go / online_volume_expansion.go
pkg/ops/rotate_auth.go         credential rotation
pkg/ops/reprovision.go         full reprovisioning
```

Each ops handler follows the pattern: set OpsRequest condition → mutate DB/PetSet → wait for readiness → update condition.

### Archiving (Continuous Backup / PITR)

```
pkg/controller/archiving/
  providers.go / common.go / snapshot.go   archiver provider logic
  backup/                                  BackupConfiguration, WAL-G backup, Sidekick setup
  restore/                                 RestoreSession, WAL-G restore, renamed-DB restore
```

Archiving integrates with KubeStash via `BackupConfiguration` and `RestoreSession` CRs.

### Key Concepts

- **PetSet** (`kubeops.dev/petset`): used instead of StatefulSet for all MongoDB workloads. PetSet is a KubeDB-specific extension of StatefulSet.
- **OpsRequest lifecycle**: `Pending` → `Progressing` → `Successful`/`Failed`. The controller re-queues with `RequeueDuration = 3s` while waiting for steps to complete.
- **BaseReconciler**: thin wrapper around `amc.Config` + `amc.Controller` from `kubedb.dev/apimachinery`. All reconcilers embed this.
- **License enforcement**: `license.MeetsLicenseRestrictions()` is checked at the top of `Reconcile()`.
- **Webhook validation**: `webhooks.MongoDBCustomWebhook.ValidateMongoDB()` is called during reconciliation in addition to admission time.

### MongoDB Topology Variants

The controller handles three topologies via separate PetSet logic:
1. **Standalone** — single PetSet
2. **ReplicaSet** — single PetSet with multiple replicas
3. **Sharded** — multiple PetSets: one per shard + config server + mongos

Topology is determined from `MongoDB.Spec.ReplicaSet` and `MongoDB.Spec.ShardTopology`.
