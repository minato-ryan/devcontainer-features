#!/bin/bash
# Installs GitLab CLI (glab) into /usr/local/bin.
# Designed for Debian- and Ubuntu-based Dev Containers using apt.
set -euo pipefail

MIN_VERSION="1.47.0"
RELEASES="https://gitlab.com/gitlab-org/cli/-/releases"
TARGET="/usr/local/bin/glab"
VERSION="${VERSION:-latest}"

# Check for apt-get package manager (supports Debian and Ubuntu)
if ! command -v apt-get >/dev/null 2>&1; then
    echo "glab feature error: only Debian- and Ubuntu-based distributions using apt are supported." >&2
    exit 1
fi

# Ensure required prerequisites (git, curl, ca-certificates, tar) are installed
install_prerequisites() {
    local missing=()
    local cmd
    for cmd in git curl tar; do
        command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
    done
    if ! dpkg-query -W -f '${Status}' ca-certificates 2>/dev/null | grep -q 'install ok installed'; then
        missing+=("ca-certificates")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "glab feature: installing missing prerequisites (${missing[*]})..."
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
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *)
            echo "glab feature error: unsupported architecture '${machine}'. Supported: x86_64, aarch64." >&2
            exit 1
            ;;
    esac
}

# Prints normalized version (without leading 'v') if it matches MAJOR.MINOR.PATCH
normalize_version() {
    local v="${1#v}"
    if [[ ! "${v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi
    echo "${v}"
}

# Compares two semantic versions; succeeds if version $1 >= version $2
version_at_least() {
    local -a ver1 ver2
    IFS='.' read -r -a ver1 <<< "$1"
    IFS='.' read -r -a ver2 <<< "$2"
    local i
    for i in 0 1 2; do
        if (( ver1[i] > ver2[i] )); then
            return 0
        elif (( ver1[i] < ver2[i] )); then
            return 1
        fi
    done
    return 0
}

# Resolve target release version
resolve_version() {
    local requested="$1"
    local ver
    if [ "${requested}" = "latest" ]; then
        local redirect_url
        redirect_url=$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error -I -o /dev/null -w "%{redirect_url}" "${RELEASES}/permalink/latest") || {
            echo "glab feature error: failed to resolve latest glab release from GitLab permalink." >&2
            exit 1
        }
        if [ -z "${redirect_url}" ]; then
            echo "glab feature error: ${RELEASES}/permalink/latest did not redirect to a release." >&2
            exit 1
        fi
        local tag="${redirect_url##*/}"
        tag="${tag%%[?#]*}"
        if ! ver=$(normalize_version "${tag}"); then
            echo "glab feature error: latest release '${tag}' is not a valid MAJOR.MINOR.PATCH version." >&2
            exit 1
        fi
    else
        if ! ver=$(normalize_version "${requested}"); then
            echo "glab feature error: invalid version '${requested}'. Use 'latest' or a release version MAJOR.MINOR.PATCH (e.g. '1.120.0')." >&2
            exit 1
        fi
    fi

    if ! version_at_least "${ver}" "${MIN_VERSION}"; then
        echo "glab feature error: version '${ver}' is not supported; minimum version is ${MIN_VERSION}." >&2
        exit 1
    fi

    echo "${ver}"
}

work_dir=""

# Runs glab binary isolated from the image
run_glab() {
    local binary="$1"
    shift
    GLAB_CONFIG_DIR="${work_dir}/config" GLAB_CHECK_UPDATE=false CHECK_UPDATE=false \
        GLAB_SEND_TELEMETRY=false "${binary}" "$@"
}

# Checks if binary reports expected version
reports_version() {
    local binary="$1"
    local expected_ver="$2"
    local output
    output=$(run_glab "${binary}" --version 2>/dev/null) || return 1
    case "${output}" in
        "glab ${expected_ver} ("* | "Current glab version: ${expected_ver}" | "Current glab version: ${expected_ver} ("*) return 0 ;;
    esac
    return 1
}

# Download archive, verify SHA256 checksum, and extract glab binary to TARGET
install_glab() {
    local version="$1"
    local arch="$2"
    local archive="glab_${version}_linux_${arch}.tar.gz"
    local downloads_url="${RELEASES}/v${version}/downloads"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    mkdir -m 700 "${tmp_dir}/config"
    work_dir="${tmp_dir}"
    trap 'rm -rf "${tmp_dir}"' EXIT

    if [ -f "${TARGET}" ] && reports_version "${TARGET}" "${version}"; then
        echo "glab feature: glab ${version} is already installed at ${TARGET}; leaving unchanged."
        rm -rf "${tmp_dir}"
        trap - EXIT
        return 0
    fi

    echo "glab feature: downloading checksums.txt for glab ${version}..."
    curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 \
        "${downloads_url}/checksums.txt" -o "${tmp_dir}/checksums.txt" || {
        echo "glab feature error: failed to download checksums.txt from ${downloads_url}/checksums.txt." >&2
        exit 1
    }

    awk -v name="${archive}" 'NF == 2 && $2 == name' "${tmp_dir}/checksums.txt" > "${tmp_dir}/archive.sha256"
    local entries
    entries=$(wc -l < "${tmp_dir}/archive.sha256")
    if [ "${entries}" -ne 1 ]; then
        echo "glab feature error: verification failed: checksums.txt holds ${entries} entries for ${archive}, expected 1." >&2
        exit 1
    fi

    echo "glab feature: downloading ${archive}..."
    curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 \
        "${downloads_url}/${archive}" -o "${tmp_dir}/${archive}" || {
        echo "glab feature error: failed to download ${archive} from ${downloads_url}/${archive}." >&2
        exit 1
    }

    echo "glab feature: verifying SHA-256 checksum..."
    (cd "${tmp_dir}" && sha256sum -c archive.sha256) || {
        echo "glab feature error: SHA-256 digest does not match checksums.txt." >&2
        exit 1
    }

    echo "glab feature: extracting bin/glab..."
    mkdir "${tmp_dir}/extract"
    tar -xzf "${tmp_dir}/${archive}" -C "${tmp_dir}/extract" bin/glab || {
        echo "glab feature error: failed to extract bin/glab from ${archive}." >&2
        exit 1
    }

    if [ ! -f "${tmp_dir}/extract/bin/glab" ] || [ -L "${tmp_dir}/extract/bin/glab" ]; then
        echo "glab feature error: ${archive} does not contain bin/glab as a regular file." >&2
        exit 1
    fi

    local target_dir
    target_dir="$(dirname "${TARGET}")"
    mkdir -p "${target_dir}"

    local staged
    staged="$(mktemp "${target_dir}/.glab-feature.XXXXXX")"
    cp "${tmp_dir}/extract/bin/glab" "${staged}"
    chmod 0755 "${staged}"
    chown root:root "${staged}"
    mv -f "${staged}" "${TARGET}"

    echo "glab feature: successfully installed $(run_glab "${TARGET}" --version 2>/dev/null || echo "glab ${version}") at ${TARGET}"

    rm -rf "${tmp_dir}"
    trap - EXIT
}

echo "glab feature: starting installation..."
install_prerequisites
ARCH="$(detect_arch)"
VERSION_TO_INSTALL="$(resolve_version "${VERSION}")"
install_glab "${VERSION_TO_INSTALL}" "${ARCH}"
echo "glab feature: installation complete."
