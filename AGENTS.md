# Agent guide

A collection of Dev Container Features located in `src/`, tested in `test/`,
and published independently to `ghcr.io/minato-ryan/devcontainer-features/<id>`.
Inspect `src/<id>/` to discover available Features, and read the manifest,
install script, and tests for the affected Feature before changing it.

## Project map

```text
src/<id>/          <- Feature metadata (devcontainer-feature.json), install.sh, optional NOTES.md, generated README.md
test/<id>/         <- Feature tests: test.sh, scenarios.json + <scenario>.sh
test/_global/      <- Multi-Feature global scenarios
.github/           <- Workflows (test, validate, secret scanning, release), local actions, Issue forms, PR template
.devcontainer/     <- Development container configuration
.agents/knowledge/ <- Agent knowledge base, routed from the table below
.agents/skills/    <- Project skills (mirrored to Claude Code via symlinks in .claude/skills/)
```

## Core conventions

- Never hand-edit generated `src/*/README.md`: the release workflow generates
  it from the manifest and `NOTES.md`.
- Do not attribute commits, issues, or pull requests to AI tools (no
  `Co-authored-by:` trailers or tool-generated markers).
- The repository is public: credentials, tokens, private hostnames, and PII
  never enter a file, commit, issue, or pull request. Never bypass pre-commit
  hooks (`--no-verify`). Every delegated `git push` or public GitHub write must
  pass `.agents/knowledge/publish-gate.md`.
- Agents inspect, edit, and validate locally. A maintainer decides when to
  commit, push, open or merge (squash merge) a PR, and trigger the manual
  release workflow, unless a later task explicitly delegates an action.
- Root documentation uses the Japanese `README.md` and its mirrors
  `README.zh-CN.md` and `README.en.md`.

## When to read what

| Situation | Read |
| --- | --- |
| Adding a Feature or changing its manifest, installer, tests, version, or release notes | `.agents/skills/devcontainer-feature-workflow/SKILL.md` |
| Creating a branch, writing a commit, working on a PR, tagging, or preparing a release | `.agents/knowledge/git-workflow.md` |
| Delegated `git push` or any GitHub write (Issue, PR, comment, review reply) | `.agents/knowledge/publish-gate.md` |
| Checking Dev Container semantics, CLI flags, GitHub Actions behavior, or tool syntax | `.agents/knowledge/reference-index.md` |
| This file passes ~120 lines, every ~10 merged Feature PRs, or a rule turns out stale | `.agents/knowledge/harness-review.md` |

## Validate changes

| Check | Command |
| --- | --- |
| Pre-commit checks (requires Pre-commit and ShellCheck) | `just lint` |
| One Feature's defaults and scenarios | `just test-feature <id>` |
| Global scenarios | `just test-global` |
| All Features and global scenarios | `just test` |

Feature tests require the Dev Container CLI and a working Docker daemon.
Metadata validation runs in `.github/workflows/validate.yml`, and
`.github/workflows/test.yaml` auto-discovers Features from `src/` to test
only changed Features (and affected global scenarios) on push/PR or all
Features on `workflow_dispatch`.

## Keep in sync

| When this changes | Update in the same change |
| --- | --- |
| A knowledge file or skill is added, renamed, or removed | "When to read what" table here and `.claude/skills/` symlink |
| Feature or test layout | `AGENTS.md` and `devcontainer-feature-workflow` skill |
| `justfile`, Pre-commit config, devcontainer setup, or test CI job | Validation table here, `.github/pull_request_template.md`, and affected skill steps |
| Release workflow, merge policy, or authority boundary | `.agents/knowledge/git-workflow.md`, `AGENTS.md`, and affected skill steps |
| A Feature is added or removed | Japanese root `README.md` and its mirrors `README.zh-CN.md` and `README.en.md` |

When editing guidance, verify its paths and commands against the repository.
Treat upstream documentation and the installed CLI's `--help` as the source
of truth for external syntax.
