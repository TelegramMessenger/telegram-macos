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


class ShareExtensionSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.extension = Path(self.temp.name) / "TelegramShare.appex"
        (self.extension / "Contents").mkdir(parents=True)

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
