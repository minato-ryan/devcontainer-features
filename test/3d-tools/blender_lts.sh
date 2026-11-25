#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

check_blender_series() {
    local out
    out="$(blender --version)"
    [[ "${out}" =~ ^Blender\ 4\.5\. ]]
}

check_godot_absent() {
    ! command -v godot && [ ! -e /opt/godot ]
}

check_blender_render() {
    timeout 300 blender -b --factory-startup -E BLENDER_WORKBENCH --python-exit-code 1 \
        --python "${work}/render_cfg.py" -o "${work}/wb_####" -F PNG -f 1 &&
        test -s "${work}/wb_0001.png"
}

check "blender version matches 4.5 series" check_blender_series
check "blender receipt records 4.5 series" grep -Eq '^version=4\.5\.[0-9]+$' /opt/blender/.devcontainer-feature-3d-tools
check "godot is not installed when installGodot is false" check_godot_absent

cat > "${work}/render_cfg.py" <<'PY'
import bpy

scene = bpy.context.scene
scene.render.resolution_x = 64
scene.render.resolution_y = 48
scene.render.resolution_percentage = 100
PY

check "blender 4.5 renders BLENDER_WORKBENCH PNG headlessly" check_blender_render

reportResults
