import importlib.util
import subprocess
import shutil
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("verify_no_labs", Path(__file__).with_name("verify-no-labs.py"))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class LabExclusionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "Telegram.app"
        self.mac = self.app / "Contents" / "MacOS"
        self.mac.mkdir(parents=True)

    def compile(self, source, destination=None, debug=False, source_name="fixture.c"):
        path = self.root / source_name
        path.write_text(source)
        destination = destination or self.mac / "Telegram"
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "clang", *(["-g"] if debug else []), str(path), "-o", str(destination)], check=True, capture_output=True)
        symbols = Path(str(destination) + ".dSYM")
        if symbols.exists():
            shutil.move(str(symbols), str(self.root / "fixture.dSYM"))
        return destination

    def test_clean_binary(self):
        self.compile("int main(void) { return 0; }")
        verifier.verify(self.app)

    def test_debug_source_reference_is_not_lab_code(self):
        self.compile("int main(void) { return 0; }", debug=True, source_name="PerfLabFixture.c")
        verifier.verify(self.app)

    def test_lab_symbol(self):
        self.compile("void PerfLabLeak(void) {} int main(void) { PerfLabLeak(); return 0; }")
        with self.assertRaisesRegex(ValueError, "lab code"):
            verifier.verify(self.app)

    def test_stripped_launch_argument(self):
        binary = self.compile('#include <stdio.h>\nint main(void) { puts("-PerfLabScenarios"); return 0; }')
        subprocess.run(["xcrun", "strip", "-x", str(binary)], check=True, capture_output=True)
        with self.assertRaisesRegex(ValueError, "lab code"):
            verifier.verify(self.app)

    def test_nested_binary(self):
        self.compile("int main(void) { return 0; }")
        self.compile("void NetworkLabLeak(void) {} int main(void) { return 0; }", self.app / "Contents/PlugIns/Share.appex/Contents/MacOS/Share")
        with self.assertRaisesRegex(ValueError, "lab code"):
            verifier.verify(self.app)

    def test_named_artifact(self):
        self.compile("int main(void) { return 0; }")
        (self.app / "Contents/PerfLab.bundle").mkdir()
        with self.assertRaisesRegex(ValueError, "lab artifact"):
            verifier.verify(self.app)

    def test_missing_binaries(self):
        with self.assertRaisesRegex(ValueError, "no Mach-O"):
            verifier.verify(self.app)


class EmojiFetchPolicyTests(unittest.TestCase):
    def test_release_without_lab_and_debug_override(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / "packages/EntertainmentUI/Sources/EntertainmentUI/EmojiesSectionRowItem.swift").read_text()
        start = source.index("let fetchMode: InlineStickerItemLayer.FetchMode")
        end = source.index("view = InlineStickerItemLayer(", start)
        policy = source[start:end]
        fixture = """
enum InlineStickerItemLayer {
    enum FetchMode { case always, whileVisible, never }
}
#if DEBUG
enum EmojiPanelLab { static var fetchMode: InlineStickerItemLayer.FetchMode = .never }
#endif
func selectedFetchMode() -> InlineStickerItemLayer.FetchMode {
__POLICY__
    return fetchMode
}
#if DEBUG
precondition(selectedFetchMode() == .never)
EmojiPanelLab.fetchMode = .whileVisible
#endif
precondition(selectedFetchMode() == .whileVisible)
""".replace("__POLICY__", policy)
        with tempfile.TemporaryDirectory(prefix="emoji-fetch-policy-") as directory:
            directory = Path(directory)
            source = directory / "main.swift"
            source.write_text(fixture)
            for configuration, flags in (("Release", ["-O"]), ("Debug", ["-D", "DEBUG"])):
                with self.subTest(configuration=configuration):
                    binary = directory / configuration
                    subprocess.run(["swiftc", "-module-cache-path", str(directory / "cache"), *flags, str(source), "-o", str(binary)], check=True, capture_output=True)
                    subprocess.run([str(binary)], check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
