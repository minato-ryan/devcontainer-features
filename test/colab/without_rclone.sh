#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "colab version on debian" colab version
check "colab-adc help on debian" colab-adc --help
check "rclone is absent when installRclone is false" bash -lc '! command -v rclone >/dev/null 2>&1'

# shellcheck disable=SC2016
check "state volume and links ready on debian" bash -lc '
    mountpoint -q /var/lib/colab &&
    [ "$(readlink -f "$HOME/.config/colab-cli")" = "/var/lib/colab/config" ]
'

reportResults
