# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubedb.dev/db-client-go` is a library of Kubernetes-aware database clients used by KubeDB operators. Each top-level directory is a self-contained Go package for one database engine. The clients read KubeDB CRs (from `kubedb.dev/apimachinery`) and Kubernetes Secrets to construct authenticated, optionally TLS-secured connections.

## Commands

```bash
# Format code
make fmt

# Run tests (inside Docker)
make test

# Run tests directly (no Docker)
GOFLAGS="-mod=vendor" go test ./mongodb/... ./postgres/... # etc.

# Lint
make lint

# Verify modules and generated files are up to date
make verify
```

There are no unit tests in the library code itself (only in vendored dependencies). Tests run against live databases.

## Architecture

### Package-per-Database Pattern

Every supported database engine has its own Go package:

```
{db}/
  kubedb_client_builder.go   Builder with fluent With* methods → terminal Get*Client()
  client.go                  Client type(s) and interface definition
  api.go (some packages)     Interface declaration and constants
  *.go                       Helper methods on Client
```

**The builder pattern is universal.** Every package exposes `NewKubeDBClientBuilder(kc client.Client, db *dbapi.XxxType)` and fluent configurators:

```go
client, err := mongodb.NewKubeDBClientBuilder(kc, db).
    WithPod(podName).
    WithContext(ctx).
    GetMongoClient()
```

The terminal method name varies by DB:
- `GetMongoClient()`, `GetElasticClient()`, `GetPostgresClient()` / `GetPostgresXormClient()`
- `GetKafkaClient()` / `GetKafkaProducerClient()` / `GetKafkaAdminClient()` / `GetKafkaConsumerClient()`
- `GetRedisClient()` / `GetRedisClusterClient()`
- etc. — see each package's `kubedb_client_builder.go`

### Client Types

Two client wrapping strategies are used:

1. **Native driver wrapper** — `Client` embeds the upstream driver client directly (e.g., `*mongo.Client`, `*redis.Client`, `*sql.DB`). Methods are added directly.
2. **XormClient** — wraps `*xorm.Engine`; used for SQL databases where ORM is more convenient (Postgres, MySQL, MariaDB, MSSQL, PgBouncer, Pgpool, PerconaXtraDB, SingleStore, ProxySQL).

Some databases expose both (e.g., Postgres has `GetPostgresClient()` for raw `*sql.DB` and `GetPostgresXormClient()` for xorm).

### Credential and TLS Resolution

The builder resolves credentials and TLS inside the terminal `Get*Client()` call by reading Kubernetes Secrets via the injected `client.Client` (`kc`). The KubeDB CR's `Spec.AuthSecret` and TLS configuration drive this resolution. The `certholder.ResourceCerts` abstraction from `kmodules.xyz/client-go` is used for cert management in some packages.

### Multi-Version Clients (Elasticsearch)

Elasticsearch is the most complex package: it supports ES v5–v9 and OpenSearch v1–v3 within a single `GetElasticClient()` call. The builder inspects the DB version from the KubeDB catalog and selects the right underlying SDK (`esv5`, `esv6`, … `osv3`). The returned `*Client` wraps the `ESClient` interface defined in `api.go`, which all version-specific implementations satisfy.

### Adding a New Database

1. Create a new top-level package named after the DB.
2. Implement `kubedb_client_builder.go` with `KubeDBClientBuilder` and a terminal `Get*Client()` method that resolves credentials/TLS from Kubernetes.
3. Define a `Client` type in `client.go` wrapping the upstream driver.
4. Add the package name to `SRC_PKGS` in the `Makefile`.
