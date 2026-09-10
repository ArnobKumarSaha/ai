---
name: cluster-images
description: Collect every container image running in one or more Kubernetes clusters (kubeconfigs in ~/Downloads/configs) and write a single sorted, de-duplicated list to ~/yamls/complete-images-list.yaml, excluding bare `sha256:<digest>` entries. Use when the user asks for the images running in named clusters, an image inventory/audit across clusters, or "which images are live". Triggers on "list images in the cluster", "collect running images", "image list for offline-ace & big-cluster", "uniq image list", "what images are running".
---

# cluster-images

For each named cluster, using `~/Downloads/configs/<name>.yaml` as the kubeconfig:

```
KUBECONFIG=~/Downloads/configs/<name>.yaml kubectl get pods -A -o yaml | grep image: | sort | uniq
```

then normalizes each hit (strips `- `, `image: `, quotes), drops kubelet's digest-only
lines (`image: sha256:<64 hex>`), merges every cluster's output and prints one sorted
unique list.

The merged list is always written to **`~/yamls/complete-images-list.yaml`** (a YAML
sequence, one `- <image>` per line; parent dir created, file overwritten each run).

## Usage

A cluster argument is the kubeconfig basename, with or without `.yaml`. At least one is
required — there is no "current context" fallback, since each cluster is its own file.

```bash
# exactly the clusters the user named, nothing else
~/.claude/skills/cluster-images/collect-images.sh offline-ace big-cluster

# every kubeconfig in ~/Downloads/configs
~/.claude/skills/cluster-images/collect-images.sh all
```

Flags:

- `--per-cluster` — print each cluster's own list first, then the merged unique list.
- `--out FILE` — write the merged list to `FILE` instead of the default.
- `CONFIG_DIR=<dir>` env var — override `~/Downloads/configs`.

## Behavior notes

- Use **only** the clusters the user names. Do not add others, and do not fall back to
  `all` when a named kubeconfig is missing.
- Duplicate names are collapsed; `foo` and `foo.yaml` are the same cluster.
- A cluster that fails (missing kubeconfig, unreachable, bad creds) does not abort the
  run: the rest are still collected and written, the failures print under
  `## failed clusters`, and the script exits 1. Report the failures to the user.
- Only bare digest lines are excluded. Tag+digest references such as
  `ghcr.io/kubedb/redis-init:0.12.2@sha256:...` are kept as-is, and a registry-qualified
  image (`docker.io/rancher/klipper-lb:v0.4.17`) stays distinct from its short form
  (`rancher/klipper-lb:v0.4.17`) — pods really do declare both.

## Reporting to the user

Show the merged unique list with its count and the output path. If the user asked about a
specific vendor or prefix, `grep` the result afterwards rather than changing the script.
