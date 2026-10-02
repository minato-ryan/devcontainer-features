#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "uv on debian" uv --version
check "uvx on debian" uvx --version

reportResults
