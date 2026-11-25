#!/usr/bin/env bash
# Initializes and verifies project-scoped persistent state under /var/lib/coding-agents
# once per container creation as the remote user. If volume ownership or permissions need
# repair, delegates `--repair <uid> <gid>` through noninteractive sudo without following
# symlinks outside /var/lib/coding-agents.
set -euo pipefail
umask 077

readonly STATE_DIR="/var/lib/coding-agents"
readonly SELF_PATH="/usr/local/share/coding-agents-feature/initialize"
readonly ENABLED_AGENTS_FILE="/usr/local/share/coding-agents-feature/enabled-agents"

ENABLED_AGENTS=()

log() {
    printf 'coding-agents feature: %s\n' "$*"
}

fail() {
    printf 'coding-agents feature: error: %s\n' "$*" >&2
    exit 1
}

load_enabled_agents() {
    [[ -r "${ENABLED_AGENTS_FILE}" ]] \
        || fail "missing '${ENABLED_AGENTS_FILE}'; reinstall the coding-agents feature."
    ENABLED_AGENTS=()
    local line
    while IFS= read -r line; do
        [[ -n "${line}" ]] && ENABLED_AGENTS+=("${line}")
    done < "${ENABLED_AGENTS_FILE}"
    (( ${#ENABLED_AGENTS[@]} > 0 )) \
        || fail "no enabled agents recorded in '${ENABLED_AGENTS_FILE}'."
}

agent_enabled() {
    local target="$1"
    local agent
    for agent in "${ENABLED_AGENTS[@]}"; do
        if [[ "${agent}" == "${target}" ]]; then
            return 0
        fi
    done
    return 1
}

require_mount() {
    if [[ -L "${STATE_DIR}" ]] || ! mountpoint -q "${STATE_DIR}"; then
        fail "${STATE_DIR} is not mounted; recreate the container with the feature's named volume."
    fi
}

# Echoes state subdirectories relative to STATE_DIR for all enabled agents.
list_state_subdirs() {
    local agent
    for agent in "${ENABLED_AGENTS[@]}"; do
        case "${agent}" in
            claude-code)
                printf '%s\n' "claude-code"
                ;;
            codex)
                printf '%s\n' "codex"
                ;;
            opencode)
                printf '%s\n' "opencode" "opencode/data" "opencode/config" "opencode/state" "opencode/cache"
                ;;
            pi)
                printf '%s\n' "pi" "pi/agent"
                ;;
            antigravity)
                printf '%s\n' "antigravity" "antigravity/cli" "antigravity/gemini-config" "antigravity/plugin-secrets"
                ;;
        esac
    done
}

# Echoes writable leaf directories relative to STATE_DIR for enabled agents.
list_writable_dirs() {
    local agent
    for agent in "${ENABLED_AGENTS[@]}"; do
        case "${agent}" in
            claude-code)
                printf '%s\n' "claude-code"
                ;;
            codex)
                printf '%s\n' "codex"
                ;;
            opencode)
                printf '%s\n' "opencode/data" "opencode/config" "opencode/state" "opencode/cache"
                ;;
            pi)
                printf '%s\n' "pi/agent"
                ;;
            antigravity)
                printf '%s\n' "antigravity/cli" "antigravity/gemini-config" "antigravity/plugin-secrets"
                ;;
        esac
    done
}

# Echoes known credential files relative to STATE_DIR for enabled agents.
list_credential_files() {
    local agent
    for agent in "${ENABLED_AGENTS[@]}"; do
        case "${agent}" in
            claude-code)
                printf '%s\n' "claude-code/.credentials.json" "claude-code/.claude.json"
                ;;
            codex)
                printf '%s\n' "codex/auth.json" "codex/config.toml"
                ;;
            opencode)
                printf '%s\n' "opencode/data/opencode.db" "opencode/data/opencode.db-wal" "opencode/data/opencode.db-shm"
                ;;
            pi)
                printf '%s\n' "pi/agent/auth.json" "pi/agent/mcp-auth.json"
                ;;
            antigravity)
                printf '%s\n' "antigravity/cli/antigravity-oauth-token" "antigravity/plugin-secrets/plugin-secrets.json"
                ;;
        esac
    done
}

