#!/usr/bin/env python3
"""Standalone command-line client for the office-vba-mcp stdio server."""

from __future__ import annotations

import argparse
import json
import os
import platform
import queue
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any

VERSION = "1.0.0"
PROTOCOL_VERSION = "2024-11-05"
SUPPORTED_EXTENSIONS = {".xlsm", ".xlam", ".docm", ".dotm", ".pptm", ".ppam", ".potm"}


class ClientError(RuntimeError):
    """Raised for actionable client or MCP transport failures."""


class MCPClient:
    def __init__(self, binary: Path, timeout: float) -> None:
        self.binary = binary
        self.timeout = timeout
        self._next_id = 1
        self._messages: queue.Queue[str | None] = queue.Queue()
        self._stderr_lines: list[str] = []
        self._process = subprocess.Popen(
            [str(binary)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        assert self._process.stdout is not None
        assert self._process.stderr is not None
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def _read_stdout(self) -> None:
        assert self._process.stdout is not None
        for line in self._process.stdout:
            self._messages.put(line)
        self._messages.put(None)

    def _read_stderr(self) -> None:
        assert self._process.stderr is not None
        for line in self._process.stderr:
            self._stderr_lines.append(line.rstrip())

    def _send(self, payload: dict[str, Any]) -> None:
        if self._process.poll() is not None:
            raise ClientError(self._closed_message())
        assert self._process.stdin is not None
        self._process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self._process.stdin.flush()

    def _closed_message(self) -> str:
        details = "\n".join(self._stderr_lines[-20:]).strip()
        base = f"office-vba-mcp exited with code {self._process.poll()}"
        return f"{base}:\n{details}" if details else base

    def request(self, method: str, params: dict[str, Any] | None = None) -> Any:
        request_id = self._next_id
        self._next_id += 1
        payload: dict[str, Any] = {"jsonrpc": "2.0", "id": request_id, "method": method}
        if params is not None:
            payload["params"] = params
        self._send(payload)

        while True:
            try:
                line = self._messages.get(timeout=self.timeout)
            except queue.Empty as exc:
                raise ClientError(f"Timed out after {self.timeout:g}s waiting for {method}") from exc
            if line is None:
                raise ClientError(self._closed_message())
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if message.get("id") != request_id:
                continue
            if "error" in message:
                error = message["error"]
                raise ClientError(f"MCP error {error.get('code')}: {error.get('message')}")
            return message.get("result")

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        payload: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        self._send(payload)

    def initialize(self) -> Any:
        result = self.request(
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "office-vba-skill", "version": VERSION},
            },
        )
        self.notify("notifications/initialized")
        return result

    def close(self) -> None:
        if self._process.poll() is None:
            self._process.terminate()
            try:
                self._process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self._process.kill()
        for stream in (self._process.stdin, self._process.stdout, self._process.stderr):
            if stream is not None:
                stream.close()

    def __enter__(self) -> "MCPClient":
        self.initialize()
        return self

    def __exit__(self, exc_type: Any, exc: Any, traceback: Any) -> None:
        self.close()


def skill_dir() -> Path:
    return Path(__file__).resolve().parent.parent


def binary_candidates() -> list[Path]:
    candidates: list[Path] = []
    configured = os.environ.get("OFFICE_VBA_MCP")
    if configured:
        candidates.append(Path(configured).expanduser())

    local_bin = skill_dir() / "bin"
    if os.name == "nt":
        candidates.extend([local_bin / "office-vba-mcp.exe", local_bin / "office-vba-mcp-windows-amd64.exe"])
    else:
        candidates.append(local_bin / "office-vba-mcp")
        system = platform.system().lower()
        machine = platform.machine().lower()
        arch = "arm64" if machine in {"arm64", "aarch64"} else "amd64"
        candidates.append(local_bin / f"office-vba-mcp-{system}-{arch}")

    on_path = shutil.which("office-vba-mcp")
    if on_path:
        candidates.append(Path(on_path))
    return candidates


def resolve_binary() -> Path:
    checked: list[str] = []
    for candidate in binary_candidates():
        resolved = candidate.resolve()
        checked.append(str(resolved))
        if resolved.is_file() and (os.name == "nt" or os.access(resolved, os.X_OK)):
            return resolved
    locations = "\n  - ".join(checked) if checked else "(none)"
    raise ClientError(
        "office-vba-mcp was not found or is not executable. Checked:\n"
        f"  - {locations}\n"
        "Run install.sh/install.ps1 or set OFFICE_VBA_MCP to the binary path."
    )


def office_file(value: str) -> Path:
    path = Path(value).expanduser().resolve()
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"File does not exist: {path}")
    if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        supported = ", ".join(sorted(SUPPORTED_EXTENSIONS))
        raise argparse.ArgumentTypeError(f"Unsupported Office extension {path.suffix!r}; expected one of: {supported}")
    return path


def existing_dir(value: str) -> Path:
    path = Path(value).expanduser().resolve()
    if not path.is_dir():
        raise argparse.ArgumentTypeError(f"Directory does not exist: {path}")
    return path


def output_dir(value: str) -> Path:
    return Path(value).expanduser().resolve()


def call_tool(client: MCPClient, name: str, arguments: dict[str, Any]) -> Any:
    return client.request("tools/call", {"name": name, "arguments": arguments})


