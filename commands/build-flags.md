---
description: Show ldflags build flags (Version, GitBranch, EnforceLicense, ...) baked into a container image's Go binary
argument-hint: <image-ref>
allowed-tools: Bash(bash ~/.claude/scripts/inspect-build-flags.sh:*)
---

Run the build-flags inspector on the image ref the user provided and report the results.

Image ref: `$ARGUMENTS`

Run exactly:

```
bash ~/.claude/scripts/inspect-build-flags.sh $ARGUMENTS
```

Then present the injected build flags as a table. Call out the value of
`info.EnforceLicense` explicitly (`true` = license enforcement on, `false`/`<empty>` = off).

The script pulls the image, extracts its entrypoint Go binary, and reads every
`-X importpath.Name=value` ldflag straight from the ELF symbol table (no need to
run the foreign-arch binary). Set `PLATFORM=linux/arm64` before the command if
the image is not linux/amd64.
