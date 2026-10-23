#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

receipt=/opt/quarto/.devcontainer-feature-quarto
check "quarto pinned version" test "$(quarto --version)" = 1.9.38
check "receipt records the pin" grep -qx 'checksums_pinned=yes' "${receipt}"
check "receipt records the pinned list" \
    grep -qx 'checksums_sha256=a936197982c2e5df434d9a10117df232650c48bdcd82320e61d085c36c60c2b7' "${receipt}"
check "receipt records the release URL" \
    grep -Eq '^archive_url=https://github\.com/quarto-dev/quarto-cli/releases/download/v1\.9\.38/quarto-1\.9\.38-linux-(amd64|arm64)\.tar\.gz$' \
    "${receipt}"
check "command links to the managed tree" test "$(readlink /usr/local/bin/quarto)" = /opt/quarto/bin/quarto

reportResults
