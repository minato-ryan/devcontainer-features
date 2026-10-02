#!/usr/bin/env bash
# Installs the NVIDIA Container Toolkit from NVIDIA's stable package repository, trusting only NVIDIA's
# signing key pinned by its full fingerprint, and registers the nvidia runtime with a Docker daemon
# installed in the image. Runs as root at image build time; options arrive as VERSION, CONFIGUREDOCKER,
# and SETASDEFAULT. Idempotent: a second run rewrites the files it owns and moves all four packages to
# the version it was asked for.
set -euo pipefail

# Unset means the default; an empty value is invalid like any other value that is not latest or X.Y.Z.
VERSION="${VERSION-latest}"
CONFIGUREDOCKER="${CONFIGUREDOCKER:-true}"
SETASDEFAULT="${SETASDEFAULT:-false}"

readonly KEY_URL="https://nvidia.github.io/libnvidia-container/gpgkey"
readonly NVIDIA_FINGERPRINT="C95B321B61E88C1809C4F759DDCAE044F796ECB0"
readonly REPO_BASE="https://nvidia.github.io/libnvidia-container/stable"
readonly APT_KEYRING="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
readonly APT_SOURCE="/etc/apt/sources.list.d/nvidia-container-toolkit.list"
readonly DAEMON_JSON="/etc/docker/daemon.json"
readonly PACKAGES=(
  nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
)

export DEBIAN_FRONTEND=noninteractive

fail() {
  echo "(!) docker-in-docker-nvidia: $*" >&2
  exit 1
}

log() {
  echo "docker-in-docker-nvidia: $*"
}

# --- Validation. Nothing changes the image until the version, distribution, and architecture pass.

if [[ "$VERSION" != "latest" && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "invalid version $(printf '%q' "$VERSION"): use 'latest' or an exact MAJOR.MINOR.PATCH release such as 1.19.1."
fi

[[ -r /etc/os-release ]] || fail "cannot read /etc/os-release to detect the distribution."
# shellcheck source=/dev/null
OS_ID="$(. /etc/os-release && echo "${ID:-}")"
# shellcheck source=/dev/null
OS_ID_LIKE="$(. /etc/os-release && echo "${ID_LIKE:-}")"

IS_APT=""
read -ra os_words <<<"$OS_ID $OS_ID_LIKE"
for word in "${os_words[@]}"; do
  case "$word" in
    debian | ubuntu) IS_APT="true" ;;
    *) continue ;;
  esac
  break
done

if [[ "$IS_APT" != "true" ]] || ! command -v apt-get >/dev/null 2>&1; then
  fail "unsupported distribution '${OS_ID:-unknown}' (ID_LIKE '${OS_ID_LIKE:-}'): this feature requires a Debian- or Ubuntu-based distribution with apt."
fi

ARCH="$(dpkg --print-architecture 2>/dev/null)" || fail "cannot detect the architecture with dpkg --print-architecture."
case "$ARCH" in
  amd64 | arm64) ;;
  *) fail "unsupported architecture '$ARCH' on '$OS_ID': the feature supports amd64 and arm64." ;;
esac

log "installing version '$VERSION' on '$OS_ID' ($ARCH)."

# --- Prerequisites, from the image's own repositories and only when missing.

GPG=""
find_gpg() {
  GPG="$(command -v gpg || command -v gpg2 || true)"
}

