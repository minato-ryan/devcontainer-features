#!/bin/bash

set -e

source dev-container-features-test-lib

check "chezmoi version" chezmoi --version
check "chezmoi path" bash -lc '[ "$(readlink -f "$(command -v chezmoi)")" = "/usr/local/bin/chezmoi" ]'
check "chezmoi ownership and mode" bash -lc '[ "$(stat -c "%U:%G %a" /usr/local/bin/chezmoi)" = "root:root 755" ]'

reportResults