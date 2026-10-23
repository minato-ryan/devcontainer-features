#!/usr/bin/env bash
# Installs the Quarto CLI tarball at image build time. Supported images must already have Bash.
# Options arrive as VERSION and CHECKSUMSSHA256; a matching install receipt keeps the existing tree.
# No upstream script runs and no release metadata is parsed; every verified input lands in the receipt.
set -euo pipefail

readonly TARGET=/opt/quarto
readonly COMMAND=/usr/local/bin/quarto
readonly RECEIPT="${TARGET}/.devcontainer-feature-quarto"
readonly REPO_URL=https://github.com/quarto-dev/quarto-cli
readonly LATEST_URL="${REPO_URL}/releases/latest"
readonly RELEASES_URL="${REPO_URL}/releases/download"
# HTTPS on every hop, redirects included; an HTTP error status fails the request. A connection
# that does not open in 30 s, or stalls below 1 KiB/s for 60 s, fails instead of hanging the build.
readonly CURL=(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3
    --connect-timeout 30 --speed-limit 1024 --speed-time 60)

# Shared installation state used by the exit trap.
tmp=""
staged=""
manager_ran=""

# Platform selection shared by prerequisite and release handling.
FAMILY=""
ARCH=""

log() { echo "quarto feature: $*"; }
fail() {
    echo "quarto feature: $*" >&2
    exit 1
}

check_platform() {
    local loader os_id os_like os_name word machine
    for loader in /lib/ld-musl-*; do
        [[ ! -e "${loader}" ]] || fail "this image uses musl; Quarto publishes glibc builds only."
    done

    # Read /etc/os-release in subshells: it defines VERSION, which would overwrite the option.
    [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; supported families are Debian and Fedora."
    # shellcheck source=/dev/null
    os_id="$(. /etc/os-release && echo "${ID:-}")"
    # shellcheck source=/dev/null
    os_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
    # shellcheck source=/dev/null
    os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-${ID:-unknown}}")"
    FAMILY=""
    for word in ${os_id} ${os_like}; do
        case "${word}" in
            debian | ubuntu) FAMILY=debian ;;
            fedora | rhel | centos) FAMILY=fedora ;;
            *) continue ;;
        esac
        break
    done
    [[ -n "${FAMILY}" ]] || fail "unsupported distribution \"${os_name}\" (ID=${os_id}); supported families are Debian and Fedora."

    machine="$(uname -m)"
    case "${machine}" in
        x86_64) ARCH=amd64 ;;
        aarch64 | arm64) ARCH=arm64 ;;
        *) fail "unsupported architecture \"${machine}\"; Quarto publishes Linux tarballs for amd64 and arm64 only." ;;
    esac
}

