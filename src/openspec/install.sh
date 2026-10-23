#!/usr/bin/env bash
# Installs the OpenSpec CLI (@fission-ai/openspec) globally using the Node.js runtime.
set -euo pipefail

VERSION="${VERSION:-latest}"
VERSION="${VERSION#v}"

log() { echo "openspec feature: $*"; }
fail() { echo "openspec feature: error: $*" >&2; exit 1; }

# Validate requested version option
if [[ "${VERSION}" != "latest" ]]; then
    if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
        fail "version '${VERSION}' is invalid; must be 'latest' or a semantic version such as 1.14.1."
    fi
fi

# Locate Node.js and npm from the environment or default Feature locations
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    if [[ -x "/usr/local/share/nvm/current/bin/node" && -x "/usr/local/share/nvm/current/bin/npm" ]]; then
        export PATH="/usr/local/share/nvm/current/bin:${PATH}"
    elif [[ -s "/usr/local/share/nvm/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        . "/usr/local/share/nvm/nvm.sh"
    fi
fi

NODE_BIN="$(command -v node || true)"
NPM_BIN="$(command -v npm || true)"

if [[ -z "${NODE_BIN}" || ! -x "${NODE_BIN}" ]]; then
    fail "Node.js executable not found. Ensure ghcr.io/devcontainers/features/node:1 is installed."
fi
if [[ -z "${NPM_BIN}" || ! -x "${NPM_BIN}" ]]; then
    fail "npm executable not found. Ensure ghcr.io/devcontainers/features/node:1 is installed."
fi

# OpenSpec requires Node.js 20.19.0 or newer
log "Checking Node.js version (${NODE_BIN})..."
# shellcheck disable=SC2016 # JavaScript template literal, expanded by Node.js.
"${NODE_BIN}" -e '
const [major, minor] = process.versions.node.split(".").map(Number);
if (major < 20 || (major === 20 && minor < 19)) {
    console.error(`Node.js 20.19.0 or newer is required (found ${process.version}).`);
    process.exit(1);
}
' || fail "Node.js version does not satisfy OpenSpec requirement (>= 20.19.0)."

# Install @fission-ai/openspec
if [[ "${VERSION}" == "latest" ]]; then
    PACKAGE="@fission-ai/openspec@latest"
else
    PACKAGE="@fission-ai/openspec@${VERSION}"
fi

log "Installing ${PACKAGE} via npm..."
"${NPM_BIN}" install -g "${PACKAGE}"

# Clean up npm cache to reduce container layer size
"${NPM_BIN}" cache clean --force 2>/dev/null || true

# Locate the installed openspec executable
NPM_PREFIX="$("${NPM_BIN}" prefix -g)"
INSTALLED_BIN="${NPM_PREFIX}/bin/openspec"
if [[ ! -x "${INSTALLED_BIN}" ]]; then
    INSTALLED_BIN="$(command -v openspec || true)"
fi

if [[ -z "${INSTALLED_BIN}" || ! -x "${INSTALLED_BIN}" ]]; then
    fail "failed to locate installed openspec executable."
fi

# Ensure openspec is on PATH for every user in the container
mkdir -p /usr/local/bin
if [[ "${INSTALLED_BIN}" != "/usr/local/bin/openspec" ]]; then
    ln -sfn "${INSTALLED_BIN}" /usr/local/bin/openspec
fi
chmod 0755 /usr/local/bin/openspec

# Ensure node executable is also reachable via /usr/local/bin if not already present
if [[ ! -e "/usr/local/bin/node" && -x "${NODE_BIN}" ]]; then
    ln -sfn "${NODE_BIN}" /usr/local/bin/node
fi

# Ensure profile.d entry for login shells
mkdir -p /etc/profile.d
cat > /etc/profile.d/openspec.sh <<'EOF'
case ":${PATH}:" in
    *:/usr/local/bin:*) ;;
    *) export PATH="/usr/local/bin:${PATH}" ;;
esac
EOF
chmod 0644 /etc/profile.d/openspec.sh

# Verify the CLI execution
log "Verifying openspec installation..."
INSTALLED_VERSION="$(/usr/local/bin/openspec --version)"
log "Successfully installed OpenSpec ${INSTALLED_VERSION}."
