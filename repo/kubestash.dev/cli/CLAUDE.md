# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`kubestash.dev/cli` is a `kubectl` plugin (`kubectl-kubestash`) that provides a CLI for managing KubeStash backup and restore operations. It interacts with the KubeStash CRDs (`kubestash.dev/apimachinery`) and uses restic directly for snapshot download/unlock operations.

## Commands

All build/test commands run inside Docker via Make.

```bash
# Build the binary
make build          # outputs to bin/kubectl-kubestash-<os>-<arch>

# Format code
make fmt

# Run unit tests (inside Docker)
make unit-tests

# Run unit tests directly (no Docker)
GOFLAGS="-mod=vendor" go test ./cmd/... ./pkg/...

# Lint
make lint

# Verify modules and generated files
make verify
```

Install the built binary as a kubectl plugin:
```bash
cp bin/kubectl-kubestash-linux-amd64 /usr/local/bin/kubectl-kubestash
kubectl kubestash --help
```

## Architecture

### Command Structure (`pkg/`)

All commands live in the `pkg` package. The entry point is `pkg/root.go` which wires all subcommands to a Cobra root. Every command file follows the pattern `NewCmdXxx(f cmdutil.Factory)` and accepts a `Factory` for kubeconfig/client resolution.

**Top-level commands:**

| Command | File | Description |
|---|---|---|
| `trigger` | `trigger.go` | Create a BackupSession to trigger immediate backup |
| `pause` / `resume` | `pause.go`, `resume.go` | Pause/resume BackupConfiguration |
| `download` | `download.go` | Download snapshot components from restic to local filesystem |
| `manifest-view` | `view.go` | View Kubernetes resources stored in a manifest snapshot |
| `manifest-restore` | `restore.go` | Restore Kubernetes resources from a manifest snapshot |
| `unlock` | `unlock.go` | Unlock restic repositories (after unclean exit) |
| `debug` | `debug.go` | Debug backup/restore/operator/storage issues with tabular output |
| `clone` | `clone.go` | Clone a PVC (using KubeStash backup+restore pipeline) |
| `copy` | `copy.go` | Copy Secrets or VolumeSnapshots across namespaces |
| `key` (password) | `key.go` | Manage restic encryption keys |
| `convert` | `convert.go` | Convert Stash v1 YAML resources to KubeStash format |

### Package-level Variables

`pkg/util.go` holds shared state:
- `klient client.Client` — global controller-runtime client, initialized once per command
- `srcNamespace`, `dstNamespace` — used by copy/clone commands
- `imgRestic` — restic container image config

### `pkg/common/` Package

Shared utilities used across multiple commands:
- `helpers.go` — `NewRuntimeClient()` builds the controller-runtime client with all needed schemes (core, storage, kubedb)
- `types.go` — `ResourceItems`, `RestoreableItem`, `ItemKey` types used for manifest view/restore
- `dump/` — restic dump helpers for extracting snapshot data

### Restic Integration

Commands that interact with restic (`download`, `unlock`, `key`) spawn restic as a subprocess (via `gomodules.xyz/restic` and `gomodules.xyz/go-sh`). They:
1. Resolve the `BackupStorage` backend credentials from Kubernetes Secrets
2. Write env vars and repo config to temp files in `ScratchDir` (`/tmp/scratch`)
3. Execute the restic binary via the `ResticImage` container (`ghcr.io/appscode-images/restic:0.18.1`)

### `convert` Command

Reads Stash v1 (`stash.appscode.dev`) YAML files from `--src-dir` and writes KubeStash equivalent YAML to `--target-dir`. Handles `BackupConfiguration`, `RestoreSession`, `BackupBlueprint`, `Repository`, `BackupStorage` conversions.

### `clone pvc` Flow

The PVC clone command orchestrates a full KubeStash backup+restore cycle:
1. Creates a BackupConfiguration targeting source PVC (using `pvc-addon`)
2. Triggers a BackupSession and waits for completion
3. Creates a RestoreSession targeting the destination PVC
4. Waits for restore completion
5. Cleans up temporary BackupConfiguration/Session