check_state_links() {
    local rel
    while IFS= read -r rel; do
        [[ -n "${rel}" ]] || continue
        [[ ! -L "${STATE_DIR}/${rel}" ]] \
            || fail "${STATE_DIR}/${rel} is a symlink; preserve it and resolve the state mapping manually."
    done < <(list_state_subdirs; list_credential_files)
}

effective_xdg_root() {
    local kind="$1"
    local root=""
    case "${kind}" in
        data) root="${XDG_DATA_HOME:-${HOME}/.local/share}" ;;
        config) root="${XDG_CONFIG_HOME:-${HOME}/.config}" ;;
        state) root="${XDG_STATE_HOME:-${HOME}/.local/state}" ;;
        cache) root="${XDG_CACHE_HOME:-${HOME}/.cache}" ;;
    esac
    [[ "${root}" == /* ]] || fail "effective XDG ${kind} root ('${root}') must be an absolute path."
    printf '%s\n' "${root}"
}

check_home_link() {
    local link_path="$1"
    local expected_target="$2"
    if [[ -L "${link_path}" ]]; then
        [[ "$(readlink -m "${link_path}")" == "${expected_target}" ]] \
            || fail "existing symlink '${link_path}' points elsewhere; resolve it manually."
    elif [[ -e "${link_path}" ]]; then
        fail "existing '${link_path}' conflicts; back it up and migrate it explicitly."
    fi
}

check_home_conflicts() {
    local home_path="${HOME%/}"

    if agent_enabled "claude-code"; then
        [[ -z "${CLAUDE_CONFIG_DIR+x}" ]] \
            || fail "CLAUDE_CONFIG_DIR is set; remove the override and rerun initialization."
        [[ ! -e "${home_path}/.claude.json" && ! -L "${home_path}/.claude.json" ]] \
            || fail "existing '${home_path}/.claude.json' is outside the mapped directory; migrate it explicitly."
        check_home_link "${home_path}/.claude" "${STATE_DIR}/claude-code"
    fi

    if agent_enabled "codex"; then
        [[ -z "${CODEX_HOME+x}" ]] \
            || fail "CODEX_HOME is set; remove the override and rerun initialization."
        check_home_link "${home_path}/.codex" "${STATE_DIR}/codex"
    fi

    if agent_enabled "opencode"; then
        local -a kinds=(data config state cache)
        local -a roots=()
        local kind root canon
        for kind in "${kinds[@]}"; do
            root="$(effective_xdg_root "${kind}")"
            if [[ -e "${root}" && ! -d "${root}" ]]; then
                fail "'${root}' is not a directory."
            fi
            check_home_link "${root}/opencode" "${STATE_DIR}/opencode/${kind}"
            canon="$(readlink -m "${root}")"
            [[ "${canon}" != "${STATE_DIR}" && "${canon}" != "${STATE_DIR}"/* ]] \
                || fail "XDG ${kind} root '${root}' must not reside inside ${STATE_DIR}."
            roots+=("${canon}")
        done
        local i j inner
        for i in 0 1 2 3; do
            for j in 0 1 2 3; do
                if (( i == j )); then
                    continue
                fi
                if (( i < j )) && [[ "${roots[i]}" == "${roots[j]}" ]]; then
                    fail "OpenCode ${kinds[i]} and ${kinds[j]} share XDG root '${roots[i]}'; use distinct roots."
                fi
                inner="${roots[j]%/}/opencode"
                [[ "${roots[i]}" != "${inner}" && "${roots[i]}" != "${inner}/"* ]] \
                    || fail "OpenCode ${kinds[i]} root '${roots[i]}' nests inside '${inner}'."
            done
        done
    fi

    if agent_enabled "pi"; then
        [[ -z "${PI_CODING_AGENT_DIR:-}" ]] \
            || fail "PI_CODING_AGENT_DIR is set; remove it so Pi uses ~/.pi/agent."
        local pi_parent="${home_path}/.pi"
        local pi_canon
        pi_canon="$(readlink -m "${pi_parent}")"
        [[ "${pi_canon}" != "${STATE_DIR}" && "${pi_canon}" != "${STATE_DIR}"/* ]] \
            || fail "'${pi_parent}' must not reside inside ${STATE_DIR}."
        if [[ ( -e "${pi_parent}" || -L "${pi_parent}" ) && ! -d "${pi_parent}" ]]; then
            fail "'${pi_parent}' is not a directory."
        fi
        check_home_link "${pi_parent}/agent" "${STATE_DIR}/pi/agent"
    fi

    if agent_enabled "antigravity"; then
        local config_home
        config_home="$(effective_xdg_root "config")"
        if [[ -e "${config_home}" && ! -d "${config_home}" ]]; then
            fail "'${config_home}' is not a directory."
        fi
        if [[ -e "${home_path}/.gemini" && ! -d "${home_path}/.gemini" ]]; then
            fail "'${home_path}/.gemini' is not a directory."
        fi
        check_home_link "${home_path}/.gemini/antigravity-cli" "${STATE_DIR}/antigravity/cli"
        check_home_link "${home_path}/.gemini/config" "${STATE_DIR}/antigravity/gemini-config"
        check_home_link "${config_home}/antigravity" "${STATE_DIR}/antigravity/plugin-secrets"
    fi
}

state_is_healthy() {
    local uid="$1"
    local rel
    [[ "$(stat -c '%u:%a' "${STATE_DIR}")" == "${uid}:700" ]] || return 1

    while IFS= read -r rel; do
        [[ -n "${rel}" ]] || continue
        [[ -d "${STATE_DIR}/${rel}" && ! -L "${STATE_DIR}/${rel}" ]] || return 1
        [[ "$(stat -c '%u:%a' "${STATE_DIR}/${rel}")" == "${uid}:700" ]] || return 1
    done < <(list_state_subdirs)

    while IFS= read -r rel; do
        [[ -n "${rel}" ]] || continue
        if [[ -e "${STATE_DIR}/${rel}" ]]; then
            [[ -f "${STATE_DIR}/${rel}" && ! -L "${STATE_DIR}/${rel}" ]] || return 1
            [[ "$(stat -c '%u:%a' "${STATE_DIR}/${rel}")" == "${uid}:600" ]] || return 1
        fi
    done < <(list_credential_files)
}

repair_state() {
    local uid="$1"
    local gid="$2"
    local rel need_chown=false

    [[ "$(id -u)" == "0" && "${uid}" =~ ^[0-9]+$ && "${gid}" =~ ^[0-9]+$ ]] \
        || fail "invalid repair identity; rerun ${SELF_PATH} as the remote user."

    load_enabled_agents
    require_mount
    check_state_links

    if [[ "$(stat -c '%u' "${STATE_DIR}")" != "${uid}" ]]; then
        need_chown=true
    else
        while IFS= read -r rel; do
            [[ -n "${rel}" ]] || continue
            if [[ -e "${STATE_DIR}/${rel}" && "$(stat -c '%u' "${STATE_DIR}/${rel}")" != "${uid}" ]]; then
                need_chown=true
                break
            fi
        done < <(list_state_subdirs; list_credential_files)
    fi

    if [[ "${need_chown}" == "true" ]]; then
        log "repairing ownership inside ${STATE_DIR} for UID ${uid}..."
        find -P "${STATE_DIR}" -xdev -exec chown -h "${uid}:${gid}" -- {} +
        find -P "${STATE_DIR}" -xdev -type d -exec chmod 00700 -- {} +
        find -P "${STATE_DIR}" -xdev -type f -exec chmod go-rwx -- {} +
    fi

    chmod 00700 "${STATE_DIR}"
    while IFS= read -r rel; do
        [[ -n "${rel}" ]] || continue
        if [[ ! -e "${STATE_DIR}/${rel}" ]]; then
            install -d -m 0700 -o "${uid}" -g "${gid}" "${STATE_DIR}/${rel}"
        fi
        chmod 00700 "${STATE_DIR}/${rel}"
    done < <(list_state_subdirs)

    while IFS= read -r rel; do
        [[ -n "${rel}" ]] || continue
        if [[ -f "${STATE_DIR}/${rel}" && ! -L "${STATE_DIR}/${rel}" ]]; then
            chown -h "${uid}:${gid}" -- "${STATE_DIR}/${rel}"
            chmod 0600 -- "${STATE_DIR}/${rel}"
        fi
    done < <(list_credential_files)
}

check_access() {
    local rel probe
    while IFS= read -r rel; do
        [[ -n "${rel}" ]] || continue
        [[ -r "${STATE_DIR}/${rel}" && -w "${STATE_DIR}/${rel}" && -x "${STATE_DIR}/${rel}" ]] \
            || fail "${STATE_DIR}/${rel} is inaccessible; repair volume permissions and retry."
        probe="$(mktemp "${STATE_DIR}/${rel}/.coding-agents-check.XXXXXX")" \
            || fail "${STATE_DIR}/${rel} is not writable; repair volume permissions and retry."
        rm -f -- "${probe}"
    done < <(list_writable_dirs)
}

ensure_link() {
    local link_path="$1"
    local target_dir="$2"
    local parent_umask="${3:-022}"
    local parent
    parent="$(dirname "${link_path}")"
    if [[ ! -L "${link_path}" ]]; then
        log "linking ${link_path} -> ${target_dir}"
        (umask "${parent_umask}" && mkdir -p "${parent}")
        ln -sfn "${target_dir}" "${link_path}"
    fi
}

create_home_links() {
    local home_path="${HOME%/}"

    if agent_enabled "claude-code"; then
        ensure_link "${home_path}/.claude" "${STATE_DIR}/claude-code" 077
    fi
    if agent_enabled "codex"; then
        ensure_link "${home_path}/.codex" "${STATE_DIR}/codex" 077
    fi
    if agent_enabled "opencode"; then
        local entry kind root
        for entry in data config state cache; do
            kind="${entry}"
            root="$(effective_xdg_root "${kind}")"
            ensure_link "${root}/opencode" "${STATE_DIR}/opencode/${kind}" 022
        done
    fi
    if agent_enabled "pi"; then
        ensure_link "${home_path}/.pi/agent" "${STATE_DIR}/pi/agent" 077
    fi
    if agent_enabled "antigravity"; then
        local config_home
        config_home="$(effective_xdg_root "config")"
        ensure_link "${home_path}/.gemini/antigravity-cli" "${STATE_DIR}/antigravity/cli" 077
        ensure_link "${home_path}/.gemini/config" "${STATE_DIR}/antigravity/gemini-config" 077
        ensure_link "${config_home}/antigravity" "${STATE_DIR}/antigravity/plugin-secrets" 022
    fi
}

initialize_state() {
    local uid gid
    uid="$(id -u)"
    gid="$(id -g)"
    [[ "${HOME:-}" == /* && -d "${HOME}" ]] \
        || fail "remote-user HOME is unavailable; fix HOME and rerun ${SELF_PATH}."

    load_enabled_agents
    require_mount
    check_state_links
    check_home_conflicts

    if ! state_is_healthy "${uid}"; then
        if [[ "${uid}" == "0" ]]; then
            repair_state "${uid}" "${gid}"
        else
            command -v sudo >/dev/null 2>&1 \
                || fail "state repair requires noninteractive sudo; restore ${STATE_DIR} ownership to UID ${uid} manually."
            sudo --non-interactive "${SELF_PATH}" --repair "${uid}" "${gid}" \
                || fail "state repair failed; grant noninteractive sudo or restore ${STATE_DIR} ownership to UID ${uid}."
        fi
        state_is_healthy "${uid}" || fail "${STATE_DIR} is still not private to UID ${uid}; repair it manually."
    fi

    check_access
    create_home_links
    log "private project state is ready (${ENABLED_AGENTS[*]})."
}

main() {
    if [[ "$#" -eq 3 && "$1" == "--repair" ]]; then
        repair_state "$2" "$3"
    elif [[ "$#" -eq 0 ]]; then
        initialize_state
    else
        fail "unexpected arguments; run ${SELF_PATH} without arguments."
    fi
}

main "$@"

