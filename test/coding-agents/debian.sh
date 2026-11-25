#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "claude on debian" claude --version
check "codex on debian" codex --version
check "opencode on debian" opencode --version
check "pi on debian" pi --version
check "agy on debian" agy --version

# shellcheck disable=SC2016
check "state volume and links ready on debian" bash -lc '
    mountpoint -q /var/lib/coding-agents &&
    [ "$(readlink -f "$HOME/.claude")" = "/var/lib/coding-agents/claude-code" ] &&
    [ "$(readlink -f "$HOME/.codex")" = "/var/lib/coding-agents/codex" ]
'

reportResults
