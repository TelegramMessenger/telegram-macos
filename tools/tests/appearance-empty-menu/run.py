import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


BASELINE = "c64a3ea77750fa753da0913cf26610df9b237640"
NAME = "appearance-empty-menu"
TEMPLATE = "AppearanceEmptyMenuTests.swift.in"
EXPECTED_ASSERTIONS = 411
EXPECTED_SCENARIOS = 94
ENV = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}


def digest(data):
    return hashlib.sha256(data).hexdigest()


class Sources:
    def __init__(self, root, revision=None):
        self.root = root
        self.revision = revision
        self.files = {}
        self.contracts = {}

    def read(self, path):
        if path not in self.files:
            if self.revision is None:
                self.files[path] = (self.root / path).read_bytes()
            else:
                self.files[path] = subprocess.check_output(
                    ["git", "-C", str(self.root), "show", f"{self.revision}:{path}"], env=ENV
                )
        return self.files[path]

    def text(self, path):
        return self.read(path).decode("utf-8")

    def hashes(self):
        return {path: digest(data) for path, data in sorted(self.files.items())}


def block(text, marker, unique=True):
    if unique and text.count(marker) != 1:
        raise ValueError(f"Expected one source anchor: {marker}")
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    index = opening + 1
    while depth and index < len(text):
        depth += (text[index] == "{") - (text[index] == "}")
        index += 1
    if depth:
        raise ValueError(f"Unclosed source block: {marker}")
    return text[start:index]


def body(text, marker, unique=True):
    result = block(text, marker, unique)
    return result[result.index("{"):]


def require(value, message):
    if not value:
        raise ValueError(message)


APPEARANCE = "packages/SettingsUI/Sources/SettingsUI/AppAppearanceViewController.swift"
INPUT = "packages/InputDataUI/Sources/InputDataUI/InputDataController.swift"
NAVIGATION = "packages/TGUIKit/Sources/NavigationBarView.swift"


def without_handlers(source):
    while "handler: {" in source:
        start = source.index("handler: {")
        handler = body(source[start:], "handler:", unique=False)
        source = source[:start] + source[start:].replace("handler: " + handler, "handler:{}", 1)
    return source


def extract(sources):
    source = sources.text(APPEARANCE)
    input_data = sources.text(INPUT).split("public class InputDataController:", 1)[1]
    navigation = sources.text(NAVIGATION)
    factory = body(source, 'identifier: "app_appearance", customRightButton:')
    updater = body(source, "controller.updateRightBarView =")
    menu = body(factory, "view.button.contextMenu =")
    sources.contracts["menu_with_action_handlers_sha256"] = digest(menu.encode())
    theme_update = body(input_data, "public override func updateLocalizationAndTheme(")
    right_update = body(input_data, "public override func requestUpdateRightBar()")
    callback = body(input_data, "appearanceDisposablet.set(appearanceSignal.start(next:")
    opacity = "right.layer?.opacity = 0"
    require(navigation.count(opacity) == 1, "Missing navigation opacity preparation")
    animation = navigation[navigation.index(opacity):].splitlines()[0] + "\n" + block(navigation, "if !right.isHidden")
    require("requestUpdateRightBar()" in theme_update, "Theme update no longer refreshes the bar")
    require("self.updateRightBarView?(self.rightBarView)" in right_update, "Missing bar updater invocation")
    require("self?.updateLocalizationAndTheme(theme: theme)" in callback, "Missing appearance callback")
    global_theme = sources.text("packages/TelegramTheme/Sources/TelegramTheme/AppearanceGlobal.swift")
    theme_signal = sources.text("packages/TelegramTheme/Sources/TelegramTheme/TelegramPresentationTheme.swift")
    theme_apply = sources.text("packages/TelegramTheme/Sources/TelegramTheme/Appearance.swift")
    require("combineLatest(languageSignal, themeSignal," in body(global_theme, "public var appearanceSignal:"), "Missing appearance/theme signal composition")
    require("_themeSignal.get() |> distinctUntilChanged |> deliverOnMainQueue" in body(theme_signal, "public var themeSignal:"), "Changed theme signal delivery")
    apply = body(theme_apply, "public func telegramUpdateTheme(")
    require(apply.index("updateTheme(theme)") < apply.index("_themeSignal.set(theme)"), "Theme must update before signal emission")
    image_bar = sources.text("packages/TGUIKit/Sources/ImageBarView.swift")
    image_button = sources.text("packages/TGUIKit/Sources/ImageButton.swift")
    require("button.setGlassEffect()" in image_bar and "addSubview(button)" in image_bar, "Changed glass owner")
    require("self.addSubview(glass, positioned: .below, relativeTo: imageView)" in image_button, "Changed glass parent")
    return {
        "__FACTORY__": without_handlers(factory),
        "__UPDATER__": updater,
        "__THEME_UPDATE__": theme_update,
        "__RIGHT_UPDATE__": right_update,
        "__APPEARANCE_CALLBACK__": callback,
        "__ANIMATION__": animation,
    }, {}


def expected_failures():
    failures = [f"initial-system-cloud{cloud}-accent{accent}/visibility"
                for cloud in ["false", "true"] for accent in ["false", "true"]]
    failures.append("animated-entry-system/visibility")
    failures += [f"live-switch-{initial}-step{step}-to-system-cloud{cloud}-accent{accent}/visibility"
                 for initial in ["system", "day"] for step in [0, 2, 6, 7]
                 for cloud in ["false", "true"] for accent in ["false", "true"]]
    return failures


