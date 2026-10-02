# Agent guide

This repository publishes Dev Container Features for `chezmoi`, `opencode`, and `uv`.
Feature metadata and install behavior live in `src/<id>/`; tests live in
`test/<id>/` and `test/_global/`. Read the manifest, install script, and tests
for the affected Feature before changing it. The root README still contains
starter examples and is not the source of truth for current Features.

## Read when needed

- Read [the Feature workflow](.agents/skills/devcontainer-feature-workflow/SKILL.md)
  when adding a Feature or changing its metadata, installer, tests, version,
  or release documentation.
- Read [the reference index](.agents/knowledge/reference-index.md) when
  checking Dev Container semantics, CLI flags, GitHub Actions behavior, or
  tool syntax. Follow its topic-specific links rather than relying on a
  remembered command.
- Read [the Git workflow](.agents/knowledge/git-workflow.md) before creating a
  branch, writing a commit, working on a PR, tagging, or preparing a release.

## Validate changes

- `just lint`: run the repository's Pre-commit checks. It requires
  Pre-commit and ShellCheck.
- `just test-feature <id>`: test one Feature's defaults and scenarios.
- `just test-global`: run global scenarios.
- `just test`: test all Features and global scenarios.
- Feature tests require the Dev Container CLI and a working Docker daemon.
  Metadata validation also runs in the pull-request `validate` workflow.

Agents may inspect, edit, and validate locally. A maintainer decides when to
commit, push, open or merge a PR, and trigger the manual release workflow,
unless a later task explicitly delegates one of those actions. Because this is
a public repository, scrubbing sensitive data after publication is rarely
complete. Before committing, pushing, or publishing any Issue or PR, agents
must explicitly inspect all diffs, messages, titles, bodies, and command output
for secrets (API keys, tokens, credentials, private keys) and personal
identifiable information (PII such as personal emails, real names, or private
hostnames). Pre-commit hooks—including Gitleaks secret scanning—must never be
bypassed under any circumstance (e.g. no `--no-verify`).

Keep guidance current in the same change:

- A new or removed Feature or a changed test layout updates this map and the
  Feature workflow.
- A changed `justfile`, Pre-commit config, devcontainer setup, or test CI job
  updates the validation commands here and any affected Feature workflow step.
- A changed release workflow or integration policy updates the Git workflow,
  the Feature release step, and the authority boundary here.
- When the root README is corrected, remove the starter warning above.

When editing guidance, verify its paths and commands against the repository.
Treat upstream documentation and the installed CLI's `--help` as the source
of truth for external syntax.
