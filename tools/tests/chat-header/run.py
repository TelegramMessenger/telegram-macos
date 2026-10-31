import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
source_root = root / "packages/ChatUI/Sources/ChatUI"
parser = argparse.ArgumentParser()
parser.add_argument("--scratch-path", type=Path)
parser.add_argument("--dependency-root", type=Path, default=root)
args = parser.parse_args()
dependency_root = args.dependency_root.resolve()


def source(name):
    return (source_root / (name + ".swift")).read_text()


def block(text, marker):
    start = text.index(marker)
    end = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end].replace("private ", "")


header = source("ChatHeaderController")
bubbles = source("ChatHeaderBubblesView")
controller = source("ChatController")
search = source("ChatSearchHeader")
search = search[search.index("class ChatSearchHeader :"):]
tone = (dependency_root / "submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Translate.swift").read_text()
frame_start = controller.index("            let headerFrame = inlineFrame?.offsetBy")
parts = {
    "__RESTART_TOPIC__": block(header, "private final class ChatRestartTopic :"),
    "__WIDTH__": block(bubbles, "static func desiredWidth(buttonSize:"),
    "__GEOMETRY__": block(bubbles, "func inlineHeaderFrame(for width:"),
    "__STATE_METHODS__": "\n".join(block(header, "var height:CGFloat" if name == "height" else "var " + name + ":") for name in ["monoforumHeight", "height", "primaryHeight", "secondaryHeight", "thirdHeight", "fourthHeight", "toleranceHeight", "canDisplayInline"]),
    "__INSETS__": "\n".join(block(controller, marker) for marker in ["private var headerHeight:", "private func inlineHeaderFrame(for width:", "private func updateHeaderInsets(width:"]),
    "__FRAME_EXPRESSION__": controller[frame_start:controller.index("\n            header.measure(", frame_start)],
    "__TRANSLATION_MENU__": "\n".join(line for line in source("ChatTranslationMenu").splitlines() if not line.startswith("import ")),
    "__TRANSLATION_TONE__": block(tone, "public enum TranslationTone:"),
    "__SEARCH_AUX__": "\n".join(block(search, marker) for marker in ["private var searchAccessoryWidth:", "private var visibleCountWidth:"]),
    "__SEARCH_WIDTH__": block(search, "private var searchWidth:"),
    "__SEARCH_LAYOUT__": block(search, "func updateLayout(size:"),
    "__ACTIVITY_UPDATE__": block(bubbles, "private func updateInputActivities()"),
    "__ACTIVITY_ATTACHMENT__": block(bubbles, "private func updateActivitiesAttachment("),
    "__ACTIVITY_REFRESH__": block(bubbles, "if inputActivities != nil, chatInteraction.mode != .scheduled"),
}
image_paths = {}
for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_ChatActions", "Icon_SearchArrow", "Icon_Calendar", "Icon_Pip_Close"]:
    imageset = dependency_root / "Telegram-Mac/Assets.xcassets" / (name + ".imageset")
    images = json.loads((imageset / "Contents.json").read_text())["images"]
    image = next(image for image in images if image.get("filename") and image.get("scale") == "1x")
    image_paths[name] = str(imageset / image["filename"])
parts["__IMAGE_PATHS__"] = "[" + ", ".join(json.dumps(name) + ": " + json.dumps(path) for name, path in image_paths.items()) + "]"

with tempfile.TemporaryDirectory(prefix="telegram-chat-header-") as directory:
    directory = Path(directory)
    dependencies = ", ".join(".package(path: " + json.dumps(str(dependency_root / "packages" / name)) + ")" for name in ["TGUIKit", "Translate", "ColorPalette"])
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatHeaderChecks", platforms: [.macOS(.v12)], dependencies: [DEPENDENCIES], targets: [
    .target(name: "ChatUI"),
    .testTarget(name: "ChatUITests", dependencies: ["ChatUI"]),
    .executableTarget(name: "HeaderIntegration", dependencies: [.product(name: "TGUIKit", package: "TGUIKit"), .product(name: "Translate", package: "Translate"), .product(name: "ColorPalette", package: "ColorPalette")])
])
'''.replace("DEPENDENCIES", dependencies))
    layout_dir = directory / "Sources/ChatUI"
    tests_dir = directory / "Tests/ChatUITests"
    integration_dir = directory / "Sources/HeaderIntegration"
    for path in [layout_dir, tests_dir, integration_dir]:
        path.mkdir(parents=True)
    shutil.copy2(source_root / "ChatHeaderInlineLayout.swift", layout_dir)
    shutil.copy2(root / "packages/ChatUI/Tests/ChatUITests/ChatHeaderInlineLayoutTests.swift", tests_dir)
    shutil.copy2(source_root / "ChatHeaderInlineLayout.swift", integration_dir)
    for name in ["HeaderFixture.swift", "NativeSearchFixture.swift", "ActivityFixture.swift", "UtilityHeaderFixture.swift", "main.swift"]:
        text = (fixtures / name).read_text()
        for marker, body in parts.items():
            text = text.replace(marker, body)
        (integration_dir / name).write_text(text)
    common = ["--package-path", str(directory), "--disable-sandbox", "--jobs", "2"]
    if args.scratch_path:
        common += ["--scratch-path", str(args.scratch_path.resolve())]
    print("Testing exact layout source and extracted header methods with native TGUIKit controls and Translate", flush=True)
    subprocess.run(["swift", "test"] + common, check=True)
    subprocess.run(["swift", "run"] + common + ["HeaderIntegration"], check=True)
