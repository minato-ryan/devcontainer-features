#!/bin/bash
# Installs Astral's uv (uv and uvx) into /usr/local/bin and optionally installs
# Python command-line tools into /usr/local/share/uv with executables in /usr/local/bin.
# Designed for Debian- and Ubuntu-based Dev Containers using apt.
# Subsequent project dependency installation and environment recreation are handled
# directly by uv sync at workspace/runtime.
set -euo pipefail

VERSION="${VERSION:-latest}"
TOOLSTOINSTALL="${TOOLSTOINSTALL:-}"

# Check for apt-get package manager (supports Debian and Ubuntu)
if ! command -v apt-get >/dev/null 2>&1; then
    echo "uv feature error: only Debian- and Ubuntu-based distributions using apt are supported." >&2
    exit 1
fi

# Ensure required prerequisites (curl, ca-certificates, tar) are installed
install_prerequisites() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v tar >/dev/null 2>&1 || missing+=("tar")
    if [ ! -e /etc/ssl/certs/ca-certificates.crt ]; then
        missing+=("ca-certificates")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "uv feature: installing missing prerequisites (${missing[*]})..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y --no-install-recommends "${missing[@]}"
        rm -rf /var/lib/apt/lists/*
    fi
}

# Detect system architecture
detect_arch() {
    local machine
    machine="$(uname -m)"
    case "${machine}" in
        x86_64 | amd64) echo "x86_64" ;;
        aarch64 | arm64) echo "aarch64" ;;
        *)
            echo "uv feature error: unsupported architecture '${machine}'. Supported: x86_64, aarch64." >&2
            exit 1
            ;;
    esac
}

# Resolve target release version
resolve_version() {
    local requested="$1"
    if [ "${requested}" = "latest" ]; then
        local redirect_url
        redirect_url=$(curl -s -f -I -o /dev/null -w "%{redirect_url}" https://github.com/astral-sh/uv/releases/latest) || {
            echo "uv feature error: failed to resolve latest uv release from GitHub." >&2
            exit 1
        }
        local resolved="${redirect_url##*/}"
        echo "${resolved#v}"
    else
        echo "${requested#v}"
    fi
}

# Download uv archive, verify SHA256 checksum, and extract binaries to /usr/local/bin
install_uv() {
    local version="$1"
    local arch="$2"
    local asset="uv-${arch}-unknown-linux-gnu.tar.gz"
    local base_url="https://github.com/astral-sh/uv/releases/download/${version}"
    local download_url="${base_url}/${asset}"
    local checksum_url="${download_url}.sha256"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT

    echo "uv feature: downloading uv ${version} for ${arch}..."
    curl -fsSL "${download_url}" -o "${tmp_dir}/${asset}"
    curl -fsSL "${checksum_url}" -o "${tmp_dir}/${asset}.sha256"

    echo "uv feature: verifying SHA-256 checksum..."
    local expected_hash
    expected_hash="$(cut -d' ' -f1 < "${tmp_dir}/${asset}.sha256")"
    local actual_hash
    actual_hash="$(sha256sum "${tmp_dir}/${asset}" | cut -d' ' -f1)"

    if [ "${expected_hash}" != "${actual_hash}" ]; then
        echo "uv feature error: checksum mismatch for ${asset} (expected ${expected_hash}, got ${actual_hash})" >&2
        exit 1
    fi

    echo "uv feature: installing uv and uvx into /usr/local/bin..."
    tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"
    local unpacked_dir="${tmp_dir}/uv-${arch}-unknown-linux-gnu"

    mkdir -p /usr/local/bin
    cp "${unpacked_dir}/uv" /usr/local/bin/uv
    cp "${unpacked_dir}/uvx" /usr/local/bin/uvx
    chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx
    chown root:root /usr/local/bin/uv /usr/local/bin/uvx

    rm -rf "${tmp_dir}"
    trap - EXIT
}

# Optionally install global CLI tools specified in toolsToInstall
install_tools() {
    local tools_list="$1"
    [ -z "${tools_list}" ] && return 0

    local share_dir="/usr/local/share/uv"
    local tool_dir="${share_dir}/tools"
    local python_dir="${share_dir}/python"
    local bin_dir="/usr/local/bin"

    mkdir -p "${tool_dir}" "${python_dir}"

    echo "uv feature: installing requested tools: ${tools_list}"
    IFS=',' read -ra tools <<< "${tools_list}"
    for raw_tool in "${tools[@]}"; do
        local tool
        tool="$(echo "${raw_tool}" | xargs)"
        [ -z "${tool}" ] && continue

        echo "uv feature: installing tool '${tool}'..."
        UV_TOOL_DIR="${tool_dir}" \
        UV_TOOL_BIN_DIR="${bin_dir}" \
        UV_PYTHON_INSTALL_DIR="${python_dir}" \
        /usr/local/bin/uv tool install "${tool}"
    done

    # Ensure all users can read and execute the installed tools and runtimes
    chmod -R a+rX "${share_dir}"
}

echo "uv feature: starting installation..."
install_prerequisites
ARCH="$(detect_arch)"
VERSION_TO_INSTALL="$(resolve_version "${VERSION}")"
install_uv "${VERSION_TO_INSTALL}" "${ARCH}"
install_tools "${TOOLSTOINSTALL}"

echo "uv feature: installation complete: $(/usr/local/bin/uv --version)"
