#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "uv version" uv --version
check "uvx version" uvx --version
# shellcheck disable=SC2016
check "uv path" bash -lc '[ "$(readlink -f "$(command -v uv)")" = "/usr/local/bin/uv" ]'
# shellcheck disable=SC2016
check "uvx path" bash -lc '[ "$(readlink -f "$(command -v uvx)")" = "/usr/local/bin/uvx" ]'
# shellcheck disable=SC2016
check "uv ownership and mode" bash -lc '[ "$(stat -c "%U:%G %a" /usr/local/bin/uv)" = "root:root 755" ]'
# shellcheck disable=SC2016
check "uvx ownership and mode" bash -lc '[ "$(stat -c "%U:%G %a" /usr/local/bin/uvx)" = "root:root 755" ]'

reportResults
