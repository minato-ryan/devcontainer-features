#!/usr/bin/env bash
# Initializes and verifies project-scoped persistent state under /var/lib/colab
# once per container creation as the remote user. If volume ownership needs repair,
# delegates `--repair` through noninteractive sudo using SUDO_UID/SUDO_GID and
# repairs strictly via directory file descriptors with O_NOFOLLOW inside /var/lib/colab.
set -euo pipefail
umask 077

readonly SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH="${SYSTEM_PATH}"

readonly STATE_DIR="/var/lib/colab"
readonly SELF_PATH="/usr/local/share/colab-feature/initialize"
readonly COLAB_PYTHON="/usr/local/share/colab-feature/uv/tools/google-colab-cli/bin/python"
readonly STATE_SUBDIRS=("adc" "config")
readonly CREDENTIAL_FILES=(
    "adc/application_default_credentials.json"
    "config/sessions.json"
    "config/settings.json"
)

log() {
    printf 'colab feature: %s\n' "$*"
}

fail() {
    printf 'colab feature: error: %s\n' "$*" >&2
    exit 1
}

require_mount() {
    if [[ -L "${STATE_DIR}" ]] || ! mountpoint -q "${STATE_DIR}"; then
        fail "${STATE_DIR} is not mounted; recreate the container with the feature's named volume."
    fi
}

check_state_links() {
    local rel
    for rel in "${STATE_SUBDIRS[@]}"; do
        [[ ! -L "${STATE_DIR}/${rel}" ]] \
            || fail "${STATE_DIR}/${rel} is a symlink; preserve it and resolve the state mapping manually."
        [[ ! -e "${STATE_DIR}/${rel}" || -d "${STATE_DIR}/${rel}" ]] \
            || fail "${STATE_DIR}/${rel} is not a directory; resolve the state mapping manually."
    done
    for rel in "${CREDENTIAL_FILES[@]}"; do
        [[ ! -L "${STATE_DIR}/${rel}" ]] \
            || fail "${STATE_DIR}/${rel} is a symlink; preserve it and resolve the state mapping manually."
        [[ ! -e "${STATE_DIR}/${rel}" || -f "${STATE_DIR}/${rel}" ]] \
            || fail "${STATE_DIR}/${rel} is not a regular file; resolve the state mapping manually."
    done
}

check_home_conflicts() {
    local home_path="$1"
    local config_dir="${home_path}/.config"
    local link_path="${config_dir}/colab-cli"

    if [[ ( -e "${config_dir}" || -L "${config_dir}" ) && ! -d "${config_dir}" ]]; then
        fail "existing '${config_dir}' is not a directory; resolve it manually."
    fi

    if [[ -L "${link_path}" ]]; then
        [[ "$(readlink -m "${link_path}")" == "${STATE_DIR}/config" ]] \
            || fail "existing symlink '${link_path}' points elsewhere; resolve it manually."
    elif [[ -e "${link_path}" ]]; then
        fail "existing '${link_path}' conflicts; back it up and migrate it explicitly."
    fi
}

restore_modes() {
    local uid="$1"
    local rel
    check_state_links
    if [[ "$(stat -c '%u' "${STATE_DIR}")" == "${uid}" ]]; then
        chmod 00700 "${STATE_DIR}"
    fi
    for rel in "${STATE_SUBDIRS[@]}"; do
        if [[ -d "${STATE_DIR}/${rel}" && ! -L "${STATE_DIR}/${rel}" && "$(stat -c '%u' "${STATE_DIR}/${rel}")" == "${uid}" ]]; then
            chmod 00700 "${STATE_DIR}/${rel}"
        fi
    done
    for rel in "${CREDENTIAL_FILES[@]}"; do
        if [[ -f "${STATE_DIR}/${rel}" && ! -L "${STATE_DIR}/${rel}" && "$(stat -c '%u' "${STATE_DIR}/${rel}")" == "${uid}" ]]; then
            chmod 0600 "${STATE_DIR}/${rel}"
        fi
    done
}

