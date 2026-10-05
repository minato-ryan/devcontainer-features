#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "deno pinned version" bash -lc 'deno --version | grep -F "2.8.0"'
# shellcheck disable=SC2016
check "deno in /usr/local/bin" bash -lc '[ -x /usr/local/bin/deno ]'
# shellcheck disable=SC2016
check "deno resolves correctly" bash -lc '[ "$(readlink -f "$(command -v deno)")" = "$(readlink -f /usr/local/bin/deno)" ]'
# shellcheck disable=SC2016
check "deno tools in PATH" bash -lc 'case ":${PATH}:" in *:/usr/local/share/deno/bin:*) exit 0 ;; *) exit 1 ;; esac'
# shellcheck disable=SC2016
check "NO_UPDATE_CHECK set" bash -lc '[ "${NO_UPDATE_CHECK}" = "1" ]'

reportResults
