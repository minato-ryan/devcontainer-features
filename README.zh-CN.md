<a id="top"></a>

<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg" />
  <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.svg" />
  <img alt="Dev Container Features" src="assets/logo-light.svg" width="96" height="96" />
</picture>

<h1>Dev Container Features</h1>

<p>
  发布于 GitHub Container Registry（<code>ghcr.io/minato-ryan/devcontainer-features</code>）的<br />
  自定义 <a href="https://containers.dev/implementors/features/">Dev Container Features</a> 集合
</p>

<p>
  <a href="https://github.com/minato-ryan/devcontainer-features/actions/workflows/test.yaml"><img src="https://github.com/minato-ryan/devcontainer-features/actions/workflows/test.yaml/badge.svg" alt="Test Features" /></a>
  <a href="https://github.com/minato-ryan/devcontainer-features/actions/workflows/validate.yml"><img src="https://github.com/minato-ryan/devcontainer-features/actions/workflows/validate.yml/badge.svg" alt="Validate Metadata" /></a>
  <img src="https://img.shields.io/badge/Features-10-0EA5E9?style=flat-square" alt="Features: 10" />
  <img src="https://img.shields.io/badge/Registry-GHCR-6366F1?style=flat-square&amp;logo=github" alt="Registry: GHCR" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-10B981?style=flat-square" alt="License: MIT" /></a>
</p>

<p>
  <a href="README.md">日本語</a> &nbsp;·&nbsp; <strong>简体中文</strong> &nbsp;·&nbsp; <a href="README.en.md">English</a>
</p>

<p>
  <a href="#features">Features</a> &nbsp;·&nbsp;
  <a href="#quick-start">快速开始</a> &nbsp;·&nbsp;
  <a href="#development">开发与测试</a> &nbsp;·&nbsp;
  <a href="#release">发布</a>
</p>

</div>

> [!NOTE]
> 本文件为 [日本語 README](README.md) 的简体中文镜像。

---

<a id="features"></a>
## Features

<table width="100%">
  <thead>
    <tr>
      <th align="left">Feature</th>
      <th align="left">简介 / 选项</th>
      <th align="left">OCI 引用</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><a href="src/3d-tools/README.md"><strong>3d-tools</strong></a><br /><sub>3D / Simulation</sub></td>
      <td>从经校验和验证的官方发布包安装 Blender 与 Godot（标准 / .NET），用于无头 3D 模拟仿真工作流<br /><sub>选项: <code>install*</code>, <code>*Version</code>, <code>godotVariant</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/3d-tools:1</code></td>
    </tr>
    <tr>
      <td><a href="src/chezmoi/README.md"><strong>chezmoi</strong></a><br /><sub>Dotfiles</sub></td>
      <td>安装并初始化配置 chezmoi<br /><sub>选项: <code>config</code> ・ 依赖: <code>common-utils</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/chezmoi:1</code></td>
    </tr>
    <tr>
      <td><a href="src/deno/README.md"><strong>deno</strong></a><br /><sub>Runtime</sub></td>
      <td>安装 Deno 运行时及 JavaScript / TypeScript 工具链<br /><sub>选项: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/deno:1</code></td>
    </tr>
    <tr>
      <td><a href="src/glab/README.md"><strong>glab</strong></a><br /><sub>GitLab CLI</sub></td>
      <td>在终端中安装 GitLab CLI（<code>glab</code>）<br /><sub>选项: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/glab:1</code></td>
    </tr>
    <tr>
      <td><a href="src/hf-cli/README.md"><strong>hf-cli</strong></a><br /><sub>AI / Hub</sub></td>
      <td>安装 Hugging Face CLI（<code>hf</code>）<br /><sub>选项: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/hf-cli:1</code></td>
    </tr>
    <tr>
      <td><a href="src/nvidia-container/README.md"><strong>nvidia-container</strong></a><br /><sub>GPU / Docker</sub></td>
      <td>安装 NVIDIA Container Toolkit 并配置 Docker 运行时<br /><sub>选项: <code>version</code>, <code>configureDocker</code>, <code>setAsDefault</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/nvidia-container:1</code></td>
    </tr>
    <tr>
      <td><a href="src/opencode/README.md"><strong>opencode</strong></a><br /><sub>AI / Coding</sub></td>
      <td>安装 OpenCode CLI<br /><sub>无配置选项（在 <code>common-utils</code> 之后安装）</sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/opencode:1</code></td>
    </tr>
    <tr>
      <td><a href="src/openspec/README.md"><strong>openspec</strong></a><br /><sub>AI / Spec</sub></td>
      <td>安装 OpenSpec CLI（<code>@fission-ai/openspec</code>）<br /><sub>选项: <code>version</code> ・ 依赖: <code>node</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/openspec:1</code></td>
    </tr>
    <tr>
      <td><a href="src/quarto/README.md"><strong>quarto</strong></a><br /><sub>Publishing</sub></td>
      <td>从经校验和验证的官方发布包安装 Quarto CLI<br /><sub>选项: <code>version</code>, <code>checksumsSha256</code> ・ VS Code 扩展: <code>quarto.quarto</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/quarto:1</code></td>
    </tr>
    <tr>
      <td><a href="src/uv/README.md"><strong>uv</strong></a><br /><sub>Python</sub></td>
      <td>安装 Astral 的 Python 包与项目管理工具 <code>uv</code> / <code>uvx</code><br /><sub>选项: <code>version</code>, <code>toolsToInstall</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/uv:1</code></td>
    </tr>
  </tbody>
