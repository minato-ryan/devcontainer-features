#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Definition specific tests
check "opencode" opencode --version

# Report result
reportResults
