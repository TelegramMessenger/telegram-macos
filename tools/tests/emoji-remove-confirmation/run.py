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
NAME = "emoji-remove-confirmation"
TEMPLATE = "EmojiRemoveConfirmationTests.swift.in"
EXPECTED_ASSERTIONS = 14
EXPECTED_SCENARIOS = 14
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


def english_value(data, key):
    lines = [line for line in data.decode("utf-16").splitlines() if line.startswith(f'"{key}" = ')]
    require(len(lines) == 1, f"Expected one English entry for {key}")
    return json.loads(lines[0].split(" = ", 1)[1].removesuffix(";"))


CONTROLLER = "packages/StickerSettingsUI/Sources/StickerSettingsUI/CustomEmojiController.swift"
LOCALIZATION = "packages/Localization/Sources/Localization/Localizable.swift"
RUNTIME = "packages/Localization/Sources/Localization/LocalizableExtension.swift"
ENGLISH = "Telegram-Mac/en.lproj/Localizable.strings"
EXPECTED_TEXT = "Are you sure you want to remove this emoji pack?"
ARCHIVE_TEXT = "This sticker set will be archived. You can quickly restore it later from the Archived Stickers section."


def extract(sources):
    source = sources.text(CONTROLLER)
    closure = body(source, "removePack: { id in")
    selected = re.findall(r"information: strings\(\)\.([A-Za-z0-9_]+)", closure)
    require(len(selected) == 1, "Expected exactly one confirmation accessor")
    selected = selected[0]
    localization = sources.text(LOCALIZATION)
    properties = {}
    for accessor in ["installedStickersRemoveDescription", selected, "installedStickersRemoveDelete", "alertCancel"]:
        lines = [line for line in localization.splitlines() if f"public static var {accessor}:" in line]
        require(len(lines) == 1, f"Missing production accessor: {accessor}")
        properties[accessor] = lines[0]
    keys = re.findall(r'L10n\.tr\("Localizable", "([^"]+)"\)', properties[selected])
    require(len(keys) == 1, "Expected a simple confirmation localization key")
    key = keys[0]
    english = sources.read(ENGLISH)
    require(english.startswith(b"\xff\xfe"), "English localization must retain its UTF-16LE BOM")
    selected_text = english_value(english, key)
    runtime = sources.text(RUNTIME)
    require('return _LocalizedStringFor(key, primary: primary, secondary: secondary)' in runtime,
            "The production translation path no longer uses the extracted lookup")
    require('Bundle.main.path(forResource: "en", ofType: "lproj")' in runtime, "Changed English fallback source")
    lookup = block(runtime, "internal func _LocalizedStringFor(")
    return {
        "__LOOKUP__": lookup,
        "__PROPERTIES__": "\n".join(properties.values()),
        "__TR_FUNCTION__": block(localization, "  private static func tr("),
        "__STRINGS_FUNCTION__": block(runtime, "public func strings() -> L10n.Type"),
        "__REMOVE_CLOSURE__": closure,
        "__SELECTED_ACCESSOR__": selected,
        "__KEY__": json.dumps(key),
        "__SELECTED_TEXT__": json.dumps(selected_text),
        "__EXPECTED_TEXT__": json.dumps(EXPECTED_TEXT),
        "__ARCHIVE_TEXT__": json.dumps(ARCHIVE_TEXT),
    }, {"en.lproj/Localizable.strings": english}


def expected_failures():
    return ["emoji-specific confirmation replaces archive promise"]


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
