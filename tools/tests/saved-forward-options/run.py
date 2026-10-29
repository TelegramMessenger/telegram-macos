from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def declaration(source, marker):
    if source.count(marker) != 1:
        raise ValueError(f"Expected exactly one declaration: {marker}")
    start = source.index(marker)
    masked = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', lambda match: " " * len(match.group()), source, flags=re.S)
    opening = masked.index("{", start)
    depth = 1
    for index in range(opening + 1, len(masked)):
        if masked[index] == "{":
            depth += 1
        elif masked[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise ValueError(f"Unclosed declaration: {marker}")


def main():
    parser = argparse.ArgumentParser(description="Run extracted production forwarding methods with real SwiftSignalKit and boundary adapters.", epilog="No AppKit UI, option-menu interaction, live Postbox, network, or server acceptance is tested. Composer state and normal-controller factory behavior are boundary adapters, not extracted UI code. Sender tests inspect enqueue attributes, not wire serialization.")
    parser.add_argument("--source-revision", help="Read production sources using git show, without changing the working tree (negative control: f7d4e807).")
    parser.add_argument("--signal-kit", type=Path, help="SSignalKit package checkout; defaults to this worktree's submodule.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    dependency = (args.signal_kit or root / "submodules/telegram-ios/submodules/SSignalKit").resolve()
    if not (dependency / "Package.swift").is_file():
        parser.error("SSignalKit checkout missing; supply --signal-kit /path/to/SSignalKit")

    def read(path):
        if args.source_revision:
            return subprocess.check_output(["git", "-C", str(root), "show", f"{args.source_revision}:{path}"], text=True)
        return (root / path).read_text()

    share = read("packages/ShareUI/Sources/ShareUI/ShareModalController.swift")
    sender = read("packages/ChatHistoryModel/Sources/ChatHistoryModel/SenderController.swift")
    delivery = read("packages/ShareUI/Sources/ShareUI/ShareDeliveryResult.swift")
    controller = read("packages/ChatUI/Sources/ChatUI/ChatController.swift")
    navigation = read("packages/TGUIKit/Sources/MajorNavigationController.swift")
    assert "self.controller.ableToNextController(controller," in navigation
    replacements = {
        "__RECORDING_CONFIRM__": declaration(controller, "public func confirmDiscardRecordingIfNeeded("),
        "__NAVIGATION_GATE__": declaration(controller, "self.ableToNextController = {"),
        "__PERFORM_FORWARD__": declaration(share, "private func performForward("),
        "__FORWARD_RESULT__": declaration(share, "public enum ForwardMessagesResult"),
        "__SENDER_FORWARD__": declaration(sender, "public static func forwardMessages("),
        "__DELIVERY__": "\n\n".join(declaration(delivery, marker) for marker in ["enum ShareDeliveryStatus", "struct ShareDeliveryPart", "struct ShareRecipientDelivery", "func shareFirstResult<"]),
    }
    fixture = Path(__file__).with_name("SavedForwardOptionsTests.swift.in").read_text()
    print(f"Production sources: {args.source_revision or 'working tree'}", flush=True)
    print(f"SwiftSignalKit: {dependency}", flush=True)
    for placeholder, source in replacements.items():
        if fixture.count(placeholder) != 1:
            raise ValueError(f"Expected exactly one fixture placeholder: {placeholder}")
        print(f"{placeholder.strip('_')}: sha256 {hashlib.sha256(source.encode()).hexdigest()}", flush=True)
        fixture = fixture.replace(placeholder, source.removeprefix("public "))
    if re.search(r"__[A-Z_]+__", fixture):
        raise ValueError("Unexpanded fixture placeholder")
    with tempfile.TemporaryDirectory(prefix="saved-forward-options-") as temporary:
        directory = Path(temporary)
        (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SavedForwardOptions", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + json.dumps(str(dependency)) + ''')], targets: [.testTarget(name: "SavedForwardOptionsTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
        (directory / "Tests").mkdir()
        (directory / "Tests/SavedForwardOptionsTests.swift").write_text(fixture)
        report = directory / "results.xml"
        result = subprocess.run(["swift", "test", "--package-path", str(directory), "--disable-sandbox", "--jobs", "4", "--xunit-output", str(report)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end="", flush=True)
        if report.exists():
            cases = ET.parse(report).getroot().findall(".//testcase")
            failures = [case.attrib.get("name") for case in cases if case.find("failure") is not None or case.find("error") is not None]
        else:
            cases = []
            failures = []
        if not cases:
            cases = re.findall(r"^Test Case '(.+)' (passed|failed) ", result.stdout, flags=re.M)
            failures = [name for name, status in cases if status == "failed"]
        print(f"Regression summary: {len(cases)} tests, {len(failures)} failing tests", flush=True)
        for name in failures:
            print(f"FAIL {name}", flush=True)
        if not cases and result.returncode == 0:
            raise RuntimeError("Swift test exited successfully without reporting any XCTest cases")
        print("Scope: extracted production bodies; model/composer state, Postbox, navigation/controller factories, success UI, and enqueue boundaries are adapters. No full UI/server verification.", flush=True)
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
