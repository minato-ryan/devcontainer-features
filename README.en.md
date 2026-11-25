<a id="top"></a>

<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg" />
  <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.svg" />
  <img alt="Dev Container Features" src="assets/logo-light.svg" width="96" height="96" />
</picture>

<h1>Dev Container Features</h1>

<p>
  Custom <a href="https://containers.dev/implementors/features/">Dev Container Features</a> collection<br />
  published to GitHub Container Registry (<code>ghcr.io/minato-ryan/devcontainer-features</code>)
</p>

<p>
  <a href="https://github.com/minato-ryan/devcontainer-features/actions/workflows/test.yaml"><img src="https://github.com/minato-ryan/devcontainer-features/actions/workflows/test.yaml/badge.svg" alt="Test Features" /></a>
  <a href="https://github.com/minato-ryan/devcontainer-features/actions/workflows/validate.yml"><img src="https://github.com/minato-ryan/devcontainer-features/actions/workflows/validate.yml/badge.svg" alt="Validate Metadata" /></a>
  <img src="https://img.shields.io/badge/Features-10-0EA5E9?style=flat-square" alt="Features: 10" />
  <img src="https://img.shields.io/badge/Registry-GHCR-6366F1?style=flat-square&amp;logo=github" alt="Registry: GHCR" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-10B981?style=flat-square" alt="License: MIT" /></a>
</p>

<p>
  <a href="README.md">日本語</a> &nbsp;·&nbsp; <a href="README.zh-CN.md">简体中文</a> &nbsp;·&nbsp; <strong>English</strong>
</p>

<p>
  <a href="#features">Features</a> &nbsp;·&nbsp;
  <a href="#quick-start">Quick Start</a> &nbsp;·&nbsp;
  <a href="#development">Development</a> &nbsp;·&nbsp;
  <a href="#release">Releases</a>
</p>

</div>

> [!NOTE]
> This file is an English mirror of the [Japanese README](README.md).

---

<a id="features"></a>
## Features

<table width="100%">
  <thead>
    <tr>
      <th align="left">Feature</th>
      <th align="left">Summary / Options</th>
      <th align="left">OCI Reference</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><a href="src/chezmoi/README.md"><strong>chezmoi</strong></a><br /><sub>Dotfiles</sub></td>
      <td>Installs and sets up chezmoi<br /><sub>Options: <code>config</code> ・ Depends on: <code>common-utils</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/chezmoi:1</code></td>
    </tr>
    <tr>
      <td><a href="src/colab/README.md"><strong>colab</strong></a><br /><sub>AI / Cloud</sub></td>
      <td>Installs Google Colab CLI (<code>colab</code>) and <code>rclone</code> with <code>colab-adc</code> auth helper and project-scoped ADC persistence<br /><sub>Options: <code>version</code>, <code>defaultAuth</code>, <code>installRclone</code>, <code>rcloneVersion</code>, <code>installRcloneMountDependencies</code> ・ Depends on: <code>uv</code> ・ Volume: <code>/var/lib/colab</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/colab:1</code></td>
    </tr>
    <tr>
      <td><a href="src/deno/README.md"><strong>deno</strong></a><br /><sub>Runtime</sub></td>
      <td>Installs the Deno runtime and JavaScript / TypeScript toolchain<br /><sub>Options: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/deno:1</code></td>
    </tr>
    <tr>
      <td><a href="src/glab/README.md"><strong>glab</strong></a><br /><sub>GitLab CLI</sub></td>
      <td>Installs the GitLab CLI (<code>glab</code>) for your terminal<br /><sub>Options: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/glab:1</code></td>
    </tr>
    <tr>
      <td><a href="src/hf-cli/README.md"><strong>hf-cli</strong></a><br /><sub>AI / Hub</sub></td>
      <td>Installs the Hugging Face CLI (<code>hf</code>)<br /><sub>Options: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/hf-cli:1</code></td>
    </tr>
    <tr>
      <td><a href="src/nvidia-container/README.md"><strong>nvidia-container</strong></a><br /><sub>GPU / Docker</sub></td>
      <td>Installs NVIDIA Container Toolkit and configures Docker runtime<br /><sub>Options: <code>version</code>, <code>configureDocker</code>, <code>setAsDefault</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/nvidia-container:1</code></td>
    </tr>
    <tr>
      <td><a href="src/opencode/README.md"><strong>opencode</strong></a><br /><sub>AI / Coding</sub></td>
      <td>Installs the OpenCode CLI<br /><sub>No options (runs after <code>common-utils</code>)</sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/opencode:1</code></td>
    </tr>
    <tr>
      <td><a href="src/openspec/README.md"><strong>openspec</strong></a><br /><sub>AI / Spec</sub></td>
      <td>Installs the OpenSpec CLI (<code>@fission-ai/openspec</code>)<br /><sub>Options: <code>version</code> ・ Depends on: <code>node</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/openspec:1</code></td>
    </tr>
    <tr>
      <td><a href="src/quarto/README.md"><strong>quarto</strong></a><br /><sub>Publishing</sub></td>
      <td>Installs Quarto CLI from checksum-verified official releases<br /><sub>Options: <code>version</code>, <code>checksumsSha256</code> ・ VS Code ext: <code>quarto.quarto</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/quarto:1</code></td>
    </tr>
    <tr>
      <td><a href="src/uv/README.md"><strong>uv</strong></a><br /><sub>Python</sub></td>
      <td>Installs Astral's Python package and project manager <code>uv</code> / <code>uvx</code><br /><sub>Options: <code>version</code>, <code>toolsToInstall</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/uv:1</code></td>
    </tr>
  </tbody>
