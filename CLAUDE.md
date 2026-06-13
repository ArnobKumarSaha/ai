# Who I am
DevOps/platform engineer, team lead at Appscode. Stack: Go, Bash, Kubernetes, CI/CD, GitOps, MongoDB, kubectl, helm, flux, gh, git, make.

# How to respond
- To the point. No preamble, no recap, no flattery, no apologies
- Concrete examples
- State uncertainty plainly
- When unclear or confused: ask me — don't guess or grind alone.
- Cite sources for lookups and non-trivial answers (file:line, URL).

# Workflow
- Write `plan.md` at the repo root and get my approval before proceeding when: (a) any new feature, or (b) a refactor or bugfix over ~30 lines. Required even when plan mode is off; when plan mode is on, write plan.md as well.
- Track complex tasks with a todo list.
- Before declaring a change done, run the build (`go build ./...` / `make build`); report failures verbatim. Don't run tests unless I ask.

# File access
- Freely use grep/find/ls/cat — no need to ask.
- If I scope a read ("only read X"), read nothing else.

# Code style
- Go/Bash: idiomatic, camelCase, meaningful names. Comments ONLY when logic is non-obvious. production-ready.
- Touch only what I asked — never refactor or reformat surrounding code.
- No scaffolding, boilerplate, or TODO/placeholder code.
- Surface or handle errors — never swallow them.

# Git
- Default branch is `master`. Never commit directly to it.
- Always work on a feature branch named `arnob/<desc>` (desc ≤12 chars, kebab-case); create it before committing.
- Never hardcode, guess, or commit secrets, endpoints, or env values.
- Commit: `git commit -m "<msg>" -s` (always `-s`)
- NEVER add "🤖 Generated with Claude Code" or any Claude-authorship variant to commits, PR bodies, issue comments, or anything pushed to a remote.
- Keep plan.md untracked (gitignore or don't stage); delete it before committing.
- Ask before `git push`, `git push --force`, and before opening any PR.


# Confirm before (destructive / irreversible)
- `kubectl delete`, `helm uninstall`, `rm -rf` — confirm first. Other cluster/git ops are fine.
- Adding/upgrading deps or editing go.mod/go.sum/vendor — ask first.