# Race-free root repair using directory file descriptors (dir_fd) and O_NOFOLLOW.
repair_state() {
    local uid="$1"
    local gid="$2"

    [[ "$(id -u)" == "0" && "${uid}" =~ ^[0-9]+$ && "${gid}" =~ ^[0-9]+$ ]] \
        || fail "invalid repair identity; rerun ${SELF_PATH} as the remote user."
    [[ -x "${COLAB_PYTHON}" ]] \
        || fail "missing runtime interpreter '${COLAB_PYTHON}'; reinstall the colab feature."

    require_mount
    check_state_links

    log "repairing ownership inside ${STATE_DIR} for UID ${uid}..."
    "${COLAB_PYTHON}" -I - "${STATE_DIR}" "${uid}" "${gid}" <<'PY'
import os
import stat
import sys

state_dir = sys.argv[1]
target_uid = int(sys.argv[2])
target_gid = int(sys.argv[3])

PROTECTED_SUBDIRS = ("adc", "config")
PROTECTED_CREDS = {
    "adc/application_default_credentials.json",
    "config/sessions.json",
    "config/settings.json",
}

def fail(msg: str) -> None:
    print(f"colab feature: error: {msg}", file=sys.stderr)
    raise SystemExit(1)

dir_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
file_flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0)

try:
    root_fd = os.open(state_dir, dir_flags)
except OSError as exc:
    fail(f"cannot open {state_dir} safely: {exc}")

try:
    root_dev = os.fstat(root_fd).st_dev

    for sub in PROTECTED_SUBDIRS:
        try:
            st = os.lstat(sub, dir_fd=root_fd)
        except FileNotFoundError:
            os.mkdir(sub, 0o700, dir_fd=root_fd)
        else:
            if stat.S_ISLNK(st.st_mode):
                fail(f"{state_dir}/{sub} is a symlink; preserve it and resolve the state mapping manually.")
            if not stat.S_ISDIR(st.st_mode):
                fail(f"{state_dir}/{sub} is not a directory; resolve the state mapping manually.")

    def repair_dir(dfd: int, rel_prefix: str) -> None:
        for name in os.listdir(dfd):
            rel = f"{rel_prefix}/{name}" if rel_prefix else name
            try:
                lst = os.lstat(name, dir_fd=dfd)
            except FileNotFoundError:
                continue

            if stat.S_ISLNK(lst.st_mode):
                if rel in PROTECTED_SUBDIRS or rel in PROTECTED_CREDS:
                    fail(f"{state_dir}/{rel} is a symlink; preserve it and resolve the state mapping manually.")
                os.chown(name, target_uid, target_gid, dir_fd=dfd, follow_symlinks=False)
                continue

            if stat.S_ISDIR(lst.st_mode):
                if rel in PROTECTED_CREDS:
                    fail(f"{state_dir}/{rel} is not a regular file; resolve the state mapping manually.")
                sub_fd = os.open(name, dir_flags, dir_fd=dfd)
                try:
                    sub_st = os.fstat(sub_fd)
                    if sub_st.st_dev != root_dev:
                        fail(f"{state_dir}/{rel} crosses filesystem boundaries.")
                    repair_dir(sub_fd, rel)
                    os.fchmod(sub_fd, 0o700)
                    os.fchown(sub_fd, target_uid, target_gid)
                finally:
                    os.close(sub_fd)
                continue

            if stat.S_ISREG(lst.st_mode):
                if rel in PROTECTED_SUBDIRS:
                    fail(f"{state_dir}/{rel} is not a directory; resolve the state mapping manually.")
                f_fd = os.open(name, file_flags, dir_fd=dfd)
                try:
                    f_st = os.fstat(f_fd)
                    if f_st.st_dev != root_dev:
                        fail(f"{state_dir}/{rel} crosses filesystem boundaries.")
                    if not stat.S_ISREG(f_st.st_mode):
                        fail(f"{state_dir}/{rel} changed type during repair.")
                    new_mode = 0o600 if rel in PROTECTED_CREDS else (stat.S_IMODE(f_st.st_mode) & 0o700)
                    os.fchmod(f_fd, new_mode)
                    os.fchown(f_fd, target_uid, target_gid)
                finally:
                    os.close(f_fd)
                continue

            fail(f"unsupported file type at {state_dir}/{rel}.")

    repair_dir(root_fd, "")
    os.fchmod(root_fd, 0o700)
    os.fchown(root_fd, target_uid, target_gid)
finally:
    os.close(root_fd)
PY
}

