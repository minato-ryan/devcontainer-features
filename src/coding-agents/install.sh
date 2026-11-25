#!/usr/bin/env bash
# Installs selected CLI coding agents (Claude Code, Codex, OpenCode, Pi, Antigravity) from verified
# official releases and prepares project-scoped state persistence under /var/lib/coding-agents.
set -euo pipefail
umask 022

readonly APP_ROOT="/usr/local/share/coding-agents"
readonly HELPER_DIR="/usr/local/share/coding-agents-feature"
readonly STATE_DIR="/var/lib/coding-agents"
readonly ENABLED_AGENTS_FILE="${HELPER_DIR}/enabled-agents"

readonly CLAUDE_RELEASE_API="https://downloads.claude.ai/claude-code-releases"
readonly CLAUDE_SIGNING_KEY_URL="https://downloads.claude.ai/keys/claude-code.asc"
readonly CLAUDE_SIGNING_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
readonly CLAUDE_MIN_VERSION="2.1.89"

readonly CODEX_RELEASES_URL="https://github.com/openai/codex/releases"

readonly OPENCODE_REGISTRY_URL="https://registry.npmjs.org"
readonly OPENCODE_TAGS_URL="${OPENCODE_REGISTRY_URL}/-/package/@opencode%2fcli/dist-tags"

readonly PI_RELEASES_URL="https://github.com/earendil-works/pi/releases"
readonly PI_MIN_VERSION="1.3.0"

readonly AGY_MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"
readonly AGY_ARCHIVE_PREFIX="https://storage.googleapis.com/antigravity-public/antigravity-cli/"

INSTALLCLAUDECODE="${INSTALLCLAUDECODE:-true}"
CLAUDECODEVERSION="${CLAUDECODEVERSION:-latest}"
INSTALLCODEX="${INSTALLCODEX:-true}"
CODEXVERSION="${CODEXVERSION:-latest}"
INSTALLOPENCODE="${INSTALLOPENCODE:-true}"
OPENCODEVERSION="${OPENCODEVERSION:-latest}"
INSTALLPI="${INSTALLPI:-true}"
PIVERSION="${PIVERSION:-latest}"
INSTALLANTIGRAVITY="${INSTALLANTIGRAVITY:-true}"

WORK_DIR=""
ARCH=""
IS_MUSL=false
REMOTE_USER=""
REMOTE_GROUP=""
REMOTE_HOME=""
ENABLED_AGENTS=()

log() {
    printf 'coding-agents feature: %s\n' "$*"
}

fail() {
    printf 'coding-agents feature: error: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi
}

fetch() {
    curl --proto '=https' --proto-redir '=https' -fsSL --retry 3 "$@"
}

