# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubedb.dev/installer` contains:
1. **Helm charts** for deploying KubeDB operators and components (`charts/`)
2. **DB version catalog** — the source of truth for all KubeDB `*Version` CRs (e.g. `MongoDBVersion`, `PostgresVersion`) (`catalog/kubedb/raw/`)
3. **Installer API types** — Go structs that mirror Helm `values.yaml` files for type-safe validation (`apis/installer/v1/`)
4. **Chart tests** — Go tests that verify chart images exist and are multi-arch (`tests/`)

## Commands

All build/test commands run inside Docker via Make.

```bash
# Format code AND regenerate catalog YAMLs + version matrix
make fmt

# Run unit tests (validates charts, image existence)
make test
# or directly (no Docker):
GOFLAGS="-mod=vendor" go test ./apis/... ./catalog/... ./tests/...

# Run a single test
GOFLAGS="-mod=vendor" go test ./tests/... -run TestCheckCharts

# Lint
make lint

# Regenerate CRDs, values schema, chart docs
make gen        # = clientset + manifests

# Regenerate only CRDs from API types
make gen-crds

# Regenerate values.openapiv3_schema.yaml for all charts
make gen-values-schema

# Regenerate catalog image scripts (requires image-packer)
./hack/scripts/update-catalog.sh

# Verify everything is up to date
make verify
```

## Architecture

### Catalog Pipeline

The catalog is the most important part of this repo. The pipeline is:

```
catalog/kubedb/raw/{db}/      ← Hand-edited source YAML files (one per DB version)
         ↓  make fmt  (runs catalog/kubedb/fmt/main.go)
charts/kubedb-catalog/templates/{db}/   ← Generated Helm templates (wrapped in if/include)
         ↓
catalog/kubedb/active_versions.json     ← Which versions are active (hand-maintained)
catalog/kubedb/backup_tasks.json        ← stash backup task mapping (generated)
catalog/kubedb/restore_tasks.json       ← stash restore task mapping (generated)
```

**`catalog/kubedb/fmt/main.go`** is the central codegen tool. On `make fmt` it:
1. Reads all `raw/{db}/*.yaml` files
2. Normalizes and validates them (image digests, UBI image list, Sprig templates)
3. Writes Helm-wrapped templates into `charts/kubedb-catalog/templates/{db}/`
4. Updates `backup_tasks.json` and `restore_tasks.json`

**`catalog/kubedb/gen-version-matrix/main.go`** generates the version compatibility matrix from `active_versions.json`.

### Adding a New DB Version

1. Create `catalog/kubedb/raw/{db}/{db}-{version}-{distro}.yaml` following an existing file as template. Key fields: `db.image`, `initContainer.image`, `exporter.image`, `archiver`, `updateConstraints.allowlist`.
2. Add the version to `catalog/kubedb/active_versions.json` if it should be active.
3. Run `make fmt` — this generates the Helm template and updates task mappings.

### Installer API ↔ Helm Chart Relationship

Each Helm chart has a corresponding Go type in `apis/installer/v1/`:
- `charts/kubedb/` ↔ `kubedb_types.go` (`KubedbSpec`)
- `charts/kubedb-catalog/` ↔ `kubedb_catalog_types.go`
- `charts/kubedb-ops-manager/` ↔ `kubedb_ops_manager_types.go`
- etc.

The Go types drive `values.openapiv3_schema.yaml` and `values.schema.json` in each chart (via `make gen-values-schema`). When adding a new field to `values.yaml`, add it to the corresponding Go type and run `make gen`.

### Chart Structure

`charts/kubedb/` is the umbrella chart — it pulls in `kubedb-provisioner`, `kubedb-ops-manager`, `kubedb-autoscaler`, `kubedb-webhook-server`, etc. as subcharts.

`charts/kubedb-catalog/` contains only `*Version` CRs (no operator deployments). It is installable independently.

### Tests

`tests/check-charts_test.go` uses `image-packer` to verify every container image referenced in all charts:
- Exists in the registry
- Is available for the required architectures
- `ignoreMissingList` and `archSkipList` in that file control known exceptions.

When adding a new DB version with images not yet published, add to `archSkipList` temporarily.
