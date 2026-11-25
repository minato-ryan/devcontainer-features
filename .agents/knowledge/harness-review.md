# Harness Review

Read this when `AGENTS.md` passes about 120 lines, after roughly every tenth
merged Feature pull request, or when a documented rule turns out to be stale or
contradicted by the repository.

Prepare a local review report with `keep / update / remove` recommendations for
the maintainer before editing anything. If a maintainer explicitly delegates
opening an Issue, mirror the headings of `.github/ISSUE_TEMPLATE/03-task.yml`
and pass `.agents/knowledge/publish-gate.md`.

## Checklist

- Every path, `just` recipe, and CI workflow or job name referenced in
  `AGENTS.md`, `.agents/knowledge/`, and `.agents/skills/` still exists and
  works.
- Every knowledge file and skill is reachable from `AGENTS.md`'s "When to read
  what" table; every skill under `.agents/skills/` has a valid relative symlink
  in `.claude/skills/`; no two files state the same rule differently.
- Tooling and Action versions across `.github/workflows/`, `.github/actions/`,
  `.devcontainer/devcontainer.json`, and `.pre-commit-config.yaml` are not far
  behind upstream and agree with the docs.
- Base images in `.github/workflows/test.yaml` still match what the
  repository's Features support.
- The Features listed in the Japanese root `README.md` and its mirrors
  `README.zh-CN.md` and `README.en.md` match the actual directories in `src/`.
- `.github/ISSUE_TEMPLATE/` and `.github/pull_request_template.md` match current
  `justfile` recipes and repository conventions.
- External links in `.agents/knowledge/reference-index.md` still resolve.