fetch_redirect_url() {
    curl --proto '=https' --proto-redir '=https' -fsS --retry 3 -I -o /dev/null -w '%{redirect_url}' "$1"
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
    validate_bool "installClaudeCode" "${INSTALLCLAUDECODE}"
    validate_bool "installCodex" "${INSTALLCODEX}"
    validate_bool "installOpenCode" "${INSTALLOPENCODE}"
    validate_bool "installPi" "${INSTALLPI}"
    validate_bool "installAntigravity" "${INSTALLANTIGRAVITY}"

    CLAUDECODEVERSION="${CLAUDECODEVERSION#v}"
    CODEXVERSION="${CODEXVERSION#v}"
    OPENCODEVERSION="${OPENCODEVERSION#v}"
    PIVERSION="${PIVERSION#v}"

    ENABLED_AGENTS=()
    if [[ "${INSTALLCLAUDECODE}" == "true" ]]; then
        validate_semver "claudeCodeVersion" "${CLAUDECODEVERSION}"
        if [[ "${CLAUDECODEVERSION}" != "latest" ]] && ! version_at_least "${CLAUDECODEVERSION}" "${CLAUDE_MIN_VERSION}"; then
            fail "claudeCodeVersion '${CLAUDECODEVERSION}' is unsupported; minimum version is ${CLAUDE_MIN_VERSION}."
        fi
        ENABLED_AGENTS+=("claude-code")
    fi
    if [[ "${INSTALLCODEX}" == "true" ]]; then
        validate_semver "codexVersion" "${CODEXVERSION}"
        ENABLED_AGENTS+=("codex")
    fi
    if [[ "${INSTALLOPENCODE}" == "true" ]]; then
        validate_semver "openCodeVersion" "${OPENCODEVERSION}"
        if [[ "${OPENCODEVERSION}" != "latest" && ! "${OPENCODEVERSION}" =~ ^2\. ]]; then
            fail "openCodeVersion '${OPENCODEVERSION}' is unsupported; only OpenCode 2.x releases are supported."
        fi
        ENABLED_AGENTS+=("opencode")
    fi
    if [[ "${INSTALLPI}" == "true" ]]; then
        validate_semver "piVersion" "${PIVERSION}"
        if [[ "${PIVERSION}" != "latest" ]] && ! version_at_least "${PIVERSION}" "${PI_MIN_VERSION}"; then
            fail "piVersion '${PIVERSION}' is unsupported; minimum version is ${PI_MIN_VERSION}."
        fi
        ENABLED_AGENTS+=("pi")
    fi
    if [[ "${INSTALLANTIGRAVITY}" == "true" ]]; then
        ENABLED_AGENTS+=("antigravity")
    fi

    if (( ${#ENABLED_AGENTS[@]} == 0 )); then
        fail "no coding agent is enabled; enable at least one agent option."
    fi
}

detect_platform() {
    local os_name os_id os_version ldd_output
    os_name="$(uname -s)"
    [[ "${os_name}" == "Linux" ]] || fail "unsupported OS '${os_name}'; Linux is required."

    ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64 | amd64) ARCH="x86_64" ;;
        aarch64 | arm64) ARCH="aarch64" ;;
        *) fail "unsupported architecture '${ARCH}'; supported: x86_64, aarch64." ;;
    esac

    ldd_output="$(ldd --version 2>&1 || true)"
    if [[ -f /etc/alpine-release || -f /lib/libc.musl-x86_64.so.1 || -f /lib/libc.musl-aarch64.so.1 || "${ldd_output,,}" == *musl* ]]; then
        IS_MUSL=true
    fi

    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        os_id="$(. /etc/os-release && printf '%s' "${ID:-unknown}")"
        # shellcheck source=/dev/null
        os_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")"
        case "${os_id}:${os_version}" in
            debian:12 | debian:13 | ubuntu:24.04 | ubuntu:22.04) ;;
            *) log "note: running on ${os_id} ${os_version}" ;;
        esac
    fi

    if [[ "${INSTALLPI}" == "true" && "${IS_MUSL}" == "true" ]]; then
        fail "Pi only publishes glibc native archives; disable installPi on musl-based images."
    fi

    REMOTE_USER="${_REMOTE_USER:-root}"
    id "${REMOTE_USER}" >/dev/null 2>&1 || fail "remote user '${REMOTE_USER}' does not exist."
    REMOTE_GROUP="$(id -g "${REMOTE_USER}")"
    if [[ -n "${_REMOTE_USER_HOME:-}" ]]; then
        REMOTE_HOME="${_REMOTE_USER_HOME}"
    elif command -v getent >/dev/null 2>&1; then
        REMOTE_HOME="$(getent passwd "${REMOTE_USER}" | cut -d: -f6 || true)"
    else
        REMOTE_HOME="$(awk -F: -v u="${REMOTE_USER}" '$1 == u { print $6; exit }' /etc/passwd || true)"
    fi
    REMOTE_HOME="${REMOTE_HOME%/}"
    [[ "${REMOTE_HOME}" == /* && "${REMOTE_HOME}" != "/" && -d "${REMOTE_HOME}" ]] \
        || fail "remote-user home directory is unavailable for '${REMOTE_USER}'."
}

check_link_target() {
    local link_path="$1"
    local expected_target="$2"
    if [[ -L "${link_path}" ]]; then
        [[ "$(readlink -m "${link_path}")" == "${expected_target}" ]] \
            || fail "existing symlink '${link_path}' points elsewhere; resolve it manually before enabling this feature."
    elif [[ -e "${link_path}" ]]; then
        fail "existing path '${link_path}' conflicts; back it up and migrate it explicitly before enabling this feature."
    fi
}

check_state_conflicts() {
    [[ ! -L "${STATE_DIR}" ]] || fail "${STATE_DIR} is a symlink; restore a real mount-point directory."
    [[ ! -e "${STATE_DIR}" || -d "${STATE_DIR}" ]] || fail "${STATE_DIR} is not a directory."

    if [[ "${INSTALLCLAUDECODE}" == "true" ]]; then
        [[ -z "${CLAUDE_CONFIG_DIR+x}" || "${CLAUDE_CONFIG_DIR}" == "${STATE_DIR}/claude-code" ]] \
            || fail "CLAUDE_CONFIG_DIR is set; unset it before installing Claude Code."
        [[ ! -e "${REMOTE_HOME}/.claude.json" && ! -L "${REMOTE_HOME}/.claude.json" ]] \
            || fail "existing '${REMOTE_HOME}/.claude.json' conflicts; back it up and migrate it explicitly."
        check_link_target "${REMOTE_HOME}/.claude" "${STATE_DIR}/claude-code"
    fi

    if [[ "${INSTALLCODEX}" == "true" ]]; then
        [[ -z "${CODEX_HOME+x}" ]] || fail "CODEX_HOME is set; unset it before installing Codex."
        check_link_target "${REMOTE_HOME}/.codex" "${STATE_DIR}/codex"
    fi

    if [[ "${INSTALLOPENCODE}" == "true" ]]; then
        local entry kind rel_root full_root
        for entry in "data:.local/share" "config:.config" "state:.local/state" "cache:.cache"; do
            kind="${entry%%:*}"
            rel_root="${entry#*:}"
            full_root="${REMOTE_HOME}/${rel_root}"
            if [[ ( -e "${full_root}" || -L "${full_root}" ) && ! -d "${full_root}" ]]; then
                fail "'${full_root}' is not a directory."
            fi
            check_link_target "${full_root}/opencode" "${STATE_DIR}/opencode/${kind}"
        done
    fi

    if [[ "${INSTALLPI}" == "true" ]]; then
        [[ -z "${PI_CODING_AGENT_DIR:-}" ]] || fail "PI_CODING_AGENT_DIR is set; unset it before installing Pi."
        if [[ ( -e "${REMOTE_HOME}/.pi" || -L "${REMOTE_HOME}/.pi" ) && ! -d "${REMOTE_HOME}/.pi" ]]; then
            fail "'${REMOTE_HOME}/.pi' is not a directory."
        fi
        check_link_target "${REMOTE_HOME}/.pi/agent" "${STATE_DIR}/pi/agent"
        if [[ -e "/usr/local/bin/pi" || -L "/usr/local/bin/pi" ]]; then
            [[ "$(readlink -m "/usr/local/bin/pi")" == "${APP_ROOT}/pi/pi" ]] \
                || fail "/usr/local/bin/pi already exists and is not managed by this feature."
        fi
        if [[ ( -e "${APP_ROOT}/pi" || -L "${APP_ROOT}/pi" ) && ! -L "/usr/local/bin/pi" ]]; then
            fail "${APP_ROOT}/pi exists without this feature's /usr/local/bin/pi link."
        fi
    fi

    if [[ "${INSTALLANTIGRAVITY}" == "true" ]]; then
        local entry rel_path subdir full_path parent
        for entry in ".gemini/antigravity-cli:cli" ".gemini/config:gemini-config" ".config/antigravity:plugin-secrets"; do
            rel_path="${entry%%:*}"
            subdir="${entry#*:}"
            full_path="${REMOTE_HOME}/${rel_path}"
            parent="$(dirname "${full_path}")"
            if [[ ( -e "${parent}" || -L "${parent}" ) && ! -d "${parent}" ]]; then
                fail "'${parent}' is not a directory."
            fi
            check_link_target "${full_path}" "${STATE_DIR}/antigravity/${subdir}"
        done
    fi
}

install_prerequisites() {
    local -a required=(curl jq tar gzip sha256sum sha512sum mountpoint find getent)
    local tool missing=false

    if [[ "${INSTALLCLAUDECODE}" == "true" ]]; then
        required+=(gpg)
    fi
    if [[ "${INSTALLOPENCODE}" == "true" ]]; then
        required+=(base64 od)
    fi

    for tool in "${required[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            missing=true
            break
        fi
    done
    if [[ ! -e /etc/ssl/certs/ca-certificates.crt && ! -e /etc/pki/tls/certs/ca-bundle.crt ]]; then
        missing=true
    fi
    if ! tar --version 2>/dev/null | grep -q "GNU"; then
        missing=true
    fi
    if ! readlink -m / >/dev/null 2>&1; then
        missing=true
    fi

    if [[ "${missing}" == "false" ]]; then
        return 0
    fi

    log "installing required download and verification prerequisites..."
    if command -v apt-get >/dev/null 2>&1; then
        local -a apt_pkgs=(ca-certificates curl jq tar gzip coreutils findutils util-linux)
        if [[ "${INSTALLCLAUDECODE}" == "true" ]]; then
            apt_pkgs+=(gnupg)
        fi
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y --no-install-recommends "${apt_pkgs[@]}"
        rm -rf /var/lib/apt/lists/*
    elif command -v apk >/dev/null 2>&1; then
        local -a apk_pkgs=(ca-certificates curl jq tar gzip coreutils findutils util-linux musl-utils)
        if [[ "${INSTALLCLAUDECODE}" == "true" ]]; then
            apk_pkgs+=(gnupg)
        fi
        apk add --no-cache "${apk_pkgs[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        local -a dnf_pkgs=(ca-certificates jq tar gzip coreutils findutils util-linux)
        if ! command -v curl >/dev/null 2>&1; then
            dnf_pkgs+=(curl)
        fi
        if [[ "${INSTALLCLAUDECODE}" == "true" ]]; then
            dnf_pkgs+=(gnupg2)
        fi
        dnf install -y "${dnf_pkgs[@]}"
        dnf clean all
    else
        fail "missing required prerequisites and no supported package manager found."
    fi
}

make_user_dir() {
    local target_dir="${1%/}"
    local mode="${2:-0755}"
    local home_base="${REMOTE_HOME%/}"

    if [[ "${target_dir}" == "${home_base}" ]]; then
        return 0
    fi
    [[ "${target_dir}" == "${home_base}/"* ]] \
        || fail "internal error: '${target_dir}' is outside '${home_base}'."

    local relative="${target_dir#"${home_base}"/}"
    local dir="${home_base}"
    local part
    local -a parts
    IFS='/' read -r -a parts <<< "${relative}"
    for part in "${parts[@]}"; do
        [[ -n "${part}" ]] || continue
        dir+="/${part}"
        if [[ ! -e "${dir}" ]]; then
            install -d -m "${mode}" -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${dir}"
        fi
    done
}

install_claude_code() {
    local target resolved expected fingerprint installed=""
    local app_dir="${APP_ROOT}/claude-code"
    local stage="${WORK_DIR}/claude-code"
    mkdir -p "${stage}/home" "${stage}/gnupg"
    chmod 0700 "${stage}/gnupg"

    case "${ARCH}" in
        x86_64) target="linux-x64" ;;
        aarch64) target="linux-arm64" ;;
    esac
    if [[ "${IS_MUSL}" == "true" ]]; then
        target+="-musl"
    fi

    resolved="${CLAUDECODEVERSION}"
    if [[ "${resolved}" == "latest" ]]; then
        log "resolving latest Claude Code release..."
        resolved="$(fetch "${CLAUDE_RELEASE_API}/latest")" \
            || fail "failed to resolve latest Claude Code version."
    fi
    [[ "${resolved}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || fail "unexpected Claude Code release version '${resolved}'."
    version_at_least "${resolved}" "${CLAUDE_MIN_VERSION}" \
        || fail "resolved Claude Code version '${resolved}' is older than ${CLAUDE_MIN_VERSION}."

    if [[ -x "${app_dir}/claude" ]]; then
        installed="$(env -u CLAUDE_CONFIG_DIR HOME="${stage}/home" "${app_dir}/claude" --version 2>/dev/null || true)"
    fi
    if [[ "${installed}" != "${resolved} (Claude Code)" ]]; then
        log "downloading and verifying Claude Code ${resolved} (${target})..."
        fetch -o "${stage}/manifest.json" "${CLAUDE_RELEASE_API}/${resolved}/manifest.json" \
            || fail "failed to download Claude Code manifest for ${resolved}."
        fetch -o "${stage}/manifest.sig" "${CLAUDE_RELEASE_API}/${resolved}/manifest.json.sig" \
            || fail "failed to download Claude Code manifest signature for ${resolved}."
        fetch -o "${stage}/key.asc" "${CLAUDE_SIGNING_KEY_URL}" \
            || fail "failed to download Claude Code signing key."

        local key_info pub_count
        key_info="$(gpg --batch --homedir "${stage}/gnupg" --with-colons --show-keys "${stage}/key.asc")" \
            || fail "failed to inspect Claude Code signing key."
        if awk -F: '$1 == "sec" || $1 == "ssb" { found=1 } END { exit !found }' <<< "${key_info}"; then
            fail "Claude Code signing key bundle contains unexpected secret key records."
        fi
        pub_count="$(awk -F: '$1 == "pub" { n++ } END { print n+0 }' <<< "${key_info}")"
        [[ "${pub_count}" == "1" ]] || fail "Claude Code signing key bundle must contain exactly 1 public key."
        fingerprint="$(awk -F: '$1 == "fpr" { print $10; exit }' <<< "${key_info}")"
        [[ "${fingerprint}" == "${CLAUDE_SIGNING_FINGERPRINT}" ]] \
            || fail "Claude Code signing key fingerprint mismatch (got '${fingerprint}')."

        gpg --batch --homedir "${stage}/gnupg" --import "${stage}/key.asc" >/dev/null 2>&1
        local gpg_status
        gpg_status="$(gpg --batch --homedir "${stage}/gnupg" --status-fd 1 \
            --verify "${stage}/manifest.sig" "${stage}/manifest.json" 2>/dev/null)" \
            || fail "Claude Code manifest signature verification failed."
        if grep -qE '^\[GNUPG:\] (PLAINTEXT|UNEXPECTED|NODATA|BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG)([[:space:]]|$)' <<< "${gpg_status}"; then
            fail "Claude Code manifest signature status indicates an invalid, expired, or non-detached signature."
        fi
        grep -q '^\[GNUPG:\] GOODSIG ' <<< "${gpg_status}" \
            || fail "Claude Code manifest signature missing GOODSIG status."
        awk -v fpr="${CLAUDE_SIGNING_FINGERPRINT}" \
            '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $12 == fpr { found=1 } END { exit !found }' <<< "${gpg_status}" \
            || fail "Claude Code manifest signature did not validate against pinned key ${CLAUDE_SIGNING_FINGERPRINT}."

        expected="$(jq -er --arg version "${resolved}" --arg target "${target}" \
            'select(.version == $version) | .platforms[$target] | select(.binary == "claude") | .checksum' \
            "${stage}/manifest.json")" || fail "Claude Code manifest lacks checksum for ${target}."
        [[ "${expected}" =~ ^[a-fA-F0-9]{64}$ ]] || fail "invalid SHA-256 checksum in Claude Code manifest."

        fetch -o "${stage}/claude" "${CLAUDE_RELEASE_API}/${resolved}/${target}/claude" \
            || fail "failed to download Claude Code binary."
        printf '%s  %s\n' "${expected}" "${stage}/claude" | sha256sum -c --quiet \
            || fail "Claude Code binary SHA-256 checksum verification failed."

        chmod 0755 "${stage}/claude"
        local verified_ver
        verified_ver="$(env -u CLAUDE_CONFIG_DIR HOME="${stage}/home" "${stage}/claude" --version)" \
            || fail "downloaded Claude Code binary failed self-test."
        [[ "${verified_ver}" == "${resolved} (Claude Code)" ]] \
            || fail "Claude Code self-test returned '${verified_ver}', expected '${resolved} (Claude Code)'."

        install -d -m 0755 "${app_dir}"
        chown root:root "${stage}/claude"
        mv -f "${stage}/claude" "${app_dir}/claude"
    else
        log "Claude Code ${resolved} is already installed."
    fi

    cat > "${stage}/claude-wrapper" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${CLAUDE_CONFIG_DIR+x}" && "${CLAUDE_CONFIG_DIR}" != "/var/lib/coding-agents/claude-code" ]]; then
    printf 'coding-agents feature: error: unset CLAUDE_CONFIG_DIR when using the managed Claude Code wrapper.\n' >&2
    exit 1
fi
export CLAUDE_CONFIG_DIR="/var/lib/coding-agents/claude-code"
export DISABLE_AUTOUPDATER=1
exec /usr/local/share/coding-agents/claude-code/claude "$@"
EOF
    chmod 0755 "${stage}/claude-wrapper"
    chown root:root "${stage}/claude-wrapper"
    mv -f "${stage}/claude-wrapper" /usr/local/bin/claude
}

install_codex() {
    local target resolved redirect_url tag asset base_url expected installed=""
    local app_dir="${APP_ROOT}/codex"
    local stage="${WORK_DIR}/codex"
    mkdir -p "${stage}/home" "${stage}/application"

    case "${ARCH}" in
        x86_64) target="x86_64-unknown-linux-musl" ;;
        aarch64) target="aarch64-unknown-linux-musl" ;;
    esac

    if [[ "${CODEXVERSION}" == "latest" ]]; then
        log "resolving latest Codex release..."
        redirect_url="$(fetch_redirect_url "${CODEX_RELEASES_URL}/latest")" \
            || fail "failed to resolve latest Codex release."
        tag="${redirect_url##*/}"
        tag="${tag%%[?#]*}"
        [[ "${tag}" =~ ^rust-v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
            || fail "unexpected latest Codex tag '${tag}'."
        resolved="${BASH_REMATCH[1]}"
    else
        resolved="${CODEXVERSION}"
    fi

    if [[ -x "${app_dir}/bin/codex" ]]; then
        installed="$(env -u CODEX_HOME HOME="${stage}/home" "${app_dir}/bin/codex" --version 2>/dev/null || true)"
    fi
    if [[ "${installed}" != "codex-cli ${resolved}" \
        || ! -x "${app_dir}/bin/codex-code-mode-host" \
        || ! -x "${app_dir}/codex-path/rg" ]]; then
        asset="codex-package-${target}.tar.gz"
        base_url="${CODEX_RELEASES_URL}/download/rust-v${resolved}"
        log "downloading and verifying Codex ${resolved} (${target})..."
        fetch -o "${stage}/SHA256SUMS" "${base_url}/codex-package_SHA256SUMS" \
            || fail "failed to download Codex SHA256SUMS for ${resolved}."

        awk -v asset="${asset}" 'NF == 2 && $2 == asset { print $1 }' "${stage}/SHA256SUMS" > "${stage}/expected"
        if [[ "$(wc -l < "${stage}/expected")" -ne 1 ]]; then
            fail "Codex SHA256SUMS does not contain a unique entry for ${asset}."
        fi
        expected="$(cat "${stage}/expected")"
        [[ "${expected}" =~ ^[a-fA-F0-9]{64}$ ]] || fail "invalid SHA-256 checksum for ${asset}."

        fetch -o "${stage}/${asset}" "${base_url}/${asset}" \
            || fail "failed to download ${asset}."
        printf '%s  %s\n' "${expected}" "${stage}/${asset}" | sha256sum -c --quiet \
            || fail "Codex archive SHA-256 checksum verification failed."

        tar -xzf "${stage}/${asset}" --no-same-owner --no-same-permissions -C "${stage}/application"
        local bin_rel
        for bin_rel in "bin/codex" "bin/codex-code-mode-host" "codex-path/rg"; do
            [[ -f "${stage}/application/${bin_rel}" && ! -L "${stage}/application/${bin_rel}" ]] \
                || fail "Codex package is missing regular file '${bin_rel}'."
        done
        if [[ -e "${stage}/application/codex-resources/bwrap" || -L "${stage}/application/codex-resources/bwrap" ]]; then
            [[ -f "${stage}/application/codex-resources/bwrap" && ! -L "${stage}/application/codex-resources/bwrap" ]] \
                || fail "Codex package contains invalid codex-resources/bwrap entry."
        fi

        chmod -R a-s,u=rwX,go=rX "${stage}/application"
        chmod 0755 "${stage}/application/bin/codex" \
            "${stage}/application/bin/codex-code-mode-host" \
            "${stage}/application/codex-path/rg"
        if [[ -f "${stage}/application/codex-resources/bwrap" ]]; then
            chmod 0755 "${stage}/application/codex-resources/bwrap"
        fi
        chown -R root:root "${stage}/application"

        local verified_ver
        verified_ver="$(env -u CODEX_HOME HOME="${stage}/home" "${stage}/application/bin/codex" --version)" \
            || fail "downloaded Codex binary failed self-test."
        [[ "${verified_ver}" == "codex-cli ${resolved}" ]] \
            || fail "Codex self-test returned '${verified_ver}', expected 'codex-cli ${resolved}'."

        if [[ -e "${app_dir}" || -L "${app_dir}" ]]; then
            mv "${app_dir}" "${stage}/previous"
        fi
        if ! mv "${stage}/application" "${app_dir}"; then
            if [[ -e "${stage}/previous" || -L "${stage}/previous" ]]; then
                mv "${stage}/previous" "${app_dir}" || true
            fi
            fail "failed to install Codex into ${app_dir}."
        fi
    else
        log "Codex ${resolved} is already installed."
    fi

    cat > "${stage}/codex-wrapper" <<'EOF'
#!/usr/bin/env bash
exec /usr/local/share/coding-agents/codex/bin/codex "$@"
EOF
    chmod 0755 "${stage}/codex-wrapper"
    chown root:root "${stage}/codex-wrapper"
    mv -f "${stage}/codex-wrapper" /usr/local/bin/codex
}

run_opencode_isolated() {
    local home="$1"
    shift
    env HOME="${home}" TMPDIR="${home}/tmp" \
        XDG_DATA_HOME="${home}/data" XDG_CONFIG_HOME="${home}/config" \
        XDG_STATE_HOME="${home}/state" XDG_CACHE_HOME="${home}/cache" "$@"
}

install_opencode() {
    local target resolved tags metadata package tarball integrity expected actual installed=""
    local cli_path="/usr/local/bin/opencode"
    local stage="${WORK_DIR}/opencode"
    mkdir -p "${stage}/home/tmp"

    case "${ARCH}" in
        x86_64)
            target="linux-x64"
            if ! grep -qwi "avx2" /proc/cpuinfo 2>/dev/null; then
                target+="-baseline"
            fi
            ;;
        aarch64) target="linux-arm64" ;;
    esac
    if [[ "${IS_MUSL}" == "true" ]]; then
        target+="-musl"
    fi

    if [[ "${OPENCODEVERSION}" == "latest" ]]; then
        log "resolving latest OpenCode release..."
        tags="$(fetch "${OPENCODE_TAGS_URL}")" || fail "failed to read OpenCode dist-tags."
        resolved="$(jq -r '.latest // empty' <<< "${tags}")"
        [[ "${resolved}" =~ ^2\.[0-9]+\.[0-9]+$ ]] \
            || fail "OpenCode latest dist-tag ('${resolved}') is not a stable 2.x release."
    else
        resolved="${OPENCODEVERSION}"
    fi

    if [[ -x "${cli_path}" ]]; then
        installed="$(run_opencode_isolated "${stage}/home" "${cli_path}" --version 2>/dev/null || true)"
    fi
    if [[ "${installed}" == "opencode v${resolved}" ]]; then
        log "OpenCode ${resolved} is already installed."
        return 0
    fi

    package="@opencode/cli-${target}"
    log "downloading and verifying ${package} ${resolved}..."
    metadata="$(fetch "${OPENCODE_REGISTRY_URL}/@opencode%2fcli-${target}/${resolved}")" \
        || fail "OpenCode ${resolved} is unavailable for ${target}."
    tarball="$(jq -r '.dist.tarball // empty' <<< "${metadata}")"
    integrity="$(jq -r '.dist.integrity // empty' <<< "${metadata}")"

    [[ "${tarball}" == "${OPENCODE_REGISTRY_URL}/${package}/-/cli-${target}-${resolved}.tgz" ]] \
        || fail "unexpected OpenCode tarball URL '${tarball}'."
    [[ "${integrity}" =~ ^sha512-[A-Za-z0-9+/]{86}==$ ]] \
        || fail "OpenCode package metadata lacks valid SHA-512 integrity."

    expected="$(base64 -d <<< "${integrity#sha512-}" | od -An -tx1 -v | tr -d '[:space:]')"
    fetch -o "${stage}/package.tgz" "${tarball}" || fail "failed to download ${tarball}."
    actual="$(sha512sum "${stage}/package.tgz" | cut -d' ' -f1)"
    [[ "${actual}" == "${expected}" ]] || fail "OpenCode tarball SHA-512 verification failed."

    tar -xzf "${stage}/package.tgz" --no-same-owner --no-same-permissions -C "${stage}" package/bin/opencode \
        || fail "OpenCode archive does not contain package/bin/opencode."
    [[ -f "${stage}/package/bin/opencode" && ! -L "${stage}/package/bin/opencode" ]] \
        || fail "OpenCode archive entry package/bin/opencode is not a regular file."
    chmod 0755 "${stage}/package/bin/opencode"

    local verified_ver
    verified_ver="$(run_opencode_isolated "${stage}/home" "${stage}/package/bin/opencode" --version)" \
        || fail "downloaded OpenCode binary failed self-test."
    [[ "${verified_ver}" == "opencode v${resolved}" ]] \
        || fail "OpenCode self-test returned '${verified_ver}', expected 'opencode v${resolved}'."

    chown root:root "${stage}/package/bin/opencode"
    mv -f "${stage}/package/bin/opencode" "${cli_path}"
}

run_pi_isolated() {
    local home="$1"
    shift
    env -u PI_CODING_AGENT_DIR -u PI_PACKAGE_DIR HOME="${home}" TMPDIR="${home}/tmp" PI_OFFLINE=1 "$@"
}

install_pi() {
    local target resolved redirect_url tag archive base_url expected installed=""
    local app_dir="${APP_ROOT}/pi"
    local cli_path="/usr/local/bin/pi"
    local stage="${WORK_DIR}/pi"
    mkdir -p "${stage}/home/tmp" "${stage}/extract"

    case "${ARCH}" in
        x86_64) target="x64" ;;
        aarch64) target="arm64" ;;
    esac

    if [[ "${PIVERSION}" == "latest" ]]; then
        log "resolving latest Pi release..."
        redirect_url="$(fetch_redirect_url "${PI_RELEASES_URL}/latest")" \
            || fail "failed to resolve latest Pi release."
        tag="${redirect_url##*/}"
        tag="${tag%%[?#]*}"
        [[ "${tag}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
            || fail "unexpected latest Pi tag '${tag}'."
        resolved="${BASH_REMATCH[1]}"
    else
        resolved="${PIVERSION}"
    fi
    version_at_least "${resolved}" "${PI_MIN_VERSION}" \
        || fail "Pi release '${resolved}' is older than ${PI_MIN_VERSION}."

    if [[ -L "${cli_path}" ]]; then
        installed="$(run_pi_isolated "${stage}/home" "${cli_path}" --version 2>/dev/null || true)"
    fi
    if [[ "${installed}" == "${resolved}" ]]; then
        log "Pi ${resolved} is already installed."
        return 0
    fi

    archive="pi-linux-${target}.tar.gz"
    base_url="${PI_RELEASES_URL}/download/v${resolved}"
    log "downloading and verifying Pi ${resolved} (${target})..."
    fetch -o "${stage}/SHA256SUMS" "${base_url}/SHA256SUMS" \
        || fail "failed to download Pi SHA256SUMS for ${resolved}."

    awk -v archive="${archive}" 'NF == 2 && $2 == archive { print $1 }' "${stage}/SHA256SUMS" > "${stage}/expected"
    if [[ "$(wc -l < "${stage}/expected")" -ne 1 ]]; then
        fail "Pi SHA256SUMS does not contain a unique entry for ${archive}."
    fi
    expected="$(cat "${stage}/expected")"
    [[ "${expected}" =~ ^[a-fA-F0-9]{64}$ ]] || fail "invalid SHA-256 checksum for ${archive}."

    fetch -o "${stage}/${archive}" "${base_url}/${archive}" || fail "failed to download ${archive}."
    printf '%s  %s\n' "${expected}" "${stage}/${archive}" | sha256sum -c --quiet \
        || fail "Pi archive SHA-256 checksum verification failed."

    tar -xzf "${stage}/${archive}" --no-same-owner --no-same-permissions -C "${stage}/extract"
    [[ -f "${stage}/extract/pi/pi" && ! -L "${stage}/extract/pi/pi" ]] \
        || fail "Pi archive does not contain pi/pi executable."
    chmod -R a-s,u=rwX,go=rX "${stage}/extract/pi"
    chmod 0755 "${stage}/extract/pi/pi"
    chown -R root:root "${stage}/extract/pi"

    local verified_ver
    verified_ver="$(run_pi_isolated "${stage}/home" "${stage}/extract/pi/pi" --version)" \
        || fail "downloaded Pi binary failed self-test."
    [[ "${verified_ver}" == "${resolved}" ]] \
        || fail "Pi self-test returned '${verified_ver}', expected '${resolved}'."

    if [[ -e "${app_dir}" || -L "${app_dir}" ]]; then
        mv "${app_dir}" "${stage}/previous"
    fi
    if ! mv "${stage}/extract/pi" "${app_dir}"; then
        if [[ -e "${stage}/previous" || -L "${stage}/previous" ]]; then
            mv "${stage}/previous" "${app_dir}" || true
        fi
        fail "failed to install Pi into ${app_dir}."
    fi
    ln -sfn "${app_dir}/pi" "${cli_path}"

    if [[ "$(run_pi_isolated "${stage}/home" "${cli_path}" --version 2>/dev/null || true)" != "${resolved}" ]]; then
        rm -rf "${app_dir}"
        if [[ -e "${stage}/previous" || -L "${stage}/previous" ]]; then
            mv "${stage}/previous" "${app_dir}"
        else
            rm -f "${cli_path}"
        fi
        fail "${cli_path} failed post-install verification; previous Pi state restored."
    fi
}

install_antigravity() {
    local platform version url digest installed=""
    local app_dir="${APP_ROOT}/antigravity"
    local stage="${WORK_DIR}/antigravity"
    mkdir -p "${stage}/home" "${stage}/payload"

    case "${ARCH}" in
        x86_64) platform="linux_amd64" ;;
        aarch64) platform="linux_arm64" ;;
    esac
    if [[ "${IS_MUSL}" == "true" ]]; then
        platform+="_musl"
    fi

    log "resolving Antigravity CLI manifest (${platform})..."
    fetch -o "${stage}/manifest.json" "${AGY_MANIFEST_URL}/${platform}.json" \
        || fail "failed to download Antigravity manifest for ${platform}."
    version="$(jq -r '.version | strings' "${stage}/manifest.json")" \
        || fail "invalid Antigravity manifest JSON."
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || fail "invalid version '${version}' in Antigravity manifest."
    url="$(jq -r '.url | strings' "${stage}/manifest.json")"
    if [[ "${url}" != "${AGY_ARCHIVE_PREFIX}"* || ! "${url}" =~ ^[A-Za-z0-9:/._-]+$ || "${url}" == *..* ]]; then
        fail "unexpected Antigravity archive URL '${url}'."
    fi
    digest="$(jq -r '.sha512 | strings' "${stage}/manifest.json")"
    [[ "${digest}" =~ ^[0-9a-fA-F]{128}$ ]] || fail "invalid SHA-512 digest in Antigravity manifest."

    if [[ -x "${app_dir}/agy" ]]; then
        installed="$(HOME="${stage}/home" "${app_dir}/agy" --version 2>/dev/null || true)"
    fi
    if [[ "${installed}" != "${version}" ]]; then
        log "downloading and verifying Antigravity CLI ${version} (${platform})..."
        fetch -o "${stage}/archive.tar.gz" "${url}" || fail "failed to download Antigravity CLI archive."
        printf '%s  %s\n' "${digest}" "${stage}/archive.tar.gz" | sha512sum -c --quiet \
            || fail "Antigravity CLI SHA-512 checksum verification failed."

        tar -xzf "${stage}/archive.tar.gz" --no-same-owner --no-same-permissions -C "${stage}/payload"
        [[ -f "${stage}/payload/antigravity" && ! -L "${stage}/payload/antigravity" ]] \
            || fail "Antigravity archive lacks antigravity binary."
        chmod 0755 "${stage}/payload/antigravity"

        local verified_ver
        verified_ver="$(HOME="${stage}/home" "${stage}/payload/antigravity" --version)" \
            || fail "downloaded Antigravity CLI binary failed self-test."
        [[ "${verified_ver}" == "${version}" ]] \
            || fail "Antigravity CLI self-test returned '${verified_ver}', expected '${version}'."

        install -d -m 0755 "${app_dir}"
        chown root:root "${stage}/payload/antigravity"
        mv -f "${stage}/payload/antigravity" "${app_dir}/agy"
    else
        log "Antigravity CLI ${version} is already installed."
    fi

    cat > "${stage}/agy-wrapper" <<'EOF'
