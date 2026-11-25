#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

check_godot_mono() {
    local out
    out="$(godot --version)"
    [[ "${out}" =~ ^4\.7\.2\.stable\.mono\.official\.[0-9a-f]+$ ]]
}

check_godot_receipt() {
    grep -qx 'version=4.7.2' /opt/godot/.devcontainer-feature-3d-tools &&
        grep -qx 'variant=dotnet' /opt/godot/.devcontainer-feature-3d-tools
}

check_blender_absent() {
    ! command -v blender && [ ! -e /opt/blender ]
}

check "dotnet SDK is available" dotnet --version
check "godot version matches pinned 4.7.2 mono build" check_godot_mono
check "GodotSharp directory exists" test -d /opt/godot/GodotSharp
check "godot receipt records version 4.7.2 and dotnet variant" check_godot_receipt
check "blender is not installed when installBlender is false" check_blender_absent

mkdir -p "${work}/project"
cat > "${work}/project/project.godot" <<'INI'
config_version=5

[application]

config/name="Probe"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.7", "C#")

[dotnet]

project/assembly_name="Probe"
INI

cat > "${work}/project/Probe.csproj" <<'XML'
<Project Sdk="Godot.NET.Sdk/4.7.2">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
XML

cat > "${work}/project/Main.cs" <<'CS'
using Godot;

public partial class Main : Node
{
}
CS

cat > "${work}/project/main.tscn" <<'TSCN'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Main.cs" id="1_main"]

[node name="Root" type="Node"]
script = ExtResource("1_main")
TSCN

check "godot headless --build-solutions --quit compiles C# project" \
    godot --headless --path "${work}/project" --build-solutions --quit
check "C# assembly was built by Godot" \
    test -f "${work}/project/.godot/mono/temp/bin/Debug/Probe.dll"

reportResults
