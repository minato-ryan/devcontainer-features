#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "nvidia-ctk version" nvidia-ctk --version
check "docker version" docker --version
check "docker daemon.json does not register nvidia runtime" bash -c '! grep -s -q "nvidia-container-runtime" /etc/docker/daemon.json'

reportResults
