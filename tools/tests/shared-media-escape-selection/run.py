import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[3]
SOURCES = {
    "window": "packages/TGUIKit/Sources/Window.swift",
    "navigation": "packages/TGUIKit/Sources/MajorNavigationController.swift",
    "base": "packages/TGUIKit/Sources/ViewController.swift",
    "editable": "packages/TelegramUtils/Sources/TelegramUtils/ControllerExtension.swift",
    "profile": "packages/PeerInfoUI/Sources/PeerInfoUI/PeerInfoController.swift",
    "media": "packages/PeerInfoUI/Sources/PeerInfoUI/PeerMediaController.swift",
    "story": "packages/StoriesUI/Sources/StoriesUI/StoryMediaController.swift",
    "input": "packages/InputDataUI/Sources/InputDataUI/InputDataController.swift",
    "search": "packages/TGUIKit/Sources/SearchView.swift",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def unique_index(source, anchor):
    if source.count(anchor) != 1:
        raise ValueError(f"Expected exactly one source anchor: {anchor!r}")
    return source.index(anchor)


def block_end(source, opening):
    depth = 0
    index = opening
    state = "code"
    comment_depth = 0
    while index < len(source):
        pair = source[index:index + 2]
        char = source[index]
        if state == "line":
            if char == "\n":
                state = "code"
        elif state == "comment":
            if pair == "/*":
                comment_depth += 1
                index += 1
            elif pair == "*/":
                comment_depth -= 1
                index += 1
                if comment_depth == 0:
                    state = "code"
        elif state == "string":
            if char == "\\":
                index += 1
            elif char == '"':
                state = "code"
        elif pair == "//":
            state = "line"
            index += 1
        elif pair == "/*":
            state = "comment"
            comment_depth = 1
            index += 1
        elif char == '"':
            state = "string"
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    raise ValueError("Unbalanced source block")


def output_directory(value):
    if ".." in value.parts:
        raise ValueError("Output path must not contain parent traversal")
    path = Path(os.path.abspath(value))
    for component in (path, *path.parents):
        if component.is_symlink():
            raise ValueError(f"Output path must not contain symlinks: {component}")
    if path.exists():
        raise ValueError(f"Output directory must be new: {path}")
    if not path.parent.is_dir():
        raise ValueError(f"Output parent must already exist: {path.parent}")
    path.mkdir(mode=0o700)
    return path


def main():
    parser = argparse.ArgumentParser(description="Compile and run extracted shared-media Escape routing with explicit boundary doubles.")
    parser.add_argument("--revision", help="Read production sources from this git revision instead of the working tree")
    parser.add_argument("--output", type=Path, help="Retain artifacts in a new directory with no symlink path components")
    args = parser.parse_args()
    if not sys.flags.isolated:
        parser.error("Run this script with python3 -I")

    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    revision = None
    if args.revision:
        revision = subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "--verify", "--end-of-options", args.revision + "^{commit}"],
            text=True, env=environment,
        ).strip()
    sources = {}
    for name, path in SOURCES.items():
        data = subprocess.check_output(["git", "-C", str(ROOT), "show", f"{revision}:{path}"], env=environment) if revision else (ROOT / path).read_bytes()
        sources[name] = data.decode("utf-8")

    extracts = []

    def extract(name, anchor, until=None):
        source = sources[name]
        start = unique_index(source, anchor)
        end = source.index(until, start + len(anchor)) if until else block_end(source, source.index("{", start))
        if end <= start:
            raise ValueError(f"Invalid extraction range: {anchor!r}")
        original = source[start:end]
        extracts.append({
            "path": SOURCES[name], "anchor": anchor,
            "start_line": source.count("\n", 0, start) + 1,
            "end_line": source.count("\n", 0, end) + 1,
            "sha256": digest(original.encode()),
        })
        return re.sub(r"\b(public|private|fileprivate|open)\s+(?=(?:override\s+)?(?:func|var|enum|class|init))", "", original)

    parts = {
        "WINDOW_TYPES": "\n".join([
            extract("window", "public enum HandlerPriority", "public enum SwipeType"),
            extract("window", "class ResponderObserver", "class MouseObserver"),
            extract("window", "class MouseObserver", "public typealias SwipeIdentifier"),
            extract("window", "public enum KeyHandlerResult"),
        ]),
        "WINDOW_METHODS": "\n".join(extract("window", anchor) for anchor in [
            "public func set(responder:", "public func set(handler:", "public func set(escape ",
            "public func removeAllHandlers(", "private func cleanUndefinedHandlers()",
            "public func applyResponderIfNeeded(", "open override func sendEvent(",
        ]),
        "BASE_ESCAPE": extract("base", "    open func escapeKeyAction()"),
        "EDITABLE_STATE": extract("editable", "    open var state: ViewControllerState"),
        "EDITABLE_UPDATE": extract("editable", "    open func update(with state: ViewControllerState)"),
        "EDITABLE_CHANGE": extract("editable", "    open func changeState()"),
        "NAVIGATION_METHODS": "\n".join(extract("navigation", anchor) for anchor in [
            "    open override func viewDidAppear(", "    open override func viewWillDisappear(",
            "    open override func escapeKeyAction()", "    override open func invokeBack(",
            "    open override func back(animated:",
        ]),
        "PROFILE_ESCAPE": extract("profile", "    public override func escapeKeyAction()"),
        "MEDIA_ESCAPE": extract("media", "    public override func escapeKeyAction()"),
        "MEDIA_SELECTION_ESCAPE": extract("media", "    func escapeSelection()") if "    func escapeSelection()" in sources["media"] else "",
        "MEDIA_UPDATE": extract("media", "    override public func update(with state:"),
        "MEDIA_STATE": extract("media", "    public override var state:ViewControllerState"),
        "MEDIA_CHANGE": extract("media", "     public override func changeState()"),
        "MEDIA_VISIBILITY": extract("media", "    func setProfileBlockVisible("),
        "MEDIA_SELECTION_NOTIFICATION": extract("media", "            if (value.state == .selecting) != (oldValue.state == .selecting)"),
        "STORY_ESCAPE": extract("story", "    public override func escapeKeyAction()"),
        "STORY_TOGGLE": extract("story", "    public func toggleSelection()"),
        "STORY_UPDATE": extract("story", "    private func updateState(_ f:"),
        "INPUT_ESCAPE": extract("input", "    public override func escapeKeyAction()", "\n    deinit {\n        disposable.dispose()"),
        "SEARCH_ESCAPE": extract("search", "        self._window?.set(escape:", "        self._window?.set(handler: { [weak self] _ -> KeyHandlerResult in\n            if self?.state == .Focus"),
        "SEARCH_CHANGE": extract("search", "    public func changeResponder("),
    }
    story_source = sources["story"]
    start_anchor = "}, toggleSelected: { [weak self] storyId in"
    start = unique_index(story_source, start_anchor) + len("}, toggleSelected: ")
    end = block_end(story_source, start)
    parts["STORY_SELECT"] = story_source[start:end]
    extracts.append({"path": SOURCES["story"], "anchor": start_anchor, "start_line": story_source.count("\n", 0, start) + 1, "end_line": story_source.count("\n", 0, end) + 1, "sha256": digest(parts["STORY_SELECT"].encode())})

    template_path = Path(__file__).with_name("SharedMediaEscapeSelectionTests.swift.in")
    template = template_path.read_text()
    for name, source in parts.items():
        marker = f"__{name}__"
        if template.count(marker) != 1:
            raise ValueError(f"Expected exactly one template marker: {marker}")
        template = template.replace(marker, source)
    if re.search(r"__[A-Z_]+__", template):
        raise ValueError("Unresolved template marker")

    temporary = None
    try:
        if args.output:
            directory = output_directory(args.output)
        else:
            temporary = tempfile.TemporaryDirectory(prefix="shared-media-escape-")
            directory = Path(temporary.name).resolve()
        tmp = directory / "tmp"
        cache = directory / "cache"
        tmp.mkdir()
        cache.mkdir()
        environment.update({"TMPDIR": str(tmp), "TMP": str(tmp), "TEMP": str(tmp), "CLANG_MODULE_CACHE_PATH": str(cache), "SWIFT_MODULECACHE_PATH": str(cache), "XDG_CACHE_HOME": str(cache)})
        source_path = directory / "SharedMediaEscapeSelectionTests.swift"
        source_path.write_text(template)
        binary = directory / "SharedMediaEscapeSelectionTests"
        command = ["swiftc", "-j2", "-module-cache-path", str(cache), str(source_path), "-o", str(binary)]
        compiler = subprocess.run(["swiftc", "--version"], cwd=directory, env=environment, text=True, capture_output=True, timeout=30)
        build = subprocess.run(command, cwd=directory, env=environment, text=True, capture_output=True, timeout=180)
        (directory / "build.log").write_text(build.stdout + build.stderr)
        run = None
        if build.returncode == 0:
            run = subprocess.run([str(binary)], cwd=directory, env=environment, text=True, capture_output=True, timeout=30)
            (directory / "test.log").write_text(run.stdout + run.stderr)
        result = {
            "source": revision or "working-tree",
            "compiler": compiler.stdout.strip(),
            "build_returncode": build.returncode,
            "test_returncode": run.returncode if run else None,
            "source_hashes": {SOURCES[name]: digest(value.encode()) for name, value in sources.items()},
            "runner_sha256": digest(Path(__file__).read_bytes()),
            "template_sha256": digest(template_path.read_bytes()),
            "generated_sha256": digest(template.encode()),
            "extracts": extracts,
            "build_command": command,
            "owned_environment": {key: environment[key] for key in ("TMPDIR", "TMP", "TEMP", "CLANG_MODULE_CACHE_PATH", "SWIFT_MODULECACHE_PATH", "XDG_CACHE_HOME")},
            "artifacts": str(directory) if args.output else "automatically removed",
        }
        (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(build.stdout + build.stderr, end="")
        if run:
            print(run.stdout + run.stderr, end="")
        print(json.dumps({key: result[key] for key in ("source", "compiler", "build_returncode", "test_returncode", "artifacts")}, indent=2))
        return 2 if build.returncode else (0 if run.returncode == 0 else 1)
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(2)
