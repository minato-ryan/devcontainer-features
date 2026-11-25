<a id="top"></a>

<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg" />
  <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.svg" />
  <img alt="Dev Container Features" src="assets/logo-light.svg" width="96" height="96" />
</picture>

<h1>Dev Container Features</h1>

<p>
  GitHub Container Registry（<code>ghcr.io/minato-ryan/devcontainer-features</code>）で公開する<br />
  カスタム <a href="https://containers.dev/implementors/features/">Dev Container Features</a> コレクション
</p>

<p>
  <a href="https://github.com/minato-ryan/devcontainer-features/actions/workflows/test.yaml"><img src="https://github.com/minato-ryan/devcontainer-features/actions/workflows/test.yaml/badge.svg" alt="Test Features" /></a>
  <a href="https://github.com/minato-ryan/devcontainer-features/actions/workflows/validate.yml"><img src="https://github.com/minato-ryan/devcontainer-features/actions/workflows/validate.yml/badge.svg" alt="Validate Metadata" /></a>
  <img src="https://img.shields.io/badge/Features-10-0EA5E9?style=flat-square" alt="Features: 10" />
  <img src="https://img.shields.io/badge/Registry-GHCR-6366F1?style=flat-square&amp;logo=github" alt="Registry: GHCR" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-10B981?style=flat-square" alt="License: MIT" /></a>
</p>

<p>
  <strong>日本語</strong> &nbsp;·&nbsp; <a href="README.zh-CN.md">简体中文</a> &nbsp;·&nbsp; <a href="README.en.md">English</a>
</p>

<p>
  <a href="#features">Features</a> &nbsp;·&nbsp;
  <a href="#quick-start">クイックスタート</a> &nbsp;·&nbsp;
  <a href="#development">開発とテスト</a> &nbsp;·&nbsp;
  <a href="#release">リリース</a>
</p>

</div>

---

<a id="features"></a>
## Features

<table width="100%">
  <thead>
    <tr>
      <th align="left">Feature</th>
      <th align="left">概要 / オプション</th>
      <th align="left">OCI 参照</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><a href="src/chezmoi/README.md"><strong>chezmoi</strong></a><br /><sub>Dotfiles</sub></td>
      <td>chezmoi のインストールと初期設定<br /><sub>オプション: <code>config</code> ・ 依存: <code>common-utils</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/chezmoi:1</code></td>
    </tr>
    <tr>
      <td><a href="src/colab/README.md"><strong>colab</strong></a><br /><sub>AI / Cloud</sub></td>
      <td>Google Colab CLI（<code>colab</code>）・<code>rclone</code> の導入、<code>colab-adc</code> コマンドおよびプロジェクト単位の ADC 認証情報永続化<br /><sub>オプション: <code>version</code>, <code>defaultAuth</code>, <code>installRclone</code>, <code>rcloneVersion</code>, <code>installRcloneMountDependencies</code> ・ 依存: <code>uv</code> ・ ボリューム: <code>/var/lib/colab</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/colab:1</code></td>
    </tr>
    <tr>
      <td><a href="src/deno/README.md"><strong>deno</strong></a><br /><sub>Runtime</sub></td>
      <td>Deno ランタイムおよび JavaScript / TypeScript ツールチェーン<br /><sub>オプション: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/deno:1</code></td>
    </tr>
    <tr>
      <td><a href="src/glab/README.md"><strong>glab</strong></a><br /><sub>GitLab CLI</sub></td>
      <td>ターミナル向け GitLab CLI（<code>glab</code>）のインストール<br /><sub>オプション: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/glab:1</code></td>
    </tr>
    <tr>
      <td><a href="src/hf-cli/README.md"><strong>hf-cli</strong></a><br /><sub>AI / Hub</sub></td>
      <td>Hugging Face CLI（<code>hf</code>）のインストール<br /><sub>オプション: <code>version</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/hf-cli:1</code></td>
    </tr>
    <tr>
      <td><a href="src/nvidia-container/README.md"><strong>nvidia-container</strong></a><br /><sub>GPU / Docker</sub></td>
      <td>NVIDIA Container Toolkit の導入および Docker ランタイム設定<br /><sub>オプション: <code>version</code>, <code>configureDocker</code>, <code>setAsDefault</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/nvidia-container:1</code></td>
    </tr>
    <tr>
      <td><a href="src/opencode/README.md"><strong>opencode</strong></a><br /><sub>AI / Coding</sub></td>
      <td>OpenCode CLI のインストール<br /><sub>オプションなし（<code>common-utils</code> の後に実行）</sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/opencode:1</code></td>
    </tr>
    <tr>
      <td><a href="src/openspec/README.md"><strong>openspec</strong></a><br /><sub>AI / Spec</sub></td>
      <td>OpenSpec CLI（<code>@fission-ai/openspec</code>）のインストール<br /><sub>オプション: <code>version</code> ・ 依存: <code>node</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/openspec:1</code></td>
    </tr>
    <tr>
      <td><a href="src/quarto/README.md"><strong>quarto</strong></a><br /><sub>Publishing</sub></td>
      <td>チェックサム検証済みリリースから Quarto CLI を導入<br /><sub>オプション: <code>version</code>, <code>checksumsSha256</code> ・ VS Code 拡張: <code>quarto.quarto</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/quarto:1</code></td>
    </tr>
    <tr>
      <td><a href="src/uv/README.md"><strong>uv</strong></a><br /><sub>Python</sub></td>
      <td>Astral 製 Python パッケージ・プロジェクトマネージャー <code>uv</code> / <code>uvx</code><br /><sub>オプション: <code>version</code>, <code>toolsToInstall</code></sub></td>
      <td><code>ghcr.io/minato-ryan/devcontainer-features/uv:1</code></td>
    </tr>
  </tbody>
