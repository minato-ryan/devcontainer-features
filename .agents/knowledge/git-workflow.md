# Git and GitHub workflow

Read this before creating branches, writing commits, handling pull requests,
tagging a Feature, or preparing a release. This file records the team's
conventions. The repository's workflows and Feature manifests are the source
of truth for actual CI triggers and published versions; GitHub settings are
configured by maintainers.

- Use GitHub Flow: `main` is the only long-lived branch. A maintainer creates
  a short-lived branch from the relevant GitHub Issue using GitHub's branch
  creation flow; agents work on the provided branch.
- Use English Conventional Commits: a lowercase type such as `feat`, `fix`,
  `docs`, or `chore`, followed by an imperative description. Keep the title at
  most 50 characters without a final period; keep body lines at most 72
  characters. Do not attribute commits to AI tools.
- Integrate through a PR after the relevant CI checks pass and a maintainer
  approves it. Use a merge commit, then delete the short-lived branch.
  `main` protection and required checks are maintainer-managed GitHub
  settings; this file does not assert that they are currently enforced.
- Treat urgent fixes the same way: branch from `main`, validate, merge through
  a PR, then let a maintainer publish the affected Feature.
- Version each Feature independently in its `devcontainer-feature.json`.
  The corresponding tag format is `feature_<id>_<semver>`, for example
  `feature_opencode_1.0.0`. A maintainer manually dispatches the release
  workflow from `main`; its publish action creates release tags by default.

Agents stop at local changes and validation unless the task explicitly
delegates a Git or GitHub action. If branch, merge, release, or approval policy
changes, update this file alongside the affected workflow or setting.
