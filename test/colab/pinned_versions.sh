#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "pinned colab version 0.7.6" bash -lc 'colab version | grep -q "0\.7\.6"'
check "pinned rclone version 1.70.0" bash -lc 'rclone version | head -n 1 | grep -qxF "rclone v1.70.0"'
check "fusermount3 installed" command -v fusermount3
# shellcheck disable=SC2016
check "defaultAuth persisted as oauth2" bash -lc '
    set -euo pipefail
    [ "$(cat /usr/local/share/colab-feature/default-auth)" = "oauth2" ]
'
check "colab-adc help" colab-adc --help

check "colab wrapper works with defaultAuth=oauth2" colab version
# shellcheck disable=SC2016
check "colab wrapper works even when default-auth has no trailing newline" bash -lc '
    set -euo pipefail
    if [ "$(id -u)" = "0" ] || sudo -n true >/dev/null 2>&1; then
        orig="$(cat /usr/local/share/colab-feature/default-auth)"
        restore_default_auth() {
            if [ "$(id -u)" = "0" ]; then
                printf "%s\n" "${orig}" > /usr/local/share/colab-feature/default-auth
            else
                printf "%s\n" "${orig}" | sudo -n tee /usr/local/share/colab-feature/default-auth >/dev/null
            fi
        }
        trap restore_default_auth EXIT
        if [ "$(id -u)" = "0" ]; then
            printf "oauth2" > /usr/local/share/colab-feature/default-auth
        else
            printf "oauth2" | sudo -n tee /usr/local/share/colab-feature/default-auth >/dev/null
        fi
        colab version
    else
        colab version
    fi
'

# shellcheck disable=SC2016
check "state mount and config link ready" bash -lc '
    set -euo pipefail
    mountpoint -q /var/lib/colab
    [ "$(readlink -f "$HOME/.config/colab-cli")" = "/var/lib/colab/config" ]
'

reportResults
