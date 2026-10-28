import argparse
import json
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--revision")
parser.add_argument("--expect-bug", action="store_true")
parser.add_argument("--scratch-path", type=Path, required=True)
parser.add_argument("--snapshots", type=Path)
args = parser.parse_args()
path = "packages/ChatUI/Sources/ChatUI/ChatLayerScene.swift"
source = subprocess.check_output(["git", "show", args.revision + ":" + path], cwd=root, text=True) if args.revision else (root / path).read_text()
selection = (root / "packages/ChatUI/Sources/ChatUI/ChatSelectText.swift").read_text()
start = selection.index("    public override func resignFirstResponder()")
end = selection.index("\n    }", start) + len("\n    }")
image_paths = {}
for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_Menu_More", "Icon_Menu_Selected"]:
    imageset = root / "Telegram-Mac/Assets.xcassets" / (name + ".imageset")
    images = json.loads((imageset / "Contents.json").read_text())["images"]
    image = next(image for image in images if image.get("filename") and image.get("scale") == "1x")
    image_paths[name] = str(imageset / image["filename"])
if args.snapshots:
    args.snapshots.mkdir(parents=True, exist_ok=True)
parts = {
    "__IMAGE_PATHS__": "[" + ", ".join(json.dumps(name) + ": " + json.dumps(path) for name, path in image_paths.items()) + "]",
    "__RESIGN__": selection[start:end],
    "__SNAPSHOTS__": json.dumps(str(args.snapshots.resolve())) if args.snapshots else "nil",
}
with tempfile.TemporaryDirectory(prefix="telegram-selection-menu-") as directory:
    directory = Path(directory)
    dependencies = ", ".join(".package(path: " + json.dumps(str(root / "packages" / name)) + ")" for name in ["TGUIKit", "ColorPalette"])
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SelectionMenuChecks", platforms: [.macOS(.v12)], dependencies: [DEPENDENCIES], targets: [.executableTarget(name: "SelectionMenuChecks", dependencies: ["TGUIKit", "ColorPalette"], path: "Sources")])
'''.replace("DEPENDENCIES", dependencies))
    (directory / "Sources").mkdir()
    (directory / "Sources/ChatLayerScene.swift").write_text(source)
    pointer_path = "packages/ChatUI/Sources/ChatUI/ChatLayerPointerVisibility.swift"
    pointer = subprocess.check_output(["git", "show", args.revision + ":" + pointer_path], cwd=root, text=True) if args.revision else (root / pointer_path).read_text()
    (directory / "Sources/ChatLayerPointerVisibility.swift").write_text(pointer)
    for name in ["Fixture.swift", "main.swift"]:
        text = (fixtures / name).read_text()
        for marker, body in parts.items():
            text = text.replace(marker, body)
        (directory / "Sources" / name).write_text(text)
    command = ["swift", "run", "--package-path", str(directory), "--scratch-path", str(args.scratch_path.resolve()), "--disable-sandbox", "--jobs", "4", "SelectionMenuChecks"]
    if args.expect_bug:
        command.append("--expect-bug")
    raise SystemExit(subprocess.run(command).returncode)
