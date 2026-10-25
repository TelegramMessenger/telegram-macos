import argparse
import json
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--revision")
parser.add_argument("--scratch-path", type=Path, required=True)
parser.add_argument("--snapshots", type=Path, required=True)
args = parser.parse_args()
path = "packages/StarsUI/Sources/StarsUI/Star_Transaction.swift"
source = subprocess.check_output(["git", "show", args.revision + ":" + path], cwd=root, text=True) if args.revision else (root / path).read_text()
start = source.index("                current.set(image: TelegramThemeHooks.shared.image(.iconChatActions)", source.index("private final class HeaderView"))
end = source.index("                current.contextMenu =", start)
styling = source[start:end]
image_paths = {}
for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_ChatActions", "Icon_Pip_Close"]:
    imageset = root / "Telegram-Mac/Assets.xcassets" / (name + ".imageset")
    images = json.loads((imageset / "Contents.json").read_text())["images"]
    image = next(image for image in images if image.get("filename") and image.get("scale") == "1x")
    image_paths[name] = str(imageset / image["filename"])
args.snapshots.mkdir(parents=True, exist_ok=True)
parts = {
    "__IMAGE_PATHS__": "[" + ", ".join(json.dumps(name) + ": " + json.dumps(path) for name, path in image_paths.items()) + "]",
    "__MORE_STYLE__": styling,
    "__SNAPSHOTS__": json.dumps(str(args.snapshots.resolve())),
}
with tempfile.TemporaryDirectory(prefix="telegram-gift-controls-") as directory:
    directory = Path(directory)
    dependencies = ", ".join(".package(path: " + json.dumps(str(root / "packages" / name)) + ")" for name in ["TGUIKit", "ColorPalette"])
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "GiftControls", platforms: [.macOS(.v12)], dependencies: [DEPENDENCIES], targets: [.executableTarget(name: "GiftControls", dependencies: ["TGUIKit", "ColorPalette"], path: "Sources")])
'''.replace("DEPENDENCIES", dependencies))
    (directory / "Sources").mkdir()
    text = (fixtures / "main.swift").read_text()
    for marker, value in parts.items():
        text = text.replace(marker, value)
    (directory / "Sources/main.swift").write_text(text)
    raise SystemExit(subprocess.run(["swift", "run", "--package-path", str(directory), "--scratch-path", str(args.scratch_path.resolve()), "--disable-sandbox", "--jobs", "4", "GiftControls"]).returncode)
