#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "chezmoi version" chezmoi --version
# shellcheck disable=SC2016
check "chezmoi path" bash -lc '[ "$(readlink -f "$(command -v chezmoi)")" = "/usr/local/bin/chezmoi" ]'
# shellcheck disable=SC2016
check "chezmoi ownership and mode" bash -lc '[ "$(stat -c "%U:%G %a" /usr/local/bin/chezmoi)" = "root:root 755" ]'

reportResults
