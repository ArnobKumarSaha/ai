# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubestash.dev/installer` contains:
1. **Helm charts** for deploying KubeStash (`charts/`)
2. **Addon/Function catalog** — source YAML files for KubeStash `Addon` and `Function` CRs (`catalog/raw/`)
3. **Installer API types** — Go structs mirroring Helm `values.yaml` for schema validation (`apis/installer/v1alpha1/`)
4. **Chart tests** — Go tests that verify chart images exist and are multi-arch (`tests/`)

## Commands

All build/test commands run inside Docker via Make.

```bash
# Format code AND regenerate catalog Helm templates
make fmt

# Run unit tests (validates chart image architectures)
make test
# or directly (no Docker):
GOFLAGS="-mod=vendor" go test ./apis/... ./tests/...

# Run a single test
GOFLAGS="-mod=vendor" go test ./tests/... -run Test_CheckImageArchitectures

# Lint
make lint

# Regenerate CRDs, values schemas, chart docs
make gen        # = clientset + manifests (gen-crds + gen-values-schema + gen-chart-doc)

# Verify everything is current
make verify
```

## Architecture

### Catalog Pipeline

The catalog is the primary artifact of this repo. The pipeline:

```
catalog/raw/{addon}/       ← Hand-edited source YAML (Addon + Function CRDs)
    ↓  make fmt  (runs hack/fmt/main.go)
charts/kubestash-catalog/templates/{addon}/   ← Generated Helm-wrapped templates
    ↓
catalog/imagelist.yaml     ← Generated list of all container images (for air-gap)
```

**`hack/fmt/main.go`** is the codegen tool. On `make fmt` it:
1. Reads all `catalog/raw/{addon}/*.yaml` files
2. Wraps each in a Helm conditional template using `hack/fmt/templates/`
3. Writes output to `charts/kubestash-catalog/templates/{addon}/`
4. Runs `helm template` to validate the generated output
5. Updates `catalog/imagelist.yaml` with all container image references

### Addon Types

The catalog contains these addon categories (each has its own subdirectory):
- `pvc` — PVC backup/restore (Restic + VolumeSnapshotter)
- `workload` — Deployment/StatefulSet/DaemonSet workload backup (Restic)
- `kubedump` — Kubernetes manifest dump
- `manifest` — generic manifest backup
- `vault` — HashiCorp Vault backup
- `volumesnapshot` — CSI VolumeSnapshot

Each addon directory contains:
- `{name}-addon.yaml` — `Addon` CR defining backup/restore tasks and their parameters
- `{name}-backup-function.yaml` — `Function` CR (the container that runs the backup)
- `{name}-restore-function.yaml` — `Function` CR (the container that runs the restore)

### Adding a New Addon

1. Create `catalog/raw/{addon}/` with `{addon}-addon.yaml`, `{addon}-backup-function.yaml`, `{addon}-restore-function.yaml`
2. Run `make fmt` — this generates the Helm templates in `charts/kubestash-catalog/templates/{addon}/`
3. Add enable/disable toggle in `apis/installer/v1alpha1/kubestash_catalog_types.go` (e.g. `MyAddonSpec`)

### Installer API ↔ Helm Chart Relationship

Each chart has a corresponding Go type in `apis/installer/v1alpha1/`:
- `charts/kubestash/` ↔ `kubestash_types.go` (`KubestashSpec`) — umbrella chart
- `charts/kubestash-catalog/` ↔ `kubestash_catalog_types.go` (`KubestashCatalogSpec`)
- `charts/kubestash-operator/` ↔ `kubestash_operator_types.go`

The Go types drive `values.openapiv3_schema.yaml` and `values.schema.json` (via `make gen-values-schema`). When adding a new field to `values.yaml`, add it to the corresponding Go type and run `make gen`.

### `charts/kubestash`

The umbrella chart. Its `Chart.yaml` lists all component charts as dependencies. Values flow from `KubestashSpec` through subcharts via the global values.

### Tests

`tests/check-charts_test.go` uses `image-packer` to verify every container image referenced across all charts:
- `Test_CheckImageArchitectures` — verifies images exist and support required platforms
- `Test_CheckUBIImageArchitectures` — verifies UBI (Red Hat UBI) variant images

To generate image scripts for air-gapped deployments:
```bash
./hack/scripts/update-catalog.sh   # requires image-packer in PATH
```
