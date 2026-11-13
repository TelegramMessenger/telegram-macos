import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
PREMIUM = "packages/PremiumUI/Sources/PremiumUI/"


def body(source, marker):
    start = source.index("{", source.index(marker)) + 1
    depth = 1
    for index in range(start, len(source)):
        depth += (source[index] == "{") - (source[index] == "}")
        if depth == 0:
            return source[start:index]
    raise AssertionError("Unclosed Swift body: " + marker)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--revision")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check-only", action="store_true")
    mode.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}

    def read(path):
        if args.revision:
            data = subprocess.check_output(["git", "-C", str(ROOT), "show", args.revision + ":" + path], env=environment)
        else:
            data = (ROOT / path).read_bytes()
        return data.decode("utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8")

    header = read(PREMIUM + "PremiumBoardingHeaderItem.swift")
    controller = read(PREMIUM + "PremiumBoardingController.swift")
    general = read("packages/GeneralRows/Sources/GeneralRows/GeneralRowItem.swift")
    fonts = read("packages/TGUIKit/Sources/TGFont.swift")
    strings = read("Telegram-Mac/en.lproj/Localizable.strings")
    call = re.search(r"return PremiumBoardingHeaderItem\([^\n]+", controller).group()
    argument = re.search(r"viewType: ([^,]+), sceneType:", call).group(1)
    selection = "let headerViewType: GeneralViewType = " + argument
    if argument == "headerViewType":
        start = controller.index("    let headerViewType: GeneralViewType")
        end = controller.index("    entries.append(", start)
        selection = controller[start:end].strip()
    selection += "\n    return headerViewType"
    super_init = re.search(r"        super.init\(initialSize, stableId: stableId[^\n]+", header).group().strip()
    make_size = body(header, "public override func makeSize(")
    height = body(header, "public override var height:")
    view_layout = body(header, "public override func layout()")

    if args.check_only:
        assert "state.source == .business_standalone || state.source == .business" in controller
        assert "if case .coin = scene" in selection
        assert "headerViewType = .singleItem" in selection
        assert "headerViewType = .legacy" in selection
        assert "viewType: viewType" in super_init
        assert "blockWidth - viewType.innerInset.left - viewType.innerInset.right" in make_size
        assert "titleLayout.measure(width: textWidth)" in make_size
        assert "infoLayout.measure(width: textWidth)" in make_size
        assert "titleLayout.layoutSize.height + 10 + infoLayout.layoutSize.height" in height
        assert "infoView.centerX(y: titleView.frame.maxY + 10)" in view_layout
        print("PASS: Business-only caller routing, viewType forwarding, constrained measurements, dynamic height and centering source contracts")
        print("No Swift compilation or native layout execution performed.")
        return

    temporary = None
    if args.output_dir is None:
        if args.prepare_only:
            parser.error("--prepare-only requires --output-dir")
        temporary = tempfile.TemporaryDirectory(prefix="business-header-layout-")
        output = Path(temporary.name)
    else:
        output = args.output_dir.absolute()
        try:
            output.mkdir(parents=True, exist_ok=False)
        except FileExistsError:
            parser.error("--output-dir must not already exist: " + str(output))

    def localized(key):
        return re.search(r'^"' + re.escape(key) + r'" = ("(?:[^"\\]|\\.)*");$', strings, re.MULTILINE).group(1)

    replacements = {
        "__INNER_INSET__": body(general, "public var innerInset:"),
        "__SINGLE_ITEM__": body(general, "public static var singleItem:"),
        "__VIEW_TYPE_SELECTION__": selection,
        "__BLOCK_WIDTH__": body(general, "open var blockWidth:"),
        "__SUPER_INIT__": super_init,
        "__MAKE_SIZE__": make_size,
        "__HEIGHT__": height,
        "__VIEW_LAYOUT__": view_layout,
        "__TITLE__": localized("PremiumBoarding.Business.TelegramBusiness"),
        "__PREMIUM_INFO__": localized("PremiumBoarding.Business.TelegramBusiness.HeaderInfo1"),
        "__NONPREMIUM_INFO__": localized("PremiumBoarding.Business.TelegramBusiness.HeaderInfo2"),
        "__HEADER_FONT_SIZE__": re.search(r"static let header: CGFloat = ([0-9.]+)", fonts).group(1),
        "__TEXT_FONT_SIZE__": re.search(r"static let text: CGFloat = ([0-9.]+)", fonts).group(1),
    }
    swift = Path(__file__).with_name("BusinessHeaderLayoutTests.swift.in").read_text()
    for key, value in replacements.items():
        swift = swift.replace(key, value)
    assert not re.search(r"__[A-Z_]+__", swift)
    source = output / "BusinessHeaderLayoutTests.swift"
    source.write_text(swift)
    binary = output / "BusinessHeaderLayoutTests"
    command = ["xcrun", "swiftc", "-module-cache-path", str(output / "module-cache"), str(source), "-o", str(binary)]
    print("Source-extracted layout contract test with native CoreText; not a Telegram view, SceneKit render, or account test.", flush=True)
    if args.prepare_only:
        print("Prepared " + str(source))
        print("Deferred compiler command: " + " ".join(command))
        return
    try:
        subprocess.run(command, check=True, env=environment)
        subprocess.run([str(binary)], check=True, env=environment)
    finally:
        if temporary is not None:
            temporary.cleanup()


if __name__ == "__main__":
    main()
