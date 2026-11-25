#!/usr/bin/env python3
"""Manage project-scoped Google Application Default Credentials (ADC) for Colab CLI."""

from __future__ import annotations

import argparse
from importlib import resources
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import warnings

import google.auth
from google.auth.credentials import with_scopes_if_required
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
import requests

STATE_DIR = Path("/var/lib/colab")
ADC_DIR = STATE_DIR / "adc"
DEFAULT_ADC_PATH = ADC_DIR / "application_default_credentials.json"
MAX_ADC_BYTES = 1024 * 1024

FALLBACK_PUBLIC_SCOPES = [
    "openid",
    "https://www.googleapis.com/auth/userinfo.profile",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/colaboratory",
    "https://www.googleapis.com/auth/drive.file",
]
FALLBACK_REMOTE_REDIRECT_URI = "https://sdk.cloud.google.com/applicationdefaultauthcode.html"

SUPPORTED_ADC_TYPES = {
    "authorized_user",
    "service_account",
    "external_account",
    "external_account_authorized_user",
    "impersonated_service_account",
    "gdch_service_account",
}


def load_colab_auth_defaults() -> tuple[list[str], str]:
    """Load default Colab OAuth scopes and remote redirect URI from colab_cli."""
    try:
        from colab_cli import auth as colab_auth

        scopes = list(getattr(colab_auth, "PUBLIC_SCOPES", FALLBACK_PUBLIC_SCOPES))
        redirect_uri = str(
            getattr(colab_auth, "REMOTE_REDIRECT_URI", FALLBACK_REMOTE_REDIRECT_URI)
        )
        return scopes, redirect_uri
    except Exception:
        return list(FALLBACK_PUBLIC_SCOPES), FALLBACK_REMOTE_REDIRECT_URI