def text_content(result: Any) -> str:
    if not isinstance(result, dict):
        return str(result)
    chunks: list[str] = []
    for item in result.get("content", []):
        if isinstance(item, dict) and item.get("type") == "text" and isinstance(item.get("text"), str):
            chunks.append(item["text"])
    return "\n".join(chunks) if chunks else json.dumps(result, indent=2, ensure_ascii=False)


def emit(result: Any, as_json: bool, metadata: dict[str, Any] | None = None) -> None:
    if as_json:
        payload = {"ok": True, "result": result}
        if metadata:
            payload["metadata"] = metadata
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        print(text_content(result))
        if metadata:
            for key, value in metadata.items():
                print(f"{key}: {value}")


def require_yes(args: argparse.Namespace, action: str) -> None:
    if not args.yes:
        raise ClientError(f"{action} requires explicit confirmation. Re-run with --yes after reviewing the target and source.")


def run_command(args: argparse.Namespace) -> None:
    binary = resolve_binary()

    if args.command == "doctor":
        with MCPClient(binary, args.timeout) as client:
            tools = client.request("tools/list")
        expected = {"vba_list", "vba_read", "vba_write", "vba_run"}
        found = {
            tool.get("name")
            for tool in tools.get("tools", [])
            if isinstance(tool, dict) and isinstance(tool.get("name"), str)
        }
        result = {
            "wrapper_version": VERSION,
            "python": sys.version.split()[0],
            "platform": platform.platform(),
            "binary": str(binary),
            "tools": sorted(found),
            "missing_tools": sorted(expected - found),
        }
        if args.json:
            print(json.dumps({"ok": not result["missing_tools"], **result}, indent=2))
        else:
            for key, value in result.items():
                print(f"{key}: {value}")
        if result["missing_tools"]:
            raise ClientError("The MCP server is missing required tools")
        return

    with MCPClient(binary, args.timeout) as client:
        if args.command == "list":
            result = call_tool(client, "vba_list", {"file_path": str(args.file)})
            emit(result, args.json)
            return

        if args.command == "read":
            arguments: dict[str, Any] = {"file_path": str(args.file)}
            if args.output_dir:
                args.output_dir.mkdir(parents=True, exist_ok=True)
                arguments["output_dir"] = str(args.output_dir)
            if args.module:
                arguments["module_name"] = args.module
            result = call_tool(client, "vba_read", arguments)
            emit(result, args.json, {"output_dir": str(args.output_dir) if args.output_dir else "server default"})
            return

        if args.command == "write":
            require_yes(args, "Writing VBA")
            source_dir = args.input_dir or (args.file.parent / "vba_src")
            if not source_dir.is_dir():
                raise ClientError(f"VBA source directory does not exist: {source_dir}")
            source_files = sorted([*source_dir.glob("*.bas"), *source_dir.glob("*.cls")])
            if not source_files:
                raise ClientError(f"No .bas or .cls files found in: {source_dir}")
            backup = Path(str(args.file) + ".bak")
            result = call_tool(
                client,
                "vba_write",
                {"file_path": str(args.file), "input_dir": str(source_dir)},
            )
            backup_exists = backup.is_file()
            metadata = {
                "input_dir": str(source_dir),
                "source_files": [path.name for path in source_files],
                "backup": str(backup),
                "backup_exists": backup_exists,
            }
            emit(result, args.json, metadata)
            if not backup_exists:
                raise ClientError(f"Write returned without the expected backup file: {backup}")
            return

        if args.command == "run":
            require_yes(args, "Running VBA")
            result = call_tool(
                client,
                "vba_run",
                {"file_path": str(args.file), "macro_name": args.macro},
            )
            emit(result, args.json, {"macro": args.macro, "file": str(args.file)})
            return

    raise ClientError(f"Unknown command: {args.command}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    parser.add_argument("--timeout", type=float, default=60.0, help="MCP request timeout in seconds (default: 60)")
    subparsers = parser.add_subparsers(dest="command", required=True)

    doctor = subparsers.add_parser("doctor", help="Verify the binary and required MCP tools")
    doctor.add_argument("--json", action="store_true")

    list_cmd = subparsers.add_parser("list", help="List VBA modules and procedures")
    list_cmd.add_argument("file", type=office_file)
    list_cmd.add_argument("--json", action="store_true")

    read = subparsers.add_parser("read", help="Extract VBA source files")
    read.add_argument("file", type=office_file)
    read.add_argument("--output-dir", type=output_dir)
    read.add_argument("--module")
    read.add_argument("--json", action="store_true")

    write = subparsers.add_parser("write", help="Write extracted VBA source files into an Office file")
    write.add_argument("file", type=office_file)
    write.add_argument("--input-dir", type=existing_dir)
    write.add_argument("--yes", action="store_true", help="Confirm this modifying operation")
    write.add_argument("--json", action="store_true")

    run = subparsers.add_parser("run", help="Execute a named macro in an open Office document")
    run.add_argument("file", type=office_file)
    run.add_argument("macro")
    run.add_argument("--yes", action="store_true", help="Confirm macro execution")
    run.add_argument("--json", action="store_true")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        run_command(args)
        return 0
    except (ClientError, OSError, subprocess.SubprocessError) as exc:
        if getattr(args, "json", False):
            print(json.dumps({"ok": False, "error": str(exc)}, indent=2), file=sys.stderr)
        else:
            print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
