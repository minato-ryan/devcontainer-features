#!/bin/bash

set -e

source dev-container-features-test-lib

check "chezmoi version" chezmoi --version
check "chezmoi config file exists" test -f ${HOME}/.config/chezmoi/chezmoi.toml
check "chezmoi config contains expected content" grep -q "something" ${HOME}/.config/chezmoi/chezmoi.toml

reportResults