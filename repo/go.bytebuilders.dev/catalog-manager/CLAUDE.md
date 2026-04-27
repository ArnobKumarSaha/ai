# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`catalog-manager` is a Kubernetes controller manager by AppsCode (Bytebuilders) that manages catalog bindings and gateway configurations for multi-database systems. It reconciles database-specific binding resources (PostgreSQL, MySQL, MongoDB, Cassandra, ClickHouse, Elasticsearch, FerretDB, Kafka, MariaDB, MSSQLServer, Oracle, Redis) and exposes them via the Kubernetes Gateway API.

## Common Commands

```bash
# Build
make build              # Build binary for current OS/ARCH
make fmt                # Format code (goimports, gofmt, shfmt)
make lint               # Run golangci-lint

# Test
make unit-tests         # Run unit tests with race detection
make e2e-tests          # Run E2E tests (Ginkgo)
make ci                 # License check + lint + build (mirrors CI pipeline)

# Run locally
make run                # Run controller locally with go run

# Kubernetes deployment
make deploy-to-kind     # Build image and load into kind cluster
make install            # Deploy to K8s cluster via Helm
make uninstall          # Remove from K8s

# Run a single test
go test -v -race ./pkg/controllers/... -run TestFunctionName
```

All builds are done with vendored dependencies (`-mod=vendor`) and CGO disabled.

## Architecture

### Entry Point & CLI

- `cmd/catalog-manager/main.go` — bootstraps the root command, initializes logging and license verification
- `pkg/cmds/root.go` — defines `version` and `run` subcommands
- `pkg/cmds/run.go` — the `run` subcommand: sets up the controller-runtime manager, registers all API schemes (Kubernetes, KubeDB, KubeVault, Gateway API, Flux CD, Envoy Gateway), and starts all reconcilers

### Controllers (`pkg/controllers/`)

`manager.go` is the central registration point — it calls `AddAllBindingReconcilers()` which registers every reconciler with the controller-runtime manager. Controller registration is guarded by API discovery so controllers gracefully degrade when optional CRDs are not installed.

Key reconciler groups:
- **Database bindings** (`cassandra/`, `clickhouse/`, `elasticsearch/`, `ferretdb/`, `kafka/`, `mariadb/`, `mongodb/`, `mssqlserver/`, `mysql/`, `oracle/`, `postgres/`, `redis/`): Database-specific reconcilers; `generic/` is a fallback for uncovered types.
- **Gateway** (`gatewaypreset/`): Reconciles GatewayPreset resources and manages GatewayClass/Gateway/Route objects.
- **RBAC** (`rbac/`, `client_org_deletion/`): Manages RBAC resources and cleans up client org artifacts.
- **Port manager** (`portmanager/controller/`): Tracks and allocates ports across services and clusters.
- **UI** (`ui/`): UI-related controllers.

### Gateway Package (`pkg/gateway/`)

Utilities for service exposure through the Kubernetes Gateway API:
- `gateway.go` — gateway discovery and configuration
- `expose.go` — logic for exposing services
- `route.go` — route lifecycle management
- `status.go` — updates gateway/route status

### Port Manager (`pkg/portmanager/`)

Handles intelligent port allocation across the cluster:
- `ServicePortManager` — allocates ports to services (unique or shared strategies)
- `ClusterManager` — tracks port usage across clusters
- `controller/` — Kubernetes reconcilers for port state

## Key Integration Points

- **KubeDB**: Primary domain — manages lifecycle of database binding resources via `kubedb.dev/apimachinery`
- **Flux CD**: Used for Helm chart releases (`fluxcd/helm-controller`, `fluxcd/source-controller`)
- **Gateway API**: `sigs.k8s.io/gateway-api` with Envoy Gateway (`envoyproxy/gateway`) as the implementation
- **KubeVault**: Optional integration — detected at runtime; controllers register only when CRDs exist
- **OpenShift**: Special-cased via `--distro.openshift` flag

## Important Flags (`run` subcommand)

| Flag | Purpose |
|------|---------|
| `--leader-elect` | Enable HA via leader election |
| `--reserved-ports` | Ports excluded from port allocation |
| `--platform-url` | URL for the AppsCode platform |
| `--oci-registry-config-file` | OCI registry proxy configuration |
| `--distro.openshift` | Enable OpenShift-specific behavior |
| `--keda-proxyservice-*` | KEDA integration settings |
| `--helmrepo-*` | Helm repository configuration |
