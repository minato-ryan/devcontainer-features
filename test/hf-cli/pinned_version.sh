#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "hf pinned version" bash -lc 'hf version | grep -F "2.1.1"'
# shellcheck disable=SC2016
check "hf in /usr/local/bin" bash -lc '[ -x /usr/local/bin/hf ]'
# shellcheck disable=SC2016
check "hf resolves correctly" bash -lc '[ "$(readlink -f "$(command -v hf)")" = "$(readlink -f /usr/local/bin/hf)" ]'
# shellcheck disable=SC2016
check "no skill installed" bash -lc '[ ! -d "${HOME}/.agents/skills/hf-cli" ]'

reportResults
