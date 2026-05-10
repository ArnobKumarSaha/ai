# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**b3** (ByteBuilders Backend) is a Go-based cloud platform backend providing multi-cluster Kubernetes management, account/billing/marketplace APIs, user authentication (LDAP, OAuth2, WebAuthn), and license enforcement. It is derived from Gitea but heavily customized for ByteBuilders' cloud platform.

## Prerequisites

Set up private Go module access before working with dependencies:
```bash
go env -w GOPRIVATE=go.bytebuilders.dev/*,go.appscode.dev/*,github.com/appscode/*,kubedb.dev/*
```

Go version: **1.25.6** (pinned in Makefile and go.mod).

## Build & Run

```bash
make build          # Build for current platform → bin/b3-<OS>-<ARCH> + ./b3 symlink
make all-build      # Build all platforms
make run            # Build and start ./b3 api
```

On macOS: direct `go build`. On Linux: Docker-based build using `ghcr.io/appscode/golang-dev:1.25`.

Run the API server manually:
```bash
./b3 api --config=/path/to/config.ini --custom-path=/path/to/data
# Web UI: http://localhost:3000/accounts
# REST API: http://localhost:3000/api
```

## Testing

```bash
make unit-tests                                          # Unit tests across core packages
go test -v -covermode=atomic ./models                    # Single package test
go test -v -run TestFunctionName ./models/...            # Run a single test by name
make test-pgsql                  # Integration tests (requires PostgreSQL)
make complete-integration-test   # Full suite (PostgreSQL + NATS + OpenFGA + James + Grafana)
make e2e-tests                   # End-to-end tests (requires Kind cluster)
```

Integration tests require environment variables:
```bash
export TEST_PGSQL_HOST=localhost
export TEST_PGSQL_PORT=5234
export TEST_PGSQL_DBNAME=test
export TEST_PGSQL_USERNAME=postgres
export TEST_PGSQL_PASSWORD=postgres
```

Start services for local integration testing:
```bash
make start-pg-db      # PostgreSQL
make nats-server      # NATS message bus
make openfga-server   # OpenFGA authorization
make inbox-server     # James email server
```

## Code Quality

> **Note:** `make fmt` and `make lint` run inside Docker — Docker must be running. On macOS you can run `goimports` / `gofmt` directly if preferred.

```bash
make fmt              # goimports + gofmt + shfmt (runs via Docker)
make lint             # golangci-lint
make check-license    # Verify license headers
make add-license      # Add missing license headers
make ci               # check-license + check-vuln + lint + build
```

Lint config: `.golangci.yml` and `.revive.toml`.

## Architecture

### Entry Point & Commands

`main.go` initializes the CLI. Key subcommands in `cmd/`:
- **api.go** — Main API server: initializes DB + NATS, sets up Macaron HTTP router, handles graceful shutdown, registers `/accounts` and `/api` route groups
- **migrate.go** — Database migration runner
- **admin.go** — Administrative user/org commands
- **marketplace.go** / **aggregator.go** — Marketplace and billing aggregation
- **cert.go** — TLS certificate management
- **issue_full_license.go** — License issuance for offline/air-gapped clusters
- **upgrade.go** — Platform upgrade helpers
- **installer_validator.go** — ACE installer pre-flight validation

### Data Layer (`models/`)

~84 packages using **XORM ORM**. Key categories:
- User/Auth: accounts, OAuth apps, external tokens
- Organization: teams, members
- Cluster: info, auth, presets, external access
- Licensing: verification, enforcement, offline licenses
- Billing: contracts, subscription usage, aggregation
- **BadgerDB cache** (`badger*.go`): embedded KV store caching Kubernetes unstructured resources with TTL (default 60 days), keyed by cluster/namespace/resource type

Schema migrations live in `models/migrations/` and run on startup.

### HTTP Routing (`routers/`)

Framework: **Macaron** (`gopkg.in/macaron.v1`)

- `routers/routes/` — UI routes under `/accounts`
- `routers/api/v1/` — REST API routes: clusters, users, orgs, marketplace, charts, billing
- `routers/swagger_json.go` — Auto-generated OpenAPI spec
- Request context with user/org info lives in `modules/context/`

### Modules (`modules/`)

Reusable packages:
- **setting** — Global INI-file config (paths, DB, auth providers, billing, license URLs)
- **nats** — NATS client; admin connections + config syncer for distributed config sync
- **auth** — LDAP, OAuth2, WebAuthn providers
- **storage** — Object storage abstraction via `gocloud.dev` (multiple backends)
- **kube** — Kubernetes client utilities
- **license** — License verification and enforcement
- **billing** — Billing utilities
- **telemetry** — OpenTelemetry instrumentation
- **installer_precheck** — ACE installer validation
- **rancher** — Rancher cluster integration

### Configuration

INI-based, loaded via flags:
- `-c` custom config, `-u` user config, `-s` system config
- `-C` custom data directory, `-w` working directory

### Key External Integrations

- **Cloud providers**: AWS, Azure, GCP, DigitalOcean, Linode
- **Kubernetes**: client-go, kmodules.xyz utilities, Rancher/Norman
- **Auth**: Firebase/Google OAuth, generic OAuth2, LDAP, WebAuthn
- **Services**: OpenFGA (fine-grained authz), NATS (messaging), Prometheus, OpenTelemetry, Helm 3

### Build Notes

- CGO disabled for portable builds (except some tests use `CGO_ENABLED=1`)
- Docker multi-stage builds: PROD (Debian), DBG (Debian+debug), UBI (Red Hat)
- License headers enforced via `ltag` in Makefile — run `make add-license` after adding new files
