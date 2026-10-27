import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


LAB = Path(__file__).resolve().parent
ROOT = LAB.parents[2]
BASELINE = "deffa9c1926317a9d66a0d41bd9b1de8fcb7ca7d"
SOURCE = "packages/TelegramMediaUtils/Sources/TelegramMediaUtils/CGImageExtensions.swift"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--telegram-ios-source", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    ios_commit = subprocess.check_output(["git", "ls-tree", BASELINE, "submodules/telegram-ios"], cwd=ROOT).decode().split()[2]
    prefix = "submodules/SSignalKit/"
    paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", ios_commit, prefix], cwd=args.telegram_ios_source).decode().splitlines()
    signal_hashes = {}
    for path in paths:
        if not (path.endswith(".swift") or path.endswith(".h") or path.endswith(".m")):
            continue
        data = subprocess.check_output(["git", "show", ios_commit + ":" + path], cwd=args.telegram_ios_source)
        target = output / "SSignalKit" / path.removeprefix(prefix)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
        signal_hashes[path] = digest(data)
    reference = subprocess.check_output(["git", "show", BASELINE + ":" + SOURCE], cwd=ROOT).decode()
    production = (ROOT / SOURCE).read_text()
    start = reference.index("    var blurred: CGImage {")
    end = reference.index("    static func loadFromFile", start)
    reference = "import Cocoa\nimport TGUIKit\nimport FastBlur\npublic extension CGImage {\n" + reference[start:end].replace("var blurred:", "var referenceBlurred:", 1) + "}\n"
    kit = output / "TGUIKit"
    shutil.copytree(ROOT / "packages/TGUIKit/Sources", kit / "Sources", dirs_exist_ok=True)
    manifest = (ROOT / "packages/TGUIKit/Package.swift").read_text()
    manifest = re.sub(r'\s*\.testTarget\([\s\S]*?path: "Tests/TGUIKitTests"\),', "", manifest)
    def dependency(match):
        path = match.group(1)
        if path == "../../submodules/telegram-ios/submodules/SSignalKit":
            path = output / "SSignalKit"
        elif path.startswith("../"):
            path = (ROOT / "packages/TGUIKit" / path).resolve()
        return 'path: "' + str(path) + '"'
    manifest = re.sub(r'path: "([^"]+)"', dependency, manifest)
    (kit / "Package.swift").write_text(manifest)
    shutil.copytree(ROOT / "packages/FastBlur", output / "FastBlur", dirs_exist_ok=True, ignore=shutil.ignore_patterns(".build", ".swiftpm"))
    for module in ["NativeBlur", "TrackedBlur"]:
        folder = output / "Sources" / module
        folder.mkdir(parents=True, exist_ok=True)
        for name, source in [("CGImageExtensions.swift", production), ("Reference.swift", reference)]:
            if module == "TrackedBlur":
                source = source.replace("DrawingContext(size:", "trackedDrawingContext(size:")
            (folder / name).write_text(source)
        (folder / "Entry.swift").write_text("import Cocoa\npublic func renderBlur(_ image: CGImage) -> CGImage { image.blurred }\npublic func renderReference(_ image: CGImage) -> CGImage { image.referenceBlurred }\n")
    shutil.copyfile(LAB / "Tracking.swift", output / "Sources/TrackedBlur/Tracking.swift")
    for module in ["BlurBench", "BlurTests"]:
        folder = output / ("Tests" if module == "BlurTests" else "Sources") / module
        folder.mkdir(parents=True, exist_ok=True)
        expected = {path.name for path in (LAB / module).glob("*.swift")} | {"Fixtures.swift"}
        for stale in folder.glob("*.swift"):
            if stale.name not in expected:
                stale.unlink()
        for path in (LAB / module).glob("*.swift"):
            shutil.copyfile(path, folder / path.name)
        shutil.copyfile(LAB / "Fixtures.swift", folder / "Fixtures.swift")
    (output / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BlurredPreviewLab", platforms: [.macOS(.v12)], dependencies: [
    .package(path: "TGUIKit"), .package(path: "FastBlur")
], targets: [
    .target(name: "NativeBlur", dependencies: ["TGUIKit", "FastBlur"]),
    .target(name: "TrackedBlur", dependencies: ["TGUIKit", "FastBlur"]),
    .executableTarget(name: "BlurBench", dependencies: ["NativeBlur", "TGUIKit"]),
    .testTarget(name: "BlurTests", dependencies: ["NativeBlur", "TrackedBlur", "TGUIKit"])
])
''')
    hashes = {str(path.relative_to(ROOT)): digest(path.read_bytes()) for name in ["TGUIKit", "FastBlur", "ObjcUtils", "ColorPalette", "Colors", "KeyboardKey"] for path in sorted((ROOT / "packages" / name).rglob("*")) if path.is_file() and ".build" not in path.parts and ".swiftpm" not in path.parts}
    provenance = {"baseline": BASELINE, "production_file": SOURCE, "production_sha256": digest(production.encode()), "reference_sha256": digest(reference.encode()), "dependencies_sha256": hashes, "telegram_ios_commit": ios_commit, "signal_sources_sha256": signal_hashes, "test_instrumentation": "TrackedBlur replaces only DrawingContext constructor calls with a recorder that returns a real TGUIKit.DrawingContext; NativeBlur and benchmarks use the unmodified production source.", "lab_sources_sha256": {str(path.relative_to(LAB)): digest(path.read_bytes()) for path in sorted(LAB.rglob("*")) if path.is_file() and path.suffix in [".swift", ".py"] and "__pycache__" not in path.parts}}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(output)


if __name__ == "__main__":
    main()
