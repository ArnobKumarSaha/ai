# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

`go.bytebuilders.dev/lib-selfhost` builds the **ACE self-host installer** — given an `AceOptionsSpec` (from `go.bytebuilders.dev/installer/apis/installer/v1alpha1`) it renders a complete workspace of Helm values, scripts, and a README, then archives it for delivery. Output is a CLI named `ace`.

## Common commands

Build/test/lint run inside the `ghcr.io/appscode/golang-dev:1.25` Docker image (the Makefile mounts the source). Vendoring is mandatory — all Go commands use `-mod=vendor`.

```
make build            # build bin/ace-<os>-<arch> via the Docker build image
make test             # = unit-tests (go test -race ./...)
make lint             # golangci-lint run
make fmt              # ./hack/fmt.sh on cmd/ client/ lib/
make ci               # what CI runs: verify + check-license + lint + go install ./... + go test ./cmd/...
make verify           # verify-gen + verify-modules (fails if `go mod tidy && go mod vendor` is dirty)
make check-license    # ltag header check (excludes vendor, contrib, image-scripts, workspace)
make add-license      # add the Apache header to new files
```

Run a single Go test directly (no Docker):

```
go test -mod=vendor -run TestName ./cmd/selfhost-server-demo/cmds
```

After changing dependencies you must run both `go mod tidy` and `go mod vendor` — `make verify-modules` fails CI otherwise.

## Running the installer locally

The `ace` binary's two main entry points:

```
go run ./cmd/selfhost-server-demo/... sample          # render a sample installer into ./workspace and ./objstore
go run ./cmd/selfhost-server-demo/... install         # serve the installer HTTP API on :4000 (auto-opens browser)
go run ./cmd/selfhost-server-demo/... status --domain appscode.ninja
```

The `install` server exposes:

- `GET  /apis/schema.json`  — OpenAPI v3 schema for `AceOptionsSpec` (from `go.bytebuilders.dev/installer/schema`)
- `GET  /apis/options.json` — sample `AceOptionsSpec` (see `cmd/selfhost-server-demo/cmds/sample.go:NewSampleOptions`)
- `POST /apis/install`      — accepts an `AceOptionsSpec` JSON body and calls `lib.CreateInstaller`

Manual test:
```
curl -X POST -d @workspace/files/options.yaml http://localhost:4000/apis/install
```

`lib.CreateInstaller` writes to `./workspace/files/`, archives to `./workspace/archive.{zip,tar.gz}`, then uploads to a local blobfs at `./objstore/installer/<owner>/<xid>/`. Both directories are wiped on every run — do not put anything you want to keep there.

## Architecture

Three Go source trees (everything else is vendored or scaffolding):

- **`lib/`** — the engine. Pure functions that turn an `AceOptionsSpec` into installer artifacts. Key files:
  - `installer.go` (~110 KB) — `CreateInstaller`, `GenerateScriptsForACE`, all values rendering for FluxCD / cert-manager / NATS / external-DNS / Envoy Gateway / KubeDB / monitoring / etc.
  - `options.go` — `NewDefaultOptions`, `NewDefaultOnpremOptions`, `NewDefaultKubernetesAppOptions`, `ValidateOptions`, feature-set defaults (`aceFeatures`).
  - `readme.go` — generates the user-facing README and DNS-records table (`tablewriter`).
  - `archiver.go` — zip/tar.gz of the rendered files dir.
  - `dns.go`, `nats.go`, `mp.go`, `status.go`, `util.go` — helpers.
- **`cmd/selfhost-server-demo/`** — the real `ace` CLI (cobra). `cmds/installer.go` is the HTTP server, `cmds/sample.go` builds sample specs, `cmds/status.go` checks an HTTPS host. `main.go` wires klog logging.
- **`client/`** — small HTTP client for the `installer-meta` endpoint of the bytebuilders API. **Excluded from golangci-lint** (see `.golangci.yml`).

`cmd/ace-installer-demo/` and `cmd/kubedb-demo/` are scratch `main` packages with multiple `main_*` functions used as ad-hoc experiments — treat them as throwaway, not as features.

### Data flow for a single install request

1. Caller posts an `AceOptionsSpec` (or `sample` builds one in-process).
2. `lib.ValidateOptions` enforces invariants (domain shape, TLS issuer config, etc.).
3. `lib.CreateInstaller` creates `./workspace/files/`, calls `GenerateScriptsForACE` to render every chart values file + scripts + README into it, archives the directory, and writes both archive + metadata into the blobfs at `./objstore/`.
4. The returned artifacts are what an operator runs (`env.sh` + Helm commands) to install ACE on a target cluster.

### External APIs the installer composes

The spec types come from third-party modules (vendored):

- `go.bytebuilders.dev/installer` — the `AceOptionsSpec` itself and its OpenAPI schema.
- `go.bytebuilders.dev/catalog/api/gateway/v1alpha1` — gateway/DNS/TLS sub-types.
- `go.bytebuilders.dev/ui-wizards`, `go.bytebuilders.dev/resource-model`, `go.openviz.dev/installer`, `go.opscenter.dev/installer`, `kubeops.dev/installer` — feature-specific options.

When changing something the spec drives (a new field, a renamed key), you usually have to update **both** `lib/installer.go` (rendering) and `lib/options.go` (defaults/validation), and may need to bump the upstream module in `go.mod` first.

## Conventions

- Apache license header is required on every Go file (`make add-license`); CI fails without it.
- The gofmt rewrite rule in `.golangci.yml` rewrites `interface{}` → `any`. Use `any` in new code.
- `client/` is intentionally exempt from lint — don't add general code there.
- Generated and vendored files (`generated.*\.go`, `vendor/`) are excluded from lint.
- `make ci` is the source of truth for what must pass before merging.
