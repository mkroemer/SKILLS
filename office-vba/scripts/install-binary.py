#!/usr/bin/env python3
"""Install a verified office-vba-mcp release into the skill's private bin directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_API_BASE = "https://api.github.com"
GITHUB_API_VERSION = "2022-11-28"
CHECKSUM_ASSET_NAMES = (
    "checksums.txt",
    "CHECKSUMS.txt",
    "SHA256SUMS",
    "sha256sums.txt",
)


class InstallError(RuntimeError):
    """Raised for installation failures that should be shown to the user."""


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise InstallError(f"Installer manifest not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise InstallError(f"Invalid installer manifest {path}: {exc}") from exc

    if manifest.get("schema_version") != 1:
        raise InstallError("Unsupported installer manifest schema")
    if not isinstance(manifest.get("repository"), str):
        raise InstallError("Manifest is missing repository")
    if not isinstance(manifest.get("assets"), dict):
        raise InstallError("Manifest is missing assets")
    return manifest


def normalize_platform(system: str | None = None, machine: str | None = None) -> str:
    raw_system = (system or platform.system()).strip().lower()
    raw_machine = (machine or platform.machine()).strip().lower()

    system_map = {
        "darwin": "darwin",
        "linux": "linux",
        "windows": "windows",
        "win32": "windows",
        "cygwin": "windows",
        "msys": "windows",
    }
    arch_map = {
        "x86_64": "amd64",
        "amd64": "amd64",
        "x64": "amd64",
        "arm64": "arm64",
        "aarch64": "arm64",
    }

    normalized_system = system_map.get(raw_system)
    normalized_arch = arch_map.get(raw_machine)
    if not normalized_system:
        raise InstallError(f"Unsupported operating system: {raw_system or 'unknown'}")
    if not normalized_arch:
        raise InstallError(f"Unsupported architecture: {raw_machine or 'unknown'}")
    return f"{normalized_system}-{normalized_arch}"


def request_headers(token: str | None = None) -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "office-vba-agent-skill-installer/1.0",
        "X-GitHub-Api-Version": GITHUB_API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def read_url(
    url: str,
    *,
    token: str | None = None,
    timeout: float = 60.0,
    max_bytes: int | None = None,
) -> bytes:
    request = urllib.request.Request(url, headers=request_headers(token))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = response.read() if max_bytes is None else response.read(max_bytes + 1)
    except urllib.error.HTTPError as exc:
        detail = exc.read(4096).decode("utf-8", errors="replace").strip()
        suffix = f": {detail}" if detail else ""
        raise InstallError(f"HTTP {exc.code} while requesting {url}{suffix}") from exc
    except urllib.error.URLError as exc:
        raise InstallError(f"Could not request {url}: {exc.reason}") from exc

    if max_bytes is not None and len(data) > max_bytes:
        raise InstallError(f"Response from {url} exceeded {max_bytes} bytes")
    return data


def read_json(url: str, *, token: str | None, timeout: float) -> dict[str, Any]:
    raw = read_url(url, token=token, timeout=timeout, max_bytes=10 * 1024 * 1024)
    try:
        result = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InstallError(f"Invalid JSON returned by {url}") from exc
    if not isinstance(result, dict):
        raise InstallError(f"Unexpected JSON response from {url}")
    return result


def release_endpoint(api_base: str, repository: str, version: str) -> str:
    base = api_base.rstrip("/")
    encoded_repo = "/".join(urllib.parse.quote(part, safe="") for part in repository.split("/"))
    if version == "latest":
        return f"{base}/repos/{encoded_repo}/releases/latest"
    return f"{base}/repos/{encoded_repo}/releases/tags/{urllib.parse.quote(version, safe='')}"


def find_asset(release: dict[str, Any], name: str) -> dict[str, Any]:
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise InstallError("Release metadata does not contain an asset list")
    for asset in assets:
        if isinstance(asset, dict) and asset.get("name") == name:
            return asset
    available = sorted(
        str(asset.get("name"))
        for asset in assets
        if isinstance(asset, dict) and asset.get("name")
    )
    raise InstallError(
        f"Release {release.get('tag_name', 'unknown')} has no asset named {name}. "
        f"Available assets: {', '.join(available) or 'none'}"
    )


def parse_sha256(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r"(?:sha256:)?([0-9a-fA-F]{64})", value.strip())
    return match.group(1).lower() if match else None


def checksum_from_text(text: str, asset_name: str) -> str | None:
    escaped = re.escape(asset_name)
    patterns = (
        rf"(?im)^\s*([0-9a-f]{{64}})\s+\*?{escaped}\s*$",
        rf"(?im)^\s*SHA256\s*\({escaped}\)\s*=\s*([0-9a-f]{{64}})\s*$",
        r"(?im)^\s*([0-9a-f]{64})\s*$",
    )
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return match.group(1).lower()
    return None


def asset_download_url(asset: dict[str, Any]) -> str:
    url = asset.get("browser_download_url")
    if not isinstance(url, str) or not url.startswith(("https://", "http://")):
        raise InstallError(f"Release asset {asset.get('name', 'unknown')} has no download URL")
    return url


def expected_checksum(
    release: dict[str, Any],
    asset: dict[str, Any],
    *,
    token: str | None,
    timeout: float,
) -> tuple[str | None, str | None]:
    direct = parse_sha256(asset.get("digest"))
    if direct:
        return direct, "GitHub release asset digest"

    assets = release.get("assets")
    if not isinstance(assets, list):
        return None, None

    asset_name = str(asset.get("name"))
    candidates: list[dict[str, Any]] = []
    sidecar_names = {f"{asset_name}.sha256", f"{asset_name}.sha256sum"}
    for candidate in assets:
        if not isinstance(candidate, dict):
            continue
        name = candidate.get("name")
        if name in sidecar_names:
            candidates.insert(0, candidate)
        elif name in CHECKSUM_ASSET_NAMES:
            candidates.append(candidate)

    for candidate in candidates:
        raw = read_url(
            asset_download_url(candidate),
            token=None,
            timeout=timeout,
            max_bytes=2 * 1024 * 1024,
        )
        checksum = checksum_from_text(raw.decode("utf-8", errors="replace"), asset_name)
        if checksum:
            return checksum, f"release checksum asset {candidate.get('name')}"
    return None, None


def stream_download(
    url: str,
    destination: Path,
    *,
    token: str | None,
    timeout: float,
) -> tuple[str, int]:
    request = urllib.request.Request(url, headers=request_headers(token))
    digest = hashlib.sha256()
    total = 0
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response, destination.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                digest.update(chunk)
                total += len(chunk)
    except urllib.error.HTTPError as exc:
        detail = exc.read(4096).decode("utf-8", errors="replace").strip()
        suffix = f": {detail}" if detail else ""
        raise InstallError(f"HTTP {exc.code} while downloading {url}{suffix}") from exc
    except urllib.error.URLError as exc:
        raise InstallError(f"Could not download {url}: {exc.reason}") from exc
    return digest.hexdigest(), total


def run_doctor(root: Path, binary: Path, timeout: float) -> None:
    wrapper = root / "scripts" / "office-vba.py"
    if not wrapper.is_file():
        raise InstallError(f"Doctor wrapper not found: {wrapper}")
    env = os.environ.copy()
    env["OFFICE_VBA_MCP"] = str(binary)
    try:
        completed = subprocess.run(
            [sys.executable, str(wrapper), "--timeout", str(timeout), "doctor"],
            cwd=str(root),
            env=env,
            check=False,
            text=True,
            timeout=timeout + 5,
        )
    except subprocess.TimeoutExpired as exc:
        raise InstallError("The installed binary did not complete its doctor check") from exc
    if completed.returncode != 0:
        raise InstallError(f"The installed binary failed its doctor check with exit code {completed.returncode}")


def output_result(result: dict[str, Any], json_output: bool) -> None:
    if json_output:
        print(json.dumps(result, indent=2, sort_keys=True))
        return
    print(f"Installed office-vba-mcp {result['version']}:")
    print(f"  binary: {result['binary']}")
    print(f"  asset: {result['asset']}")
    print(f"  sha256: {result['sha256']}")
    print(f"  verified: {str(result['verified']).lower()}")
    if result.get("verification_source"):
        print(f"  verification source: {result['verification_source']}")
    elif result.get("warning"):
        print(f"  warning: {result['warning']}")


def install(args: argparse.Namespace) -> dict[str, Any]:
    script_path = Path(__file__).resolve()
    root = script_path.parent.parent
    manifest_path = Path(args.manifest).expanduser().resolve() if args.manifest else root / "manifest.json"
    manifest = load_manifest(manifest_path)

    repository = args.repository or os.getenv("OFFICE_VBA_MCP_REPOSITORY") or manifest["repository"]
    version = args.version or os.getenv("OFFICE_VBA_MCP_VERSION") or manifest.get("default_version", "latest")
    platform_key = args.platform or normalize_platform()
    asset_name = manifest["assets"].get(platform_key)
    if not isinstance(asset_name, str):
        supported = ", ".join(sorted(manifest["assets"]))
        raise InstallError(f"No binary is configured for {platform_key}. Supported platforms: {supported}")

    install_dir = Path(args.install_dir).expanduser().resolve() if args.install_dir else root / "bin"
    executable_name = "office-vba-mcp.exe" if platform_key.startswith("windows-") else "office-vba-mcp"
    destination = install_dir / executable_name
    version_file = install_dir / "VERSION.json"

    if destination.exists() and not args.force:
        raise InstallError(f"Binary already exists: {destination}. Use --force to replace it.")

    token = args.token or os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
    api_base = args.api_base or os.getenv("OFFICE_VBA_MCP_GITHUB_API_BASE") or DEFAULT_API_BASE
    release = read_json(
        release_endpoint(api_base, repository, version),
        token=token,
        timeout=args.timeout,
    )
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not tag:
        raise InstallError("Release metadata does not contain tag_name")

    asset = find_asset(release, asset_name)
    expected_sha256, verification_source = expected_checksum(
        release,
        asset,
        token=token,
        timeout=args.timeout,
    )
    if not expected_sha256 and args.require_checksum:
        raise InstallError(
            f"Release {tag} does not provide a SHA-256 digest or checksum for {asset_name}"
        )

    download_url = asset_download_url(asset)
    declared_size = asset.get("size")
    install_dir.mkdir(parents=True, exist_ok=True)

    temporary: Path | None = None
    try:
        temporary_suffix = ".exe" if platform_key.startswith("windows-") else ".download"
        with tempfile.NamedTemporaryFile(
            prefix=".office-vba-mcp-",
            suffix=temporary_suffix,
            dir=install_dir,
            delete=False,
        ) as temp_file:
            temporary = Path(temp_file.name)

        actual_sha256, actual_size = stream_download(
            download_url,
            temporary,
            token=None,
            timeout=args.timeout,
        )
        if isinstance(declared_size, int) and declared_size >= 0 and actual_size != declared_size:
            raise InstallError(
                f"Downloaded size mismatch for {asset_name}: expected {declared_size}, got {actual_size}"
            )
        if expected_sha256 and actual_sha256 != expected_sha256:
            raise InstallError(
                f"SHA-256 mismatch for {asset_name}: expected {expected_sha256}, got {actual_sha256}"
            )

        if not platform_key.startswith("windows-"):
            temporary.chmod(temporary.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        if not args.no_doctor:
            run_doctor(root, temporary, args.timeout)

        os.replace(temporary, destination)
        temporary = None

        metadata = {
            "repository": repository,
            "version": tag,
            "requested_version": version,
            "platform": platform_key,
            "asset": asset_name,
            "binary": str(destination),
            "download_url": download_url,
            "sha256": actual_sha256,
            "verified": bool(expected_sha256),
            "verification_source": verification_source,
            "installed_at": datetime.now(timezone.utc).isoformat(),
        }
        if not expected_sha256:
            metadata["warning"] = "No upstream SHA-256 checksum was available; use --require-checksum to reject unverified releases."
        version_file.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        return metadata
    except Exception:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="Release tag to install, or 'latest' (default from manifest)")
    parser.add_argument("--repository", help="Override the upstream GitHub repository (owner/name)")
    parser.add_argument("--install-dir", help="Destination directory (default: skill bin directory)")
    parser.add_argument("--manifest", help="Path to an alternate installer manifest")
    parser.add_argument("--platform", help="Override detected platform for testing, e.g. linux-amd64")
    parser.add_argument("--api-base", help=argparse.SUPPRESS)
    parser.add_argument("--token", help=argparse.SUPPRESS)
    parser.add_argument("--timeout", type=float, default=60.0, help="Network and doctor timeout in seconds")
    parser.add_argument("--force", action="store_true", help="Replace an existing installed binary")
    parser.add_argument(
        "--require-checksum",
        action="store_true",
        help="Fail unless the release provides a SHA-256 digest or checksum asset",
    )
    parser.add_argument("--no-doctor", action="store_true", help="Skip the post-install MCP tool check")
    parser.add_argument("--json", action="store_true", help="Print structured installation metadata")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        result = install(args)
        output_result(result, args.json)
        return 0
    except (InstallError, OSError, subprocess.SubprocessError) as exc:
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}, indent=2), file=sys.stderr)
        else:
            print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