def compile_and_run(sources, output, frameworks, libraries):
    output.mkdir()
    replacements, resources = extract(sources)
    template = Path(__file__).with_name(TEMPLATE).read_text()
    generated = template
    for marker, value in replacements.items():
        require(marker in generated, f"Missing template marker: {marker}")
        generated = generated.replace(marker, value)
    require(re.search(r"__[A-Z_]+__", generated) is None, "Unresolved template marker")
    source = output / "main.swift"
    source.write_text(generated)
    arguments = []
    for path, data in resources.items():
        destination = output / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    if resources:
        arguments.append(str(output / "en.lproj"))
    result = {
        "source_revision": sources.revision or "working-tree",
        "source_sha256": sources.hashes(),
        "extracted_sha256": {key: digest(value.encode()) for key, value in replacements.items()},
        "template_sha256": digest(template.encode()),
        "generated_sha256": digest(generated.encode()),
        "source_contracts": sources.contracts,
    }
    with tempfile.TemporaryDirectory(prefix="compiler-", dir=output) as temporary:
        temporary = Path(temporary)
        executable = temporary / "tests"
        command = [
            "xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5",
            "-module-cache-path", str(temporary / "module-cache"),
            "-F", str(frameworks), "-I", str(libraries), "-L", str(libraries),
            "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
            "-Xlinker", "-rpath", "-Xlinker", str(libraries),
            str(source), "-o", str(executable),
        ]
        compiled = subprocess.run(command, capture_output=True, text=True, env=ENV, cwd=output)
        (output / "compile.log").write_text(compiled.stdout + compiled.stderr)
        result.update(compile_command=command, compile_exit=compiled.returncode)
        if compiled.returncode != 0:
            (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            raise RuntimeError(f"Compilation failed; this is not a negative control: {output / 'compile.log'}")
        tested = subprocess.run([str(executable), *arguments], capture_output=True, text=True, env=ENV, cwd=output)
        (output / "tests.log").write_text(tested.stdout + tested.stderr)
        lines = [line[7:] for line in tested.stdout.splitlines() if line.startswith("RESULT ")]
        require(len(lines) == 1, "Native test process did not produce exactly one RESULT record")
        result.update(json.loads(lines[0]), exit_code=tested.returncode)
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    require(result["test_cases"] == 1, "The XCTest method did not execute exactly once")
    require(result["scenarios"] == EXPECTED_SCENARIOS, "Unexpected scenario count")
    require(result["assertions"] == EXPECTED_ASSERTIONS, "Unexpected assertion count")
    require(result["xctest_failures"] == len(result["failures"]), "XCTest and labelled assertion failures disagree")
    return result


def run_tests(args, output):
    platform = Path(subprocess.check_output(
        ["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], env=ENV, text=True
    ).strip())
    frameworks = platform / "Developer/Library/Frameworks"
    libraries = platform / "Developer/usr/lib"
    require((frameworks / "XCTest.framework").is_dir(), "Select a full Xcode installation containing XCTest")
    version = subprocess.run(["xcrun", "swiftc", "--version"], env=ENV, capture_output=True, text=True, check=True)
    (output / "toolchain.log").write_text(version.stdout + version.stderr)
    variants = [("fixed", Sources(args.root))]
    if args.baseline:
        revision = subprocess.check_output(
            ["git", "-C", str(args.root), "rev-parse", "--verify", "--end-of-options", f"{args.baseline}^{{commit}}"],
            env=ENV, text=True,
        ).strip()
        require(revision == BASELINE, f"The recorded negative control must resolve to {BASELINE}")
        variants.append(("baseline", Sources(args.root, revision)))
    results = {}
    for label, sources in variants:
        results[label] = compile_and_run(sources, output / label, frameworks, libraries)
        result = results[label]
        expected = [] if label == "fixed" else expected_failures()
        matched = sorted(result["failures"]) == sorted(expected)
        matched = matched and result["exit_code"] == (1 if expected else 0)
        result["expectation_matched"] = matched
        print(f"{label}: {result['test_cases']} XCTest method, {result['scenarios']} scenarios, "
              f"{result['assertions']} assertions, {len(result['failures'])} failed assertions; "
              f"{'expected' if matched else 'UNEXPECTED'}", flush=True)
    if "baseline" in results:
        require(results["fixed"]["source_contracts"] == results["baseline"]["source_contracts"],
                "A source contract outside the tested change differs from the original baseline")
    summary = {"name": NAME, "baseline_commit": BASELINE, "results": results}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if all(result["expectation_matched"] for result in results.values()) else 1


def run(args, output):
    with tempfile.TemporaryDirectory(prefix="process-", dir=output) as temporary:
        ENV["TMPDIR"] = temporary
        return run_tests(args, output)


def main():
    if not sys.flags.isolated:
        raise SystemExit("Run this script with python3 -I")
    parser = argparse.ArgumentParser(description=f"Offline native XCTest regressions: {NAME}")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--baseline", metavar="REV", help="Also run the original c64a3ea7 negative control without a checkout")
    parser.add_argument("--output", type=Path, help="Preserve source, logs, and JSON in a new directory; its parent must exist")
    args = parser.parse_args()
    args.root = args.root.resolve()
    try:
        if args.output is not None:
            output = args.output.absolute()
            output.mkdir(exist_ok=False)
            return run(args, output)
        with tempfile.TemporaryDirectory(prefix=NAME + "-") as temporary:
            return run(args, Path(temporary))
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"SETUP/EXECUTION ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
