#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "nvidia-ctk version" nvidia-ctk --version
check "default-runtime set to nvidia in daemon.json" bash -c 'grep -q "\"default-runtime\": \"nvidia\"" /etc/docker/daemon.json'

reportResults
