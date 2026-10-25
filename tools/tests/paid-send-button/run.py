import argparse
import json
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--scratch-path", type=Path)
parser.add_argument("--snapshots", type=Path)
parser.add_argument("--revision")
parser.add_argument("--captures-only", action="store_true")
args = parser.parse_args()
if args.revision and not args.captures_only:
    parser.error("Use --captures-only when rendering a baseline revision")


def source(name):
    path = "packages/ChatUI/Sources/ChatUI/" + name + ".swift"
    return subprocess.check_output(["git", "show", args.revision + ":" + path], cwd=root, text=True) if args.revision else (root / path).read_text()


def block(text, marker):
    start = text.index(marker)
    end = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end].replace("private ", "")


button = source("ChatInputSendButton")
container = source("ChatInputView")
constants = "\n".join(line for line in button.splitlines() if "static let field" in line or "static let planeFlightOffset" in line)
placement_start = container.index("        let sendFrame: NSRect")
placement = container[placement_start:container.index("\n        let attachGhostFrame", placement_start)]
parts = {
    "__STARS_VIEW__": block(source("ChatInputActionsView"), "public final class StarsSendActionView"),
    "__STATE__": block(button, "public struct State:"),
    "__CONSTANTS__": constants,
    "__FIELD_STATE__": block(button, "public var isInField:"),
    "__FIELD_ACTION__": block(button, "private func isFieldAction(") if "private func isFieldAction(" in button else "",
    "__DESIRED_SIZE__": block(button, "public var desiredSize:"),
    "__UPDATE__": block(button, "public func update(state:"),
    "__LAYOUT__": block(button, "public func updateLayout(size:"),
    "__SEND_SLOT__": block(container, "private func sendSlot("),
    "__PLACEMENT__": placement,
    "__FIELD_TRANSITION__": block(button, "private func animateFieldTransition(").replace("{\n", "{\n        fieldTransitions.append((view, appearing))\n", 1),
    "__PLANE_FLIGHT__": block(button, "private func animatePlaneFlight()"),
    "__ACTIONS_LAYOUT__": block(source("ChatInputActionsView"), "public func updateLayout(size:"),
}
image_paths = {}
for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "star_small", "Icon_Entertainments", "Icon_SendMessage_Large"]:
    imageset = root / "Telegram-Mac/Assets.xcassets" / (name + ".imageset")
    images = json.loads((imageset / "Contents.json").read_text())["images"]
    image = next(image for image in images if image.get("filename") and image.get("scale") == "1x")
    image_paths[name] = str(imageset / image["filename"])
parts["__IMAGE_PATHS__"] = "[" + ", ".join(json.dumps(name) + ": " + json.dumps(path) for name, path in image_paths.items()) + "]"
snapshot_path = args.snapshots.resolve() if args.snapshots else None
if snapshot_path:
    snapshot_path.mkdir(parents=True, exist_ok=True)
parts["__SNAPSHOT_PATH__"] = json.dumps(str(snapshot_path)) if snapshot_path else "nil"
parts["__CAPTURES_ONLY__"] = str(args.captures_only).lower()

with tempfile.TemporaryDirectory(prefix="telegram-paid-send-") as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / "packages/TGUIKit"))
    palette_dependency = json.dumps(str(root / "packages/ColorPalette"))
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PaidSendChecks", platforms: [.macOS(.v12)], dependencies: [.package(path: DEPENDENCY), .package(path: PALETTE)], targets: [.executableTarget(name: "PaidSendChecks", dependencies: [.product(name: "TGUIKit", package: "TGUIKit"), "ColorPalette"], path: "Sources")])
'''.replace("DEPENDENCY", dependency).replace("PALETTE", palette_dependency))
    (directory / "Sources").mkdir()
    for name in ["Fixture.swift", "main.swift"]:
        text = (fixtures / name).read_text()
        for marker, body in parts.items():
            text = text.replace(marker, body)
        (directory / "Sources" / name).write_text(text)
    command = ["swift", "run", "--package-path", str(directory), "--disable-sandbox", "--jobs", "4"]
    if args.scratch_path:
        command += ["--scratch-path", str(args.scratch_path.resolve())]
    print("Compiling production paid-send view and send-button methods against native TGUIKit", flush=True)
    raise SystemExit(subprocess.run(command + ["PaidSendChecks"]).returncode)
