#!/bin/bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "uv dependency installed" uv --version
check "colab version" colab version
check "colab help" colab --help
check "colab version in login shell" bash -lc 'colab version'
check "colab explicit --auth=oauth2 version" colab --auth=oauth2 version
check "colab-adc help" colab-adc --help

# shellcheck disable=SC2016
check "colab-adc path points to project volume" bash -lc '
    set -euo pipefail
    [ "$(colab-adc path)" = "/var/lib/colab/adc/application_default_credentials.json" ]
'

# shellcheck disable=SC2016
check "colab-adc login --print-url-only outputs Google auth URL" bash -lc '
    set -euo pipefail
    url="$(colab-adc login --print-url-only)"
    [[ "${url}" == https://accounts.google.com/* ]]
    [[ "${url}" == *colaboratory* ]]
    [[ "${url}" == *applicationdefaultauthcode.html* ]]
'

# shellcheck disable=SC2016
check "colab wrapper isolates Python from PYTHONPATH poisoning" bash -lc '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    trap '\''rm -rf "${tmp_dir}"'\'' EXIT
    printf "raise RuntimeError(\"poisoned\")\n" > "${tmp_dir}/typer.py"
    printf "raise RuntimeError(\"poisoned\")\n" > "${tmp_dir}/colab_cli.py"
    PYTHONPATH="${tmp_dir}" colab version >/dev/null
'

# shellcheck disable=SC2016
check "colab-adc rejects incompatible --use-gcloud --print-url-only" bash -lc '
    set -euo pipefail
    if colab-adc login --use-gcloud --print-url-only >/dev/null 2>&1; then
        echo "expected --use-gcloud --print-url-only to fail" >&2
        exit 1
    fi
'

# shellcheck disable=SC2016
check "state volume mounted with private mode" bash -lc '
    set -euo pipefail
    mountpoint -q /var/lib/colab
    [ "$(stat -c "%u:%a" /var/lib/colab)" = "$(id -u):700" ]
    [ "$(stat -c "%u:%a" /var/lib/colab/adc)" = "$(id -u):700" ]
    [ "$(stat -c "%u:%a" /var/lib/colab/config)" = "$(id -u):700" ]
'

# shellcheck disable=SC2016
check "colab-cli config symlink resolves into /var/lib/colab/config and persists writes" bash -lc '
    set -euo pipefail
    [ "$(readlink -f "$HOME/.config/colab-cli")" = "/var/lib/colab/config" ]
    printf "{\"ok\":true}\n" > "$HOME/.config/colab-cli/test-state.json"
    grep -q "\"ok\":true" /var/lib/colab/config/test-state.json
    rm -f "$HOME/.config/colab-cli/test-state.json"
'

# shellcheck disable=SC2016
check "synthetic ADC lifecycle via colab-adc import/status/logout" bash -lc '
    set -euo pipefail
    if colab-adc status >/dev/null 2>&1; then
        echo "expected colab-adc status to fail when no ADC exists" >&2
        exit 1
    fi

    tmp_dir="$(mktemp -d)"
    trap '\''rm -rf "${tmp_dir}"'\'' EXIT
    fixture="${tmp_dir}/adc.json"
    placeholder_secret="synthetic-test-placeholder-value"
    placeholder_token="synthetic-test-refresh-token"
    cat > "${fixture}" <<EOF
{
  "account": "",
  "client_id": "synthetic-test-client-id",
  "client_secret": "${placeholder_secret}",
  "refresh_token": "${placeholder_token}",
  "type": "authorized_user",
  "universe_domain": "googleapis.com"
}
EOF

    colab-adc import "${fixture}"
    adc_path="$(colab-adc path)"
    [ -f "${adc_path}" ]
    [ "$(stat -c "%a" "${adc_path}")" = "600" ]

    # Overwrite without --force must fail; with --force via stdin must succeed.
    if colab-adc import - < "${fixture}" >/dev/null 2>&1; then
        echo "expected import without --force to fail when ADC already exists" >&2
        exit 1
    fi
    colab-adc import --force - < "${fixture}"

    # Invalid JSON and unsupported type must fail without overwriting valid ADC.
    printf "{bad json\n" > "${tmp_dir}/bad.json"
    if colab-adc import --force "${tmp_dir}/bad.json" >/dev/null 2>&1; then
        echo "expected invalid JSON import to fail" >&2
        exit 1
    fi
    printf "{\"type\":\"unknown_type\"}\n" > "${tmp_dir}/badtype.json"
    if colab-adc import --force "${tmp_dir}/badtype.json" >/dev/null 2>&1; then
        echo "expected unsupported ADC type import to fail" >&2
        exit 1
    fi

    status_out="$(colab-adc status)"
    [[ "${status_out}" == *"authorized_user"* ]]
    [[ "${status_out}" != *"${placeholder_secret}"* ]]
    [[ "${status_out}" != *"${placeholder_token}"* ]]

    status_json="$(colab-adc status --json)"
    [[ "${status_json}" == *"\"valid\": true"* ]]
    [[ "${status_json}" == *"\"overridden_by_env\": false"* ]]
    [[ "${status_json}" != *"${placeholder_secret}"* ]]
    [[ "${status_json}" != *"${placeholder_token}"* ]]

    # Override via GOOGLE_APPLICATION_CREDENTIALS must be reflected by status.
    cp "${fixture}" "${tmp_dir}/override.json"
    override_json="$(GOOGLE_APPLICATION_CREDENTIALS="${tmp_dir}/override.json" colab-adc status --json)"
    [[ "${override_json}" == *"\"overridden_by_env\": true"* ]]
    [[ "${override_json}" == *"${tmp_dir}/override.json"* ]]

    colab-adc logout
    [ ! -e "${adc_path}" ]
    if colab-adc status >/dev/null 2>&1; then
        echo "expected colab-adc status to fail after logout" >&2
        exit 1
    fi

    # Broken symlink at project ADC path must be reported as invalid, not missing.
    ln -s "${tmp_dir}/does-not-exist.json" "${adc_path}"
    if broken_out="$(colab-adc status 2>&1)"; then
        rm -f "${adc_path}"
        echo "expected colab-adc status to fail on broken symlink" >&2
        exit 1
    fi
    rm -f "${adc_path}"
    [[ "${broken_out}" == *"invalid"* && "${broken_out}" == *"symlink"* ]]
'

# shellcheck disable=SC2016
check "rclone installed with completions and local copy works" bash -lc '
    set -euo pipefail
    [ "$(command -v rclone)" = "/usr/local/bin/rclone" ]
    [ "$(stat -c "%a %U" /usr/local/bin/rclone)" = "755 root" ]
    rclone version
    [ -s /usr/local/share/bash-completion/completions/rclone ]
    [ -s /usr/local/share/zsh/site-functions/_rclone ]
    [ -s /usr/share/fish/vendor_completions.d/rclone.fish ]
    if command -v fusermount3 >/dev/null 2>&1; then
        echo "expected fusermount3 to be absent" >&2
        exit 1
    fi
    work="$(mktemp -d)"
    trap '\''rm -rf "${work}"'\'' EXIT
    mkdir -p "${work}/src" "${work}/dst" "${work}/home"
    printf "colab-rclone-test\n" > "${work}/src/hello.txt"
    HOME="${work}/home" XDG_CONFIG_HOME="${work}/home/.config" RCLONE_CONFIG="${work}/home/rclone.conf" \
        rclone copy "${work}/src" "${work}/dst"
    cmp -s "${work}/src/hello.txt" "${work}/dst/hello.txt"
'

# shellcheck disable=SC2016
check "initialize is idempotent, repairs modes/ownership, and rejects conflicts and state symlinks" bash -lc '
    set -euo pipefail
    init_bin="/usr/local/share/colab-feature/initialize"
    "${init_bin}"

    chmod 0755 /var/lib/colab/adc
    "${init_bin}"
    [ "$(stat -c "%a" /var/lib/colab/adc)" = "700" ]

    work="$(mktemp -d)"
    trap '\''rm -rf "${work}"'\'' EXIT

    mkdir -p "${work}/conflict-home/.config/colab-cli"
    printf "keep-me\n" > "${work}/conflict-home/.config/colab-cli/user.txt"
    if HOME="${work}/conflict-home" "${init_bin}" >/dev/null 2>&1; then
        echo "expected initialize to fail on conflicting directory" >&2
        exit 1
    fi
    grep -qxF "keep-me" "${work}/conflict-home/.config/colab-cli/user.txt"

    mkdir -p "${work}/outside"
    printf "external\n" > "${work}/outside/secret.json"
    chmod 0644 "${work}/outside/secret.json"
    ln -s "${work}/outside/secret.json" /var/lib/colab/adc/application_default_credentials.json
    if "${init_bin}" >/dev/null 2>&1; then
        rm -f /var/lib/colab/adc/application_default_credentials.json
        echo "expected initialize to reject symlink inside /var/lib/colab" >&2
        exit 1
    fi
    rm -f /var/lib/colab/adc/application_default_credentials.json
    [ "$(stat -c "%a" "${work}/outside/secret.json")" = "644" ]

    if [ "$(id -u)" = "0" ] || sudo -n true >/dev/null 2>&1; then
        before_ext="$(stat -c "%u:%g:%a" "${work}/outside/secret.json")"
        ln -s "${work}/outside/secret.json" /var/lib/colab/config/ext-link
        if [ "$(id -u)" = "0" ]; then
            chown -R -h 23456:23456 /var/lib/colab
        else
            sudo -n chown -R -h 23456:23456 /var/lib/colab
        fi
        "${init_bin}"
        rm -f /var/lib/colab/config/ext-link
        [ "$(stat -c "%u:%a" /var/lib/colab)" = "$(id -u):700" ]
        [ "$(stat -c "%u:%a" /var/lib/colab/adc)" = "$(id -u):700" ]
        [ "$(stat -c "%u:%a" /var/lib/colab/config)" = "$(id -u):700" ]
        [ "$(stat -c "%u:%g:%a" "${work}/outside/secret.json")" = "${before_ext}" ]
    fi
'

reportResults
