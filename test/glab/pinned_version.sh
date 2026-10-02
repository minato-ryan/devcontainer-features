#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "glab pinned version" bash -lc 'glab --version | grep -F "1.50.0"'

reportResults
