import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--revision")
parser.add_argument("--expect-regression", action="store_true")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
if args.expect_regression and not args.revision:
    parser.error("--expect-regression requires --revision")
if args.output:
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
manifest = {}


def source(path):
    if args.revision:
        text = subprocess.check_output(["git", "-C", str(root), "show", args.revision + ":" + path], env=environment, text=True)
    else:
        text = (root / path).read_text()
    manifest[path] = hashlib.sha256(text.encode()).hexdigest()
    return text


def block(text, marker):
    start = text.index(marker)
    end = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


def clean(text):
    text = "\n".join(line for line in text.splitlines() if not line.startswith("import "))
    return re.sub(r"\b(public|open|private)(\(set\))? ", "", text)


settings = source("packages/SettingsUI/Sources/SettingsUI/EditAccountInfoController.swift")
hooks = source("packages/SettingsUI/Sources/SettingsUI/SettingsNavigationHooks.swift")
install = source("Telegram-Mac/packages-integration/hooks/SettingsHooksInstall.swift")
privacy = source("packages/SettingsUI/Sources/SettingsUI/SelectivePrivacySettingsController.swift")
calendar = source("packages/CalendarUI/Sources/CalendarUI/CalendarController.swift")
month = source("packages/CalendarUI/Sources/CalendarUI/CalendarMonthController.swift")
birthday = source("packages/TelegramUtils/Sources/TelegramUtils/TelegramBirthday.swift")
extras = source("packages/TelegramUtils/Sources/TelegramUtils/CoreTypeExtras.swift")
month_start = month.index("open class CalendarMonthController:")
month_end = month.index("    open override func getCenterBarViewOnce()", month_start)
parts = {
    "__HOOK__": next(line for line in hooks.splitlines() if "var makeBirthdayCalendarController:" in line),
    "__INSTALL__": block(install, "    hooks.makeBirthdayCalendarController ="),
    "__OPEN__": block(settings, "}, birthday: {").split("birthday: ", 1)[1],
    "__PRIVACY__": block(privacy, "}, setupBirthday: {").split("setupBirthday: ", 1)[1],
    "__DATE_FOR_PICKER__": block(birthday, "    var dateForPicker:"),
    "__BIRTHDAY__": block(extras, "public extension Date {"),
    "__CONTROLLER__": calendar,
    "__INTERACTIONS__": block(month, "public struct CalendarMonthInteractions"),
    "__MONTH__": block(month, "public final class CalendarMonthStruct"),
    "__MONTH_CONTROLLER__": month[month_start:month_end] + block(month, "    open var isNextEnabled:") + "\n" + block(month, "    open var isPrevEnabled:") + "\n}",
}
fixture = (fixtures / "BirthdayPickerTests.swift.in").read_text()
for marker, text in parts.items():
    fixture = fixture.replace(marker, clean(text))
if re.search(r"__[A-Z_]+__", fixture):
    raise RuntimeError("Unexpanded source marker")
headers = {name: source("packages/CalendarUtils/Sources/CalendarUtils/" + name) for name in ["CalendarUtils.h", "CalendarUtils.m"]}
logs = []
result = {
    "revision": args.revision or "working-tree",
    "expected_regression": args.expect_regression,
    "source_sha256": manifest,
    "extracted_sha256": {marker: hashlib.sha256(clean(text).encode()).hexdigest() for marker, text in parts.items()},
    "jobs": 2,
}
with tempfile.TemporaryDirectory(prefix="birthday-picker-regression-") as temporary:
    directory = Path(temporary)
    (directory / "Tests").mkdir()
    (directory / "Tests/BirthdayPickerTests.swift").write_text(fixture)
    (directory / "CalendarUtils").mkdir()
    for name, text in headers.items():
        (directory / "CalendarUtils" / name).write_text(text)
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BirthdayPickerRegression", platforms: [.macOS(.v12)], targets: [.target(name: "CalendarUtils", path: "CalendarUtils", publicHeadersPath: "."), .testTarget(name: "BirthdayPickerTests", dependencies: ["CalendarUtils"], path: "Tests")])
''')
    environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(directory / "swift-cache")
    base = ["swift", "test", "--package-path", str(directory), "--scratch-path", str(directory / "build"), "--cache-path", str(directory / "cache"), "--config-path", str(directory / "config"), "--security-path", str(directory / "security"), "--disable-sandbox", "--jobs", "2"]
    build = subprocess.run(base + ["list"], cwd=directory, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    logs.append(("build.log", build.stdout))
    result["build_exit"] = build.returncode
    if build.returncode == 0:
        tests = subprocess.run(base + ["--skip-build"], cwd=directory, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        logs.append(("tests.log", tests.stdout))
        result["test_exit"] = tests.returncode
        result["assertion_failure"] = "XCTAssert" in tests.stdout and "failed" in tests.stdout
        result["accepted"] = tests.returncode != 0 and result["assertion_failure"] if args.expect_regression else tests.returncode == 0
    else:
        result["accepted"] = False
    for name, log in logs:
        print(log)
        if args.output:
            (args.output / name).write_text(log.replace(str(directory), "<temporary>"))
if args.output:
    (args.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
raise SystemExit(0 if result["accepted"] else 1)
