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
    return re.sub(r"\b(public|open|private)(\(set\))? ", "", text)


header = source("packages/ChatUI/Sources/ChatUI/ChatSearchHeader.swift")
view = source("packages/ChatUI/Sources/ChatUI/ChatSearchView.swift")
controller = source("packages/ChatUI/Sources/ChatUI/ChatController.swift")
base_view = source("packages/TGUIKit/Sources/SearchView.swift")
parts = {
    "__STATE__": header[header.index("private final class CSearchContextState"):header.index("private final class ChatSearchTagsView")],
    "__TOKEN_ENUM__": block(view, "enum TokenSearchState"),
    "__VIEW_ACTIONS__": "\n".join(block(view, marker) for marker in ["    override var isEmpty:", "    override func cancelSearch()", "    override func textView(", "    override func textDidChange(", "    func initToken()", "    func completeToken(", "    func completeEmojiToken(", "    func cancelEmojiToken("]),
    "__TOKEN_PUBLICATION__": view[view.index("    let tokenPromise:"):view.index("            switch tokenState {", view.index("    var tokenState:"))] + "\n        }\n    }",
    "__BASE_SET_STRING__": block(base_view, "    public func setString("),
    "__BASE_CANCEL__": block(base_view, "    open func cancelSearch()"),
    "__BASE_TEXT_CHANGE__": base_view[base_view.index("    open func textDidChange("):base_view.index("        _searchValue.set(value)") + len("        _searchValue.set(value)")] + "\n    }",
    "__MOVE_PEER__": block(header, "        self.chatInteraction.movePeerToInput ="),
    "__TOKEN_SUBSCRIPTION__": block(header, "        self.tokenDisposable.set(") + "))",
    "__SEARCH_INTERACTIONS__": header[header.index("        self.searchView.searchInteractions ="):header.index("        let apply = query.get()")],
    "__APPLY__": header[header.index("        let apply = query.get()"):header.index("        next.autohighlight =")],
    "__REMOVE__": block(header, "    func remove(animated:"),
    "__ENGINE_REQUEST__": block(controller, "}, searchRequest: {").split("searchRequest: ", 1)[1],
}
fixture = (fixtures / "SenderFilterTests.swift.in").read_text()
for marker, text in parts.items():
    fixture = fixture.replace(marker, clean(text))
if re.search(r"__[A-Z_]+__", fixture):
    raise RuntimeError("Unexpanded source marker")
result = {
    "revision": args.revision or "working-tree",
    "expected_regression": args.expect_regression,
    "source_sha256": manifest,
    "extracted_sha256": {marker: hashlib.sha256(clean(text).encode()).hexdigest() for marker, text in parts.items()},
    "jobs": 2,
}
logs = []
with tempfile.TemporaryDirectory(prefix="sender-filter-regression-") as temporary:
    directory = Path(temporary)
    (directory / "Tests").mkdir()
    (directory / "Tests/SenderFilterTests.swift").write_text(fixture)
    (directory / "Tests/Doubles.swift").write_text((fixtures / "Doubles.swift.in").read_text())
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SenderFilterRegression", platforms: [.macOS(.v12)], targets: [.testTarget(name: "SenderFilterTests", path: "Tests")])
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