</table>

> [!TIP]
> Click any Feature name in the table above to open its `src/<id>/README.md` for full option schemas, defaults, and notes.

<a id="quick-start"></a>
## Quick Start

Add the desired Features to the `features` object in your `devcontainer.json`:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/minato-ryan/devcontainer-features/uv:1": {
            "toolsToInstall": "ruff"
        },
        "ghcr.io/minato-ryan/devcontainer-features/deno:1": {
            "version": "latest"
        }
    }
}
```

<details>
<summary><strong>Recipe 1: GPU / AI Workspace (NVIDIA + Hugging Face + uv)</strong></summary>

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/devcontainers/features/docker-in-docker:2": {},
        "ghcr.io/minato-ryan/devcontainer-features/nvidia-container:1": {
            "configureDocker": true,
            "setAsDefault": false
        },
        "ghcr.io/minato-ryan/devcontainer-features/hf-cli:1": {},
        "ghcr.io/minato-ryan/devcontainer-features/uv:1": {}
    }
}
```

</details>

<details>
<summary><strong>Recipe 2: Publishing &amp; Dotfiles Workspace (Quarto + chezmoi)</strong></summary>

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/minato-ryan/devcontainer-features/quarto:1": {},
        "ghcr.io/minato-ryan/devcontainer-features/chezmoi:1": {}
    }
}
```

</details>

<a id="development"></a>
## Development & Testing

Local linting and testing require the [Dev Container CLI](https://github.com/devcontainers/cli), a running Docker daemon, `just`, `pre-commit`, and `shellcheck`.

| Command | Purpose |
| --- | --- |
| `just lint` | Run `pre-commit` (formatting, YAML/JSON, Gitleaks) and `shellcheck` across all files |
| `just test-feature <id>` | Run default and scenario tests for a specific Feature |
| `just test-global` | Run only global multi-Feature test scenarios |
| `just test` | Run all Feature tests and global scenarios together |

<details>
<summary><strong>View Repository Structure</strong></summary>

```text
.
├── assets/                             # Light/dark adaptive SVG logos for README
├── src/
│   └── <feature>/
│       ├── devcontainer-feature.json   # Feature metadata and option definitions
│       ├── install.sh                  # Install script run during container build
│       ├── NOTES.md                    # Optional notes (merged into generated README)
│       └── README.md                   # Auto-generated by the release workflow
├── test/
│   ├── <feature>/
│   │   ├── scenarios.json              # Per-Feature test scenarios
│   │   ├── test.sh                     # Default configuration test
│   │   └── *.sh                        # Scenario-specific test scripts
│   └── _global/                        # Global test scenarios
├── .github/workflows/                  # CI validation, test, and release workflows
└── justfile                            # Local lint and test recipes
```

</details>

<a id="release"></a>
## Releases & Documentation Generation

1. Each Feature's version is managed independently via SemVer in `src/<id>/devcontainer-feature.json` (`version`).
2. Triggering the manual [release workflow](.github/workflows/release.yaml) on `main` publishes every Feature to GHCR and creates `feature_<id>_<semver>` tags.
3. The workflow also auto-generates `src/<id>/README.md` (merging any existing `src/<id>/NOTES.md`) and opens a Pull Request with the documentation updates.

<hr />

<div align="center">
  <p>
    Released under the <a href="LICENSE">MIT License</a> &nbsp;·&nbsp; <a href="#top">↑ Back to top</a>
  </p>
</div>