</table>

> [!TIP]
> 各 Feature 的完整选项说明、默认值与补充说明，请点击表格中的 Feature 名称查看对应的 `src/<id>/README.md`。

<a id="quick-start"></a>
## 快速开始

只需将所需的 Feature 添加到 `devcontainer.json` 的 `features` 字段中即可使用：

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
<summary><strong>配置示例 1：GPU / AI 开发环境（NVIDIA + Hugging Face + uv）</strong></summary>

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
<summary><strong>配置示例 2：文档写作与 Dotfiles 环境（Quarto + chezmoi）</strong></summary>

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
## 开发与测试

本地校验与测试需要 [Dev Container CLI](https://github.com/devcontainers/cli)、Docker 守护进程、`just`、`pre-commit` 与 `shellcheck`。

| 命令 | 说明 |
| --- | --- |
| `just lint` | 对所有文件运行 `pre-commit`（格式、YAML/JSON、Gitleaks）与 `shellcheck` |
| `just test-feature <id>` | 运行指定 Feature 的默认测试与场景测试 |
| `just test-global` | 仅运行多 Feature 组合等全局测试场景 |
| `just test` | 一次性运行全部 Feature 测试与全局场景 |

<details>
<summary><strong>查看仓库结构</strong></summary>

```text
.
├── assets/                             # README 浅色/深色自适应 SVG Logo
├── src/
│   └── <feature>/
│       ├── devcontainer-feature.json   # Feature 元数据与选项定义
│       ├── install.sh                  # 容器构建时执行的安装脚本
│       ├── NOTES.md                    # 可选补充说明（合并至自动生成的 README）
│       └── README.md                   # 由发布工作流自动生成的文档
├── test/
│   ├── <feature>/
│   │   ├── scenarios.json              # 单个 Feature 的测试场景
│   │   ├── test.sh                     # 默认配置测试
│   │   └── *.sh                        # 场景测试脚本
│   └── _global/                        # 全局测试场景
├── .github/workflows/                  # CI 校验、测试与发布工作流
└── justfile                            # 本地校验与测试命令
```

</details>

<a id="release"></a>
## 发布与文档生成

1. 各 Feature 的版本通过 `src/<id>/devcontainer-feature.json` 中的 `version` 字段按 SemVer 独立管理。
2. 在 `main` 分支手动触发[发布工作流](.github/workflows/release.yaml)后，会将各个 Feature 发布至 GHCR，并创建 `feature_<id>_<semver>` 标签。
3. 工作流同时会为每个 Feature 自动生成 `src/<id>/README.md`（如存在 `src/<id>/NOTES.md` 则合并其内容），并创建用于更新文档的 Pull Request。

<hr />

<div align="center">
  <p>
    Released under the <a href="LICENSE">MIT License</a> &nbsp;·&nbsp; <a href="#top">↑ 返回顶部</a>
  </p>
</div>