</table>

> [!TIP]
> 各 Feature のオプション仕様・既定値・補足ノートは、テーブル内の Feature 名からそれぞれの `src/<id>/README.md` を参照してください。

<a id="quick-start"></a>
## クイックスタート

`devcontainer.json` の `features` に使いたい Feature を追加するだけで利用できます。

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
<summary><strong>構成例 1：GPU / AI 開発環境（NVIDIA + Hugging Face + uv）</strong></summary>

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
<summary><strong>構成例 2：ドキュメント &amp; Dotfiles 環境（Quarto + chezmoi）</strong></summary>

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
## 開発とテスト

ローカル検証には [Dev Container CLI](https://github.com/devcontainers/cli)、Docker デーモン、`just`、`pre-commit`、`shellcheck` が必要です。

| コマンド | 用途 |
| --- | --- |
| `just lint` | 全ファイルに対して `pre-commit`（フォーマット、YAML/JSON、Gitleaks）と `shellcheck` を実行 |
| `just test-feature <id>` | 指定した Feature のデフォルトテストおよびシナリオテストを実行 |
| `just test-global` | 複数 Feature を組み合わせたグローバルシナリオのみを実行 |
| `just test` | すべての Feature テストとグローバルシナリオを一括実行 |

<details>
<summary><strong>リポジトリ構成を見る</strong></summary>

```text
.
├── assets/                             # README 用ライト/ダーク対応 SVG ロゴ
├── src/
│   └── <feature>/
│       ├── devcontainer-feature.json   # Feature のメタデータとオプション定義
│       ├── install.sh                  # ビルド時に実行されるインストールスクリプト
│       ├── NOTES.md                    # 任意の補足ノート（自動生成 README に統合）
│       └── README.md                   # リリースワークフローにより自動生成
├── test/
│   ├── <feature>/
│   │   ├── scenarios.json              # Feature 別テストシナリオ
│   │   ├── test.sh                     # デフォルト構成テスト
│   │   └── *.sh                        # シナリオ別テストスクリプト
│   └── _global/                        # グローバルテストシナリオ
├── .github/workflows/                  # CI 検証・テスト・リリース用ワークフロー
└── justfile                            # ローカル検証・テスト用レシピ
```

</details>

<a id="release"></a>
## リリースとドキュメント生成

1. 各 Feature のバージョンは `src/<id>/devcontainer-feature.json` の `version` フィールド（SemVer）で個別に管理します。
2. `main` ブランチで手動実行の [リリースワークフロー](.github/workflows/release.yaml) を起動すると、各 Feature が GHCR へ公開され、`feature_<id>_<semver>` タグが付与されます。
3. 同時に各 Feature の `src/<id>/README.md`（既存の `src/<id>/NOTES.md` がある場合は統合）が自動生成され、更新用 Pull Request が作成されます。

<hr />

<div align="center">
  <p>
    Released under the <a href="LICENSE">MIT License</a> &nbsp;·&nbsp; <a href="#top">↑ トップへ戻る</a>
  </p>
</div>
