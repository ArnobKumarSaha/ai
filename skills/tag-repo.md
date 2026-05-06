---
name: tag-repo
description: >
  Tag or retag one or more Git repositories in a given GitHub org.
  Triggers on: "tag repo", "retag repo", "tag <repo> to <version>", "retag <repo> to <version>",
  "tag/retag", "create tag", "push tag", or any request mentioning repo names + a semver version.
  Examples: "Tag kubedb-ui to v0.1.0", "Retag console-ui in bytebuilders to v2.3.0",
  "Tag/Retag kubedb-ui, billing-ui in bytebuilders org to v1.5.0".
---

# Repo Tagger / Retagger

Tags or retags one or more repos in a GitHub org.

## Inputs (parse from user message)

- **Operation**: `tag` or `retag` (if user says "tag/retag", treat as `retag`)
- **Org**: e.g. `bytebuilders`, `appscode`, `kubedb` (see org → path mapping below)
- **Repos**: list of repo names, e.g. `kubedb-ui`, `console-ui`
- **Tag**: semver string, e.g. `v0.1.0`

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

## Project Type Detection

Before running the TAG workflow, detect the project type:

```bash
if [ -f "$REPO_DIR/package.json" ]; then
  PROJECT_TYPE="node"
else
  PROJECT_TYPE="other"
fi
```

Use this to decide which TAG path to follow below.

---

## Workflow

### For each repo — RETAG

A retag means: delete the existing tag locally (if any), re-point it at HEAD of master, then force-push.

```bash
REPO_DIR=~/go/src/<org-path>/<repo-name>
TAG=v0.1.0

cd "$REPO_DIR"

# Make sure we're on master and up to date
git checkout master
git pull origin master

# Force-create the tag at HEAD
git tag -fa "$TAG" -m "$TAG"

# Force-push the tag
git push origin "$TAG" -f
```

After pushing, report success: `Retagged <repo> → <tag>`.

### For each repo — TAG (new tag with PR)

First detect the project type:

```bash
if [ -f "$REPO_DIR/package.json" ]; then
  PROJECT_TYPE="node"
else
  PROJECT_TYPE="other"
fi
```

---

#### Node/JS projects (`package.json` exists)

A tag creates a branch, bumps the version in `package.json`, runs `npm i`, commits, pushes, and opens a PR.

##### Step 1 — Create branch from master

```bash
REPO_DIR=~/go/src/<org-path>/<repo-name>
TAG=v0.1.0
BRANCH="arnob-${TAG}"

cd "$REPO_DIR"
git checkout master
git pull origin master
git checkout -b "$BRANCH"
```

##### Step 2 — Update version in package.json

Use `jq` to update the `version` field (strip the leading `v`):

```bash
VERSION="${TAG#v}"   # e.g. "0.1.0"

tmp=$(mktemp)
jq --arg v "$VERSION" '.version = $v' package.json > "$tmp" && mv "$tmp" package.json
```

##### Step 3 — Install dependencies

```bash
npm i
```

If `npm i` fails, report the error and stop for that repo (don't commit broken state).

##### Step 4 — Commit and push

Stage only `package.json` and `package-lock.json` (if it changed):

```bash
git add package.json package-lock.json 2>/dev/null || git add package.json
git commit -s -m "Update to ${TAG}"
git push origin "$BRANCH"
```

Do NOT add `Co-Authored-By` or any extra trailer to this commit.

##### Step 5 — Open Pull Request

```bash
gh pr create \
  --title "Update to ${TAG}" \
  --body "Bump version to ${TAG}" \
  --base master \
  --head "$BRANCH"
```

Print the PR URL to the user.

---

#### Non-Node/JS projects (no `package.json`)

No version file to bump or dependencies to install. Tag HEAD on master directly:

```bash
cd "$REPO_DIR"
git checkout master
git pull origin master

git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"
```

If the tag already exists, stop and tell the user to use **retag** instead.

After pushing, report success: `Tagged <repo> → <tag>`.

## Processing Order

Process repos sequentially (not in parallel) so errors are easy to trace.
After all repos are done, print a summary table:

| Repo | Operation | Outcome |
|---|---|---|
| kubedb-ui | tag | PR opened: <url> |
| billing-ui | retag | Pushed tag v0.1.0 |

## Error Handling

- **Repo directory not found**: skip that repo, warn the user.
- **`git pull` fails (conflicts/no remote)**: stop for that repo, report the error.
- **`npm i` fails**: stop for that repo before committing; report the error.
- **`gh pr create` fails** (e.g. branch already has an open PR): report the error and print the branch name so the user can handle it manually.
- **Tag already exists (retag path)**: `-fa` already handles force-retagging; this should not fail.

## Notes

- Always pull latest master before branching or tagging — never tag stale state.
- The branch name is always `arnob-<tag>` (e.g. `arnob-v0.1.0`).
- Commit message is exactly `"Update to <tag>"` — no period, no extras.
- PRs target `master` unless the user says otherwise.
- If the user says "tag/retag", treat it as a **retag** (force operation).