def load_client_config(config_path: str | None) -> dict:
    """Load OAuth client configuration from an explicit path or colab_cli resources."""
    if config_path:
        path = Path(config_path).expanduser()
        if not path.is_file():
            raise SystemExit(f"colab-adc: error: OAuth client config not found: {path}")
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise SystemExit(
                f"colab-adc: error: failed to parse OAuth client config '{path}': {exc}"
            ) from exc
        if not isinstance(data, dict):
            raise SystemExit(
                f"colab-adc: error: OAuth client config '{path}' must be a JSON object."
            )
        return data

    try:
        resource = resources.files("colab_cli").joinpath("oauth_config.json")
        if resource.is_file():
            data = json.loads(resource.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
    except Exception as exc:
        raise SystemExit(
            f"colab-adc: error: failed to load bundled OAuth client config from colab_cli: {exc}"
        ) from exc

    raise SystemExit(
        "colab-adc: error: no OAuth client config available; pass --client-oauth-config."
    )


def extract_client_identity(client_config: dict) -> tuple[str, str]:
    """Extract client_id and client_secret from an installed/web OAuth config dict."""
    section = client_config.get("installed") or client_config.get("web") or client_config
    if not isinstance(section, dict):
        raise SystemExit("colab-adc: error: invalid OAuth client config structure.")
    client_id = section.get("client_id")
    client_secret = section.get("client_secret") or ""
    if not isinstance(client_id, str) or not client_id:
        raise SystemExit(
            "colab-adc: error: OAuth client config is missing 'client_id'."
        )
    if not isinstance(client_secret, str):
        raise SystemExit(
            "colab-adc: error: OAuth client config has invalid 'client_secret'."
        )
    return client_id, client_secret


def warn_if_unmounted(target: Path) -> None:
    """Warn if target sits under STATE_DIR when STATE_DIR is not a mounted volume."""
    try:
        resolved_parent = target.parent.resolve()
        if (
            resolved_parent == STATE_DIR
            or STATE_DIR in resolved_parent.parents
        ) and not os.path.ismount(STATE_DIR):
            print(
                f"colab-adc: warning: {STATE_DIR} is not a mounted volume; "
                "credentials will not persist across container rebuilds.",
                file=sys.stderr,
            )
    except OSError:
        pass


def ensure_writable_target_dir(target: Path) -> None:
    """Ensure the ADC target path and its parent directory are safe to write."""
    if STATE_DIR.is_symlink():
        raise SystemExit(
            f"colab-adc: error: {STATE_DIR} is a symlink; remove or resolve it manually."
        )
    if target.is_symlink():
        raise SystemExit(
            f"colab-adc: error: {target} is a symlink; remove or resolve it manually."
        )
    if target.exists() and target.is_dir():
        raise SystemExit(
            f"colab-adc: error: {target} is a directory; resolve it manually."
        )
    parent = target.parent
    if parent.is_symlink():
        raise SystemExit(
            f"colab-adc: error: {parent} is a symlink; remove or resolve it manually."
        )
    if not parent.exists():
        try:
            parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        except OSError as exc:
            raise SystemExit(
                f"colab-adc: error: cannot create directory '{parent}': {exc}"
            ) from exc
    if not parent.is_dir():
        raise SystemExit(f"colab-adc: error: '{parent}' is not a directory.")
    warn_if_unmounted(target)


def validate_adc_file(path: Path) -> tuple[dict, object]:
    """Parse and validate an ADC JSON file using google-auth."""
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ValueError(f"cannot read '{path}': {exc}") from exc

    try:
        data = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON in '{path}': {exc}") from exc

    if not isinstance(data, dict):
        raise ValueError(f"ADC file '{path}' must contain a JSON object")

    cred_type = data.get("type")
    if cred_type not in SUPPORTED_ADC_TYPES:
        raise ValueError(
            f"unsupported ADC credential type {cred_type!r} in '{path}'"
        )

    with warnings.catch_warnings():
        warnings.filterwarnings(
            "ignore",
            message=r"Your application has authenticated using end user credentials.*",
            category=UserWarning,
        )
        creds, _ = google.auth.load_credentials_from_file(str(path))
    return data, creds


def write_adc_atomic(target: Path, payload: bytes, *, validate: bool = True) -> dict | None:
    """Validate (optional) and atomically write ADC JSON with owner-only 0600 permissions."""
    if len(payload) > MAX_ADC_BYTES:
        raise SystemExit(
            f"colab-adc: error: ADC payload exceeds maximum size ({MAX_ADC_BYTES} bytes)."
        )
    ensure_writable_target_dir(target)
    try:
        fd, tmp_name = tempfile.mkstemp(
            prefix=".adc-", suffix=".tmp", dir=str(target.parent)
        )
    except OSError as exc:
        raise SystemExit(
            f"colab-adc: error: cannot create temporary ADC file in '{target.parent}': {exc}"
        ) from exc

    tmp_path = Path(tmp_name)
    data: dict | None = None
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        if validate:
            try:
                data, _ = validate_adc_file(tmp_path)
            except Exception as exc:
                raise SystemExit(
                    f"colab-adc: error: invalid ADC credentials: {exc}"
                ) from exc
        os.chmod(tmp_path, 0o600)
        try:
            os.replace(tmp_path, target)
        except OSError as exc:
            raise SystemExit(
                f"colab-adc: error: failed to write ADC file '{target}': {exc}"
            ) from exc
    except BaseException:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    return data


def confirm_overwrite(target: Path, force: bool) -> None:
    """Prevent accidental overwrite of an existing ADC file unless forced or confirmed."""
    if target.is_symlink():
        raise SystemExit(
            f"colab-adc: error: {target} is a symlink; resolve it manually."
        )
    if target.exists() and target.is_dir():
        raise SystemExit(
            f"colab-adc: error: {target} is a directory; resolve it manually."
        )
    if not target.exists():
        return
    if force:
        return
    if sys.stdin.isatty() and sys.stdout.isatty():
        try:
            answer = input(f"Overwrite existing ADC file at {target}? [y/N]: ").strip().lower()
        except (EOFError, KeyboardInterrupt) as exc:
            raise SystemExit("\ncolab-adc: aborted; existing ADC preserved.") from exc
        if answer in {"y", "yes"}:
            return
        raise SystemExit("colab-adc: aborted; existing ADC preserved.")
    raise SystemExit(
        f"colab-adc: error: {target} already exists; rerun with --force to overwrite."
    )


def parse_scopes(raw_scopes: str | None, default_scopes: list[str]) -> list[str]:
    """Parse comma-separated OAuth scopes or fall back to Colab defaults."""
    if not raw_scopes:
        return list(default_scopes)
    scopes = [item.strip() for item in raw_scopes.split(",") if item.strip()]
    if not scopes:
        raise SystemExit("colab-adc: error: --scopes must not be empty.")
    return scopes


def build_oauth_flow(client_config: dict, scopes: list[str], redirect_uri: str) -> InstalledAppFlow:
    """Construct InstalledAppFlow with consistent error handling."""
    try:
        flow = InstalledAppFlow.from_client_config(client_config, scopes)
    except Exception as exc:
        raise SystemExit(
            f"colab-adc: error: invalid OAuth client config ({type(exc).__name__}): {exc}"
        ) from exc
    flow.redirect_uri = redirect_uri
    return flow


def cmd_login(args: argparse.Namespace) -> int:
    """Create and persist project-scoped ADC credentials."""
    default_scopes, redirect_uri = load_colab_auth_defaults()
    scopes = parse_scopes(args.scopes, default_scopes)

    if args.use_gcloud and args.print_url_only:
        raise SystemExit(
            "colab-adc: error: --print-url-only cannot be combined with --use-gcloud."
        )

    if args.print_url_only:
        client_config = load_client_config(args.client_oauth_config)
        flow = build_oauth_flow(client_config, scopes, redirect_uri)
        auth_url, _ = flow.authorization_url(
            prompt="consent",
            token_usage="remote",
            access_type="offline",
        )
        print(auth_url)
        return 0

    if args.use_gcloud:
        gcloud_bin = shutil.which("gcloud")
        if not gcloud_bin:
            raise SystemExit(
                "colab-adc: error: --use-gcloud requested, but 'gcloud' is not installed on PATH."
            )
        if args.client_oauth_config:
            load_client_config(args.client_oauth_config)
        confirm_overwrite(DEFAULT_ADC_PATH, args.force)
        return login_with_gcloud(
            gcloud_bin=gcloud_bin,
            scopes=scopes,
            quota_project=args.quota_project,
            client_oauth_config=args.client_oauth_config,
        )

    client_config = load_client_config(args.client_oauth_config)
    client_id, client_secret = extract_client_identity(client_config)
    flow = build_oauth_flow(client_config, scopes, redirect_uri)

    confirm_overwrite(DEFAULT_ADC_PATH, args.force)

    auth_url, _ = flow.authorization_url(
        prompt="consent",
        token_usage="remote",
        access_type="offline",
    )

    print("Open the following URL in your browser to authorize Google Colab ADC:\n", file=sys.stderr)
    print(f"  {auth_url}\n", file=sys.stderr)
    print(
        "After signing in and approving access, paste the authorization code below.",
        file=sys.stderr,
    )
    try:
        code = input("Enter authorization code: ").strip()
    except (EOFError, KeyboardInterrupt) as exc:
        raise SystemExit(
            "colab-adc: error: no authorization code received on stdin."
        ) from exc

    if not code:
        raise SystemExit("colab-adc: error: authorization code cannot be empty.")

    flow.oauth2session.scope = None
    try:
        token = flow.fetch_token(code=code)
    except Exception as exc:
        raise SystemExit(
            f"colab-adc: error: failed to exchange authorization code ({type(exc).__name__})."
        ) from exc
    flow.oauth2session.scope = token.get("scope")
    creds = flow.credentials

    if not getattr(creds, "refresh_token", None):
        raise SystemExit(
            "colab-adc: error: OAuth response did not include a refresh_token; "
            "retry consent flow."
        )

    adc_payload: dict[str, object] = {
        "account": "",
        "client_id": creds.client_id or client_id,
        "client_secret": creds.client_secret or client_secret,
        "refresh_token": creds.refresh_token,
        "type": "authorized_user",
        "universe_domain": getattr(creds, "universe_domain", None) or "googleapis.com",
    }
    if args.quota_project:
        adc_payload["quota_project_id"] = args.quota_project

    serialized = (json.dumps(adc_payload, indent=2) + "\n").encode("utf-8")
    write_adc_atomic(DEFAULT_ADC_PATH, serialized, validate=True)

    print(f"Saved project ADC credentials to {DEFAULT_ADC_PATH}")
    return 0


def login_with_gcloud(
    *,
    gcloud_bin: str,
    scopes: list[str],
    quota_project: str | None,
    client_oauth_config: str | None,
) -> int:
    """Delegate login to `gcloud auth application-default login` and persist the result."""
    ensure_writable_target_dir(DEFAULT_ADC_PATH)
    with tempfile.TemporaryDirectory(prefix=".adc-gcloud-", dir=str(ADC_DIR)) as gcloud_dir:
        os.chmod(gcloud_dir, 0o700)
        cmd = [
            gcloud_bin,
            "auth",
            "application-default",
            "login",
            "--no-launch-browser",
            f"--scopes={','.join(scopes)}",
        ]
        if quota_project:
            cmd.append(f"--billing-project={quota_project}")
        else:
            cmd.append("--disable-quota-project")
        if client_oauth_config:
            cmd.append(f"--client-id-file={Path(client_oauth_config).expanduser()}")

        env = os.environ.copy()
        env["CLOUDSDK_CONFIG"] = gcloud_dir
        result = subprocess.run(cmd, env=env, check=False)
        if result.returncode != 0:
            raise SystemExit(
                f"colab-adc: error: gcloud application-default login exited with {result.returncode}."
            )

        generated = Path(gcloud_dir) / "application_default_credentials.json"
        if not generated.is_file():
            raise SystemExit(
                "colab-adc: error: gcloud did not produce application_default_credentials.json."
            )
        try:
            raw_bytes = generated.read_bytes()
        except OSError as exc:
            raise SystemExit(
                f"colab-adc: error: cannot read generated gcloud ADC file: {exc}"
            ) from exc
        write_adc_atomic(DEFAULT_ADC_PATH, raw_bytes, validate=True)

    print(f"Saved project ADC credentials from gcloud to {DEFAULT_ADC_PATH}")
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    """Validate and import an existing ADC JSON file into project storage."""
    if args.source == "-":
        raw_bytes = sys.stdin.buffer.read(MAX_ADC_BYTES + 1)
        if len(raw_bytes) > MAX_ADC_BYTES:
            raise SystemExit(
                f"colab-adc: error: ADC input exceeds maximum size ({MAX_ADC_BYTES} bytes)."
            )
    else:
        src = Path(args.source).expanduser()
        if not src.is_file():
            raise SystemExit(f"colab-adc: error: source ADC file not found: {src}")
        try:
            size = src.stat().st_size
            if size > MAX_ADC_BYTES:
                raise SystemExit(
                    f"colab-adc: error: source ADC file exceeds maximum size ({MAX_ADC_BYTES} bytes)."
                )
            raw_bytes = src.read_bytes()
        except OSError as exc:
            raise SystemExit(
                f"colab-adc: error: cannot read source ADC file '{src}': {exc}"
            ) from exc

    if not raw_bytes.strip():
        raise SystemExit("colab-adc: error: ADC input is empty.")

    confirm_overwrite(DEFAULT_ADC_PATH, args.force)
    data = write_adc_atomic(DEFAULT_ADC_PATH, raw_bytes, validate=True)
    cred_type = data.get("type") if data else "unknown"
    print(f"Imported {cred_type} ADC credentials into {DEFAULT_ADC_PATH}")
    return 0


def resolve_status_target() -> tuple[Path, bool]:
    """Return the active ADC file path and whether GOOGLE_APPLICATION_CREDENTIALS overrides it."""
    env_override = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if env_override:
        return Path(env_override).expanduser(), True
    return DEFAULT_ADC_PATH, False


def cmd_status(args: argparse.Namespace) -> int:
    """Inspect active ADC metadata and optionally verify token refresh."""
    target, is_override = resolve_status_target()
    mounted = os.path.ismount(STATE_DIR)

    report: dict[str, object] = {
        "path": str(target),
        "default_path": str(DEFAULT_ADC_PATH),
        "overridden_by_env": is_override,
        "volume_mounted": mounted,
        "exists": target.exists(),
        "valid": False,
    }

    if target.is_symlink() and not is_override:
        report["error"] = "project ADC path is unexpectedly a symlink"
        if args.as_json:
            print(json.dumps(report, indent=2))
        else:
            print(f"ADC status: invalid ({report['error']})", file=sys.stderr)
        return 1

    if not target.exists():
        if args.as_json:
            print(json.dumps(report, indent=2))
        else:
            print(f"ADC status: missing ({target})", file=sys.stderr)
            if not mounted:
                print(
                    f"Warning: {STATE_DIR} is not mounted.",
                    file=sys.stderr,
                )
            print(
                "Run 'colab-adc login' (or 'colab-adc import <path>') to configure credentials.",
                file=sys.stderr,
            )
        return 1

    mode_str = None
    try:
        mode = stat.S_IMODE(target.stat().st_mode)
        mode_str = f"{mode:04o}"
        report["mode"] = mode_str
    except OSError:
        pass

    try:
        data, creds = validate_adc_file(target)
    except Exception as exc:
        report["error"] = str(exc)
        if args.as_json:
            print(json.dumps(report, indent=2))
        else:
            print(f"ADC status: invalid ({exc})", file=sys.stderr)
        return 1

    report["valid"] = True
    report["type"] = data.get("type")
    report["quota_project_id"] = data.get("quota_project_id") or None
    report["universe_domain"] = data.get("universe_domain") or "googleapis.com"

    if args.verify:
        try:
            default_scopes, _ = load_colab_auth_defaults()
            scoped_creds = with_scopes_if_required(creds, default_scopes)
            scoped_creds.refresh(Request())
            report["verified"] = True
        except Exception as exc:
            report["verified"] = False
            report["verify_error"] = type(exc).__name__
            if args.as_json:
                print(json.dumps(report, indent=2))
            else:
                print(
                    f"ADC verification failed ({type(exc).__name__}).",
                    file=sys.stderr,
                )
            return 1

    if args.as_json:
        print(json.dumps(report, indent=2))
    else:
        print("ADC status: valid")
        print(f"Path: {target}")
        if is_override:
            print("Source: GOOGLE_APPLICATION_CREDENTIALS override")
        else:
            print(f"Project volume mounted: {'yes' if mounted else 'no'}")
        print(f"Type: {report['type']}")
        if mode_str is not None:
            print(f"Permissions: {mode_str}")
            if mode_str != "0600":
                print("Warning: expected owner-only permissions (0600).", file=sys.stderr)
        if report["quota_project_id"]:
            print(f"Quota project: {report['quota_project_id']}")
        if args.verify:
            print("Token refresh: ok")
    return 0


def cmd_logout(args: argparse.Namespace) -> int:
    """Remove persisted project ADC credentials and optionally revoke OAuth refresh token."""
    if DEFAULT_ADC_PATH.is_symlink():
        raise SystemExit(
            f"colab-adc: error: {DEFAULT_ADC_PATH} is a symlink; remove it manually."
        )
    if not DEFAULT_ADC_PATH.exists():
        print(f"No project ADC file found at {DEFAULT_ADC_PATH}; already logged out.")
        return 0

    if args.revoke:
        try:
            data = json.loads(DEFAULT_ADC_PATH.read_text(encoding="utf-8"))
            token = data.get("refresh_token") if isinstance(data, dict) else None
            if isinstance(token, str) and token:
                resp = requests.post(
                    "https://oauth2.googleapis.com/revoke",
                    data={"token": token},
                    headers={"Content-Type": "application/x-www-form-urlencoded"},
                    allow_redirects=False,
                    timeout=10,
                )
                if resp.status_code == 200:
                    print("Revoked OAuth refresh token with Google.")
                else:
                    print(
                        f"colab-adc: warning: token revocation returned HTTP {resp.status_code}.",
                        file=sys.stderr,
                    )
        except Exception as exc:
            print(
                f"colab-adc: warning: failed to revoke token remotely ({type(exc).__name__}); "
                "removing local ADC file anyway.",
                file=sys.stderr,
            )

    try:
        DEFAULT_ADC_PATH.unlink()
    except OSError as exc:
        raise SystemExit(
            f"colab-adc: error: failed to remove '{DEFAULT_ADC_PATH}': {exc}"
        ) from exc
    print(f"Removed project ADC credentials at {DEFAULT_ADC_PATH}")
    return 0


def cmd_path(_args: argparse.Namespace) -> int:
    """Print the default project-scoped ADC file path."""
    print(DEFAULT_ADC_PATH)
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="colab-adc",
        description="Manage project-scoped Application Default Credentials (ADC) for Colab CLI.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    login_p = subparsers.add_parser(
        "login",
        help="Authenticate via OAuth2 copy-paste flow (or gcloud) and save ADC credentials.",
    )
    login_p.add_argument(
        "--client-oauth-config",
        help="Optional path to a custom OAuth client JSON file.",
    )
    login_p.add_argument(
        "--scopes",
        help="Comma-separated OAuth scopes (defaults to Colab CLI scopes).",
    )
    login_p.add_argument(
        "--quota-project",
        help="Optional GCP quota_project_id to record in the ADC JSON.",
    )
    login_p.add_argument(
        "--use-gcloud",
        action="store_true",
        help="Use installed gcloud CLI (`gcloud auth application-default login`) instead of the built-in OAuth flow.",
    )
    login_p.add_argument(
        "--print-url-only",
        action="store_true",
        help="Print the OAuth authorization URL and exit without prompting for a code.",
    )
    login_p.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="Overwrite existing project ADC file without prompting.",
    )
    login_p.set_defaults(func=cmd_login)

    import_p = subparsers.add_parser(
        "import",
        help="Validate and import an existing ADC JSON file (or '-' for stdin) into project storage.",
    )
    import_p.add_argument("source", help="Path to ADC JSON file, or '-' to read stdin.")
    import_p.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="Overwrite existing project ADC file without prompting.",
    )
    import_p.set_defaults(func=cmd_import)

    status_p = subparsers.add_parser(
        "status",
        help="Check active ADC file status and metadata.",
    )
    status_p.add_argument(
        "--verify",
        action="store_true",
        help="Attempt a live token refresh against Google OAuth to verify credentials.",
    )
    status_p.add_argument(
        "--json",
        dest="as_json",
        action="store_true",
        help="Emit status output as JSON.",
    )
    status_p.set_defaults(func=cmd_status)

    logout_p = subparsers.add_parser(
        "logout",
        help="Remove persisted project ADC credentials.",
    )
    logout_p.add_argument(
        "--revoke",
        action="store_true",
        help="Attempt to revoke the refresh token remotely before deleting the local file.",
    )
    logout_p.set_defaults(func=cmd_logout)

    path_p = subparsers.add_parser(
        "path",
        help="Print the project-scoped ADC file path.",
    )
    path_p.set_defaults(func=cmd_path)

    return parser


def main(argv: list[str] | None = None) -> int:
    os.umask(0o077)
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