detect_repair_need() {
    local uid="$1"
    local rel

    if [[ "$(stat -c '%u' "${STATE_DIR}")" != "${uid}" ]]; then
        printf 'ownership\n'
        return
    fi
    for rel in "${STATE_SUBDIRS[@]}" "${CREDENTIAL_FILES[@]}"; do
        if [[ -e "${STATE_DIR}/${rel}" && "$(stat -c '%u' "${STATE_DIR}/${rel}")" != "${uid}" ]]; then
            printf 'ownership\n'
            return
        fi
    done

    if [[ "$(stat -c '%a' "${STATE_DIR}")" != "700" ]]; then
        printf 'modes\n'
        return
    fi
    for rel in "${STATE_SUBDIRS[@]}"; do
        if [[ -d "${STATE_DIR}/${rel}" && "$(stat -c '%a' "${STATE_DIR}/${rel}")" != "700" ]]; then
            printf 'modes\n'
            return
        fi
    done
    for rel in "${CREDENTIAL_FILES[@]}"; do
        if [[ -f "${STATE_DIR}/${rel}" && "$(stat -c '%a' "${STATE_DIR}/${rel}")" != "600" ]]; then
            printf 'modes\n'
            return
        fi
    done

    printf 'none\n'
}

check_access() {
    local rel probe
    for rel in "${STATE_SUBDIRS[@]}"; do
        [[ -d "${STATE_DIR}/${rel}" && -r "${STATE_DIR}/${rel}" && -w "${STATE_DIR}/${rel}" && -x "${STATE_DIR}/${rel}" ]] \
            || fail "${STATE_DIR}/${rel} is inaccessible; repair volume permissions and retry."
        probe="$(mktemp "${STATE_DIR}/${rel}/.colab-check.XXXXXX")" \
            || fail "${STATE_DIR}/${rel} is not writable; repair volume permissions and retry."
        rm -f -- "${probe}"
    done
}

ensure_home_link() {
    local home_path="$1"
    local config_dir="${home_path}/.config"
    local link_path="${config_dir}/colab-cli"

    if [[ ! -L "${link_path}" ]]; then
        log "linking ${link_path} -> ${STATE_DIR}/config"
        (umask 022 && mkdir -p "${config_dir}")
        ln -sfn "${STATE_DIR}/config" "${link_path}"
    fi
}

initialize_state() {
    local uid gid home_path repair rel
    uid="$(id -u)"
    gid="$(id -g)"
    home_path="${HOME:-$(getent passwd "${uid}" | cut -d: -f6 || true)}"
    home_path="${home_path%/}"
    [[ "${home_path}" == /* && -d "${home_path}" ]] \
        || fail "remote-user HOME is unavailable; fix HOME and rerun ${SELF_PATH}."

    require_mount
    check_state_links
    check_home_conflicts "${home_path}"

    repair="$(detect_repair_need "${uid}")"
    if [[ "${repair}" == "modes" ]]; then
        log "restoring private permissions inside ${STATE_DIR}..."
        restore_modes "${uid}"
        repair="$(detect_repair_need "${uid}")"
    fi

    if [[ "${repair}" == "ownership" ]]; then
        if [[ "${uid}" == "0" ]]; then
            repair_state "${uid}" "${gid}"
        else
            command -v sudo >/dev/null 2>&1 \
                || fail "state repair requires noninteractive sudo; restore ${STATE_DIR} ownership to UID ${uid} manually."
            sudo --non-interactive "${SELF_PATH}" --repair \
                || fail "state repair failed; grant noninteractive sudo or restore ${STATE_DIR} ownership to UID ${uid}."
        fi
    fi

    if [[ "$(detect_repair_need "${uid}")" != "none" ]]; then
        fail "${STATE_DIR} is still not private to UID ${uid}; repair it manually."
    fi

    check_state_links
    for rel in "${STATE_SUBDIRS[@]}"; do
        if [[ ! -e "${STATE_DIR}/${rel}" ]]; then
            mkdir -m 0700 "${STATE_DIR}/${rel}"
        fi
    done

    check_access
    ensure_home_link "${home_path}"
    log "private project state is ready."
}

main() {
    if [[ "$#" -eq 1 && "$1" == "--repair" ]]; then
        [[ "$(id -u)" == "0" ]] \
            || fail "--repair must be invoked via sudo as root."
        [[ "${SUDO_UID:-}" =~ ^[1-9][0-9]*$ && "${SUDO_GID:-}" =~ ^[0-9]+$ ]] \
            || fail "missing or invalid SUDO_UID/SUDO_GID for --repair."
        repair_state "${SUDO_UID}" "${SUDO_GID}"
    elif [[ "$#" -eq 0 ]]; then
        initialize_state
    else
        fail "unexpected arguments; run ${SELF_PATH} without arguments."
    fi
}

main "$@"
