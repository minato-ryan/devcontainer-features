#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

check_godot_pinned() {
    local out
    out="$(godot --version)"
    [[ "${out}" =~ ^4\.6\.3\.stable\.official\.[0-9a-f]+$ ]]
}

check_godot_receipt() {
    grep -qx 'version=4.6.3' /opt/godot/.devcontainer-feature-3d-tools &&
        grep -qx 'variant=standard' /opt/godot/.devcontainer-feature-3d-tools
}

check_blender_absent() {
    ! command -v blender && [ ! -e /opt/blender ]
}

check "godot version matches pinned 4.6.3" check_godot_pinned
check "godot receipt records version 4.6.3 and standard variant" check_godot_receipt
check "blender is not installed when installBlender is false" check_blender_absent

mkdir -p "${work}/project"
cat > "${work}/project/project.godot" <<'INI'
config_version=5

[application]

config/name="Godot Pinned Probe"
run/main_scene="res://main.tscn"
INI
cat > "${work}/project/main.tscn" <<'TSCN'
[gd_scene format=3]

[node name="Root" type="Node"]
TSCN

check "godot headless --quit works" godot --headless --path "${work}/project" --quit

reportResults
