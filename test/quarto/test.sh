#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "quarto version" quarto --version
check "command links to the managed tree" test "$(readlink /usr/local/bin/quarto)" = /opt/quarto/bin/quarto
check "receipt version matches quarto" \
    test "$(quarto --version)" = "$(sed -n 's/^version=//p' /opt/quarto/.devcontainer-feature-quarto)"
check "receipt records a verified archive" grep -Eq '^archive_sha256=[0-9a-f]{64}$' /opt/quarto/.devcontainer-feature-quarto
check "receipt records the checksum list" grep -Eq '^checksums_sha256=[0-9a-f]{64}$' /opt/quarto/.devcontainer-feature-quarto
check "tree belongs to root" test "$(stat -c %u:%g /opt/quarto)" = 0:0
check "tree is not writable by group or others" bash -c '! find /opt/quarto ! -type l -perm /022 -print -quit | grep -q .'
work="$(mktemp -d)"
printf '# Hello Quarto\n\nA plain document.\n' >"${work}/example.qmd"
check "renders a document without code to HTML" quarto render "${work}/example.qmd" --to html
check "HTML output is nonempty" test -s "${work}/example.html"
rm -rf "${work}"

reportResults
