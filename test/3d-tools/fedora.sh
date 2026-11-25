#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

check_blender_render() {
    timeout 300 blender -b --factory-startup -E BLENDER_WORKBENCH --python-exit-code 1 \
        --python "${work}/render_cfg.py" -o "${work}/wb_####" -F PNG -f 1 &&
        test -s "${work}/wb_0001.png"
}

check "blender version" blender --version

cat > "${work}/render_cfg.py" <<'PY'
import bpy

scene = bpy.context.scene
scene.render.resolution_x = 64
scene.render.resolution_y = 48
scene.render.resolution_percentage = 100
PY

check "blender renders BLENDER_WORKBENCH PNG headlessly on Fedora" check_blender_render

check "godot version" godot --version

mkdir -p "${work}/project"
cat > "${work}/project/project.godot" <<'INI'
config_version=5

[application]

config/name="Fedora Godot Probe"
run/main_scene="res://main.tscn"
INI
cat > "${work}/project/main.tscn" <<'TSCN'
[gd_scene format=3]

[node name="Root" type="Node"]
TSCN

check "godot headless --quit works on Fedora" godot --headless --path "${work}/project" --quit

reportResults
