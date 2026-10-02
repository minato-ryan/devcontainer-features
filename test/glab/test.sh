#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "glab version" glab --version
# shellcheck disable=SC2016
check "glab path" bash -lc '[ "$(readlink -f "$(command -v glab)")" = "/usr/local/bin/glab" ]'
# shellcheck disable=SC2016
check "glab ownership and mode" bash -lc '[ "$(stat -c "%U:%G %a" /usr/local/bin/glab)" = "root:root 755" ]'

reportResults
