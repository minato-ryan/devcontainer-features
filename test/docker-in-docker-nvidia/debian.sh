#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "nvidia-ctk version" nvidia-ctk --version
check "nvidia-container-runtime version" nvidia-container-runtime --version
check "docker version" docker --version
check "nvidia runtime registered in docker daemon.json" bash -c 'grep -q "nvidia-container-runtime" /etc/docker/daemon.json'

reportResults
