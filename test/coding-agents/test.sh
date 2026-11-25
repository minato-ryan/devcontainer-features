#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "claude version" claude --version
check "codex version" codex --version
check "opencode version" opencode --version
check "pi version" pi --version
check "agy version" agy --version
# shellcheck disable=SC2016
check "AGY_CLI_DISABLE_AUTO_UPDATE is true" bash -lc '[ "${AGY_CLI_DISABLE_AUTO_UPDATE:-}" = "true" ]'

# shellcheck disable=SC2016
check "state volume mounted with private mode" bash -lc '
    mountpoint -q /var/lib/coding-agents &&
    [ "$(stat -c "%u:%a" /var/lib/coding-agents)" = "$(id -u):700" ]
'

# shellcheck disable=SC2016
check "agent state symlinks resolve into /var/lib/coding-agents" bash -lc '
    [ "$(readlink -f "$HOME/.claude")" = "/var/lib/coding-agents/claude-code" ] &&
    [ "$(readlink -f "$HOME/.codex")" = "/var/lib/coding-agents/codex" ] &&
    [ "$(readlink -f "$HOME/.local/share/opencode")" = "/var/lib/coding-agents/opencode/data" ] &&
    [ "$(readlink -f "$HOME/.config/opencode")" = "/var/lib/coding-agents/opencode/config" ] &&
    [ "$(readlink -f "$HOME/.local/state/opencode")" = "/var/lib/coding-agents/opencode/state" ] &&
    [ "$(readlink -f "$HOME/.cache/opencode")" = "/var/lib/coding-agents/opencode/cache" ] &&
    [ "$(readlink -f "$HOME/.pi/agent")" = "/var/lib/coding-agents/pi/agent" ] &&
    [ "$(readlink -f "$HOME/.gemini/antigravity-cli")" = "/var/lib/coding-agents/antigravity/cli" ] &&
    [ "$(readlink -f "$HOME/.gemini/config")" = "/var/lib/coding-agents/antigravity/gemini-config" ] &&
    [ "$(readlink -f "$HOME/.config/antigravity")" = "/var/lib/coding-agents/antigravity/plugin-secrets" ]
'

# shellcheck disable=SC2016
check "writes through home links land on state volume" bash -lc '
    printf "{\"ok\":true}\n" > "$HOME/.codex/test-state.json" &&
    grep -q "\"ok\":true" /var/lib/coding-agents/codex/test-state.json &&
    rm -f "$HOME/.codex/test-state.json"
'

check "initialize script is idempotent" /usr/local/share/coding-agents-feature/initialize

reportResults

