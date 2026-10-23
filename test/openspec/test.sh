#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "openspec version" openspec --version
# shellcheck disable=SC2016
check "openspec in /usr/local/bin" bash -lc '[ -x /usr/local/bin/openspec ]'
# shellcheck disable=SC2016
check "openspec resolves correctly" bash -lc '[ "$(readlink -f "$(command -v openspec)")" = "$(readlink -f /usr/local/bin/openspec)" ]'
# shellcheck disable=SC2016
check "openspec help command" openspec --help

reportResults
