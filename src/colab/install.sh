#!/usr/bin/env bash
# Installs Google Colab CLI (google-colab-cli) via uv with managed Python 3.12,
# optionally installs GPG/SHA-256-verified rclone with shell completions, sets up
# project-scoped ADC and config persistence under /var/lib/colab, and installs
# the `colab` wrapper and `colab-adc` helper command.
set -euo pipefail

readonly UV_BIN="/usr/local/bin/uv"
readonly MIN_UV_VERSION="0.12.16"
readonly PACKAGE_NAME="google-colab-cli"
readonly PACKAGE_INDEX_URL="https://pypi.org/simple/google-colab-cli/"

readonly HELPER_DIR="/usr/local/share/colab-feature"
readonly UV_SHARE_DIR="${HELPER_DIR}/uv"
readonly UV_TOOL_DIR="${UV_SHARE_DIR}/tools"
readonly UV_BIN_DIR="${UV_SHARE_DIR}/bin"
readonly UV_PYTHON_DIR="${UV_SHARE_DIR}/python"
readonly TOOL_ENV="${UV_TOOL_DIR}/google-colab-cli"
readonly REAL_COLAB_BIN="${UV_BIN_DIR}/colab"
readonly DEFAULT_AUTH_FILE="${HELPER_DIR}/default-auth"
readonly COLAB_WRAPPER="/usr/local/bin/colab"
readonly COLAB_ADC_WRAPPER="/usr/local/bin/colab-adc"
readonly STATE_DIR="/var/lib/colab"

readonly RCLONE_MIN_VERSION="1.63.0"
readonly RCLONE_DOWNLOADS="https://downloads.rclone.org"
readonly RCLONE_VERSION_URL="${RCLONE_DOWNLOADS}/version.txt"
readonly RCLONE_KEYS_URL="https://rclone.org/KEYS"
readonly RCLONE_SIGNING_FINGERPRINT="FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA"
readonly RCLONE_BIN="/usr/local/bin/rclone"
readonly RCLONE_BASH_COMPLETION="/usr/local/share/bash-completion/completions/rclone"
readonly RCLONE_ZSH_COMPLETION="/usr/local/share/zsh/site-functions/_rclone"
readonly RCLONE_FISH_COMPLETION="/usr/share/fish/vendor_completions.d/rclone.fish"

readonly SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH="${SYSTEM_PATH}"

VERSION="${VERSION:-latest}"
DEFAULTAUTH="${DEFAULTAUTH:-adc}"
INSTALLRCLONE="${INSTALLRCLONE:-true}"
RCLONEVERSION="${RCLONEVERSION:-latest}"
INSTALLRCLONEMOUNTDEPENDENCIES="${INSTALLRCLONEMOUNTDEPENDENCIES:-false}"

WORK_DIR=""
ARCH=""
RCLONE_ARCH=""
REMOTE_USER=""
REMOTE_GROUP=""
REMOTE_HOME=""
LATEST_COLAB_VERSION=""
TARGET_RCLONE_VERSION=""
STAGED_RCLONE=""
STAGED_BASH=""
STAGED_ZSH=""
STAGED_FISH=""

log() {
    printf 'colab feature: %s\n' "$*"
}

fail() {
    printf 'colab feature: error: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    local f
    for f in "${STAGED_RCLONE}" "${STAGED_BASH}" "${STAGED_ZSH}" "${STAGED_FISH}"; do
        if [[ -n "${f}" ]]; then
            rm -f -- "${f}"
        fi
    done
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        rm -rf -- "${WORK_DIR}"
    fi
}

