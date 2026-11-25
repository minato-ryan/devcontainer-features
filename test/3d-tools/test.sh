#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

check_no_build_home_artifacts() {
    local rel_path
    for rel_path in .config/godot .local/share/godot .cache/godot .config/blender; do
        if [ -e "${HOME}/${rel_path}" ]; then
            printf 'unexpected home artifact: %s/%s\n' "${HOME}" "${rel_path}" >&2
            return 1
        fi
    done

    if [ "$(id -u)" -eq 0 ]; then
        for rel_path in .config/godot .local/share/godot .cache/godot .config/blender; do
            if [ -e "/root/${rel_path}" ]; then
                printf 'unexpected root artifact: /root/%s\n' "${rel_path}" >&2
                return 1
            fi
        done
    else
        sudo -n true 2>/dev/null || {
            printf 'cannot verify /root without passwordless sudo\n' >&2
            return 1
        }
        for rel_path in .config/godot .local/share/godot .cache/godot .config/blender; do
            if sudo -n test -e "/root/${rel_path}"; then
                printf 'unexpected root artifact: /root/%s\n' "${rel_path}" >&2
                return 1
            fi
        done
    fi
}

check_blender_receipt_version() {
    local expected out first_line
    expected="$(sed -n 's/^version=//p' /opt/blender/.devcontainer-feature-3d-tools)"
    out="$(blender --version)"
    first_line="${out%%$'\n'*}"
    [[ "${first_line}" =~ ^Blender\ ${expected//./\\.}([[:space:]]|$) ]]
}

check_tree_permissions() {
    local dir="$1"
    [ "$(stat -c '%u:%g' "${dir}")" = "0:0" ] &&
        ! find "${dir}" ! -type l -perm /6022 -print -quit | grep -q .
}

check_blender_pyc_paths() {
    local pyc py_bin
    pyc="$(find /opt/blender -name '*.pyc' -print -quit)"
    [ -n "${pyc}" ]
    py_bin="$(find /opt/blender -path '*/python/bin/python3.*' -type f -executable -print -quit)"
    [ -n "${py_bin}" ]
    "${py_bin}" - "$pyc" <<'PY'
import marshal, sys

with open(sys.argv[1], "rb") as fh:
    fh.read(16)
    code = marshal.load(fh)

filename = code.co_filename
assert filename.startswith("/opt/blender/"), f"unexpected co_filename: {filename}"
assert ".blender-3d-tools." not in filename, f"staging path leaked into pyc: {filename}"
PY
}

check_blender_raise_exits_one() {
    local status=0
    timeout 300 blender -b --factory-startup --python-exit-code 1 --python "${work}/fail.py" >/dev/null 2>&1 || status=$?
    [ "${status}" -eq 1 ]
}

check_blender_render() {
    local engine="$1"
    local prefix="$2"
    timeout 300 blender -b --factory-startup -E "${engine}" --python-exit-code 1 \
        --python "${work}/render_cfg.py" -o "${work}/${prefix}_####" -F PNG -f 1 &&
        test -s "${work}/${prefix}_0001.png"
}

check_godot_standard_version() {
    local out
    out="$(godot --version)"
    [[ "${out}" =~ ^[0-9]+(\.[0-9]+)+\.stable\.official\.[0-9a-f]+$ ]]
}

check_godot_receipt_version() {
    local expected out
    expected="$(sed -n 's/^version=//p' /opt/godot/.devcontainer-feature-3d-tools)"
    out="$(godot --version)"
    [[ "${out}" == "${expected}.stable.official."* ]]
}

# Verify build-time checks left no user/root state before invoking blender or godot.
check "no build-time state written to home directories" check_no_build_home_artifacts

check "blender version" blender --version
check "blender command links to managed tree" test "$(readlink /usr/local/bin/blender)" = /opt/blender/blender
check "blender receipt ownership and mode" test "$(stat -c '%u:%g:%a' /opt/blender/.devcontainer-feature-3d-tools)" = "0:0:644"
check "blender receipt version matches blender --version" check_blender_receipt_version
check "blender tree is root-owned and has no group/world-write or setuid/setgid bits" check_tree_permissions /opt/blender
check "blender precompiled pyc files point to /opt/blender" check_blender_pyc_paths

cat > "${work}/ok.py" <<'PY'
print("ok")
PY
cat > "${work}/fail.py" <<'PY'
raise RuntimeError("expected failure")
PY

check "blender --python-exit-code 1 returns 0 on succeeding script" \
    timeout 300 blender -b --factory-startup --python-exit-code 1 --python "${work}/ok.py"
check "blender --python-exit-code 1 returns 1 on raising script" check_blender_raise_exits_one

cat > "${work}/render_cfg.py" <<'PY'
import bpy

scene = bpy.context.scene
scene.render.resolution_x = 64
scene.render.resolution_y = 48
scene.render.resolution_percentage = 100
scene.cycles.samples = 4
PY

check "blender renders CYCLES PNG headlessly" check_blender_render CYCLES cycles
check "blender renders BLENDER_WORKBENCH PNG headlessly" check_blender_render BLENDER_WORKBENCH workbench

check "godot version" godot --version
check "godot reports official standard build" check_godot_standard_version
check "godot command links to managed tree" test "$(readlink /usr/local/bin/godot)" = /opt/godot/godot
check "godot receipt ownership and mode" test "$(stat -c '%u:%g:%a' /opt/godot/.devcontainer-feature-3d-tools)" = "0:0:644"
check "godot receipt records standard variant" grep -qx 'variant=standard' /opt/godot/.devcontainer-feature-3d-tools
check "godot receipt version matches godot --version" check_godot_receipt_version
check "godot tree is root-owned and has no group/world-write or setuid/setgid bits" check_tree_permissions /opt/godot

mkdir -p "${work}/project"
cat > "${work}/project/project.godot" <<'INI'
config_version=5

[application]

config/name="3D Tools Probe"
run/main_scene="res://main.tscn"
INI
cat > "${work}/project/main.tscn" <<'TSCN'
[gd_scene format=3]

[node name="Root" type="Node"]
TSCN

check "godot headless --quit exits 0 on minimal project" \
    godot --headless --path "${work}/project" --quit
check "godot headless --import exits 0 on minimal project" \
    godot --headless --path "${work}/project" --import

reportResults
