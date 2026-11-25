#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "opencode version" opencode --version
# shellcheck disable=SC2016
check "opencode config resolves to coding-agents volume" bash -lc '
    [ "$(readlink -f "$HOME/.config/opencode")" = "/var/lib/coding-agents/opencode/config" ]
'

reportResults