version_at_least() {
    local -a have want
    local i
    IFS='.' read -r -a have <<< "$1"
    IFS='.' read -r -a want <<< "$2"
    for i in 0 1 2; do
        if (( 10#${have[i]} > 10#${want[i]} )); then
            return 0
        elif (( 10#${have[i]} < 10#${want[i]} )); then
            return 1
        fi
    done
    return 0
}

validate_bool() {
    local name="$1"
    local val="$2"
    case "${val}" in
        true | false) ;;
        *) fail "option ${name} must be 'true' or 'false' (got '${val}')." ;;
    esac
}

validate_semver() {
    local name="$1"
    local val="$2"
    if [[ "${val}" != "latest" && ! "${val}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fail "option ${name} ('${val}') is invalid; use 'latest' or MAJOR.MINOR.PATCH."
    fi
}

validate_options() {
    VERSION="${VERSION#v}"
    RCLONEVERSION="${RCLONEVERSION#v}"

    validate_semver "version" "${VERSION}"
    case "${DEFAULTAUTH}" in
        adc | oauth2) ;;
        *) fail "option defaultAuth must be 'adc' or 'oauth2' (got '${DEFAULTAUTH}')." ;;
    esac
    validate_bool "installRclone" "${INSTALLRCLONE}"
    validate_bool "installRcloneMountDependencies" "${INSTALLRCLONEMOUNTDEPENDENCIES}"

    if [[ "${INSTALLRCLONE}" == "true" ]]; then
        validate_semver "rcloneVersion" "${RCLONEVERSION}"
        if [[ "${RCLONEVERSION}" != "latest" ]] && ! version_at_least "${RCLONEVERSION}" "${RCLONE_MIN_VERSION}"; then
            fail "rcloneVersion '${RCLONEVERSION}' is below minimum supported ${RCLONE_MIN_VERSION}."
        fi
    fi
}

detect_platform() {
    local os_name os_id os_id_like
    os_name="$(uname -s)"
    [[ "${os_name}" == "Linux" ]] || fail "unsupported OS '${os_name}'; Linux is required."

    ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64 | amd64)
            ARCH="x86_64"
            RCLONE_ARCH="amd64"
            ;;
        aarch64 | arm64)
            ARCH="aarch64"
            RCLONE_ARCH="arm64"
            ;;
        *)
            fail "unsupported architecture '${ARCH}'; supported: x86_64, aarch64."
            ;;
    esac

    [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; use a Debian or Ubuntu image."
    # Read in subshells because /etc/os-release defines VERSION.
    # shellcheck source=/dev/null
    os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    # shellcheck source=/dev/null
    os_id_like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"

    case " ${os_id} ${os_id_like} " in
        *" debian "* | *" ubuntu "*) ;;
        *) fail "unsupported distribution '${os_id}'; use a Debian- or Ubuntu-based image." ;;
    esac

    command -v apt-get >/dev/null 2>&1 \
        || fail "apt-get is required; use a Debian- or Ubuntu-based image."

    REMOTE_USER="${_REMOTE_USER:-root}"
    id "${REMOTE_USER}" >/dev/null 2>&1 || fail "remote user '${REMOTE_USER}' does not exist."
    REMOTE_GROUP="$(id -g "${REMOTE_USER}")"
    REMOTE_HOME="${_REMOTE_USER_HOME:-$(getent passwd "${REMOTE_USER}" | cut -d: -f6 || true)}"
    REMOTE_HOME="${REMOTE_HOME%/}"
    [[ "${REMOTE_HOME}" == /* && -d "${REMOTE_HOME}" ]] \
        || fail "remote-user home directory is unavailable for '${REMOTE_USER}'."

    readonly VERSION DEFAULTAUTH INSTALLRCLONE RCLONEVERSION INSTALLRCLONEMOUNTDEPENDENCIES
}

check_uv_dependency() {
    local uv_output uv_version
    [[ -x "${UV_BIN}" ]] || fail "uv is missing at ${UV_BIN}; install the uv feature dependency first."
    uv_output="$("${UV_BIN}" --version)"
    uv_version="${uv_output#uv }"
    uv_version="${uv_version%% *}"
    [[ "${uv_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || fail "cannot read uv version from '${uv_output}'; uv >= ${MIN_UV_VERSION} is required."
    if ! version_at_least "${uv_version}" "${MIN_UV_VERSION}"; then
        fail "uv ${uv_version} is unsupported; uv >= ${MIN_UV_VERSION} is required."
    fi
}

check_conflicts() {
    local rel config_dir link_path target_path parent_dir

    [[ ! -L "${STATE_DIR}" ]] || fail "${STATE_DIR} is a symlink; restore a real directory."
    [[ ! -e "${STATE_DIR}" || -d "${STATE_DIR}" ]] || fail "${STATE_DIR} is not a directory."

    for rel in "adc" "config"; do
        [[ ! -L "${STATE_DIR}/${rel}" ]] || fail "${STATE_DIR}/${rel} is a symlink; resolve it manually."
        [[ ! -e "${STATE_DIR}/${rel}" || -d "${STATE_DIR}/${rel}" ]] || fail "${STATE_DIR}/${rel} is not a directory."
    done

    config_dir="${REMOTE_HOME}/.config"
    if [[ ( -e "${config_dir}" || -L "${config_dir}" ) && ! -d "${config_dir}" ]]; then
        fail "existing '${config_dir}' is not a directory; resolve it manually."
    fi
    link_path="${config_dir}/colab-cli"
    if [[ -L "${link_path}" ]]; then
        [[ "$(readlink -m "${link_path}")" == "${STATE_DIR}/config" ]] \
            || fail "existing symlink '${link_path}' points elsewhere; resolve it manually."
    elif [[ -e "${link_path}" ]]; then
        fail "existing '${link_path}' conflicts; back it up and migrate it explicitly."
    fi

    for target_path in "${COLAB_WRAPPER}" "${COLAB_ADC_WRAPPER}" "${DEFAULT_AUTH_FILE}"; do
        if [[ -e "${target_path}" || -L "${target_path}" ]]; then
            if [[ ! -f "${target_path}" || -L "${target_path}" ]]; then
                fail "${target_path} exists and is not a regular file; remove it and retry."
            fi
        fi
        parent_dir="${target_path%/*}"
        if [[ ( -e "${parent_dir}" || -L "${parent_dir}" ) && ! -d "${parent_dir}" ]]; then
            fail "${parent_dir} exists and is not a directory; remove it and retry."
        fi
    done

    if [[ "${INSTALLRCLONE}" == "true" ]]; then
        for target_path in "${RCLONE_BIN}" "${RCLONE_BASH_COMPLETION}" "${RCLONE_ZSH_COMPLETION}" "${RCLONE_FISH_COMPLETION}"; do
            if [[ -e "${target_path}" || -L "${target_path}" ]]; then
                if [[ ! -f "${target_path}" || -L "${target_path}" ]]; then
                    fail "${target_path} exists and is not a regular file; remove it and retry."
                fi
            fi
            parent_dir="${target_path%/*}"
            if [[ ( -e "${parent_dir}" || -L "${parent_dir}" ) && ! -d "${parent_dir}" ]]; then
                fail "${parent_dir} exists and is not a directory; remove it and retry."
            fi
        done
    fi
}

package_installed() {
    local pkg="$1"
    local status
    status="$(dpkg-query --show --showformat='${db:Status-Status}' "${pkg}" 2>/dev/null || true)"
    [[ "${status}" == "installed" ]]
}

install_prerequisites() {
    local -a missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    package_installed "ca-certificates" || missing+=("ca-certificates")
    command -v mountpoint >/dev/null 2>&1 || missing+=("util-linux")
    command -v find >/dev/null 2>&1 || missing+=("findutils")

    if [[ "${INSTALLRCLONE}" == "true" ]]; then
        command -v gpg >/dev/null 2>&1 || missing+=("gpg")
        command -v unzip >/dev/null 2>&1 || missing+=("unzip")
        if [[ "${INSTALLRCLONEMOUNTDEPENDENCIES}" == "true" ]] && ! package_installed "fuse3"; then
            missing+=("fuse3")
        fi
    fi

    if (( ${#missing[@]} == 0 )); then
        return 0
    fi

    log "installing prerequisites: ${missing[*]}..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || fail "apt-get update failed."
    apt-get install -y --no-install-recommends "${missing[@]}" \
        || fail "apt-get install failed for: ${missing[*]}."
    rm -rf /var/lib/apt/lists/*
}

fetch_https() {
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 15 --max-time 300 -fsSL --retry 3 "$@"
}

fetch_rclone_https() {
    curl --proto '=https' --max-redirs 0 --tlsv1.2 --connect-timeout 15 --max-time 300 -fsSL --retry 3 "$@"
}

run_uv() {
    local -a proxy_env=()
    local var
    for var in HTTP_PROXY HTTPS_PROXY NO_PROXY ALL_PROXY http_proxy https_proxy no_proxy all_proxy; do
        if [[ -v "${var}" ]]; then
            proxy_env+=("${var}=${!var}")
        fi
    done

    env --ignore-environment \
        PATH="${SYSTEM_PATH}" \
        HOME="${WORK_DIR}/uv-home" \
        LANG=C.UTF-8 \
        "${proxy_env[@]}" \
        UV_CACHE_DIR="${WORK_DIR}/uv-cache" \
        UV_PYTHON_INSTALL_DIR="${UV_PYTHON_DIR}" \
        UV_TOOL_DIR="${UV_TOOL_DIR}" \
        UV_TOOL_BIN_DIR="${UV_BIN_DIR}" \
        UV_LINK_MODE=copy \
        "${UV_BIN}" --no-config "$@"
}

resolve_latest_colab_version() {
    local python_bin="$1"
    log "checking latest stable ${PACKAGE_NAME} release from PyPI..."
    fetch_https \
        --header 'Accept: application/vnd.pypi.simple.v1+json' \
        --output "${WORK_DIR}/pypi-index.json" \
        "${PACKAGE_INDEX_URL}" \
        || fail "failed to fetch PyPI package metadata from ${PACKAGE_INDEX_URL}."

    LATEST_COLAB_VERSION="$(
        env --ignore-environment "${python_bin}" -I -B - "${WORK_DIR}/pypi-index.json" <<'PY'
import json
import platform
import sys
from packaging.specifiers import InvalidSpecifier, SpecifierSet
from packaging.utils import (
    InvalidSdistFilename,
    InvalidWheelFilename,
    parse_sdist_filename,
    parse_wheel_filename,
)
from packaging.version import Version

with open(sys.argv[1], encoding="utf-8") as fh:
    files = json.load(fh)["files"]

py_ver = Version(platform.python_version())
releases = set()
for item in files:
    if item.get("yanked") not in (None, False):
        continue
    req_py = item.get("requires-python")
    if isinstance(req_py, str) and req_py.strip():
        try:
            if not SpecifierSet(req_py).contains(py_ver, prereleases=True):
                continue
        except InvalidSpecifier:
            continue
    name = item.get("filename", "")
    try:
        release = (
            parse_wheel_filename(name)
            if name.endswith(".whl")
            else parse_sdist_filename(name)
        )[1]
    except (InvalidWheelFilename, InvalidSdistFilename):
        continue
    if not release.is_prerelease and not release.is_devrelease:
        releases.add(release)

if not releases:
    raise SystemExit("no compatible stable releases found")
print(max(releases))
PY
    )" || fail "failed to parse newest stable release from ${PACKAGE_INDEX_URL}."
}

install_colab_cli() {
    local installed_version=""
    local interpreter_ok=false
    local -a install_args=()
    local package_spec="${PACKAGE_NAME}"

    mkdir -p "${WORK_DIR}/uv-home" "${WORK_DIR}/uv-cache" "${WORK_DIR}/probe-home"
    install -d -m 0755 "${HELPER_DIR}" "${UV_SHARE_DIR}" "${UV_TOOL_DIR}" "${UV_BIN_DIR}" "${UV_PYTHON_DIR}"

    if [[ -x "${TOOL_ENV}/bin/python" && -x "${REAL_COLAB_BIN}" ]]; then
        installed_version="$(
            env --ignore-environment "${TOOL_ENV}/bin/python" -I -c \
                'from importlib.metadata import version; print(version("google-colab-cli"))' 2>/dev/null || true
        )"
        if env --ignore-environment "${TOOL_ENV}/bin/python" -I -c '
import sys
from pathlib import Path
sys.exit(not (sys.version_info[:2] == (3, 12) and Path(sys.executable).resolve().is_relative_to("/usr/local/share/colab-feature/uv/python")))
' 2>/dev/null; then
            interpreter_ok=true
        fi
    fi

    if [[ "${VERSION}" != "latest" && "${installed_version}" == "${VERSION}" && "${interpreter_ok}" == "true" ]]; then
        log "${PACKAGE_NAME} ${VERSION} is already installed; skipping package install."
    else
        local skip_latest=false
        if [[ "${VERSION}" == "latest" && -n "${installed_version}" && "${interpreter_ok}" == "true" ]]; then
            resolve_latest_colab_version "${TOOL_ENV}/bin/python"
            if [[ "${installed_version}" == "${LATEST_COLAB_VERSION}" ]]; then
                log "${PACKAGE_NAME} ${LATEST_COLAB_VERSION} is already the latest stable release; skipping package install."
                skip_latest=true
            fi
        fi

        if [[ "${skip_latest}" == "false" ]]; then
            if [[ -e "${TOOL_ENV}" || -L "${TOOL_ENV}" || -e "${REAL_COLAB_BIN}" || -L "${REAL_COLAB_BIN}" ]]; then
                install_args+=(--force)
            fi
            if [[ "${VERSION}" == "latest" ]]; then
                install_args+=(--upgrade-package "${PACKAGE_NAME}")
            else
                package_spec="${PACKAGE_NAME}==${VERSION}"
            fi

            log "installing ${package_spec} with managed Python 3.12..."
            run_uv tool install --python 3.12 --managed-python "${install_args[@]}" "${package_spec}" \
                || fail "uv tool install failed for ${package_spec}."

            installed_version="$(
                env --ignore-environment "${TOOL_ENV}/bin/python" -I -c \
                    'from importlib.metadata import version; print(version("google-colab-cli"))'
            )"
            if [[ "${VERSION}" != "latest" && "${installed_version}" != "${VERSION}" ]]; then
                fail "installed ${PACKAGE_NAME} ${installed_version}, expected ${VERSION}."
            fi
        fi
    fi

    if [[ "${VERSION}" == "latest" ]]; then
        if [[ -z "${LATEST_COLAB_VERSION}" ]]; then
            resolve_latest_colab_version "${TOOL_ENV}/bin/python"
        fi
        [[ "${installed_version}" == "${LATEST_COLAB_VERSION}" ]] \
            || fail "installed ${PACKAGE_NAME} ${installed_version} instead of latest ${LATEST_COLAB_VERSION}."
    fi

    env --ignore-environment HOME="${WORK_DIR}/probe-home" PATH="${SYSTEM_PATH}" \
        "${TOOL_ENV}/bin/python" -I "${REAL_COLAB_BIN}" version \
        || fail "colab version smoke check failed."
    env --ignore-environment HOME="${WORK_DIR}/probe-home" PATH="${SYSTEM_PATH}" \
        "${TOOL_ENV}/bin/python" -I "${REAL_COLAB_BIN}" --help >/dev/null \
        || fail "colab --help smoke check failed."

    chown -R root:root "${UV_SHARE_DIR}"
    chmod -R a+rX,go-w "${UV_SHARE_DIR}"
}

install_wrappers_and_helpers() {
    local script_dir staged_default_auth staged_colab_adc staged_colab
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    install -d -m 0755 "${HELPER_DIR}"
    install -m 0755 -o root -g root "${script_dir}/initialize.sh" "${HELPER_DIR}/initialize"
    install -m 0755 -o root -g root "${script_dir}/colab_adc.py" "${HELPER_DIR}/colab_adc.py"

    staged_default_auth="$(mktemp "${HELPER_DIR}/.default-auth.XXXXXX")"
    printf '%s\n' "${DEFAULTAUTH}" > "${staged_default_auth}"
    chmod 0644 "${staged_default_auth}"
    chown root:root "${staged_default_auth}"
    mv -f "${staged_default_auth}" "${DEFAULT_AUTH_FILE}"

    staged_colab_adc="$(mktemp "${COLAB_ADC_WRAPPER%/*}/.colab-adc.XXXXXX")"
    cat > "${staged_colab_adc}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077
exec /usr/local/share/colab-feature/uv/tools/google-colab-cli/bin/python -I /usr/local/share/colab-feature/colab_adc.py "$@"
EOF
    chmod 0755 "${staged_colab_adc}"
    chown root:root "${staged_colab_adc}"
    mv -f "${staged_colab_adc}" "${COLAB_ADC_WRAPPER}"

    staged_colab="$(mktemp "${COLAB_WRAPPER%/*}/.colab.XXXXXX")"
    cat > "${staged_colab}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

readonly COLAB_PYTHON="/usr/local/share/colab-feature/uv/tools/google-colab-cli/bin/python"
readonly COLAB_REAL_BIN="/usr/local/share/colab-feature/uv/bin/colab"
readonly DEFAULT_AUTH_FILE="/usr/local/share/colab-feature/default-auth"
readonly PROJECT_ADC_PATH="/var/lib/colab/adc/application_default_credentials.json"

if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -f "${PROJECT_ADC_PATH}" && ! -L "${PROJECT_ADC_PATH}" ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS="${PROJECT_ADC_PATH}"
fi

default_auth="adc"
if [[ -r "${DEFAULT_AUTH_FILE}" ]]; then
    IFS= read -r default_auth < "${DEFAULT_AUTH_FILE}" || [[ -n "${default_auth}" ]] || default_auth="adc"
fi

has_explicit_auth=false
args=("$@")
i=0
while (( i < ${#args[@]} )); do
    arg="${args[i]}"
    case "${arg}" in
        --)
            break
            ;;
        --auth | --auth=*)
            has_explicit_auth=true
            break
            ;;
        -c | --client-oauth-config | --config)
            ((i += 2))
            continue
            ;;
        -*)
            ((i += 1))
            continue
            ;;
        *)
            # Reached the subcommand token; flags after this belong to the subcommand or forwarded script.
            break
            ;;
    esac
done

if [[ "${has_explicit_auth}" == "false" && "${default_auth}" == "adc" && "$#" -gt 0 ]]; then
    case "$1" in
        -h | --help)
            exec "${COLAB_PYTHON}" -I "${COLAB_REAL_BIN}" "$@"
            ;;
        *)
            exec "${COLAB_PYTHON}" -I "${COLAB_REAL_BIN}" --auth=adc "$@"
            ;;
    esac
fi

exec "${COLAB_PYTHON}" -I "${COLAB_REAL_BIN}" "$@"
EOF
    chmod 0755 "${staged_colab}"
    chown root:root "${staged_colab}"
    mv -f "${staged_colab}" "${COLAB_WRAPPER}"
}

run_isolated_rclone() {
    local bin="$1"
    shift
    mkdir -p "${WORK_DIR}/rclone-home/.config/rclone" "${WORK_DIR}/rclone-home/.cache"
    env --ignore-environment \
        PATH="${SYSTEM_PATH}" \
        HOME="${WORK_DIR}/rclone-home" \
        XDG_CONFIG_HOME="${WORK_DIR}/rclone-home/.config" \
        XDG_CACHE_HOME="${WORK_DIR}/rclone-home/.cache" \
        RCLONE_CONFIG="${WORK_DIR}/rclone-home/.config/rclone/rclone.conf" \
        "${bin}" "$@"
}

resolve_rclone_version() {
    if [[ "${RCLONEVERSION}" != "latest" ]]; then
        TARGET_RCLONE_VERSION="${RCLONEVERSION}"
        return 0
    fi

    log "checking latest rclone release from ${RCLONE_VERSION_URL}..."
    fetch_rclone_https --output "${WORK_DIR}/rclone-version.txt" "${RCLONE_VERSION_URL}" \
        || fail "failed to fetch ${RCLONE_VERSION_URL}."
    local line_count raw_text parsed
    line_count="$(wc -l < "${WORK_DIR}/rclone-version.txt" | tr -d '[:space:]')"
    raw_text="$(tr -d '\r\n' < "${WORK_DIR}/rclone-version.txt")"
    if [[ "${line_count}" -le 1 && "${raw_text}" =~ ^rclone\ v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        parsed="${BASH_REMATCH[1]}"
        if version_at_least "${parsed}" "${RCLONE_MIN_VERSION}"; then
            TARGET_RCLONE_VERSION="${parsed}"
            log "resolved latest rclone version: ${TARGET_RCLONE_VERSION}"
            return 0
        fi
    fi
    fail "unexpected rclone version response from ${RCLONE_VERSION_URL}: '${raw_text}'."
}

verify_rclone_checksums() {
    local checksums_url="${RCLONE_DOWNLOADS}/v${TARGET_RCLONE_VERSION}/SHA256SUMS"
    local key_block signers signer
    local first_line signed_headers sig_headers
    local plaintext_cnt newsig_cnt goodsig_cnt validsig_cnt

    fetch_rclone_https --output "${WORK_DIR}/SHA256SUMS" "${checksums_url}" \
        || fail "failed to download ${checksums_url}."
    fetch_rclone_https --output "${WORK_DIR}/KEYS" "${RCLONE_KEYS_URL}" \
        || fail "failed to download ${RCLONE_KEYS_URL}."

    first_line="$(head -n 1 "${WORK_DIR}/SHA256SUMS" | tr -d '\r')"
    [[ "${first_line}" == "-----BEGIN PGP SIGNED MESSAGE-----" ]] \
        || fail "${checksums_url} is not a PGP clearsigned message."
    signed_headers="$(grep -c '^-----BEGIN PGP SIGNED MESSAGE-----$' "${WORK_DIR}/SHA256SUMS" || true)"
    sig_headers="$(grep -c '^-----BEGIN PGP SIGNATURE-----$' "${WORK_DIR}/SHA256SUMS" || true)"
    [[ "${signed_headers}" == "1" && "${sig_headers}" == "1" ]] \
        || fail "${checksums_url} must contain exactly one PGP clearsigned block."

    mkdir -p "${WORK_DIR}/gnupg" "${WORK_DIR}/key-blocks"
    chmod 0700 "${WORK_DIR}/gnupg"
    awk -v dir="${WORK_DIR}/key-blocks" '
        /^-----BEGIN PGP PUBLIC KEY BLOCK-----$/ { in_block = 1; n++; out = sprintf("%s/key-%03d.asc", dir, n) }
        in_block { print > out }
        /^-----END PGP PUBLIC KEY BLOCK-----$/ { close(out); in_block = 0 }
    ' "${WORK_DIR}/KEYS"

    : > "${WORK_DIR}/keys.gpg"
    local found_keys=0
    for key_block in "${WORK_DIR}/key-blocks"/key-*.asc; do
        [[ -f "${key_block}" ]] || continue
        found_keys=1
        gpg --batch --homedir "${WORK_DIR}/gnupg" --output "${key_block}.gpg" --dearmor "${key_block}" \
            2>"${WORK_DIR}/gpg-dearmor.log" \
            || fail "failed to parse rclone signing key block: $(cat "${WORK_DIR}/gpg-dearmor.log")"
        cat "${key_block}.gpg" >> "${WORK_DIR}/keys.gpg"
    done
    (( found_keys == 1 )) || fail "no PGP public key blocks found in ${RCLONE_KEYS_URL}."

    if ! gpg --batch --homedir "${WORK_DIR}/gnupg" --no-default-keyring --keyring "${WORK_DIR}/keys.gpg" \
        --status-file "${WORK_DIR}/gpg-status" --output "${WORK_DIR}/signed-sums" --decrypt "${WORK_DIR}/SHA256SUMS" \
        2>"${WORK_DIR}/gpg-verify.log"; then
        fail "GPG signature verification failed for ${checksums_url}: $(cat "${WORK_DIR}/gpg-verify.log")"
    fi

    if grep -qE '^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|NO_PUBKEY|NODATA|UNEXPECTED|DECRYPTION_OKAY|ENC_TO)([[:space:]]|$)' "${WORK_DIR}/gpg-status"; then
        fail "GPG signature status for ${checksums_url} indicates an invalid or unexpected packet."
    fi

    plaintext_cnt="$(grep -c '^\[GNUPG:\] PLAINTEXT ' "${WORK_DIR}/gpg-status" || true)"
    newsig_cnt="$(grep -c '^\[GNUPG:\] NEWSIG' "${WORK_DIR}/gpg-status" || true)"
    goodsig_cnt="$(grep -c '^\[GNUPG:\] GOODSIG ' "${WORK_DIR}/gpg-status" || true)"
    validsig_cnt="$(grep -c '^\[GNUPG:\] VALIDSIG ' "${WORK_DIR}/gpg-status" || true)"
    if [[ "${plaintext_cnt}" != "1" || "${newsig_cnt}" != "1" || "${goodsig_cnt}" != "1" || "${validsig_cnt}" != "1" ]]; then
        fail "GPG status counts for ${checksums_url} failed single-message invariants (PLAINTEXT=${plaintext_cnt}, NEWSIG=${newsig_cnt}, GOODSIG=${goodsig_cnt}, VALIDSIG=${validsig_cnt})."
    fi

    signers="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && NF >= 12 { print $12 }' "${WORK_DIR}/gpg-status")"
    [[ -n "${signers}" ]] || fail "no valid primary GPG fingerprint found in ${checksums_url} status."
    while IFS= read -r signer; do
        [[ -n "${signer}" ]] || continue
        [[ "${signer}" == "${RCLONE_SIGNING_FINGERPRINT}" ]] \
            || fail "unexpected rclone signing key '${signer}' (expected ${RCLONE_SIGNING_FINGERPRINT})."
    done <<< "${signers}"
    log "verified rclone SHA256SUMS signature (${RCLONE_SIGNING_FINGERPRINT})."
}

new_staged_file() {
    local target="$1"
    local dir="${target%/*}"
    if [[ ! -d "${dir}" ]]; then
        install -d -m 0755 "${dir}"
    fi
    mktemp "${dir}/.colab-rclone.XXXXXX"
}

install_rclone() {
    resolve_rclone_version

    local current_out=""
    local already_installed=false
    if [[ -f "${RCLONE_BIN}" ]]; then
        current_out="$(run_isolated_rclone "${RCLONE_BIN}" version 2>/dev/null | head -n 1 || true)"
        if [[ "${current_out}" == "rclone v${TARGET_RCLONE_VERSION}" ]]; then
            already_installed=true
            log "rclone ${TARGET_RCLONE_VERSION} is already installed; refreshing completions."
        fi
    fi

    local active_bin="${RCLONE_BIN}"
    if [[ "${already_installed}" == "false" ]]; then
        verify_rclone_checksums

        local archive="rclone-v${TARGET_RCLONE_VERSION}-linux-${RCLONE_ARCH}.zip"
        local archive_url="${RCLONE_DOWNLOADS}/v${TARGET_RCLONE_VERSION}/${archive}"
        local entries
        awk -v name="${archive}" 'NF == 2 && length($1) == 64 && $1 ~ /^[0-9a-fA-F]+$/ && $2 == name' \
            "${WORK_DIR}/signed-sums" > "${WORK_DIR}/archive.sha256"
        entries="$(wc -l < "${WORK_DIR}/archive.sha256" | tr -d '[:space:]')"
        [[ "${entries}" == "1" ]] \
            || fail "signed SHA256SUMS contains ${entries} entries for ${archive} (expected 1)."

        log "downloading ${archive_url}..."
        fetch_rclone_https --output "${WORK_DIR}/${archive}" "${archive_url}" \
            || fail "failed to download ${archive_url}."
        (cd "${WORK_DIR}" && sha256sum --strict -c archive.sha256) \
            || fail "SHA-256 verification failed for ${archive}."

        local member="rclone-v${TARGET_RCLONE_VERSION}-linux-${RCLONE_ARCH}/rclone"
        mkdir -p "${WORK_DIR}/rclone-extract"
        unzip -q -o "${WORK_DIR}/${archive}" "${member}" -d "${WORK_DIR}/rclone-extract" \
            || fail "failed to extract ${member} from ${archive}."
        if [[ ! -f "${WORK_DIR}/rclone-extract/${member}" || -L "${WORK_DIR}/rclone-extract/${member}" ]]; then
            fail "extracted ${member} is not a regular file."
        fi

        STAGED_RCLONE="$(new_staged_file "${RCLONE_BIN}")"
        cp "${WORK_DIR}/rclone-extract/${member}" "${STAGED_RCLONE}"
        chmod 0755 "${STAGED_RCLONE}"
        chown root:root "${STAGED_RCLONE}"

        local staged_out
        staged_out="$(run_isolated_rclone "${STAGED_RCLONE}" version 2>/dev/null | head -n 1 || true)"
        [[ "${staged_out}" == "rclone v${TARGET_RCLONE_VERSION}" ]] \
            || fail "staged rclone reported '${staged_out}' instead of 'rclone v${TARGET_RCLONE_VERSION}'."
        active_bin="${STAGED_RCLONE}"
    fi

    STAGED_BASH="$(new_staged_file "${RCLONE_BASH_COMPLETION}")"
    run_isolated_rclone "${active_bin}" completion bash - > "${STAGED_BASH}" \
        || fail "rclone completion bash failed."
    STAGED_ZSH="$(new_staged_file "${RCLONE_ZSH_COMPLETION}")"
    run_isolated_rclone "${active_bin}" completion zsh - > "${STAGED_ZSH}" \
        || fail "rclone completion zsh failed."
    STAGED_FISH="$(new_staged_file "${RCLONE_FISH_COMPLETION}")"
    run_isolated_rclone "${active_bin}" completion fish - > "${STAGED_FISH}" \
        || fail "rclone completion fish failed."
    chmod 0644 "${STAGED_BASH}" "${STAGED_ZSH}" "${STAGED_FISH}"
    chown root:root "${STAGED_BASH}" "${STAGED_ZSH}" "${STAGED_FISH}"

    if [[ -n "${STAGED_RCLONE}" ]]; then
        mv -f "${STAGED_RCLONE}" "${RCLONE_BIN}"
        STAGED_RCLONE=""
        log "installed rclone ${TARGET_RCLONE_VERSION} to ${RCLONE_BIN}."
    fi
    mv -f "${STAGED_BASH}" "${RCLONE_BASH_COMPLETION}"
    STAGED_BASH=""
    mv -f "${STAGED_ZSH}" "${RCLONE_ZSH_COMPLETION}"
    STAGED_ZSH=""
    mv -f "${STAGED_FISH}" "${RCLONE_FISH_COMPLETION}"
    STAGED_FISH=""
    log "installed rclone shell completions."
}

prepare_state_skeleton() {
    local config_dir="${REMOTE_HOME}/.config"
    local link_path="${config_dir}/colab-cli"
    local rel

    if [[ ! -e "${STATE_DIR}" ]]; then
        install -d -m 0700 -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${STATE_DIR}"
    fi
    for rel in "adc" "config"; do
        if [[ ! -e "${STATE_DIR}/${rel}" ]]; then
            install -d -m 0700 -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${STATE_DIR}/${rel}"
        fi
    done

    if [[ ! -e "${config_dir}" ]]; then
        install -d -m 0755 -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${config_dir}"
    fi
    if [[ ! -L "${link_path}" ]]; then
        ln -sfn "${STATE_DIR}/config" "${link_path}"
        chown -h "${REMOTE_USER}:${REMOTE_GROUP}" "${link_path}"
    fi
}

main() {
    log "starting installation..."
    validate_options
    detect_platform
    check_uv_dependency
    check_conflicts
    install_prerequisites

    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    WORK_DIR="$(mktemp -d /tmp/.colab-feature-install.XXXXXX)"
    chmod 0700 "${WORK_DIR}"

    install_colab_cli
    install_wrappers_and_helpers

    if [[ "${INSTALLRCLONE}" == "true" ]]; then
        install_rclone
    fi

    prepare_state_skeleton
    log "installation complete."
}

main "$@"
