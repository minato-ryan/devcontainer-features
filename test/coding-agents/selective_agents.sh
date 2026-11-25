#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "codex pinned version" bash -lc 'codex --version | grep -F "0.172.0"'
check "opencode pinned version" bash -lc 'opencode --version | grep -F "2.4.1"'

# shellcheck disable=SC2016
check "disabled agents are absent" bash -lc '
    ! command -v claude >/dev/null 2>&1 &&
    ! command -v pi >/dev/null 2>&1 &&
    ! command -v agy >/dev/null 2>&1
'

# shellcheck disable=SC2016
check "only enabled agent links exist" bash -lc '
    [ "$(readlink -f "$HOME/.codex")" = "/var/lib/coding-agents/codex" ] &&
    [ "$(readlink -f "$HOME/.config/opencode")" = "/var/lib/coding-agents/opencode/config" ] &&
    [ ! -e "$HOME/.claude" ] &&
    [ ! -e "$HOME/.pi" ] &&
    [ ! -e "$HOME/.gemini" ]
'

reportResults

