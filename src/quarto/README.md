
# Quarto (quarto)

Installs the Quarto CLI from its checksum-verified official release tarball and records an install receipt.

## Example Usage

```json
"features": {
    "ghcr.io/minato-ryan/devcontainer-features/quarto:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Select or enter a stable Quarto version (e.g. 'latest' or '1.10.19'). | string | latest |
| checksumsSha256 | Optional SHA-256 of the release's quarto-<version>-checksums.txt. Pins every asset of that release independently of GitHub; requires an exact version. | string | - |

## Customizations

### VS Code Extensions

- `quarto.quarto`

## Installation

Installs the official Quarto Linux tarball under `/opt/quarto` and links
`/usr/local/bin/quarto` to `/opt/quarto/bin/quarto`. The tree belongs to root
and is not writable by group or others. The Feature also requests the
`quarto.quarto` VS Code extension. Python/Jupyter, R, LaTeX, and browsers are
not installed.

Supported images: Debian, Ubuntu, and Fedora families on amd64 and arm64 with
glibc. Missing `curl`, `tar`, `gzip`, or CA certificates come from the image's
own package repositories.

## Audit model

`install.sh` runs six logged steps in order: validate options, check the
platform, install prerequisites, resolve the version, download and verify, then
stage, self-test, and activate. It contacts only
`github.com/quarto-dev/quarto-cli` (and the download host that GitHub redirects
to), runs no upstream script, and parses no JSON.

| Step | Network request | Accepted only if |
| --- | --- | --- |
| Resolve `latest` | `HEAD /releases/latest`, redirect not followed | Redirect target is `/releases/tag/vMAJOR.MINOR.PATCH` |
| Checksum list | `quarto-<version>-checksums.txt` | Download succeeds; matches `checksumsSha256` when set |
| Archive | `quarto-<version>-linux-<arch>.tar.gz` | SHA-256 equals the list's single entry for that file |
| Self-test | none | Staged `bin/quarto --version` prints the requested version |

Without `checksumsSha256`, the checksum list is trusted on HTTPS alone, because
Quarto does not sign its releases. Setting `checksumsSha256` to the SHA-256 of
`quarto-<version>-checksums.txt` pins every asset of that release, for every
architecture, independently of GitHub:

```bash
curl -fsSL https://github.com/quarto-dev/quarto-cli/releases/download/v1.9.38/quarto-1.9.38-checksums.txt | sha256sum
```

```json
"features": {
    "ghcr.io/minato-ryan/devcontainer-features/quarto:1": {
        "version": "1.9.38",
        "checksumsSha256": "a936197982c2e5df434d9a10117df232650c48bdcd82320e61d085c36c60c2b7"
    }
}
```

## Install receipt

`/opt/quarto/.devcontainer-feature-quarto` records what was verified. It has no
timestamp, so identical inputs produce an identical file:

```text
version=1.9.38
platform=linux-amd64
archive_url=https://github.com/quarto-dev/quarto-cli/releases/download/v1.9.38/quarto-1.9.38-linux-amd64.tar.gz
archive_sha256=<hex>
checksums_url=https://github.com/quarto-dev/quarto-cli/releases/download/v1.9.38/quarto-1.9.38-checksums.txt
checksums_sha256=<hex>
checksums_pinned=yes
```

To re-check an image, compare `checksums_sha256` against a fresh download of
`checksums_url`, and `archive_sha256` against that list.

## Reinstallation and existing installations

A rerun whose newly built receipt equals the installed one keeps the existing
tree. Otherwise the new release is staged next to `/opt/quarto`, self-tested,
and swapped in by rename; a failure before the swap leaves the previous tree in
place. The Feature refuses to replace an `/opt/quarto` without its receipt, or a
`/usr/local/bin/quarto` that is not its own symlink. It does not search the
rest of `PATH` for other Quarto commands.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/minato-ryan/devcontainer-features/blob/main/src/quarto/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