#!/usr/bin/env bash
export AGY_CLI_DISABLE_AUTO_UPDATE=true
exec /usr/local/share/coding-agents/antigravity/agy "$@"
EOF
    chmod 0755 "${stage}/agy-wrapper"
    chown root:root "${stage}/agy-wrapper"
    mv -f "${stage}/agy-wrapper" /usr/local/bin/agy
}

link_state_dir() {
    local link_path="$1"
    local target_dir="$2"
    local parent_mode="${3:-0755}"
    local parent
    parent="$(dirname "${link_path}")"

    if [[ ! -e "${target_dir}" ]]; then
        install -d -m 0700 -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${target_dir}"
    fi
    if [[ ! -L "${link_path}" ]]; then
        make_user_dir "${parent}" "${parent_mode}"
        ln -sfn "${target_dir}" "${link_path}"
        chown -h "${REMOTE_USER}:${REMOTE_GROUP}" "${link_path}"
    fi
}

prepare_runtime_and_state() {
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    install -d -m 0755 "${HELPER_DIR}"
    install -m 0755 "${script_dir}/initialize.sh" "${HELPER_DIR}/initialize"

    # Merge with any existing enabled-agents list so sequential installs remain cumulative.
    local -a merged_agents=("${ENABLED_AGENTS[@]}")
    if [[ -f "${ENABLED_AGENTS_FILE}" ]]; then
        local existing
        while IFS= read -r existing; do
            [[ -n "${existing}" ]] && merged_agents+=("${existing}")
        done < "${ENABLED_AGENTS_FILE}"
    fi
    printf '%s\n' "${merged_agents[@]}" | sort -u > "${ENABLED_AGENTS_FILE}"
    chmod 0644 "${ENABLED_AGENTS_FILE}"

    if [[ ! -e "${STATE_DIR}" ]]; then
        install -d -m 0700 -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${STATE_DIR}"
    fi

    local agent entry kind rel_root rel_path subdir rest pmode
    for agent in "${ENABLED_AGENTS[@]}"; do
        case "${agent}" in
            claude-code)
                link_state_dir "${REMOTE_HOME}/.claude" "${STATE_DIR}/claude-code" 0700
                ;;
            codex)
                link_state_dir "${REMOTE_HOME}/.codex" "${STATE_DIR}/codex" 0700
                ;;
            opencode)
                install -d -m 0700 -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${STATE_DIR}/opencode"
                for entry in "data:.local/share" "config:.config" "state:.local/state" "cache:.cache"; do
                    kind="${entry%%:*}"
                    rel_root="${entry#*:}"
                    link_state_dir "${REMOTE_HOME}/${rel_root}/opencode" "${STATE_DIR}/opencode/${kind}" 0755
                done
                ;;
            pi)
                install -d -m 0700 -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${STATE_DIR}/pi"
                link_state_dir "${REMOTE_HOME}/.pi/agent" "${STATE_DIR}/pi/agent" 0700
                ;;
            antigravity)
                install -d -m 0700 -o "${REMOTE_USER}" -g "${REMOTE_GROUP}" "${STATE_DIR}/antigravity"
                for entry in ".gemini/antigravity-cli:cli:0700" ".gemini/config:gemini-config:0700" ".config/antigravity:plugin-secrets:0755"; do
                    rel_path="${entry%%:*}"
                    rest="${entry#*:}"
                    subdir="${rest%%:*}"
                    pmode="${rest#*:}"
                    link_state_dir "${REMOTE_HOME}/${rel_path}" "${STATE_DIR}/antigravity/${subdir}" "${pmode}"
                done
                ;;
        esac
    done
}

main() {
    log "starting installation..."
    validate_options
    detect_platform
    install_prerequisites
    check_state_conflicts

    install -d -m 0755 /usr/local/bin "${APP_ROOT}"
    WORK_DIR="$(mktemp -d "${APP_ROOT}/.install.XXXXXX")"
    chmod 0700 "${WORK_DIR}"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    local agent
    for agent in "${ENABLED_AGENTS[@]}"; do
        case "${agent}" in
            claude-code) install_claude_code ;;
            codex) install_codex ;;
            opencode) install_opencode ;;
            pi) install_pi ;;
            antigravity) install_antigravity ;;
        esac
    done

    prepare_runtime_and_state
    log "installation complete (enabled: ${ENABLED_AGENTS[*]})."
}

main "$@"