validate_options() {
    local requested="$1" pin="$2"
    # Option check before any network access, package managers included. Unset means the default.
    if [[ "${requested}" != latest && ! "${requested}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fail "option version is \"${requested}\"; use \"latest\" or an exact release version MAJOR.MINOR.PATCH such as 1.10.19."
    fi
    [[ -n "${pin}" ]] || return 0
    [[ "${pin}" =~ ^[0-9A-Fa-f]{64}$ ]] || fail "option checksumsSha256 is not a 64-digit hexadecimal SHA-256."
    [[ "${requested}" != latest ]] ||
        fail "option checksumsSha256 pins one release; set version to that exact release instead of \"latest\"."
}

# Refuse to replace a tree or command that this Feature did not create.
check_ownership() {
    if [[ -e "${TARGET}" || -L "${TARGET}" ]]; then
        [[ -d "${TARGET}" && ! -L "${TARGET}" && -f "${RECEIPT}" ]] ||
            fail "${TARGET} exists without this Feature's receipt; remove that installation first."
    fi
    if [[ -e "${COMMAND}" || -L "${COMMAND}" ]]; then
        [[ -L "${COMMAND}" && "$(readlink -- "${COMMAND}")" == "${TARGET}/bin/quarto" ]] ||
            fail "${COMMAND} is not this Feature's link to ${TARGET}/bin/quarto; remove that installation first."
    fi
}

# Remove downloads, staging, and package-manager caches on success and failure alike.
cleanup() {
    local status=$?
    rm -rf "${tmp}"
    if [[ -n "${staged}" ]]; then rm -rf "${staged}"; fi
    case "${manager_ran}" in
        apt-get) apt-get clean; rm -rf /var/lib/apt/lists/* ;;
        dnf) dnf clean all ;;
    esac
    return "${status}"
}

ensure_prerequisites() {
    local bundle tool manager
    local missing_packages=()
    for tool in curl tar gzip; do
        command -v "${tool}" >/dev/null 2>&1 || missing_packages+=("${tool}")
    done
    local ca_present=0
    for bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt; do
        if [[ -s "${bundle}" ]]; then ca_present=1; break; fi
    done
    ((ca_present)) || missing_packages+=(ca-certificates)
    if ((${#missing_packages[@]} == 0)); then return; fi
    case "${FAMILY}" in
        debian) manager=apt-get ;;
        fedora) manager=dnf ;;
    esac
    command -v "${manager}" >/dev/null 2>&1 ||
        fail "missing ${missing_packages[*]}; this family needs ${manager} to install them."
    log "installing ${missing_packages[*]} with ${manager}"
    manager_ran="${manager}"
    case "${manager}" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y --no-install-recommends "${missing_packages[@]}"
            ;;
        dnf) dnf install -y --setopt=install_weak_deps=False "${missing_packages[@]}" ;;
    esac
}

# fetch <url> <file>: follows redirects and fails with the URL, HTTP status, and curl's message.
fetch() {
    local url="$1" out="$2" code status=0
    code="$("${CURL[@]}" --location --output "${out}" --write-out '%{http_code}' "${url}" 2>"${tmp}/curl.err")" ||
        status=$?
    if ((status == 0)); then return 0; fi
    rm -f "${out}"
    fail "downloading ${url} failed (HTTP ${code:-none}, curl exit ${status}): $(cat "${tmp}/curl.err"). Nothing was installed."
}

# The latest-release redirect excludes drafts and prereleases; it is read, not followed.
resolve_version() {
    local requested="$1" location
    if [[ "${requested}" != latest ]]; then
        echo "${requested}"
        return
    fi
    location="$("${CURL[@]}" --head --output /dev/null --write-out '%{redirect_url}' "${LATEST_URL}")" ||
        fail "cannot reach ${LATEST_URL}; cannot resolve \"latest\"."
    if [[ ! "${location}" =~ ^${REPO_URL}/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        fail "${LATEST_URL} redirected to \"${location:0:200}\", which is not a stable release tag; nothing was installed."
    fi
    log "latest resolves to ${BASH_REMATCH[1]}" >&2
    echo "${BASH_REMATCH[1]}"
}

actual_hash() {
    local sum
    sum="$(sha256sum "$1")"
    echo "${sum%% *}"
}

# expected_hash <checksum file> <name>: the hash of the file's single line whose name field is <name>.
expected_hash() {
    local file="$1" name="$2" line hash=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        [[ "${line}" =~ ^([0-9A-Fa-f]{64})\ [\ *](.+)$ && "${BASH_REMATCH[2]}" == "${name}" ]] || continue
        [[ -z "${hash}" ]] || fail "${file##*/} lists ${name} more than once. Nothing was installed."
        hash="${BASH_REMATCH[1],,}"
    done <"${file}"
    [[ -n "${hash}" ]] || fail "${file##*/} has no SHA-256 line for ${name}. Nothing was installed."
    echo "${hash}"
}

