#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "remote user is not root" test "$(id -u)" != 0
check "quarto on the remote user's login PATH" bash -lc 'quarto --version'
check "remote user cannot modify the tree" test ! -w /opt/quarto/bin

reportResults
