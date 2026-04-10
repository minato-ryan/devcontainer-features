#!/bin/bash

set -euo pipefail

CONFIG=${CONFIG:-}

install_chezmoi() {
    mkdir -p "/usr/local/bin"

    CHEZMOI_INSTALLER_SCRIPT=$(mktemp)

    echo "Downloading chezmoi installer..."
    curl -fsSL "https://get.chezmoi.io" -o "${CHEZMOI_INSTALLER_SCRIPT}"

    echo "Installing chezmoi into /usr/local/bin..."
    sh "${CHEZMOI_INSTALLER_SCRIPT}" -b "/usr/local/bin"
    rm -f "${CHEZMOI_INSTALLER_SCRIPT}"

    if [ ! -x "/usr/local/bin/chezmoi" ]; then
        echo "chezmoi binary was not installed correctly."
        exit 1
    fi

    chown root:root "/usr/local/bin/chezmoi"
    chmod 0755 "/usr/local/bin/chezmoi"
}


write_config() {
    if [ -n "${_REMOTE_USER:-}" ] && [ "${_REMOTE_USER}" != "root" ]; then
        USER_HOME="/home/${_REMOTE_USER}"
    else
        USER_HOME="/root"
    fi

    config_dir="${USER_HOME}/.config/chezmoi"
    config_file="${config_dir}/chezmoi.toml"

    mkdir -p "${config_dir}"
    printf '%s' "${CONFIG}" > "${config_file}"
    chown -R "${_REMOTE_USER}:" "${config_dir}"
}


echo "Installing chezmoi..."
install_chezmoi
if [ -n "${CONFIG}" ]; then
    write_config
fi
echo "chezmoi installation complete."