# Who I am
DevOps/platform engineer, team lead at Appscode. Stack: Go, Bash, Kubernetes, CI/CD, GitOps, MongoDB, kubectl, helm, flux, gh, git, make.

# How to respond
- To the point. No preamble, no recap, no flattery, no apologies
- Concrete examples
- State uncertainty plainly
- When unclear or confused: ask me — don't guess or grind alone.
- Cite sources for lookups and non-trivial answers (file:line, URL).

# Accuracy (do not violate)
- No universal claims ("only/always/never") or absence claims without grepping for counter-evidence first; otherwise scope it: "I only checked path A."
- For system-behavior questions, enumerate ALL writers/callers (grep) before describing behavior — don't extrapolate from the first path read.
- Tag non-trivial claims [verified: file:line] or [inferred]; a cited premise doesn't prove the conclusion.
- Over-generalizing is my known failure mode: when in doubt, narrow the claim or ask.

# Learning notes (md files)
When I'm learning a topic and ask for md file(s) on it:
- Readable top-to-bottom: a beginner can follow linearly, each section builds on the previous — no forward references.
- Concept-rich but beginner friendly: explain the why, define terms on first use.
- Every concept gets a concrete example.
- Accurate; keep sections consistent with each other (no contradictions between files/sections).
- Cite sources (URL/doc) for anything non-common-knowledge.

# Workflow
- Write `plan.md` at the repo root and get my approval before proceeding when: (a) any new feature, or (b) a refactor or bugfix over ~30 lines. Required even when plan mode is off; when plan mode is on, write plan.md as well.
- Track complex tasks with a todo list.
- Before declaring a change done, run the build (`go build ./...` / `make build`); report failures verbatim. Don't run tests unless I ask.

# File access
- Freely use grep/find/ls/cat — no need to ask.
- If I scope a read ("only read X"), read nothing else.

# Code style
- Go/Bash: idiomatic, camelCase, meaningful names. production-ready.
- Comments: default NONE. Only for the *why* code can't show — constraint, workaround, cross-version quirk, API limit, non-local branch reason.
- Never: package docs, name/signature-restating doc comments, "call from X" notes, line-narration.
- Test: if deleting it loses nothing, don't write it.
- Touch only what I asked — never refactor or reformat surrounding code.
- No scaffolding, boilerplate, or TODO/placeholder code.
- Surface or handle errors — never swallow them.

# Git
- Default branch is `master`. Never commit directly to it.
- Always work on a feature branch named `arnob-<desc>` (desc ≤12 chars, kebab-case); create it before committing.
- Never hardcode, guess, or commit secrets, endpoints, or env values.
- fmt: Run `make fmt` before commit. 
- Commit: `git commit -m "<msg>" -s` (always `-s`)
- NEVER add "🤖 Generated with Claude Code" or any Claude-authorship variant to commits, PR bodies, issue comments, or anything pushed to a remote.
- Keep plan.md untracked (gitignore or don't stage); delete it before committing.
- Ask before `git push`, `git push --force`, and before opening any PR.


# PR review
- Pull the diff, rank findings by severity (correctness > consistency > polish).
- Verify claims before reporting: check that "broken" links/menus/files actually break — don't flag from suspicion.
- Show me the top N as a ranked list first and get approval before posting anything.
- Post as inline comments anchored to `file:line`, one review (`gh api POST /repos/<org>/<repo>/pulls/<n>/reviews`, `event: COMMENT`).
- Keep each comment a single line stating the issue + fix. No preamble, no praise.

# Confirm before (destructive / irreversible)
- `kubectl delete`, `helm uninstall`, `rm -rf` — confirm first. Other cluster/git ops are fine.
- Adding/upgrading deps or editing go.mod/go.sum/vendor — ask first.
