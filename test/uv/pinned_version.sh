#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "uv pinned version" bash -lc 'uv --version | grep -F "0.5.11"'
check "uvx pinned version" bash -lc 'uvx --version | grep -F "0.5.11"'

reportResults
