#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "nvidia-ctk version" nvidia-ctk --version
check "pinned package version" bash -c 'dpkg -s nvidia-container-toolkit | grep -q "^Version: 1.19.1-1"'

reportResults
