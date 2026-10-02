#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "nvidia-ctk version" nvidia-ctk --version
check "nvidia-container-runtime binary exists" which nvidia-container-runtime
check "nvidia-container-toolkit package installed" dpkg -s nvidia-container-toolkit
check "libnvidia-container-tools package installed" dpkg -s libnvidia-container-tools

reportResults
