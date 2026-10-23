#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "quarto on fedora" quarto --version
check "receipt is unpinned by default" grep -qx 'checksums_pinned=no' /opt/quarto/.devcontainer-feature-quarto
check "image is fedora" grep -qx "ID=fedora" /etc/os-release

reportResults
