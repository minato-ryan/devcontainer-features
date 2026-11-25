
# Google Colab CLI (colab) (colab)

Installs Google Colab CLI (colab) and rclone, persists project-scoped Application Default Credentials (ADC) and CLI configuration in a private volume, and provides the colab-adc helper command.

## Example Usage

```json
"features": {
    "ghcr.io/minato-ryan/devcontainer-features/colab:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Google Colab CLI (google-colab-cli) release to install ('latest' or an exact MAJOR.MINOR.PATCH version). | string | latest |
| defaultAuth | Default authentication strategy injected by the colab wrapper when --auth is omitted ('adc' or 'oauth2'). | string | adc |
| installRclone | Install signature-verified rclone with bash, zsh, and fish shell completions. | boolean | true |
| rcloneVersion | rclone version to install when installRclone is true ('latest' or MAJOR.MINOR.PATCH >= 1.63.0). | string | latest |
| installRcloneMountDependencies | Install fuse3 (fusermount3) required by rclone mount when installRclone is true. | boolean | false |

## Customizations

### VS Code Extensions

- `google.colab`

## Included Tools & Verification

This Feature installs the Google Colab CLI (`google-colab-cli`) using `uv` with an isolated managed Python 3.12 runtime under `/usr/local/share/colab-feature/uv`, adds a custom `colab-adc` helper command for managing Application Default Credentials (ADC), and optionally installs `rclone` with shell completions:

- **`colab`** (`/usr/local/bin/colab`): wrapper around `google-colab-cli` (invoked in Python isolated mode `-I`) that wires project-scoped ADC and defaults `--auth` according to `defaultAuth` (`adc` by default) unless `--auth` is explicitly passed before the subcommand. (`defaultAuth: "oauth2"` uses `google-colab-cli`'s keyring-backed flow; `"adc"` is recommended for headless containers.)
- **`colab-adc`** (`/usr/local/bin/colab-adc`): helper CLI for creating, importing, inspecting, and revoking project-scoped ADC credentials at `/var/lib/colab/adc/application_default_credentials.json`. Requires `uv >= 0.12.16` from the `uv` dependency.
- **`rclone`** (`/usr/local/bin/rclone`, when `installRclone` is `true`): installed from `downloads.rclone.org` after verifying the release `SHA256SUMS` PGP signature against `https://rclone.org/KEYS` (fingerprint `FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA`) and verifying the archive SHA-256 digest. Generates bash, zsh, and fish completion scripts under standard system directories.

## Project-Scoped ADC & State Persistence

A private named volume `colab-${devcontainerId}` is mounted at `/var/lib/colab`:

| Container Path | Volume Path | Purpose |
| --- | --- | --- |
| `/var/lib/colab/adc/application_default_credentials.json` | `adc/application_default_credentials.json` | Persisted Google ADC credentials (`0600`) |
| `~/.config/colab-cli` (symlink) | `config/` | Persisted Colab CLI `sessions.json` and `settings.json` |

When `GOOGLE_APPLICATION_CREDENTIALS` is unset, the `/usr/local/bin/colab` wrapper automatically exports `GOOGLE_APPLICATION_CREDENTIALS=/var/lib/colab/adc/application_default_credentials.json` if that file exists, and injects `--auth=adc` when `defaultAuth` is `"adc"` and no `--auth` flag is supplied. Setting `GOOGLE_APPLICATION_CREDENTIALS` explicitly or passing `--auth=oauth2` overrides the wrapper defaults.

## Creating and Authenticating ADC with `colab-adc`

After the container starts, authenticate once to persist ADC credentials across container rebuilds on the same `devcontainerId`:

```bash
# Built-in remote OAuth2 copy-paste flow (no gcloud required)
colab-adc login

# Or delegate to gcloud if installed in the container (--quota-project maps to gcloud's --billing-project)
colab-adc login --use-gcloud

# Or import an existing ADC JSON file into the project volume
colab-adc import /path/to/application_default_credentials.json
```

Useful `colab-adc` subcommands:

- `colab-adc login [--client-oauth-config PATH] [--scopes ...] [--quota-project ID] [--use-gcloud] [--print-url-only] [--force]`
- `colab-adc import <SOURCE|-> [--force]`
- `colab-adc status [--verify] [--json]`
- `colab-adc logout [--revoke]`
- `colab-adc path`

## Using `rclone` and `rclone mount`

When `installRclone` is `true`, `rclone` and its bash/zsh/fish completions are installed. No rclone configuration is written during build; run `rclone config` inside the container or mount `~/.config/rclone` in your own `devcontainer.json`.

To use `rclone mount` inside a container, set `installRcloneMountDependencies` to `true` (installs `fuse3` / `fusermount3`) and grant FUSE access in `devcontainer.json`:

```jsonc
{
    "runArgs": [
        "--cap-add=SYS_ADMIN",
        "--device=/dev/fuse",
        "--security-opt=apparmor=unconfined"
    ]
}
```

## Initialization & Conflict Handling

The `onCreateCommand` hook (`/usr/local/share/colab-feature/initialize`) runs once per container creation as the remote user:

- Verifies `/var/lib/colab` is a mounted volume and enforces private permissions (`0700` on `/var/lib/colab`, `adc`, and `config`; `0600` on known credential files).
- Refuses to overwrite existing non-matching files, directories, or symlinks at `~/.config/colab-cli` or inside `/var/lib/colab`.
- Repairs volume ownership via noninteractive `sudo` strictly inside `/var/lib/colab` (without following external symlinks) if the container's remote-user UID changes.

To inspect which Docker volume backs a container:

```sh
docker inspect <CONTAINER_ID> --format '{{range .Mounts}}{{if eq .Destination "/var/lib/colab"}}{{.Name}}{{end}}{{end}}'
```

## Editor Integration

This Feature requests Google's official `google.colab` VS Code extension. To exclude it from automatic installation in a project, add `"-google.colab"` under `customizations.vscode.extensions` in `devcontainer.json`.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/minato-ryan/devcontainer-features/blob/main/src/colab/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
