# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Kubepack** is a Kubernetes package management toolkit that bundles multiple Helm charts into a single installable unit. It handles bundle composition, dependency management, permission pre-flight checks, and generates Helm 3 or YAML install scripts. The main API types live in the external `x-helm.dev/apimachinery` module.

## Common Commands

```bash
make build          # Build binaries via Docker (output: bin/{OS}_{ARCH}/kubepack-operator)
make fmt            # Format code: goimports + gofmt + shfmt
make lint           # Run golangci-lint
make unit-tests     # go test -race -mod=vendor
make ci             # verify-modules + check-license + lint + build + unit-tests

# Run a single test
go test -v -race -mod=vendor ./pkg/lib/... -run TestFunctionName
```

Builds use `CGO_ENABLED=0`, `GO111MODULE=on`, `GOFLAGS="-mod=vendor"`, Go 1.25.

## Architecture

### Data Flow

```
Helm Chart Repo
    → Bundle (chart defining package groups)
    → BundleView (rendered selectable options)
    → Order (user's selections)
    → Install Scripts (helm3 commands or kubectl YAML)
    → AppRelease CRD + Application upload to blob storage
```

### Core Packages

**`pkg/lib/`** — all business logic:

| File | Responsibility |
|------|---------------|
| `bundle.go` | Load a Bundle from a Helm chart (`GetBundle`) |
| `bundleview.go` | Render a Bundle into selectable UI options (`CreateBundleViewForBundle/Chart`) |
| `order.go` | Convert BundleView selections into an Order (`CreateOrder`) |
| `helm3.go` / `yaml.go` | Generate helm install commands or kubectl YAML (`GenerateHelm3Script`, `GenerateYAMLScript`) |
| `executors.go` | All executor types implementing `Do() error` — compose install operations |
| `permissions.go` | RBAC pre-flight via SubjectAccessReview (`CheckPermissions`) |
| `plan.go` | Feature comparison across bundle versions (`ComparePlans`) |
| `blob.go` | Multi-cloud storage abstraction (GCS/S3/Azure/local) via `gocloud.dev/blob` |
| `script.go` | `ScriptOptions` / functional options pattern for script generation |

**`cmd/`** — 21 standalone CLI tools, each thin wrappers over `pkg/lib`. Common ones:
- `bundle-generator`, `bundleview-generator`, `order-generator` — pipeline steps
- `helm3-command-generator`, `install-yaml-generator` — script output
- `permission-checker` — RBAC validation
- `install-order`, `uninstall-order` — execute installs
- `chart-to-bundleview` — shortcut: chart → BundleView in one step

All CLI tools share a cached chart registry via `cmd/internal/DefaultRegistry` (`repo.NewDiskCacheRegistry()`).

### Key Patterns

**Executor / `Do()` pattern** (`executors.go`): Every install step is an executor with a `Do() error` method. Sequential operations are composed in order — e.g., `WaitForPrinter → Helm3CommandPrinter → ApplicationUploader`. All write to a shared `io.Writer`.

**Functional options** (`script.go`): Script generation functions accept `...ScriptOption`; each option implements `Apply(*ScriptOptions)`.

**Bundle composition**: Bundles contain charts, sub-bundles, or `OneOf` selections. BundleView generation is recursive (level tracking controls whether nested packages are marked required).

**Values patching**: JSON Patch (RFC 6902) applied on top of base values; used for license key injection and overrides.

### External API Dependencies

- `x-helm.dev/apimachinery` — Bundle, Order, PackageView, BundleView CRD types
- `kubepack.dev/lib-helm` — `IRegistry` interface and disk-cache chart registry
- `helm.sh/helm/v3` — chart rendering (uses x-helm fork)
- `k8s.io/client-go@v0.34.3` — Kubernetes API client
- `gocloud.dev/blob` — cloud-agnostic blob storage
