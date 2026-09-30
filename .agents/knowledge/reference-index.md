# Reference index

Read this index when a task needs Dev Container semantics, CLI flags, GitHub
Actions behavior, or tool syntax. Follow only the references relevant to that
task. Upstream documentation and the installed tool's `--help` are authoritative
for external behavior; this file is a route to them, not a copy of their rules.
Update this index when a selected tool or upstream documentation location
changes.

## Dev Containers

| Read when | Source and role |
| --- | --- |
| Defining Feature metadata, dependency order, distribution, `legacyIds`, or `deprecated` | [Specification Markdown](https://github.com/devcontainers/spec/tree/main/docs/specs) is normative; [JSON Schemas](https://github.com/devcontainers/spec/tree/main/schemas) define structure. |
| Checking rendered Feature guidance | [containers.dev](https://containers.dev/) and its [Feature implementor pages](https://containers.dev/implementors/features/) explain the spec; [implementor sources](https://github.com/devcontainers/devcontainers.github.io/tree/gh-pages/_implementors) and [posts](https://github.com/devcontainers/devcontainers.github.io/tree/gh-pages/_posts) supply their maintained text. |
| Testing a Feature or verifying a CLI command | [CLI docs](https://github.com/devcontainers/cli/tree/main/docs), especially [Feature testing](https://github.com/devcontainers/cli/blob/main/docs/features/test.md); verify flags with `devcontainer <command> --help`. |
| Looking for implementation patterns | [Official Feature collection](https://github.com/devcontainers/features) (`src/`, `test/`, workflows) and [Feature starter](https://github.com/devcontainers/feature-starter) are examples, not this repository's contract. |
| Validating, publishing, generating docs, or tagging during release | [Dev Container publish action](https://github.com/devcontainers/action) and its [inputs](https://github.com/devcontainers/action/blob/main/action.yml) define the release workflow's behavior. |
| Reviewing agent guidance patterns | [Dev Container Templates AGENTS.md](https://raw.githubusercontent.com/devcontainers/templates/main/AGENTS.md) is an example for a different repository. |
| Building or running complete dev container images in CI | [Dev Container CI action docs](https://github.com/devcontainers/ci/tree/main/docs) apply to images; this repository's Feature tests use the CLI. |

## OpenSpec

Read these only when the team explicitly reconsiders a specification workflow;
OpenSpec is not part of the current development process. Start with the
[index](https://openspec.dev/llms.txt) or [rendered docs](https://openspec.dev/docs),
then consult the [full text](https://openspec.dev/llms-full.txt),
[documentation source](https://github.com/Fission-AI/OpenSpec/tree/main/docs),
[worked specs](https://github.com/Fission-AI/OpenSpec/tree/main/openspec), or
[skills](https://github.com/Fission-AI/OpenSpec/tree/main/skills) as needed.

## GitHub

| Read when | Source and role |
| --- | --- |
| Changing Actions syntax or PR checks | [GitHub docs index](https://docs.github.com/llms.txt) locates the docs APIs; [Actions docs](https://docs.github.com/en/actions) are authoritative, with [source](https://github.com/github/docs/tree/main/content/actions). Append `.md` to an article URL for Markdown. |
| Using or documenting a `gh` command | [GitHub CLI manual](https://cli.github.com/manual/) and its [source](https://github.com/cli/cli/tree/trunk/docs); confirm locally with `gh <command> --help`. |

## Tooling

| Read when | Source and role |
| --- | --- |
| Adding a Deno management script | [Deno index](https://docs.deno.com/llms.txt) and [full docs](https://docs.deno.com/llms-full.txt) are the command and API references. |
| Choosing uv for a new script or its PEP 723 dependencies | [uv index](https://docs.astral.sh/uv/llms.txt) and [documentation source](https://github.com/astral-sh/uv/tree/main/docs) are references; uv is not currently required by this harness. |
| Editing `justfile` recipes | [just manual](https://just.systems/man/en/) is authoritative; [agent notes](https://raw.githubusercontent.com/casey/just/master/skills/just/SKILL.md) and [README](https://raw.githubusercontent.com/casey/just/master/README.md) are supplementary. |
| Editing Pre-commit hooks | [Pre-commit docs](https://pre-commit.com/) define hook configuration; [site source](https://github.com/pre-commit/pre-commit.com/tree/main/sections) is supplementary. |
