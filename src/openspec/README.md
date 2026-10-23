
# OpenSpec CLI (openspec) (openspec)

Installs the OpenSpec CLI (openspec), published on npm as @fission-ai/openspec, an AI-native system for spec-driven development.

## Example Usage

```json
"features": {
    "ghcr.io/minato-ryan/devcontainer-features/openspec:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Select or enter an OpenSpec version (e.g. 'latest' or '1.14.1'). | string | latest |

## OpenSpec Dev Container Feature

This feature installs the [OpenSpec CLI](https://openspec.dev/) (`openspec`), published on npm as `@fission-ai/openspec`, for spec-driven AI development workflows.

### Node.js Runtime Dependency

OpenSpec requires Node.js `20.19.0` or newer. This feature automatically declares a dependency on the official [Node.js Dev Container Feature](https://github.com/devcontainers/features/tree/main/src/node) (`ghcr.io/devcontainers/features/node:1`), ensuring an appropriate LTS runtime is available.

### PATH Availability

The `openspec` executable is placed and symlinked into `/usr/local/bin/openspec`, making it available system-wide for all container users (including root, non-root users, login shells, and non-interactive subshells).


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/minato-ryan/devcontainer-features/blob/main/src/openspec/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
