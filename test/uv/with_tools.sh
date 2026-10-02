#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "uv version" uv --version
check "ruff installed" ruff --version
# shellcheck disable=SC2016
check "ruff in path" bash -lc '[ -x "/usr/local/bin/ruff" ]'

reportResults
