#!/usr/bin/env bash
# Installs 3D simulation and modeling tools (Blender and Godot) from checksum-verified
# official releases into /opt/blender and /opt/godot with symlinks in /usr/local/bin.
set -euo pipefail

readonly BLENDER_RELEASE_URL="https://download.blender.org/release/"
readonly BLENDER_TARGET="/opt/blender"
readonly BLENDER_COMMAND="/usr/local/bin/blender"
readonly BLENDER_MIN_MAJOR=4
readonly BLENDER_MIN_MINOR=2

readonly GODOT_RELEASES_URL="https://github.com/godotengine/godot/releases"
readonly GODOT_LATEST_URL="${GODOT_RELEASES_URL}/latest"
readonly GODOT_TARGET="/opt/godot"
readonly GODOT_COMMAND="/usr/local/bin/godot"
readonly GODOT_MIN_MAJOR=4
readonly GODOT_MIN_MINOR=2
readonly GODOT_MIN_PATCH=2

readonly RECEIPT_NAME=".devcontainer-feature-3d-tools"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly SUPPORTED_FAMILIES="Debian, Ubuntu, or Fedora"

readonly APT_BLENDER_LIBS=(
    libx11-6
    libxrender1
    libxfixes3
    libxi6
    libxkbcommon0
    libsm6
    libice6
    libxext6
    libgl1
    libegl1
    libegl-mesa0
    libgl1-mesa-dri
)
readonly DNF_BLENDER_LIBS=(
    libX11
    libXrender
    libXfixes
    libXi
    libxkbcommon
    libSM
    libICE
    libXext
    libglvnd-glx
    libglvnd-egl
    mesa-libEGL
    mesa-dri-drivers
)

readonly BLENDER_INPUT_RE='^(latest|(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?)$'
readonly GODOT_STABLE_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?(-stable)?$'
readonly GODOT_PRERELEASE_RE='^[0-9]+\.[0-9]+(\.[0-9]+)?-(dev|alpha|beta|rc)[0-9]*$'

INSTALLBLENDER="${INSTALLBLENDER-true}"
BLENDERVERSION="${BLENDERVERSION-latest}"
INSTALLGODOT="${INSTALLGODOT-true}"
GODOTVERSION="${GODOTVERSION-latest}"
GODOTVARIANT="${GODOTVARIANT-standard}"

PM=""
ARCH=""
MANAGER_RAN=""
WORK_DIR=""

BLENDER_MANAGED="false"
GODOT_MANAGED="false"

BLENDER_STAGED=""
GODOT_STAGED=""

ACTIVE_TARGET=""
ACTIVE_COMMAND=""
ACTIVE_EXEC=""
ACTIVE_BACKUP=""
ACTIVE_BACKED_UP="false"
ACTIVE_ACTIVATED="false"
ACTIVE_COMMITTED="false"

GODOT_VERSION=""
GODOT_TAG=""

log() {
    printf '3d-tools feature: %s\n' "$*"
}

fail() {
    printf '3d-tools feature: error: %s\n' "$*" >&2
    exit 1
}

rollback_active_swap() {
    if [[ "${ACTIVE_ACTIVATED}" == "true" && "${ACTIVE_COMMITTED}" == "false" && -n "${ACTIVE_TARGET}" ]]; then
        rm -rf "${ACTIVE_TARGET}" || true
        if [[ "${ACTIVE_BACKED_UP}" == "true" && -n "${ACTIVE_BACKUP}" && -d "${ACTIVE_BACKUP}" ]]; then
            mv -T -- "${ACTIVE_BACKUP}" "${ACTIVE_TARGET}" || true
            ln -sfn "${ACTIVE_TARGET}/${ACTIVE_EXEC}" "${ACTIVE_COMMAND}" || true
        else
            rm -f "${ACTIVE_COMMAND}" || true
        fi
    elif [[ "${ACTIVE_BACKED_UP}" == "true" && -n "${ACTIVE_BACKUP}" && -d "${ACTIVE_BACKUP}" && -n "${ACTIVE_TARGET}" && ! -e "${ACTIVE_TARGET}" ]]; then
        mv -T -- "${ACTIVE_BACKUP}" "${ACTIVE_TARGET}" || true
    elif [[ "${ACTIVE_BACKED_UP}" == "false" && -n "${ACTIVE_BACKUP}" ]]; then
        rm -rf "${ACTIVE_BACKUP}" || true
    fi
}

