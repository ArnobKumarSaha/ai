---
name: update-deps
description: >
  Update Go module dependencies in a repo's go.mod, run go mod tidy && go mod vendor, then commit and push.
  Triggers on: "update deps", "update dependencies", "update go.mod", or any request mentioning
  a repo name + dependency names with target branches.
  Examples: "Update deps of installer in kubedb org with kubedb/apimachinery to master",
  "Update dependencies of repo installer in kubedb org, with kubedb/apimachinery to master & kubestash/apimachinery to master & kubeops/installer to abc branch".
---

# Go Dependency Updater

Updates specific Go module dependencies in a single repo using `go get`, then tidies, vendors, and commits the result.

## Inputs (parse from user message)

- **Org**: e.g. `kubedb`, `kubeops` (see org → path mapping below)
- **Repo**: single repo name, e.g. `installer`
- **Deps**: one or more `<dep-org>/<dep-repo>` → `<branch>` pairs
  - Separator between pairs: `&`, `and`, or `,`
  - Branch keywords: `to <branch>`, `@ <branch>`, `on <branch>`
  - Example: `kubedb/apimachinery to master & kubeops/installer to abc`

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
| kubestash | `kubestash.dev` |
| kubevault | `kubevault.dev` |
| voyagermesh | `voyagermesh.dev` |

If the org is not in the table, search for a matching directory under `~/go/src/` (case-insensitive substring match). If still not found, ask the user to clarify.

The full path to a repo is: `~/go/src/<org-path>/<repo-name>`

## Dep Org → Module Path Mapping

Use the same table to resolve the module path for each dependency:

- `kubedb/apimachinery` → `kubedb.dev/apimachinery`
- `kubestash/apimachinery` → `kubestash.dev/apimachinery`
- `kubeops/installer` → `kubeops.dev/installer`

If the dep org is **not** in the mapping table, fall back to `github.com/<dep-org>/<dep-repo>`.

## Workflow

### Step 1 — Resolve and verify repo path

```bash
REPO_DIR=~/go/src/<org-path>/<repo-name>
```

If the directory does not exist, stop and tell the user. Do not proceed.

### Step 2 — Check current git branch

```bash
cd "$REPO_DIR"
CURRENT_BRANCH=$(git branch --show-current)
echo "$CURRENT_BRANCH"
```

- If `master`: ask the user for a working branch name, then create and check it out:
  ```bash
  git checkout -b <user-provided-branch>
  ```
- If any other branch: proceed on that branch as-is (no checkout needed).

### Step 3 — Update each dependency

For each dep pair `<dep-org>/<dep-repo>` → `<branch>`:

1. Resolve the full module path using the mapping table (or fall back to `github.com/<dep-org>/<dep-repo>`).

2. Check if it exists in `go.mod`:
   ```bash
   grep -q "<module-path>" go.mod
   ```

3. If **not found**: print a warning and skip:
   > ⚠ `<module-path>` not found in go.mod — skipping

4. If **found**: update it:
   ```bash
   go get <module-path>@<branch>
   ```
   Report success or the full error output if it fails. On failure, stop — go.mod may be partially modified.

### Step 4 — Tidy and vendor

```bash
go mod tidy && go mod vendor
```

Report success. On failure, print the full error and stop.

### Step 5 — Commit and push

```bash
git add go.mod go.sum vendor/
git commit -m "Update deps" -s
git push origin HEAD
```

- `-s` adds a DCO `Signed-off-by:` line using the user's git config name/email. Do **not** add a Claude co-author line.
- If push fails because the remote branch doesn't exist yet, retry with:
  ```bash
  git push --set-upstream origin <branch>
  ```

## Error Handling

| Situation | Action |
|---|---|
| Repo directory not found | Stop immediately, tell the user |
| Dep not in go.mod | Warn and skip that dep, continue with others |
| `go get` fails | Report full error, stop (go.mod may be partially changed) |
| `go mod tidy` or `go mod vendor` fails | Report full error, stop |
| `git push` fails (no upstream) | Retry with `--set-upstream origin <branch>` |
| `git push` fails for another reason | Report the error, do not retry |

## Final Summary

After all steps complete, print a summary table:

| Dep | Module Path | Branch | Result |
|---|---|---|---|
| kubedb/apimachinery | kubedb.dev/apimachinery | master | Updated |
| kubestash/apimachinery | kubestash.dev/apimachinery | master | Updated |
| kubeops/installer | kubeops.dev/installer | abc | Not in go.mod (skipped) |

Then: `Committed and pushed to <branch>.`

## Notes

- Always one repo per invocation. If the user mentions multiple repos, ask which one to process first.
- The branch the user specifies per-dep is the **Go module version ref** (passed to `go get`), not a local git branch.
- `go mod vendor` is always run — do not skip it even if the repo has no `vendor/` directory yet.
- Never amend commits or force-push. Always create a new commit.
