# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubedb.dev/apimachinery` is the shared API library for KubeDB — a Kubernetes operator for managing databases. It defines all CRDs (Custom Resource Definitions), typed clients, informers, listers, and helper utilities used by KubeDB operators.

## Commands

All build/test commands run inside Docker containers via Make targets.

```bash
# Format code
make fmt

# Run unit tests
make test

# Lint
make lint

# Run tests directly (no Docker)
GOFLAGS="-mod=vendor" go test ./apis/... ./client/... ./pkg/...

# Run a single test
GOFLAGS="-mod=vendor" go test ./apis/kubedb/v1/... -run TestFunctionName

# Verify generated files and modules are up to date
make verify
```

### Code Generation

Code generation uses Docker with `ghcr.io/appscode/gengo:release-1.32`:

```bash
make gen          # full: clientset + enums + CRDs + openapi + conversions
make clientset    # typed clientset, informers, listers (-> client/)
make manifests    # CRD YAML files (-> crds/)
make openapi      # OpenAPI schema
```

After adding a new type or modifying markers, run `make gen` then `make fmt`.

## Architecture

### API Groups (`apis/`)

Each subdirectory is a Kubernetes API group:

| Package | Group | Purpose |
|---|---|---|
| `apis/kubedb/v1` | `kubedb.com/v1` | Core DB types (MongoDB, Postgres, MySQL, Redis, Elasticsearch, etc.) — **storage version** |
| `apis/kubedb/v1alpha2` | `kubedb.com/v1alpha2` | Extended/newer DB types (Cassandra, ClickHouse, Druid, FerretDB, Hazelcast, etc.) |
| `apis/ops/v1alpha1` | `ops.kubedb.com/v1alpha1` | OpsRequest types for day-2 operations (restart, upgrade, scaling, TLS rotation, etc.) |
| `apis/autoscaling/v1alpha1` | `autoscaling.kubedb.com/v1alpha1` | Autoscaling policies per database |
| `apis/catalog/v1alpha1` | `catalog.kubedb.com/v1alpha1` | DB version catalog (`MongoDBVersion`, `PostgresVersion`, etc.) |
| `apis/schema/v1alpha1` | `schema.kubedb.com/v1alpha1` | Schema management for databases |
| `apis/archiver/v1alpha1` | `archiver.kubedb.com/v1alpha1` | Continuous archiving / PITR configuration |
| `apis/gitops/v1alpha1` | `gitops.kubedb.com/v1alpha1` | GitOps integration types |
| `apis/kafka/v1alpha1` | `kafka.kubedb.com/v1alpha1` | Kafka-specific connector types |
| `apis/migrator/v1alpha1` | `migrator.kubedb.com/v1alpha1` | DB migration types |
| `apis/config/v1alpha1` | `config.kubedb.com/v1alpha1` | Operator configuration |
| `apis/ui/v1alpha1` | `ui.kubedb.com/v1alpha1` | UI-facing aggregated types |

### File Naming Conventions

Within each API version package, files follow a consistent pattern:
- `{db}_types.go` — struct definitions with kubebuilder markers
- `{db}_helpers.go` — methods on the types (defaults, validation helpers, status helpers)
- `{db}_ops_types.go` / `{db}_ops_helpers.go` — OpsRequest types (in `ops/v1alpha1`)
- `{db}_version_types.go` — catalog version types (in `catalog/v1alpha1`)
- `zz_generated.deepcopy.go` — generated, do not edit
- `zz_generated.conversion.go` — generated conversion from v1alpha2 → v1

### Conversion Strategy

`v1alpha2` is the hub for conversion in older types; `v1` is the storage version. Conversion functions live in `apis/kubedb/v1alpha2/conversion.go` and use `zz_generated.conversion.go`.

### Generated Client (`client/`)

- `client/clientset/versioned/` — typed Go client for all API groups
- `client/informers/externalversions/` — shared informer factory
- `client/listers/` — typed listers

These are fully generated; never edit them manually.

### Utility Packages (`pkg/`)

- `pkg/controller/` — shared controller utilities (OpsRequest lifecycle, PetSet helpers)
- `pkg/validator/` — admission webhook validation logic (per DB type, per API group)
- `pkg/webhooks/` — webhook handler registration
- `pkg/phase/` — shared DB phase/condition transition helpers
- `pkg/features/` — feature gate definitions
- `pkg/double_optin/` — double opt-in admission pattern

### Key External Dependencies

- `kmodules.xyz/client-go` — generic Kubernetes client utilities
- `kmodules.xyz/offshoot-api` — shared PodTemplate/ServiceTemplate types used in DB specs
- `kubeops.dev/petset` — PetSet (stateful workload) client used instead of StatefulSet
- `kmodules.xyz/monitoring-agent-api` — monitoring integration types

### Adding a New Database Type

1. Add `{db}_types.go` and `{db}_helpers.go` in `apis/kubedb/v1` (or `v1alpha2` for newer types)
2. Register the type in the group's `register.go` and `install/` package
3. Add corresponding ops types in `apis/ops/v1alpha1/`
4. Add catalog version type in `apis/catalog/v1alpha1/`
5. Add webhook validator in `pkg/webhooks/` and `pkg/validator/`
6. Run `make gen` to regenerate clientset, CRDs, and OpenAPI specs
