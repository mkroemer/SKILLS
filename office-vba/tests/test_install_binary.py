from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "install-binary.py"
SPEC = importlib.util.spec_from_file_location("install_binary", MODULE_PATH)
assert SPEC and SPEC.loader
install_binary = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(install_binary)


class ReleaseHandler(BaseHTTPRequestHandler):
    payload = b"fake-office-vba-mcp"
    digest = hashlib.sha256(payload).hexdigest()
    bad_digest = False

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/repos/miclip/office-vba-mcp/releases/latest":
            digest = "0" * 64 if self.bad_digest else self.digest
            body = json.dumps(
                {
                    "tag_name": "v-test",
                    "assets": [
                        {
                            "name": "office-vba-mcp-linux-amd64",
                            "browser_download_url": f"http://127.0.0.1:{self.server.server_port}/asset",
                            "size": len(self.payload),
                            "digest": f"sha256:{digest}",
                        }
                    ],
                }
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/asset":
            self.send_response(200)
            self.send_header("Content-Length", str(len(self.payload)))
            self.end_headers()
            self.wfile.write(self.payload)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, format: str, *args: object) -> None:
        return


class InstallerTests(unittest.TestCase):
    def setUp(self) -> None:
        ReleaseHandler.bad_digest = False
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), ReleaseHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def args(self, temp: Path):
        parser = install_binary.build_parser()
        return parser.parse_args(
            [
                "--platform",
                "linux-amd64",
                "--api-base",
                f"http://127.0.0.1:{self.server.server_port}",
                "--install-dir",
                str(temp / "bin"),
                "--manifest",
                str(Path(__file__).resolve().parents[1] / "manifest.json"),
                "--no-doctor",
                "--require-checksum",
            ]
        )

    def test_platform_normalization(self) -> None:
        self.assertEqual(install_binary.normalize_platform("Darwin", "arm64"), "darwin-arm64")
        self.assertEqual(install_binary.normalize_platform("Linux", "x86_64"), "linux-amd64")
        self.assertEqual(install_binary.normalize_platform("Windows", "AMD64"), "windows-amd64")

    def test_verified_install(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            result = install_binary.install(self.args(temp))
            binary = temp / "bin" / "office-vba-mcp"
            metadata = json.loads((temp / "bin" / "VERSION.json").read_text())
            self.assertEqual(binary.read_bytes(), ReleaseHandler.payload)
            self.assertTrue(result["verified"])
            self.assertEqual(metadata["version"], "v-test")
            self.assertEqual(metadata["sha256"], ReleaseHandler.digest)

    def test_checksum_mismatch_does_not_install(self) -> None:
        ReleaseHandler.bad_digest = True
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            with self.assertRaises(install_binary.InstallError):
                install_binary.install(self.args(temp))
            self.assertFalse((temp / "bin" / "office-vba-mcp").exists())


if __name__ == "__main__":
    unittest.main()