install_prerequisites() {
  local missing=()
  find_gpg
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  dpkg -s ca-certificates >/dev/null 2>&1 || missing+=(ca-certificates)
  [[ -n "$GPG" ]] || missing+=(gnupg)

  if ((${#missing[@]} == 0)); then
    return
  fi
  log "installing prerequisites: ${missing[*]}."
  apt-get update
  apt-get install -y --no-install-recommends "${missing[@]}"
  find_gpg
  [[ -n "$GPG" ]] || fail "gpg is still missing after installing the prerequisites."
}

# --- Signing key: exactly one primary key with the pinned fingerprint, checked in a temporary GNUPGHOME.

GNUPG_TMP=""
cleanup() {
  if [[ -n "$GNUPG_TMP" && -d "$GNUPG_TMP" ]]; then
    if command -v gpgconf >/dev/null 2>&1; then
      GNUPGHOME="$GNUPG_TMP" gpgconf --kill all >/dev/null 2>&1 || true
    fi
    rm -rf "$GNUPG_TMP"
  fi
}
trap cleanup EXIT

install_key() {
  local key_file records primaries first kind fingerprint exported
  GNUPG_TMP="$(mktemp -d /tmp/nvidia-container-toolkit-gnupg.XXXXXXXXXX)"
  export GNUPGHOME="$GNUPG_TMP"
  key_file="$GNUPG_TMP/gpgkey"
  exported="$GNUPG_TMP/exported"

  curl --proto '=https' -fsSL "$KEY_URL" -o "$key_file" \
    || fail "could not download NVIDIA's signing key from $KEY_URL (expected fingerprint $NVIDIA_FINGERPRINT)."
  records="$("$GPG" --batch --show-keys --with-colons "$key_file" 2>/dev/null)" \
    || fail "the file at $KEY_URL holds no readable OpenPGP key (expected fingerprint $NVIDIA_FINGERPRINT)."
  primaries="$(grep -cE '^(pub|sec):' <<<"$records" || true)"
  first="$(
    awk -F: '$1 == "pub" || $1 == "sec" { kind = $1; next } kind && $1 == "fpr" { print kind, $10; exit }' \
      <<<"$records"
  )"
  kind="${first%% *}"
  fingerprint="${first#* }"
  if [[ "$primaries" != "1" || "$kind" != "pub" || "$fingerprint" != "$NVIDIA_FINGERPRINT" ]]; then
    fail "the key at $KEY_URL is not NVIDIA's pinned signing key: expected exactly one primary key, a public key with fingerprint $NVIDIA_FINGERPRINT, found $primaries primary key(s), the first (${kind:-none}) with fingerprint '${fingerprint:-none}'."
  fi

  "$GPG" --batch --quiet --import "$key_file"
  "$GPG" --batch --export "$NVIDIA_FINGERPRINT" >"$exported"
  [[ -s "$exported" ]] || fail "exporting key $NVIDIA_FINGERPRINT produced nothing."
  mkdir -p "$(dirname "$APT_KEYRING")"
  install -m 0644 "$exported" "$APT_KEYRING"

  cleanup
  GNUPG_TMP=""
  unset GNUPGHOME
  log "verified NVIDIA's signing key $NVIDIA_FINGERPRINT."
}

# --- Repository: one source definition, written whole at a fixed path.

write_repository() {
  mkdir -p "$(dirname "$APT_SOURCE")"
  printf 'deb [signed-by=%s] %s/deb/%s /\n' "$APT_KEYRING" "$REPO_BASE" "$ARCH" >"$APT_SOURCE"
}

# --- Packages: all four together, pinned to <version>-1 for an exact version.

install_packages() {
  local specs=("${PACKAGES[@]}") failed=""
  if [[ "$VERSION" != "latest" ]]; then
    specs=("${PACKAGES[@]/%/=$VERSION-1}")
  fi
  apt-get update
  apt-get install -y --no-install-recommends --allow-downgrades "${specs[@]}" || failed=1
  if [[ -n "$failed" ]]; then
    fail "could not install NVIDIA Container Toolkit version '$VERSION' from NVIDIA's stable repository; check that the repository offers this version for $ARCH."
  fi
}

installed_version() {
  # shellcheck disable=SC2016 # ${Version} is a dpkg-query field, not a shell variable
  dpkg-query -W -f='${Version}' "$1"
}

verify_versions() {
  local expected="" first="" package version
  if [[ "$VERSION" != "latest" ]]; then
    expected="$VERSION-1"
  fi
  for package in "${PACKAGES[@]}"; do
    version="$(installed_version "$package" 2>/dev/null)" \
      || fail "$package is not installed after installing NVIDIA Container Toolkit version '$VERSION'."
    if [[ -z "$first" ]]; then
      first="$version"
    fi
    if [[ "$version" != "$first" || (-n "$expected" && "$version" != "$expected") ]]; then
      fail "requested NVIDIA Container Toolkit version '$VERSION', but $package is at $version (${PACKAGES[0]} at $first)."
    fi
  done
  log "installed ${PACKAGES[*]} at $first."
}

# --- Docker: register the nvidia runtime only where a Docker daemon is installed.

configure_docker() {
  if [[ "$CONFIGUREDOCKER" != "true" ]]; then
    log "configureDocker is disabled: $DAEMON_JSON is left unchanged."
    return
  fi
  # sbin directories too: distribution packages install dockerd there, and a build PATH may omit them.
  if ! PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin" command -v dockerd >/dev/null 2>&1; then
    log "no Docker daemon (dockerd) is installed: skipped the Docker configuration."
    return
  fi

  mkdir -p "$(dirname "$DAEMON_JSON")"
  # nvidia-ctk fails on a zero-length file; treat it as an empty object.
  if [[ -f "$DAEMON_JSON" && ! -s "$DAEMON_JSON" ]]; then
    printf '{}\n' >"$DAEMON_JSON"
  fi

  local extra_flags=()
  if [[ "$SETASDEFAULT" == "true" ]]; then
    extra_flags+=(--set-as-default)
  fi

  # nvidia-ctk keys the runtime by name, keeps every other setting, and leaves an invalid file unwritten.
  nvidia-ctk runtime configure --runtime=docker "${extra_flags[@]}" \
    || fail "could not register the nvidia runtime in $DAEMON_JSON; check that the file holds valid JSON."
  log "registered the nvidia runtime in $DAEMON_JSON (setAsDefault: $SETASDEFAULT)."
}

clean_caches() {
  apt-get clean
  rm -rf /var/lib/apt/lists/*
}

install_prerequisites
install_key
write_repository
install_packages
verify_versions
configure_docker
clean_caches
log "done."
