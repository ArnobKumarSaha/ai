# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Does

`external-dns-operator` is a Kubernetes operator (built with kubebuilder/controller-runtime) that manages DNS records across multiple cloud providers. Users define `ExternalDNS` custom resources specifying a DNS provider (AWS Route53, Azure DNS, Google Cloud DNS, Cloudflare, etc.) and a source type (Services, Ingresses, Nodes). The operator watches those sources and automatically creates/updates/deletes DNS records via the `sigs.k8s.io/external-dns` library.

## Common Commands

```bash
# Build
make build                  # Binary for current OS/ARCH
make container              # Docker image

# Lint & format
make lint                   # golangci-lint
make fmt                    # gofmt + goimports
make check-license          # Verify license headers
make add-license            # Add missing license headers

# Test
make unit-tests             # Unit tests via hack/test.sh (runs in Docker)
go test -race ./pkg/...     # Run unit tests locally
go test ./pkg/controllers/external-dns/... -v  # Single package

# Code generation (after changing CRD types or markers)
make gen                    # clientset + manifests + openapi
make manifests              # CRD YAML only
make clientset              # client-go code only

# CI check (what runs on PRs)
make ci                     # check-license + lint + build

# Local cluster development
make install                # Install via Helm to current kubeconfig cluster
make run                    # Run operator locally (go run)
make deploy-to-kind         # Build image, push to Kind, install
```

To run a single Ginkgo test suite directly:
```bash
ginkgo -v ./pkg/controllers/external-dns
```

## Architecture

### Reconciliation Flow

1. User creates an `ExternalDNS` resource (CR) referencing a DNS provider and a Kubernetes source type.
2. The reconciler (`pkg/controllers/external-dns/externaldns_controller.go`) runs:
   - Registers a dynamic watcher on the source resource type (Service/Ingress/Node) via `pkg/informers`.
   - Loads provider credentials from the referenced Kubernetes Secret via `pkg/credentials`.
   - Calls `plan.SetDNSRecords()` (`pkg/plan/plan.go`) which creates provider+source instances from the external-dns library, builds a DNS plan, and applies it to the provider API.
   - Updates `ExternalDNS.Status` (`.phase`, `.dnsRecords`, `.conditions`).
3. Changes to source resources or their credentials re-trigger reconciliation automatically.

### Key Packages

| Package | Purpose |
|---|---|
| `apis/external/v1alpha1/` | CRD type definitions — `ExternalDNS` spec/status, provider configs |
| `pkg/controllers/external-dns/` | `Reconcile()` loop, manager setup |
| `pkg/plan/` | Wraps `sigs.k8s.io/external-dns` — creates Provider+Source, applies DNS plan |
| `pkg/credentials/` | Extracts credentials from Secrets and sets provider-specific env vars |
| `pkg/informers/` | `ObjectTracker` — dynamic watcher for arbitrary source GVKs |
| `pkg/cmds/` | CLI root command and `run` subcommand (flags, manager startup) |

### CRD: ExternalDNS

The central type. Key spec fields:
- `provider` — selects the DNS backend (aws, azure, google, cloudflare, …)
- `source` — TypeInfo (GVK) for the Kubernetes source, plus per-type config
- `domainFilter`, `zoneIDFilter` — DNS scope
- `aws`, `azure`, `google`, `cloudflare` — provider-specific blocks, each with a `secretRef`

Status reflects: `phase` (InProgress/Current/Failed), `conditions`, and the list of `dnsRecords` written.

### Credential Handling

`pkg/credentials/secret.go` dispatches by provider to per-provider functions that read a Kubernetes Secret and set the appropriate environment variables (e.g. `AWS_ACCESS_KEY_ID`, `AZURE_TENANT_ID`, `GOOGLE_APPLICATION_CREDENTIALS`). The external-dns library then picks these up when constructing provider clients.

### Test Setup

Tests use Ginkgo + Gomega with `controller-runtime/pkg/envtest` (an in-process fake Kubernetes API server). CRDs are loaded from the `crds/` directory. The suite entry point is `pkg/controllers/external-dns/suite_test.go`.

## Code Generation

CRD markers live in `apis/external/v1alpha1/`. After editing types or markers, run `make gen` to regenerate clientsets (`/client/`), CRD YAML (`/crds/`), and OpenAPI schemas. Generated files must be committed.

## Dependencies

- Go 1.25
- `sigs.k8s.io/controller-runtime` v0.22 — operator framework
- `sigs.k8s.io/external-dns` v0.20 — DNS provider/source library (the actual DNS logic lives here)
- `github.com/onsi/ginkgo` / `gomega` — test framework
