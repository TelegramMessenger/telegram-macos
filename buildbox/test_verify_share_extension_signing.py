import base64
import plistlib
import tempfile
import unittest
from pathlib import Path

import importlib.util


spec = importlib.util.spec_from_file_location(
    "verify_share_extension_signing",
    Path(__file__).with_name("verify-share-extension-signing.py"),
)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


REAL_CODESIGN_STDOUT = base64.b64decode(
    "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48IURPQ1RZUEUgcGxpc3QgUFVCTElDICItLy9BcHBsZS8vRFREIFBMSVNUIDEuMC8vRU4iICJodHRwczovL3d3dy5hcHBsZS5jb20vRFREcy9Qcm9wZXJ0eUxpc3QtMS4wLmR0ZCI+PHBsaXN0IHZlcnNpb249IjEuMCI+PGRpY3Q+PGtleT5jb20uYXBwbGUuc2VjdXJpdHkuYXBwLXNhbmRib3g8L2tleT48dHJ1ZS8+PGtleT5rZXljaGFpbi1hY2Nlc3MtZ3JvdXBzPC9rZXk+PGFycmF5PjxzdHJpbmc+Nk4zOFZXUzVCWC5ydS5rZWVwY29kZXIuVGVsZWdyYW1TaGFyZTwvc3RyaW5nPjwvYXJyYXk+PC9kaWN0PjwvcGxpc3Q+Cg=="
)
REAL_CODESIGN_STDERR = base64.b64decode(
    "RXhlY3V0YWJsZT0vcHJpdmF0ZS90bXAvY29kZXNpZ24tY2FwdHVyZS9UZWxlZ3JhbVNoYXJlCndhcm5pbmc6IFNwZWNpZnlpbmcgJzonIGluIHRoZSBwYXRoIGlzIGRlcHJlY2F0ZWQgYW5kIHdpbGwgbm90IHdvcmsgaW4gYSBmdXR1cmUgcmVsZWFzZQo="
)


class ShareExtensionSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.extension = Path(self.temp.name) / "TelegramShare.appex"
        (self.extension / "Contents").mkdir(parents=True)

    def make_codesign_stub(self, stdout, stderr):
        output_dir = Path(self.temp.name) / "codesign-output"
        output_dir.mkdir()
        (output_dir / "stdout").write_bytes(stdout)
        (output_dir / "stderr").write_bytes(stderr)
        shim = Path(self.temp.name) / "codesign"
        shim.write_text(
            "#!/bin/sh\n"
            f"cat '{output_dir / 'stdout'}'\n"
            f"cat '{output_dir / 'stderr'}' >&2\n"
            "exit 0\n"
        )
        shim.chmod(0o755)
        return shim

    def make_app(self):
        app = Path(self.temp.name) / "Telegram.app"
        extension = app / "Contents" / "PlugIns" / "TelegramShare.appex"
        (extension / "Contents" / "MacOS").mkdir(parents=True)
        (extension / "Contents" / "MacOS" / "TelegramShare").touch()
        return app, extension

    def test_real_codesign_streams_only_parse_from_stdout(self):
        with self.assertRaises(Exception):
            plistlib.loads(REAL_CODESIGN_STDOUT + REAL_CODESIGN_STDERR)
        entitlements = plistlib.loads(REAL_CODESIGN_STDOUT)
        self.assertIn("keychain-access-groups", entitlements)

    def test_codesign_stdout_is_parsed_despite_stderr_diagnostics(self):
        app, _ = self.make_app()
        shim = self.make_codesign_stub(REAL_CODESIGN_STDOUT, REAL_CODESIGN_STDERR)
        with self.assertRaisesRegex(ValueError, "keychain-access-groups"):
            verifier.verify(app, codesign=str(shim))

    def test_codesign_stderr_diagnostics_do_not_affect_verification_with_profile(self):
        app, extension = self.make_app()
        (extension / "Contents" / "embedded.provisionprofile").touch()
        shim = self.make_codesign_stub(REAL_CODESIGN_STDOUT, REAL_CODESIGN_STDERR)
        verifier.verify(app, codesign=str(shim))


    def test_share_extension_without_keychain_groups_is_valid_without_profile(self):
        verifier.verify_entitlements(self.extension, {})

    def test_keychain_groups_require_embedded_profile(self):
        with self.assertRaisesRegex(ValueError, "keychain-access-groups"):
            verifier.verify_entitlements(
                self.extension,
                {"keychain-access-groups": ["example.share"]},
            )

    def test_keychain_groups_are_valid_with_embedded_profile(self):
        (self.extension / "Contents" / "embedded.provisionprofile").touch()
        verifier.verify_entitlements(
            self.extension,
            {"keychain-access-groups": ["example.share"]},
        )


if __name__ == "__main__":
    unittest.main()
