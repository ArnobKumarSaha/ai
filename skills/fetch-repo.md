---
name: fetch-repo
description: >
  Fetch and reset one or more Git repositories to a clean state from remote.
  Triggers on: "fetch branch", "fetch master", "fetch repo", "sync repo", "reset repo",
  "pull master", "clean fetch", or any request to fetch/reset/sync repos to a branch.
  Examples: "Fetch master in kubedb-ui", "Fetch the master in kubedb-ui, billing-ui in bytebuilders org",
  "Sync console-ui to master", "Fetch branch dev in kubedb-ui in bytebuilders".
---

# Repo Fetcher / Branch Syncer

Fetches and resets one or more repos to a clean remote state, then optionally checks out a specific branch.

## Inputs (parse from user message)

- **Org**: e.g. `bytebuilders`, `appscode`, `kubedb` (see org → path mapping below)
- **Repos**: list of repo names, e.g. `kubedb-ui`, `console-ui`
- **Branch**: the branch to fetch/reset to (default: `master`)

## Org → Local Path Mapping

| Org name (user says) | Local path under `~/go/src/` |
|---|---|
| bytebuilders | `go.bytebuilders.dev` |
| appscode | `go.appscode.dev` |
| kubedb | `kubedb.dev` |
| opscenter | `go.opscenter.dev` |
| kubeops | `kubeops.dev` |
| kmodules | `kmodules.xyz` |
| gomodules | `gomodules.xyz` |

If the user's org is not in this table, look for a matching directory under `~/go/src/` by name
(case-insensitive substring match). If still not found, ask the user to clarify.

The full path to a repo is: `~/go/src/<org-path>/<repo-name>`

Verify each path exists before proceeding. If a repo directory is missing, tell the user and skip it.

## Workflow

Process repos sequentially. For each repo:

### Step 1 — Check for local changes

```bash
REPO_DIR=~/go/src/<org-path>/<repo-name>
cd "$REPO_DIR"

git status --short
```

If the output is non-empty (there are uncommitted changes or untracked files), **notify the user**:

> ⚠ `<repo-name>` has local changes:
> ```
> <git status --short output>
> ```
> Proceeding will discard them. Continuing anyway...

Do NOT stop — just warn and continue. The reset in Step 3 will discard the changes.

### Step 2 — Fetch all remotes

```bash
git fetch --all
```

### Step 3 — Reset to master

```bash
git checkout master
git reset --hard origin/master
```

### Step 4 — Delete all local branches except master

List all local branches except `master` and delete them (force-delete since some may not be merged):

```bash
git branch | grep -v '^\* master$' | grep -v '^  master$' | xargs -r git branch -D
```

### Step 5 — Prune stale remote-tracking refs

```bash
git fetch --prune
```

### Step 6 — Checkout target branch (if not master)

If the user asked for a branch other than `master`:

```bash
git checkout <branch>
```

If the branch doesn't exist locally but exists on the remote, Git will automatically track it.
If it doesn't exist at all, report the error and leave the repo on `master`.

If the user asked for `master`, nothing more to do.

## Processing Order

Process repos sequentially so errors are easy to trace.
After all repos are done, print a summary table:

| Repo | Branch | Outcome |
|---|---|---|
| kubedb-ui | master | Clean, reset to origin/master |
| console-ui | master | Had local changes (warned), reset to origin/master |
| billing-ui | dev | Reset to origin/master, checked out dev |

## Error Handling

- **Repo directory not found**: skip that repo, warn the user.
- **`git fetch` fails** (e.g. no network, bad remote): report the error and skip remaining steps for that repo.
- **`git checkout master` fails**: report and stop for that repo (master may not exist — unlikely but report it).
- **Target branch not found after fetch**: leave repo on master, tell the user the branch doesn't exist.

## Notes

- Always warn about local changes but never stop because of them — the user explicitly requested a reset.
- Delete ALL local branches except master in Step 4 — this is intentional cleanup.
- `git fetch --prune` in Step 5 removes stale remote-tracking branches (e.g. deleted on remote).
- If the user says "fetch" without specifying a branch, default to `master`.
