## Included Agents & Verification

This Feature installs popular CLI coding agents from their verified official native releases without requiring Node.js or editing shell startup files:

| Agent | CLI | Option | Verification |
| --- | --- | --- | --- |
| Claude Code | `claude` | `installClaudeCode`, `claudeCodeVersion` | GPG-signed manifest (`31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`) + SHA-256 |
| OpenAI Codex | `codex` | `installCodex`, `codexVersion` | Release `codex-package_SHA256SUMS` |
| OpenCode | `opencode` | `installOpenCode`, `openCodeVersion` | npm registry `dist.integrity` SHA-512 |
| Pi | `pi` | `installPi`, `piVersion` | Release `SHA256SUMS` (glibc Linux only) |
| Antigravity | `agy` | `installAntigravity` | Official platform manifest SHA-512 (`AGY_CLI_DISABLE_AUTO_UPDATE=true`) |

All installed binaries are placed on `/usr/local/bin` with a private `umask 077` launcher where applicable so newly created state files stay owner-readable only.

## Project-Scoped State Persistence

A private named volume `coding-agents-${devcontainerId}` is mounted at `/var/lib/coding-agents`. Enabled agents link their credential, configuration, and session directories into this volume:

| Agent | Container Path | Volume Subdirectory | Persisted State |
| --- | --- | --- | --- |
| Claude Code | `~/.claude` (`CLAUDE_CONFIG_DIR` set by wrapper) | `/var/lib/coding-agents/claude-code` | `.credentials.json`, `.claude.json`, settings, skills, sessions |
| Codex | `~/.codex` | `/var/lib/coding-agents/codex` | `auth.json`, `config.toml`, skills, sessions |
| OpenCode | `~/.local/share/opencode`, `~/.config/opencode`, `~/.local/state/opencode`, `~/.cache/opencode` | `/var/lib/coding-agents/opencode/{data,config,state,cache}` | `opencode.db`, config, runtime state, cache |
| Pi | `~/.pi/agent` | `/var/lib/coding-agents/pi/agent` | `auth.json`, `mcp-auth.json`, settings, sessions, packages |
| Antigravity | `~/.gemini/antigravity-cli`, `~/.gemini/config`, `$XDG_CONFIG_HOME/antigravity` | `/var/lib/coding-agents/antigravity/{cli,gemini-config,plugin-secrets}` | OAuth token, MCP/plugin config, `plugin-secrets.json` |

OpenCode and Antigravity also honor custom absolute `XDG_*_HOME` roots at container creation time without linking entire XDG root directories.

## Initialization & Conflict Handling

The `onCreateCommand` hook (`/usr/local/share/coding-agents-feature/initialize`) runs once per container creation as the remote user:

- Confirms `/var/lib/coding-agents` is a mounted volume and enforces private permissions (`0700` on directories, `0600` on known credential files).
- Refuses to overwrite existing non-matching files, directories, or symlinks at mapped paths or conflicting environment overrides (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `PI_CODING_AGENT_DIR`).
- Repairs volume ownership via noninteractive `sudo` inside `/var/lib/coding-agents` only (without following external symlinks) if the remote user UID changed.

## Authentication & Migration

Sign in after the container starts (for example `claude`, `codex login`, `opencode auth login`, `/login` in `pi`, or `agy`). File-based credentials stored inside the mapped directories persist across container rebuilds on the same `devcontainerId`. API keys passed via environment variables or external D-Bus/keyring backends are outside the volume and must be managed separately.

To inspect which Docker volume a container uses:

```sh
docker inspect <CONTAINER_ID> --format '{{range .Mounts}}{{if eq .Destination "/var/lib/coding-agents"}}{{.Name}}{{end}}{{end}}'
```