# Verify the checksum list (against the pin, when set), then the archive against its entry.
download_verified_release() {
    local version="$1" pin="$2" sums_actual archive_expected archive_actual
    local base="${RELEASES_URL}/v${version}"
    local archive="quarto-${version}-linux-${ARCH}.tar.gz" sums="quarto-${version}-checksums.txt"

    log "downloading ${base}/${sums}"
    fetch "${base}/${sums}" "${tmp}/${sums}"
    sums_actual="$(actual_hash "${tmp}/${sums}")"
    if [[ -n "${pin}" && "${sums_actual}" != "${pin,,}" ]]; then
        fail "checksum mismatch for ${sums}: checksumsSha256 is ${pin,,}, got ${sums_actual}. Nothing was installed."
    fi
    archive_expected="$(expected_hash "${tmp}/${sums}" "${archive}")"

    log "downloading ${base}/${archive}"
    fetch "${base}/${archive}" "${tmp}/${archive}"
    archive_actual="$(actual_hash "${tmp}/${archive}")"
    if [[ "${archive_actual}" != "${archive_expected}" ]]; then
        fail "checksum mismatch for the archive ${archive}: expected ${archive_expected}, got ${archive_actual}." \
            "Nothing was extracted or installed."
    fi
    log "verified ${archive} (${archive_actual}) against ${sums} (${sums_actual})"

    # The receipt has no timestamp, so identical inputs produce an identical file.
    {
        echo "version=${version}"
        echo "platform=linux-${ARCH}"
        echo "archive_url=${base}/${archive}"
        echo "archive_sha256=${archive_actual}"
        echo "checksums_url=${base}/${sums}"
        echo "checksums_sha256=${sums_actual}"
        if [[ -n "${pin}" ]]; then echo "checksums_pinned=yes"; else echo "checksums_pinned=no"; fi
    } >"${tmp}/receipt"
}

# Version reported by a quarto executable: the first line of --version.
reported_version() {
    local out
    out="$("$1" --version 2>/dev/null)" || return 0
    echo "${out%%$'\n'*}"
}

# Stage next to the target so activation is a rename, and self-test before replacing anything.
install_release() {
    local version="$1" staged_version previous
    local archive="${tmp}/quarto-${version}-linux-${ARCH}.tar.gz"
    mkdir -p "${TARGET%/*}" "${COMMAND%/*}"
    staged="$(mktemp -d "${TARGET%/*}/.quarto.XXXXXX")"
    tar --extract --gzip --no-same-owner --file "${archive}" --directory "${staged}" --strip-components=1 ||
        fail "cannot extract ${archive##*/}. Nothing was installed."
    cp "${tmp}/receipt" "${staged}/${RECEIPT##*/}"
    chown -R root:root "${staged}"
    chmod -R go-w "${staged}"
    chmod 0755 "${staged}"
    staged_version="$(reported_version "${staged}/bin/quarto")"
    if [[ "${staged_version}" != "${version}" ]]; then
        fail "the verified bundle reports version \"${staged_version}\", not ${version}; it may not run on this image." \
            "It was not installed."
    fi

    if [[ -d "${TARGET}" ]]; then
        previous="$(mktemp -d "${TARGET%/*}/.quarto-previous.XXXXXX")"
        mv -T "${TARGET}" "${previous}"
        mv -T "${staged}" "${TARGET}" || { mv -T "${previous}" "${TARGET}"; fail "cannot activate ${TARGET}."; }
        rm -rf "${previous}"
    else
        mv -T "${staged}" "${TARGET}"
    fi
    staged=""
    ln -sfn "${TARGET}/bin/quarto" "${COMMAND}"
    log "installed Quarto ${version} at ${TARGET}; receipt ${RECEIPT}:"
    sed 's/^/    /' "${RECEIPT}"
}

main() {
    local requested="${VERSION-latest}" pin="${CHECKSUMSSHA256-}" version
    validate_options "${requested}" "${pin}"
    check_platform
    check_ownership

    tmp="$(mktemp -d)"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    ensure_prerequisites
    version="$(resolve_version "${requested}")"
    download_verified_release "${version}" "${pin}"
    if [[ -f "${RECEIPT}" && "$(<"${RECEIPT}")" == "$(<"${tmp}/receipt")" &&
        "$(reported_version "${TARGET}/bin/quarto")" == "${version}" ]]; then
        log "Quarto ${version} with an identical receipt is already installed; keeping it."
        return
    fi
    install_release "${version}"
}

main "$@"
