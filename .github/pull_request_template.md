<!--
Title format: Conventional Commits `<type>(<scope>): <subject>` or `<type>: <subject>` (<= 50 chars, no trailing period).
Scope (optional): the Feature id, or the area (`ci`, `agents`, `devcontainer`, `docs`).
Do not include AI tool attribution or `Co-authored-by` trailers in commits, title, or description.
-->

## What and why

<!-- The outcome this PR makes true once merged, and why it matters. -->

## Changes

<!-- Brief summary of the Features, tests, docs, or tooling touched. -->

## Related work

<!-- Closes #N — links and closes the issue on merge. -->

## Validation

<!-- Each acceptance criterion with how it was verified, local commands run, and CI status. -->

## Checklist

- [ ] `just lint` passes locally
- [ ] Relevant Feature tests (`just test-feature <id>`, and `just test-global` if applicable) pass locally
- [ ] Changed Feature `version` in `devcontainer-feature.json` bumped using SemVer (if `src/<id>/` changed)
- [ ] Root `README.md`, `README.zh-CN.md`, and `README.en.md` updated (if a Feature was added or removed)
- [ ] No secrets, credentials, or personal data in the diff, description, or commits
- [ ] No AI tool attribution or `Co-authored-by` trailers in the commits, title, or description
