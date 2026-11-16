import argparse
import fcntl
import hashlib
import json
import platform
import re
import shutil
import subprocess
from pathlib import Path

BASE = "246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5"
CORE = "24638bc69bd083981b178dd1e7f921eebbf7fc46"
CHAT = "packages/ChatUI/Sources/ChatUI/"
CORE_FILE = "submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaFile.swift"
API_FILE = "submodules/TelegramCore/Sources/ApiUtils/TelegramMediaFile.swift"


def command(args):
    return subprocess.check_output(args, text=True).strip()


def git_source(root, revision, path):
    return subprocess.check_output(["git", "-C", str(root), "show", f"{revision}:{path}"], text=True)


def between(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def block(text, marker):
    begin = text.index(marker)
    opening = text.index("{", begin)
    depth = 1
    position = opening + 1
    while depth:
        if text[position] == "{":
            depth += 1
        elif text[position] == "}":
            depth -= 1
        position += 1
    return text[begin:position]


def internal(text):
    return re.sub(r"\bpublic\s+", "", text)


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--dependency-root", type=Path)
    parser.add_argument("--compiler-lock", type=Path)
    args = parser.parse_args()
    root = args.source_root.resolve()
    harness_root = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    if not root.is_dir():
        parser.error("--source-root must be an existing checkout directory")
    if output == root or root.is_relative_to(output) or output.is_relative_to(root) or output == harness_root or harness_root.is_relative_to(output) or output.is_relative_to(harness_root):
        parser.error("--output must be outside and must not contain either source checkout")
    output.mkdir(parents=True, exist_ok=True)
    compiler_lock = args.compiler_lock.resolve() if args.compiler_lock else output / "compiler.lock"
    if compiler_lock.is_dir() or compiler_lock.is_relative_to(root) or compiler_lock.is_relative_to(harness_root):
        parser.error("--compiler-lock must be a file outside both source checkouts")
    dependency_root = args.dependency_root.resolve() if args.dependency_root else root
    if not dependency_root.is_dir() or output == dependency_root or dependency_root.is_relative_to(output) or output.is_relative_to(dependency_root):
        parser.error("--dependency-root must exist outside --output")
    if compiler_lock.is_relative_to(dependency_root):
        parser.error("--compiler-lock must be outside the dependency checkout")
    common = Path(command(["git", "-C", str(harness_root), "rev-parse", "--path-format=absolute", "--git-common-dir"]))
    core_git = common / "modules/submodules/telegram-ios"
    if not core_git.exists():
        core_git = Path(command(["git", "-C", str(harness_root / "submodules/telegram-ios"), "rev-parse", "--absolute-git-dir"]))

    def core_source(path):
        return subprocess.check_output(["git", f"--git-dir={core_git}", "show", f"{CORE}:{path}"], text=True)

    core = core_source(CORE_FILE)
    api = core_source(API_FILE)
    namespaces = core_source("submodules/TelegramCore/Sources/SyncCore/SyncCore_Namespaces.swift")
    attributes = between(core, "    case FileName(fileName:", "    public init(decoder:")
    core_properties = "\n".join(block(core, marker) for marker in [
        "public var fileName:", "private var isSecretChatTgs:", "public var isSticker:",
        "public var isStaticSticker:", "public var isVideo:", "public var isInstantVideo:",
        "public var isAnimated:", "public var isAnimatedSticker:", "public var isVideoSticker:",
        "public var isCustomEmoji:", "public var isMusic:", "public var isVoice:",
    ])
    template = Path(__file__).with_name("StickerDocumentFallbackTests.swift.in").read_text()
    source_hashes = {}
    paths = [CHAT + name for name in ["ChatLayoutUtils.swift", "ChatRowItem.swift", "ChatMediaItem.swift", "StickerMediaContentView.swift", "ChatMediaLayoutParameters.swift", "ChatFileMediaItem.swift"]]
    paths += ["packages/TelegramMediaUtils/Sources/TelegramMediaUtils/CoreMediaResourceExtensions.swift", "packages/TelegramMediaUtils/Sources/TelegramMediaUtils/FetchCachedRepresentations.swift", "packages/TelegramUtils/Sources/TelegramUtils/InlineMediaAttributes.swift", "packages/TelegramUtils/Sources/TelegramUtils/StickerImage.swift", "packages/TelegramTheme/Sources/TelegramTheme/ChatTypeExtensions.swift", "packages/TGUIKit/Sources/Extensions.swift"]
    variants = {}
    for variant in ["baseline", "fixed"]:
        sources = {}
        for path in paths:
            local = root / path
            sources[path] = local.read_text() if variant == "fixed" and local.exists() else git_source(harness_root, BASE, path)
        source_hashes[variant] = {path: sha(text) for path, text in sources.items()}
        row = sources[CHAT + "ChatRowItem.swift"]
        layout = sources[CHAT + "ChatLayoutUtils.swift"]
        media = sources[CHAT + "ChatMediaItem.swift"]
        sticker = sources[CHAT + "StickerMediaContentView.swift"]
        extensions = sources["packages/TGUIKit/Sources/Extensions.swift"]
        factory = between(row, "                    if file.isVideoSticker {", "                } else if let story = message.media[0]")
        bubble = between(block(row, "public static func hasBubble("), "            if let file = media as? TelegramMediaFile {", "            if media is TelegramMediaDice")
        overlay = between(block(row, "        var isStateOverlayLayout: Bool {"), "                if let file = media as? TelegramMediaFile {", "                if media is TelegramMediaDice")
        caption = between(media, "        var canAddCaption: Bool = true", "        if media is TelegramMediaDice")
        renderer = between(sticker, "        var contentClass: ChatMediaContentView.Type", "        if content == nil")
        preview = between(media, "                    if file.isVideoSticker && !file.isWebm {", "                }\n            } else if contentNode is VideoStickerContentView")
        file_size = between(layout, "            var contentSize:NSSize = NSZeroSize", "        } else if let media = media as? TelegramMediaMap")
        content_node = block(layout, "public static func contentNode(")
        helper = block(layout, "extension TelegramMediaFile {") if "var isChatStaticSticker:" in layout else ""
        resource = block(sources["packages/TelegramUtils/Sources/TelegramUtils/StickerImage.swift"], "public func chatMessageStickerResource(")
        filename = between(sources[CHAT + "ChatMediaLayoutParameters.swift"], '            var fileName:String = "Unknown.file"', "            return ChatFileLayoutParameters(")
        html = git_source(harness_root, BASE, "packages/HTMLBubbles/Sources/HTMLBubbles/HTMLDocumentBubbles.swift")
        html_max_size = next(line.strip() for line in html.splitlines() if "public static let maxSize:" in line)
        decode = next(line.strip() for line in block(sources["packages/TelegramMediaUtils/Sources/TelegramMediaUtils/FetchCachedRepresentations.swift"], "private func fetchCachedStickerAJpegRepresentation(").splitlines() if "let image = convertFromWebP(data)" in line)
        pieces = {
            "__ATTRIBUTES__": attributes,
            "__FLAGS__": block(core, "public struct TelegramMediaVideoFlags:"),
            "__MEDIA_NAMESPACES__": block(namespaces, "public struct Media {"),
            "__CORE_PROPERTIES__": core_properties,
            "__DIMENSIONS_FUNCTION__": block(api, "func dimensionsForFileAttributes("),
            "__DIMENSIONS__": block(api, "var dimensions: PixelDimensions? {"),
            "__EMOJI_PREDICATE__": block(sources["packages/TelegramTheme/Sources/TelegramTheme/ChatTypeExtensions.swift"], "var isEmojiAnimatedSticker:"),
            "__WEBM__": block(sources["packages/TelegramUtils/Sources/TelegramUtils/InlineMediaAttributes.swift"], "var isWebm:"),
            "__PROBABLY_STICKER__": block(sources["packages/TelegramMediaUtils/Sources/TelegramMediaUtils/CoreMediaResourceExtensions.swift"], "var probablySticker:"),
            "__HELPER__": helper,
            "__FACTORY__": factory,
            "__ROW_IS_STICKER__": block(row, "public var isSticker: Bool {"),
            "__BUBBLE__": bubble,
            "__OVERLAY__": overlay,
            "__CAPTION__": caption,
            "__RENDERER__": renderer,
            "__PREVIEW__": preview,
            "__FILE_SIZE__": file_size,
            "__CONTENT_NODE__": content_node,
            "__GEOMETRY__": block(extensions, "func aspectFitted(") + "\n" + block(extensions, "func fitted("),
            "__IMAGE_ACCESSOR__": block(extensions, "var _cgImage:"),
            "__RESOURCE__": resource,
            "__FILENAME__": filename,
            "__HTML_ELIGIBILITY__": html_max_size + "\n" + block(html, "public static func isHTMLDocument("),
            "__DECODE__": decode,
        }
        fixture = template
        for marker, text in pieces.items():
            if fixture.count(marker) != 1:
                raise RuntimeError(f"Template marker mismatch: {marker}")
            fixture = fixture.replace(marker, internal(text))
        if re.search(r"__[A-Z_]+__", fixture):
            raise RuntimeError("Unexpanded template marker")
        destination = output / variant
        destination.mkdir(exist_ok=True)
        (destination / "main.swift").write_text(fixture)
        variants[variant] = destination

    codec = output / "codec"
    codec.mkdir(exist_ok=True)
    codec_hashes = {}
    for name in ["libwebp.m", "libwebp.h", "WebPImageCoder.m", "WebPImageCoder.h"]:
        path = "submodules/libwebp/Sources/" + name
        source = git_source(harness_root, BASE, path)
        (codec / name).write_text(source)
        codec_hashes[path] = sha(source)
    (codec / "Bridge.h").write_text('#import "libwebp.h"\n#import "encode.h"\n')
    dependency = dependency_root / "core-xprojects/libwebp/build"
    includes = dependency / "libwebp-master/src/webp"
    libraries = [dependency / platform.machine() / name for name in ["libwebpdemux.a", "libwebp.a", "libsharpyuv.a"]]
    for path in [includes / "encode.h", *libraries]:
        if not path.is_file():
            raise RuntimeError(f"Missing native codec dependency: {path}")
    report = {
        "base": BASE, "core": CORE, "source_root": str(root), "core_git": str(core_git),
        "source_sha256": source_hashes,
        "core_sha256": {CORE_FILE: sha(core), API_FILE: sha(api)},
        "codec_source_sha256": codec_hashes,
        "codec_archives": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in libraries},
        "compiler_lock": str(compiler_lock), "harness_root": str(harness_root), "dependency_root": str(dependency_root), "variants": {},
    }

    def run_logged(argv, log):
        result = subprocess.run([str(value) for value in argv], capture_output=True, text=True)
        log.write_text(result.stdout + result.stderr)
        return result

    compiler_lock.parent.mkdir(parents=True, exist_ok=True)
    with compiler_lock.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            objects = []
            for name in ["libwebp", "WebPImageCoder"]:
                obj = codec / (name + ".o")
                result = run_logged(["xcrun", "clang", "-fobjc-arc", "-fmodules", "-fmodules-cache-path=" + str(output / "clang-cache"), "-I", includes, "-I", codec, "-c", codec / (name + ".m"), "-o", obj], codec / (name + "-compile.log"))
                if result.returncode:
                    raise RuntimeError(f"Codec compilation failed: {codec / (name + '-compile.log')}")
                objects.append(obj)
            version = subprocess.run(["xcrun", "swiftc", "--version"], capture_output=True, text=True, check=True)
            report["compiler"] = (version.stdout + version.stderr).strip()
            for variant, destination in variants.items():
                argv = ["xcrun", "swiftc", "-j1", "-Onone", "-module-cache-path", output / "swift-cache", "-import-objc-header", codec / "Bridge.h", "-Xcc", "-I" + str(includes), "-framework", "AppKit", "-framework", "ImageIO", "-framework", "Accelerate", destination / "main.swift", *objects, *libraries, "-o", destination / "tests"]
                compiled = run_logged(argv, destination / "compile.log")
                result = {"compile_exit": compiled.returncode, "compile_command": [str(value) for value in argv]}
                report["variants"][variant] = result
                if compiled.returncode:
                    break
                tested = run_logged([destination / "tests"], destination / "run.log")
                result["run_exit"] = tested.returncode
                try:
                    result["assertions"] = json.loads(tested.stdout)
                except json.JSONDecodeError:
                    result["output_error"] = tested.stdout + tested.stderr
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
    for name in ["clang-cache", "swift-cache"]:
        shutil.rmtree(output / name, ignore_errors=True)
    baseline = report["variants"].get("baseline", {})
    fixed = report["variants"].get("fixed", {})
    baseline_checks = baseline.get("assertions", {})
    fixed_checks = fixed.get("assertions", {})
    expected_failures = {f"{name}: {check}" for name in ["lower-bound", "bounded-webp", "upper-bound", "no-dimensions", "secret-file-webp"] for check in ["row", "sticker-state", "bubble", "overlay", "caption", "renderer", "preview", "size"]}
    report["expected_baseline_failures"] = sorted(expected_failures)
    report["success"] = baseline.get("compile_exit") == 0 and baseline.get("run_exit") == 1 and set(baseline_checks.get("failures", [])) == expected_failures and fixed.get("compile_exit") == 0 and fixed.get("run_exit") == 0 and fixed_checks.get("failed") == 0 and fixed_checks.get("passed", 0) > 0
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"success": report["success"], "baseline": baseline_checks, "fixed": fixed_checks, "report": str(output / "results.json")}, indent=2))
    raise SystemExit(0 if report["success"] else 1)


if __name__ == "__main__":
    main()
