#!/bin/bash

set -euo pipefail

INSTALL_SCRIPT_URL="https://opencode.ai/install"

if [ -n "${_REMOTE_USER:-}" ] && [ "${_REMOTE_USER}" != "root" ]; then
    USER_HOME="/home/${_REMOTE_USER}"
else
    USER_HOME="/root"
fi

remote_do() {
    local cmd=$1
    if [ -n "${_REMOTE_USER:-}" ] && [ "${_REMOTE_USER}" != "root" ]; then
        su - "${_REMOTE_USER}" -c "$cmd"
    else
        bash -c "$cmd"
    fi
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates
rm -rf /var/lib/apt/lists/*

remote_do "curl -fsSL \"$INSTALL_SCRIPT_URL\" | bash -s -- --no-modify-path"
