## Included Tools & Verification

This Feature installs 3D simulation, rendering, and project workflow tools from checksum-verified official releases without requiring a display server or modifying user home directories at build time:

| Tool | CLI | Install Root | Options | Verification |
| --- | --- | --- | --- | --- |
| Blender | `/usr/local/bin/blender` | `/opt/blender` | `installBlender`, `blenderVersion` | Official `download.blender.org` SHA-256 (mirror redirects disallowed) |
| Godot | `/usr/local/bin/godot` | `/opt/godot` | `installGodot`, `godotVersion`, `godotVariant` | Official GitHub release `SHA512-SUMS.txt` |

Each installed tree is root-owned (`0:0`), non-writable by group or others, and records an install receipt at `/opt/<tool>/.devcontainer-feature-3d-tools`. Re-running the installer with the same resolved version and variant keeps the existing installation; changing version or variant swaps atomically and rolls back on failure. Existing unmanaged installations on `PATH` or at target paths fail the build rather than being overwritten.

## Version & Variant Selection

- **Blender (`blenderVersion`)**:
  - `latest` (default): resolves the newest series `>= 4.2` that publishes a Linux x64 tarball and `.sha256` file.
  - Series (e.g. `4.5`, `5.3`): resolves the newest patch release within that series.
  - Exact release (e.g. `4.5.17`): installs that exact `MAJOR.MINOR.PATCH` release (`>= 4.2.0`).
- **Godot (`godotVersion`, `godotVariant`)**:
  - `latest` (default): resolves the current stable release from GitHub (`>= 4.2.2`).
  - `MAJOR.MINOR` or `MAJOR.MINOR.PATCH` (with or without `-stable`, e.g. `4.6.3` or `4.7.2-stable`): installs that exact stable release (`>= 4.2.2`; pre-releases are rejected).
  - `godotVariant: "standard"` installs the GDScript build; `godotVariant: "dotnet"` installs the C# / .NET build (including `GodotSharp/`).

### Using Godot with .NET (`godotVariant: "dotnet"`)

Pair `godotVariant: "dotnet"` with the official LTS .NET SDK Feature in your `devcontainer.json`:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/devcontainers/features/dotnet:2": {
            "version": "lts"
        },
        "ghcr.io/minato-ryan/devcontainer-features/3d-tools:1": {
            "godotVariant": "dotnet"
        }
    }
}
```

## Headless Usage

### Blender

Run Blender in background mode (`-b`) for headless scripting and rendering (Mesa software OpenGL/EGL libraries are installed automatically):

```bash
timeout 600 blender -b --factory-startup --python-exit-code 1 --python render.py -- output.png
```

- Always pass `--python-exit-code 1` before `--python` so uncaught Python exceptions return a non-zero exit code.
- Available render engines (`-E`): `CYCLES` (CPU), `BLENDER_WORKBENCH`, and `BLENDER_EEVEE` (or `BLENDER_EEVEE_NEXT` in 4.2–4.5) via Mesa software rendering.
- If `LD_LIBRARY_PATH` in a container conflicts with Blender's bundled libraries, invoke `/opt/blender/blender-launcher`.

### Godot

Run Godot headlessly without a display server using `--headless`:

```bash
godot --headless --path . --import      # import project resources and exit
godot --headless --path . --quit        # run main scene once and exit
godot --headless --editor --path . --lsp-port 6008  # run GDScript LSP
```

For `.NET` projects (`godotVariant: "dotnet"`), build C# solutions before running scenes:

```bash
godot --headless --path . --build-solutions --quit
```

## Platform & Footprint Notes

- **Supported OS families**: Debian, Ubuntu, and Fedora/RHEL-compatible glibc distributions. Alpine and other musl-based images are unsupported.
- **Architectures**: Godot supports `x86_64` and `aarch64`. Blender only publishes Linux `x86_64` builds; on `aarch64`, set `"installBlender": false`.
- **Image size**: Blender plus its Mesa/X11/EGL runtime dependencies adds roughly 1.4 GiB to the built container image.