cleanup() {
    local status=$?
    rollback_active_swap || true
    if [[ -n "${BLENDER_STAGED}" ]]; then
        rm -rf "${BLENDER_STAGED}" || true
    fi
    if [[ -n "${GODOT_STAGED}" ]]; then
        rm -rf "${GODOT_STAGED}" || true
    fi
    if [[ -n "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}" || true
    fi
    case "${MANAGER_RAN}" in
        apt-get)
            apt-get clean || true
            rm -rf "${APT_LISTS_DIR:?}"/* || true
            ;;
        dnf)
            dnf clean all || true
            ;;
    esac
    return "${status}"
}

fetch_direct() {
    curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location --max-redirs 0 --retry 3 \
        --connect-timeout 30 --speed-limit 1024 --speed-time 60 "$@"
}

fetch_https() {
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error --retry 6 \
        --connect-timeout 30 --speed-limit 1024 --speed-time 60 "$@"
}

run_isolated() {
    env --unset=XDG_CONFIG_HOME --unset=XDG_DATA_HOME --unset=XDG_CACHE_HOME --unset=XDG_STATE_HOME \
        HOME="${WORK_DIR}/home" "$@"
}

validate_bool() {
    local name="$1"
    local val="$2"
    case "${val}" in
        true | false) ;;
        *) fail "option ${name} must be 'true' or 'false' (got '${val}')." ;;
    esac
}

blender_below_min() {
    local major="$1"
    local minor="$2"
    if (( major > BLENDER_MIN_MAJOR || (major == BLENDER_MIN_MAJOR && minor >= BLENDER_MIN_MINOR) )); then
        return 1
    fi
    return 0
}

godot_meets_min() {
    local ver="$1"
    local major="${ver%%.*}"
    local rest="${ver#*.}"
    local minor="${rest%%.*}"
    local patch=0
    if [[ "${rest}" == *.* ]]; then
        patch="${rest#*.}"
    fi
    if (( major > GODOT_MIN_MAJOR
        || (major == GODOT_MIN_MAJOR && minor > GODOT_MIN_MINOR)
        || (major == GODOT_MIN_MAJOR && minor == GODOT_MIN_MINOR && patch >= GODOT_MIN_PATCH) )); then
        return 0
    fi
    return 1
}

validate_options() {
    validate_bool "installBlender" "${INSTALLBLENDER}"
    validate_bool "installGodot" "${INSTALLGODOT}"

    if [[ "${INSTALLBLENDER}" == "false" && "${INSTALLGODOT}" == "false" ]]; then
        fail "no tool is enabled; enable at least one of installBlender or installGodot."
    fi

    if [[ "${INSTALLBLENDER}" == "true" ]]; then
        local blender_hint="use 'latest', a series such as '4.5' or '5.3', or an exact MAJOR.MINOR.PATCH >= 4.2.0"
        [[ "${BLENDERVERSION}" =~ ${BLENDER_INPUT_RE} ]] \
            || fail "option blenderVersion is '${BLENDERVERSION}'; ${blender_hint}."
        if [[ "${BLENDERVERSION}" != "latest" ]] && blender_below_min "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; then
            fail "option blenderVersion '${BLENDERVERSION}' is older than ${BLENDER_MIN_MAJOR}.${BLENDER_MIN_MINOR}.0; ${blender_hint}."
        fi
    fi

    if [[ "${INSTALLGODOT}" == "true" ]]; then
        case "${GODOTVARIANT}" in
            standard | dotnet) ;;
            *) fail "option godotVariant must be 'standard' or 'dotnet' (got '${GODOTVARIANT}')." ;;
        esac

        if [[ "${GODOTVERSION}" != "latest" ]]; then
            if [[ "${GODOTVERSION}" =~ ${GODOT_PRERELEASE_RE} ]]; then
                fail "option godotVersion '${GODOTVERSION}' is a pre-release; only stable releases are supported."
            fi
            if [[ ! "${GODOTVERSION}" =~ ${GODOT_STABLE_RE} ]]; then
                fail "option godotVersion is '${GODOTVERSION}'; use 'latest' or a stable MAJOR.MINOR[.PATCH] release >= 4.2.2."
            fi
            GODOT_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
            if [[ -n "${BASH_REMATCH[4]}" && "${BASH_REMATCH[4]}" != "0" ]]; then
                GODOT_VERSION+=".${BASH_REMATCH[4]}"
            fi
            if ! godot_meets_min "${GODOT_VERSION}"; then
                fail "option godotVersion '${GODOT_VERSION}' is below minimum ${GODOT_MIN_MAJOR}.${GODOT_MIN_MINOR}.${GODOT_MIN_PATCH}."
            fi
            GODOT_TAG="${GODOT_VERSION}-stable"
        fi
    fi
}

detect_platform() {
    local os_name os_id os_like os_pretty word machine userland_arch

    os_name="$(uname -s)"
    [[ "${os_name}" == "Linux" ]] || fail "unsupported OS '${os_name}'; Linux is required."

    if [[ -f /etc/alpine-release ]] || (compgen -G '/lib/ld-musl-*.so*' >/dev/null && ! getconf GNU_LIBC_VERSION >/dev/null 2>&1); then
        fail "musl-based images are unsupported; Blender and Godot require glibc."
    fi

    [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; supported families are ${SUPPORTED_FAMILIES}."
    # Read /etc/os-release inside subshells so it cannot overwrite the VERSION variable.
    # shellcheck source=/dev/null
    os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    # shellcheck source=/dev/null
    os_like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    # shellcheck source=/dev/null
    os_pretty="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-${ID:-unknown}}")"

    set -f
    for word in ${os_id} ${os_like}; do
        case "${word}" in
            debian | ubuntu)
                PM="apt-get"
                break
                ;;
            fedora | rhel | centos)
                PM="dnf"
                break
                ;;
        esac
    done
    set +f

    [[ -n "${PM}" ]] || fail "unsupported distribution '${os_pretty}' (ID=${os_id}); supported families are ${SUPPORTED_FAMILIES}."
    command -v "${PM}" >/dev/null 2>&1 || fail "distribution '${os_pretty}' requires '${PM}', which is missing."

    machine="$(uname -m)"
    case "${machine}" in
        x86_64) ARCH="x86_64" ;;
        aarch64 | arm64) ARCH="aarch64" ;;
        *) fail "unsupported architecture '${machine}'; supported: x86_64, aarch64." ;;
    esac

    if [[ "${PM}" == "apt-get" ]]; then
        userland_arch="$(dpkg --print-architecture)"
        case "${ARCH}:${userland_arch}" in
            x86_64:amd64 | aarch64:arm64) ;;
            *) fail "unsupported userland architecture '${userland_arch}' for ${ARCH}; ${ARCH} userland is required." ;;
        esac
    else
        userland_arch="$(rpm --eval '%{_arch}')"
        case "${ARCH}:${userland_arch}" in
            x86_64:x86_64 | aarch64:aarch64) ;;
            *) fail "unsupported userland architecture '${userland_arch}' for ${ARCH}; ${ARCH} userland is required." ;;
        esac
    fi

    if [[ "${INSTALLBLENDER}" == "true" && "${ARCH}" != "x86_64" ]]; then
        fail "Blender only publishes Linux x86_64 builds (detected '${ARCH}'); set installBlender to false on ${ARCH}."
    fi
}

install_prerequisites() {
    local -a missing=()
    local pkg tool status ca_bundle ldconfig_bin linker_cache
    local ca_ok=false

    for ca_bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt; do
        if [[ -s "${ca_bundle}" ]]; then
            ca_ok=true
            break
        fi
    done

    if [[ "${PM}" == "apt-get" ]]; then
        local -a apt_pkgs=(curl tar coreutils)
        if [[ "${ca_ok}" == "false" ]]; then
            apt_pkgs+=(ca-certificates)
        fi
        if [[ "${INSTALLBLENDER}" == "true" ]]; then
            apt_pkgs+=(xz-utils "${APT_BLENDER_LIBS[@]}")
        fi
        if [[ "${INSTALLGODOT}" == "true" ]]; then
            apt_pkgs+=(unzip)
        fi
        if [[ "${_REMOTE_USER:-root}" != "root" ]]; then
            apt_pkgs+=(util-linux)
        fi
        for pkg in "${apt_pkgs[@]}"; do
            if ! status="$(dpkg-query --show --showformat='${Status}' "${pkg}" 2>/dev/null)"; then
                status=""
            fi
            if [[ "${status}" != *'install ok installed'* ]]; then
                missing+=("${pkg}")
            fi
        done
        if [[ "${INSTALLGODOT}" == "true" ]]; then
            ldconfig_bin="$(command -v ldconfig || printf '/sbin/ldconfig')"
            linker_cache="$("${ldconfig_bin}" --print-cache 2>/dev/null || true)"
            if [[ ! "${linker_cache}" =~ (^|[[:space:]])libfontconfig\.so\.1[[:space:]] ]]; then
                missing+=(libfontconfig1)
            fi
        fi
        if (( ${#missing[@]} > 0 )); then
            log "installing prerequisites with apt-get: ${missing[*]}"
            MANAGER_RAN="apt-get"
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y --no-install-recommends "${missing[@]}"
        fi
    else
        # Fedora/EL may ship curl-minimal, which provides curl while conflicting with the curl package.
        for tool in curl tar find sha256sum sha512sum; do
            if ! command -v "${tool}" >/dev/null 2>&1; then
                case "${tool}" in
                    find) missing+=(findutils) ;;
                    sha256sum | sha512sum) missing+=(coreutils) ;;
                    *) missing+=("${tool}") ;;
                esac
            fi
        done
        if [[ "${ca_ok}" == "false" ]] && ! rpm --query ca-certificates >/dev/null 2>&1; then
            missing+=(ca-certificates)
        fi
        if [[ "${_REMOTE_USER:-root}" != "root" ]] && ! command -v runuser >/dev/null 2>&1; then
            missing+=(util-linux)
        fi
        if [[ "${INSTALLBLENDER}" == "true" ]]; then
            if ! command -v xz >/dev/null 2>&1; then
                missing+=(xz)
            fi
            for pkg in "${DNF_BLENDER_LIBS[@]}"; do
                if ! rpm --query "${pkg}" >/dev/null 2>&1; then
                    missing+=("${pkg}")
                fi
            done
        fi
        if [[ "${INSTALLGODOT}" == "true" ]]; then
            if ! command -v unzip >/dev/null 2>&1; then
                missing+=(unzip)
            fi
            ldconfig_bin="$(command -v ldconfig || printf '/sbin/ldconfig')"
            linker_cache="$("${ldconfig_bin}" --print-cache 2>/dev/null || true)"
            if [[ ! "${linker_cache}" =~ (^|[[:space:]])libfontconfig\.so\.1[[:space:]] ]]; then
                missing+=(fontconfig)
            fi
        fi
        if (( ${#missing[@]} > 0 )); then
            local -a deduped=()
            mapfile -t deduped < <(printf '%s\n' "${missing[@]}" | sort -u)
            log "installing prerequisites with dnf: ${deduped[*]}"
            MANAGER_RAN="dnf"
            dnf install -y --setopt=install_weak_deps=False "${deduped[@]}"
        fi
    fi
}

check_single_tool_conflict() {
    local tool="$1"
    local target_dir="$2"
    local command_path="$3"
    local combined_paths="$4"
    local managed_var="$5"
    local managed="false"
    local expected_resolved dir resolved

    expected_resolved="$(readlink --canonicalize-missing -- "${target_dir}/${tool}")"

    if [[ -e "${target_dir}" || -L "${target_dir}" ]]; then
        [[ -d "${target_dir}" && ! -L "${target_dir}" && -f "${target_dir}/${RECEIPT_NAME}" && ! -L "${target_dir}/${RECEIPT_NAME}" ]] \
            || fail "${target_dir} already exists without this feature's receipt; remove it first."
        [[ "$(stat --format '%u:%g:%a' "${target_dir}")" == "0:0:755" \
            && "$(stat --format '%u:%g:%a' "${target_dir}/${RECEIPT_NAME}")" == "0:0:644" ]] \
            || fail "${target_dir} has unmanaged ownership or permissions; remove it first."
        managed="true"
    fi

    if [[ -e "${command_path}" || -L "${command_path}" ]]; then
        [[ "${managed}" == "true" && -L "${command_path}" && "$(readlink -- "${command_path}")" == "${target_dir}/${tool}" ]] \
            || fail "${command_path} already exists and is not managed by this feature; remove it first."
    fi

    while IFS= read -r dir; do
        [[ -n "${dir}" ]] || continue
        [[ -x "${dir}/${tool}" && ! -d "${dir}/${tool}" ]] || continue
        resolved="$(readlink --canonicalize-missing -- "${dir}/${tool}")"
        [[ "${managed}" == "true" && "${resolved}" == "${expected_resolved}" ]] \
            || fail "${dir}/${tool} conflicts with this feature; remove the existing installation first."
    done < <(printf '%s\n' "${combined_paths}" | tr ':' '\n')

    printf -v "${managed_var}" '%s' "${managed}"
}

check_tool_conflicts() {
    local remote_path=""
    local combined_paths="${PATH}"

    if [[ "${_REMOTE_USER:-root}" != "root" ]]; then
        [[ "${_REMOTE_USER}" =~ ^[a-zA-Z0-9._][a-zA-Z0-9._-]*$ ]] \
            || fail "invalid _REMOTE_USER '${_REMOTE_USER}'."
        if getent passwd -- "${_REMOTE_USER}" >/dev/null 2>&1 || id -- "${_REMOTE_USER}" >/dev/null 2>&1; then
            # Query via /bin/sh with a sentinel so profile banners or non-POSIX login shells cannot corrupt PATH.
            # shellcheck disable=SC2016
            remote_path="$(runuser --shell=/bin/sh --login --command 'printf "\n__3DTOOLS_PATH__=%s\n" "$PATH"' -- "${_REMOTE_USER}" </dev/null 2>/dev/null \
                | sed -n 's/^__3DTOOLS_PATH__=//p' | tail -n 1 || true)"
            if [[ -n "${remote_path}" ]]; then
                combined_paths="${PATH}:${remote_path}"
            fi
        fi
    fi

    if [[ "${INSTALLBLENDER}" == "true" ]]; then
        check_single_tool_conflict "blender" "${BLENDER_TARGET}" "${BLENDER_COMMAND}" "${combined_paths}" BLENDER_MANAGED
    fi
    if [[ "${INSTALLGODOT}" == "true" ]]; then
        check_single_tool_conflict "godot" "${GODOT_TARGET}" "${GODOT_COMMAND}" "${combined_paths}" GODOT_MANAGED
    fi
}

managed_binary_is_safe() {
    local bin="$1"
    [[ -f "${bin}" && ! -L "${bin}" ]] || return 1
    [[ -z "$(find "${bin}" -maxdepth 0 \( ! -user 0 -o ! -group 0 -o -perm /6022 \) -print -quit)" ]]
}

activate_staged_tree() {
    local staged_dir="$1"
    local target_dir="$2"
    local command_path="$3"
    local exec_name="$4"
    local managed="$5"
    local backup_dir=""

    ACTIVE_TARGET="${target_dir}"
    ACTIVE_COMMAND="${command_path}"
    ACTIVE_EXEC="${exec_name}"
    ACTIVE_BACKUP=""
    ACTIVE_BACKED_UP="false"
    ACTIVE_ACTIVATED="false"
    ACTIVE_COMMITTED="false"

    if [[ "${managed}" == "true" ]]; then
        backup_dir="$(mktemp -d "${target_dir%/*}/.${exec_name}-backup.XXXXXX")"
        ACTIVE_BACKUP="${backup_dir}"
        mv -T -- "${target_dir}" "${backup_dir}"
        ACTIVE_BACKED_UP="true"
    fi

    mv -T -- "${staged_dir}" "${target_dir}"
    ACTIVE_ACTIVATED="true"
    mkdir -p "${command_path%/*}"
    ln -sfn "${target_dir}/${exec_name}" "${command_path}"
}

commit_active_swap() {
    ACTIVE_COMMITTED="true"
    if [[ -n "${ACTIVE_BACKUP}" && -d "${ACTIVE_BACKUP}" ]]; then
        rm -rf "${ACTIVE_BACKUP}"
    fi
    ACTIVE_TARGET=""
    ACTIVE_COMMAND=""
    ACTIVE_EXEC=""
    ACTIVE_BACKUP=""
    ACTIVE_BACKED_UP="false"
    ACTIVE_ACTIVATED="false"
}

listed_hrefs() {
    grep --only-matching --extended-regexp 'href="[^"]*"' "$1" \
        | sed --expression 's/^href="//' --expression 's/"$//'
}

resolve_blender_in_series() {
    local series="$1"
    local listing_url="${BLENDER_RELEASE_URL}Blender${series}/"
    local names name patch best=-1

    log "reading Blender release listing ${listing_url}..." >&2
    fetch_direct --output "${WORK_DIR}/blender-series.html" "${listing_url}" \
        || fail "cannot read Blender series listing ${listing_url}."
    names="$(listed_hrefs "${WORK_DIR}/blender-series.html" || true)"

    while IFS= read -r name; do
        [[ "${name}" =~ ^blender-${series//./\\.}\.(0|[1-9][0-9]*)-linux-x64\.tar\.xz$ ]] || continue
        patch="${BASH_REMATCH[1]}"
        grep --quiet --line-regexp --fixed-strings "blender-${series}.${patch}.sha256" <<< "${names}" || continue
        if (( patch > best )); then
            best="${patch}"
        fi
    done <<< "${names}"

    if (( best >= 0 )); then
        printf '%s.%s\n' "${series}" "${best}"
    fi
}

resolve_blender_version() {
    local name candidate resolved=""
    local -a candidates=()

    if [[ "${BLENDERVERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s\n' "${BLENDERVERSION}"
        return 0
    fi

    if [[ "${BLENDERVERSION}" != "latest" ]]; then
        resolved="$(resolve_blender_in_series "${BLENDERVERSION}")"
        [[ -n "${resolved}" ]] || fail "Blender series '${BLENDERVERSION}' has no Linux x64 release with checksums at ${BLENDER_RELEASE_URL}."
        printf '%s\n' "${resolved}"
        return 0
    fi

    log "reading Blender release index ${BLENDER_RELEASE_URL}..." >&2
    fetch_direct --output "${WORK_DIR}/blender-index.html" "${BLENDER_RELEASE_URL}" \
        || fail "cannot read Blender release index ${BLENDER_RELEASE_URL}."

    while IFS= read -r name; do
        [[ "${name}" =~ ^Blender((0|[1-9][0-9]*)\.(0|[1-9][0-9]*))/$ ]] || continue
        if ! blender_below_min "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; then
            candidates+=("${BASH_REMATCH[1]}")
        fi
    done < <(listed_hrefs "${WORK_DIR}/blender-index.html" || true)

    (( ${#candidates[@]} > 0 )) || fail "no Blender series >= 4.2 found at ${BLENDER_RELEASE_URL}."

    while IFS= read -r candidate; do
        resolved="$(resolve_blender_in_series "${candidate}")"
        if [[ -n "${resolved}" ]]; then
            printf '%s\n' "${resolved}"
            return 0
        fi
    done < <(printf '%s\n' "${candidates[@]}" | sort --version-sort --reverse)

    fail "no Linux x64 Blender release >= 4.2 with checksums found at ${BLENDER_RELEASE_URL}."
}

blender_reports_version() {
    local bin="$1"
    local expected="$2"
    local output
    output="$(run_isolated "${bin}" --version 2>/dev/null)" || return 1
    [[ "${output}" =~ ^Blender\ ${expected//./\\.}([[:space:]]|$) ]]
}

receipt_field() {
    local receipt="$1"
    local key="$2"
    sed -n "s/^${key}=//p" "${receipt}" | head -n 1
}

validate_staged_blender_tree() {
    local staged_dir="$1"
    local staged_real link_path link_target resolved_link

    [[ -z "$(find "${staged_dir}" ! -type f ! -type d ! -type l -print -quit)" ]] \
        || fail "extracted Blender archive contains disallowed special files."

    staged_real="$(readlink -f -- "${staged_dir}")"
    while IFS= read -r -d '' link_path; do
        link_target="$(readlink -- "${link_path}")"
        [[ "${link_target}" != /* ]] \
            || fail "extracted Blender archive contains absolute symlink '${link_path}' -> '${link_target}'."
        resolved_link="$(readlink -m -- "${link_path%/*}/${link_target}")"
        [[ "${resolved_link}" == "${staged_real}" || "${resolved_link}" == "${staged_real}/"* ]] \
            || fail "extracted Blender archive contains escaping symlink '${link_path}' -> '${link_target}'."
    done < <(find "${staged_dir}" -type l -print0)
}

harden_blender_tree() {
    local tree_dir="$1"
    chown -hR root:root "${tree_dir}"
    chmod -R u-s,g-s,go-w "${tree_dir}"
    chmod 00755 "${tree_dir}"
}

install_blender() {
    local version series base_url archive checksum_file expected="" actual
    local entries=0 line interpreter
    local stage_dir="${WORK_DIR}/blender"
    mkdir -p "${stage_dir}"

    version="$(resolve_blender_version)"
    series="${version%.*}"
    log "selected Blender ${version}"

    if [[ "${BLENDER_MANAGED}" == "true" \
        && -L "${BLENDER_COMMAND}" \
        && "$(receipt_field "${BLENDER_TARGET}/${RECEIPT_NAME}" "tool")" == "blender" \
        && "$(receipt_field "${BLENDER_TARGET}/${RECEIPT_NAME}" "version")" == "${version}" ]] \
        && managed_binary_is_safe "${BLENDER_TARGET}/blender" \
        && blender_reports_version "${BLENDER_TARGET}/blender" "${version}"; then
        log "Blender ${version} is already installed at ${BLENDER_TARGET}; skipping download."
        return 0
    fi

    base_url="${BLENDER_RELEASE_URL}Blender${series}/"
    archive="blender-${version}-linux-x64.tar.xz"
    checksum_file="blender-${version}.sha256"

    log "downloading ${base_url}${checksum_file}..."
    fetch_direct --output "${stage_dir}/${checksum_file}" "${base_url}${checksum_file}" \
        || fail "failed to download Blender checksum file ${base_url}${checksum_file}."

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        if [[ "${line}" =~ ^([0-9A-Fa-f]{64})[[:space:]]+\*?(.+)$ && "${BASH_REMATCH[2]}" == "${archive}" ]]; then
            expected="${BASH_REMATCH[1],,}"
            entries=$((entries + 1))
        fi
    done < "${stage_dir}/${checksum_file}"

    [[ "${entries}" -eq 1 && "${expected}" =~ ^[0-9a-f]{64}$ ]] \
        || fail "${checksum_file} has ${entries} entries for ${archive}; expected exactly one valid SHA-256."

    log "downloading ${base_url}${archive}..."
    fetch_direct --output "${stage_dir}/${archive}" "${base_url}${archive}" \
        || fail "failed to download Blender archive ${base_url}${archive}."

    actual="$(sha256sum "${stage_dir}/${archive}")"
    actual="${actual%% *}"
    [[ "${actual}" == "${expected}" ]] \
        || fail "SHA-256 mismatch for ${archive}: expected ${expected}, got ${actual}."

    mkdir -p "${BLENDER_TARGET%/*}"
    BLENDER_STAGED="$(mktemp -d "${BLENDER_TARGET%/*}/.blender-3d-tools.XXXXXX")"
    log "extracting ${archive}..."
    tar --extract --xz --no-same-owner --no-same-permissions --file "${stage_dir}/${archive}" \
        --directory "${BLENDER_STAGED}" --strip-components=1 \
        || fail "failed to extract ${archive}."
    rm -f "${stage_dir}/${archive}"

    validate_staged_blender_tree "${BLENDER_STAGED}"
    [[ -f "${BLENDER_STAGED}/blender" && ! -L "${BLENDER_STAGED}/blender" ]] \
        || fail "extracted Blender ${version} lacks regular executable 'blender'."

    interpreter="$(compgen -G "${BLENDER_STAGED}/${series}/python/bin/python3.[0-9]*" || true)"
    [[ "${interpreter}" =~ ^"${BLENDER_STAGED}/${series}/python/bin/python3."[0-9]+$ \
        && -f "${interpreter}" && ! -L "${interpreter}" ]] \
        || fail "Blender ${version} lacks a single regular bundled Python interpreter under ${series}/python/bin."

    harden_blender_tree "${BLENDER_STAGED}"
    chmod 00755 "${BLENDER_STAGED}/blender" "${interpreter}"

    blender_reports_version "${BLENDER_STAGED}/blender" "${version}" \
        || fail "extracted Blender ${version} failed version self-test."

    log "precompiling Blender ${version} bundled Python modules..."
    run_isolated "${interpreter}" -I -m compileall -q -j 0 \
        -s "${BLENDER_STAGED}" -p "${BLENDER_TARGET}" "${BLENDER_STAGED}/${series}" \
        || fail "failed to precompile bundled Python modules for Blender ${version}."

    {
        printf 'tool=blender\n'
        printf 'version=%s\n' "${version}"
        printf 'platform=linux-x64\n'
        printf 'archive_url=%s\n' "${base_url}${archive}"
        printf 'archive_sha256=%s\n' "${actual}"
    } > "${BLENDER_STAGED}/${RECEIPT_NAME}"

    harden_blender_tree "${BLENDER_STAGED}"
    chmod 00644 "${BLENDER_STAGED}/${RECEIPT_NAME}"

    log "activating Blender ${version} at ${BLENDER_TARGET}..."
    activate_staged_tree "${BLENDER_STAGED}" "${BLENDER_TARGET}" "${BLENDER_COMMAND}" "blender" "${BLENDER_MANAGED}"
    BLENDER_STAGED=""

    blender_reports_version "${BLENDER_COMMAND}" "${version}" \
        || fail "activated Blender at ${BLENDER_COMMAND} did not report ${version}."
    commit_active_swap
    log "installed Blender ${version} at ${BLENDER_TARGET}"
}

resolve_godot_version() {
    local location tag
    local redirect_re="^${GODOT_RELEASES_URL}/tag/((0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(\\.[1-9][0-9]*)?-stable)$"

    if [[ "${GODOTVERSION}" != "latest" ]]; then
        return 0
    fi

    log "resolving latest Godot release..."
    location="$(fetch_https --head --output /dev/null --write-out '%{redirect_url}' "${GODOT_LATEST_URL}")" \
        || fail "failed to query ${GODOT_LATEST_URL}."
    [[ -n "${location}" ]] || fail "${GODOT_LATEST_URL} did not redirect to a release."

    location="${location%%[?#]*}"
    location="${location%/}"
    [[ "${location}" =~ ${redirect_re} ]] \
        || fail "latest Godot redirect target '${location}' is not a stable release tag URL."

    tag="${BASH_REMATCH[1]}"
    GODOT_TAG="${tag}"
    GODOT_VERSION="${tag%-stable}"
    if ! godot_meets_min "${GODOT_VERSION}"; then
        fail "latest Godot release '${GODOT_TAG}' is below minimum ${GODOT_MIN_MAJOR}.${GODOT_MIN_MINOR}.${GODOT_MIN_PATCH}."
    fi
}

godot_reports_version() {
    local bin="$1"
    local expected_prefix output suffix
    if [[ "${GODOTVARIANT}" == "dotnet" ]]; then
        expected_prefix="${GODOT_VERSION}.stable.mono.official."
    else
        expected_prefix="${GODOT_VERSION}.stable.official."
    fi
    output="$(run_isolated "${bin}" --version 2>/dev/null)" || return 1
    suffix="${output#"${expected_prefix}"}"
    [[ "${output}" == "${expected_prefix}"* && "${suffix}" =~ ^[0-9a-f]+$ ]]
}

extract_and_stage_godot() {
    local archive_path="$1"
    local executable="$2"
    local top_dir="$3"
    local listing unzip_list
    local extract_dir="${WORK_DIR}/godot-extract"
    mkdir -p "${extract_dir}"

    listing="$(unzip -Z "${archive_path}")" \
        || fail "cannot inspect entries in ${archive_path##*/}."
    if [[ "${listing}" =~ (^|$'\n')l ]]; then
        fail "${archive_path##*/} contains symbolic links, which is disallowed."
    fi

    unzip_list="$(unzip -Z1 "${archive_path}")" \
        || fail "cannot list entries in ${archive_path##*/}."

    if [[ "${GODOTVARIANT}" == "standard" ]]; then
        [[ "${unzip_list}" == "${executable}" ]] \
            || fail "${archive_path##*/} does not contain solely '${executable}'."
        unzip -q -n "${archive_path}" "${executable}" -d "${extract_dir}" \
            || fail "failed to extract ${archive_path##*/}."
        [[ -f "${extract_dir}/${executable}" && ! -L "${extract_dir}/${executable}" ]] \
            || fail "${executable} is not a regular file in ${archive_path##*/}."
    else
        local name rest
        local has_exec="false"
        local has_sharp="false"
        local -a names=()
        local -A seen=()

        mapfile -t names <<< "${unzip_list}"
        for name in "${names[@]}"; do
            [[ -z "${seen["${name}"]+x}" ]] \
                || fail "${archive_path##*/} contains duplicate entry '${name}'."
            seen["${name}"]=1
            if [[ "${name}" == /* || "/${name}/" == */../* ]]; then
                fail "${archive_path##*/} contains unsafe path '${name}'."
            fi
            [[ "${name}" == "${top_dir}/"* ]] \
                || fail "${archive_path##*/} entry '${name}' lies outside '${top_dir}/'."
            rest="${name#"${top_dir}/"}"
            case "${rest}" in
                "") ;;
                "${executable}") has_exec="true" ;;
                GodotSharp/*) has_sharp="true" ;;
                *) fail "${archive_path##*/} contains unexpected entry '${rest}'." ;;
            esac
        done
        [[ "${has_exec}" == "true" && "${has_sharp}" == "true" ]] \
            || fail "${archive_path##*/} is missing ${executable} or GodotSharp/."

        unzip -q -n "${archive_path}" -d "${extract_dir}" \
            || fail "failed to extract ${archive_path##*/}."
        [[ -f "${extract_dir}/${top_dir}/${executable}" && ! -L "${extract_dir}/${top_dir}/${executable}" ]] \
            || fail "${executable} is not a regular file in ${archive_path##*/}."
        [[ -d "${extract_dir}/${top_dir}/GodotSharp" && ! -L "${extract_dir}/${top_dir}/GodotSharp" ]] \
            || fail "GodotSharp is not a directory in ${archive_path##*/}."
        [[ -z "$(find "${extract_dir}" ! -type f ! -type d -print -quit)" ]] \
            || fail "${archive_path##*/} extracted a symbolic link or special file."
    fi

    rm -f "${archive_path}"
    mkdir -p "${GODOT_TARGET%/*}"
    GODOT_STAGED="$(mktemp -d "${GODOT_TARGET%/*}/.godot-3d-tools.XXXXXX")"
    if [[ "${GODOTVARIANT}" == "standard" ]]; then
        mv -- "${extract_dir}/${executable}" "${GODOT_STAGED}/godot"
    else
        mv -- "${extract_dir}/${top_dir}/${executable}" "${GODOT_STAGED}/godot"
        mv -- "${extract_dir}/${top_dir}/GodotSharp" "${GODOT_STAGED}/GodotSharp"
    fi
}

install_godot() {
    local godot_arch archive executable top_dir="" base_url
    local checksums_file="SHA512-SUMS.txt"
    local line expected="" actual entries=0
    local stage_dir="${WORK_DIR}/godot"
    mkdir -p "${stage_dir}"

    case "${ARCH}" in
        x86_64) godot_arch="x86_64" ;;
        aarch64) godot_arch="arm64" ;;
    esac

    resolve_godot_version
    log "selected Godot ${GODOT_VERSION} (${GODOTVARIANT}, ${godot_arch})"

    if [[ "${GODOT_MANAGED}" == "true" \
        && -L "${GODOT_COMMAND}" \
        && "$(receipt_field "${GODOT_TARGET}/${RECEIPT_NAME}" "tool")" == "godot" \
        && "$(receipt_field "${GODOT_TARGET}/${RECEIPT_NAME}" "variant")" == "${GODOTVARIANT}" \
        && "$(receipt_field "${GODOT_TARGET}/${RECEIPT_NAME}" "version")" == "${GODOT_VERSION}" ]] \
        && [[ "${GODOTVARIANT}" != "dotnet" || ( -d "${GODOT_TARGET}/GodotSharp" && ! -L "${GODOT_TARGET}/GodotSharp" ) ]] \
        && managed_binary_is_safe "${GODOT_TARGET}/godot" \
        && godot_reports_version "${GODOT_TARGET}/godot"; then
        log "Godot ${GODOT_VERSION} (${GODOTVARIANT}) is already installed at ${GODOT_TARGET}; skipping download."
        return 0
    fi

    if [[ "${GODOTVARIANT}" == "standard" ]]; then
        archive="Godot_v${GODOT_TAG}_linux.${godot_arch}.zip"
        executable="Godot_v${GODOT_TAG}_linux.${godot_arch}"
    else
        archive="Godot_v${GODOT_TAG}_mono_linux_${godot_arch}.zip"
        top_dir="Godot_v${GODOT_TAG}_mono_linux_${godot_arch}"
        executable="Godot_v${GODOT_TAG}_mono_linux.${godot_arch}"
    fi

    base_url="${GODOT_RELEASES_URL}/download/${GODOT_TAG}"
    log "downloading ${base_url}/${checksums_file}..."
    fetch_https --location --max-redirs 5 --output "${stage_dir}/${checksums_file}" "${base_url}/${checksums_file}" \
        || fail "failed to download ${base_url}/${checksums_file}."

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        if [[ "${line}" =~ ^([0-9A-Fa-f]{128})[[:space:]]+\*?(.+)$ && "${BASH_REMATCH[2]}" == "${archive}" ]]; then
            expected="${BASH_REMATCH[1],,}"
            entries=$((entries + 1))
        fi
    done < "${stage_dir}/${checksums_file}"

    [[ "${entries}" -eq 1 && "${expected}" =~ ^[0-9a-f]{128}$ ]] \
        || fail "${checksums_file} for ${GODOT_TAG} has ${entries} entries for ${archive}; expected exactly one valid SHA-512."

    log "downloading ${base_url}/${archive}..."
    fetch_https --location --max-redirs 5 --output "${stage_dir}/${archive}" "${base_url}/${archive}" \
        || fail "failed to download ${base_url}/${archive}."

    actual="$(sha512sum "${stage_dir}/${archive}")"
    actual="${actual%% *}"
    [[ "${actual}" == "${expected}" ]] \
        || fail "SHA-512 verification failed for ${archive}: expected ${expected}, got ${actual}."

    extract_and_stage_godot "${stage_dir}/${archive}" "${executable}" "${top_dir}"

    {
        printf 'tool=godot\n'
        printf 'variant=%s\n' "${GODOTVARIANT}"
        printf 'version=%s\n' "${GODOT_VERSION}"
        printf 'tag=%s\n' "${GODOT_TAG}"
        printf 'platform=linux-%s\n' "${godot_arch}"
        printf 'archive_url=%s\n' "${base_url}/${archive}"
        printf 'archive_sha512=%s\n' "${actual}"
    } > "${GODOT_STAGED}/${RECEIPT_NAME}"

    chown -hR root:root "${GODOT_STAGED}"
    find "${GODOT_STAGED}" -type d -exec chmod 00755 {} +
    find "${GODOT_STAGED}" -type f -exec chmod 00644 {} +
    chmod 00755 "${GODOT_STAGED}/godot"

    godot_reports_version "${GODOT_STAGED}/godot" \
        || fail "staged Godot ${GODOT_VERSION} (${GODOTVARIANT}) failed version self-test."

    log "activating Godot ${GODOT_VERSION} (${GODOTVARIANT}) at ${GODOT_TARGET}..."
    activate_staged_tree "${GODOT_STAGED}" "${GODOT_TARGET}" "${GODOT_COMMAND}" "godot" "${GODOT_MANAGED}"
    GODOT_STAGED=""

    godot_reports_version "${GODOT_COMMAND}" \
        || fail "activated Godot at ${GODOT_COMMAND} did not report ${GODOT_VERSION} (${GODOTVARIANT})."
    commit_active_swap
    log "installed Godot ${GODOT_VERSION} (${GODOTVARIANT}) at ${GODOT_TARGET}"
}

main() {
    umask 0022
    validate_options
    detect_platform

    readonly INSTALLBLENDER BLENDERVERSION INSTALLGODOT GODOTVERSION GODOTVARIANT

    WORK_DIR="$(mktemp -d)"
    mkdir -m 0700 "${WORK_DIR}/home"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    install_prerequisites
    check_tool_conflicts

    if [[ "${INSTALLBLENDER}" == "true" ]]; then
        install_blender
    fi
    if [[ "${INSTALLGODOT}" == "true" ]]; then
        install_godot
    fi

    log "installation complete."
}

main "$@"
