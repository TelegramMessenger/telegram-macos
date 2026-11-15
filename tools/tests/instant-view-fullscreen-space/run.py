import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BASE = "246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5"
SOURCE = "packages/WebAppUI/Sources/WebAppUI/InstantViewInBrowser.swift"
WINDOW = "packages/TGUIKit/Sources/Window.swift"
KEYBOARD = "packages/KeyboardKey/Sources/KeyboardKey/KeyboardKey.swift"


def between(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.source_root.resolve()
    repository = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    if output == root or root in output.parents:
        parser.error("--output must be outside the source worktree")
    output.mkdir(parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    for key, directory in (("TMPDIR", "tmp"), ("CLANG_MODULE_CACHE_PATH", "clang-cache"), ("SWIFT_MODULECACHE_PATH", "swift-cache"), ("HOME", "home")):
        path = output / directory
        path.mkdir(exist_ok=True)
        env[key] = str(path)
    env["PYTHONDONTWRITEBYTECODE"] = "1"

    def git_source(path):
        return subprocess.check_output(["git", "-C", str(repository), "show", f"{BASE}:{path}"], env=env, cwd=output).decode()

    baseline = git_source(SOURCE)
    current = (root / SOURCE).read_text()
    window = git_source(WINDOW)
    keyboard = git_source(KEYBOARD)
    template = Path(__file__).with_name("regression.swift.in").read_text()
    template = template.replace("@@KEYBOARD@@", keyboard[keyboard.index("public enum KeyboardKey"):])
    template = template.replace("@@HANDLER_TYPES@@", between(window, "public enum HandlerPriority", "public enum SwipeType"))
    template = template.replace("@@RESULT_TYPE@@", between(window, "public enum KeyHandlerResult", "open class Window"))
    template = template.replace("@@SET_HANDLER@@", between(window, "    public func set(handler:", "    public func add(swipe"))
    template = template.replace("@@DISPATCH@@", between(window, "                if let globalHandlers =", "            } else if eventType == .scrollWheel"))
    removal = between(window, "        var newKeyHandlers:[KeyboardKey:[KeyHandler]]", "        var newMouseHandlers:")
    template = template.replace("@@REMOVE_HANDLERS@@", removal)
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], env=env, cwd=output, text=True).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=env, cwd=output, text=True).strip()
    results = {}
    for label, source in (("current", current), ("baseline", baseline)):
        appear = source[source.index("    public override func viewDidAppear("):]
        body = between(appear, "        window?.set(handler:", "        window?.set(handler: { [weak self] _ in\n            let isBackButton")
        swift = output / f"{label}.swift"
        binary = output / label
        swift.write_text(template.replace("@@PRODUCTION@@", body))
        command = [compiler, "-j1", "-sdk", sdk, "-target", f"{os.uname().machine}-apple-macosx13.0", "-module-cache-path", str(output / "swift-cache"), str(swift), "-o", str(binary)]
        compile_result = subprocess.run(command, cwd=output, env=env, capture_output=True, text=True)
        (output / f"{label}-compile.log").write_text(compile_result.stdout + compile_result.stderr)
        if compile_result.returncode:
            raise RuntimeError(f"{label} did not compile; this is NOT a passing negative control. See {output / (label + '-compile.log')}")
        execution = subprocess.run([str(binary)], cwd=output, env=env, capture_output=True, text=True)
        (output / f"{label}-run.log").write_text(execution.stdout + execution.stderr)
        counts = re.search(r"RESULT checks=(\d+) failures=(\d+)", execution.stdout)
        if counts is None:
            raise RuntimeError(f"{label} did not finish the assertion suite")
        checks, failures = map(int, counts.groups())
        results[label] = {"compiled": True, "checks": checks, "failures": failures, "exit": execution.returncode, "source_sha256": hashlib.sha256(source.encode()).hexdigest(), "compile_command": command}
        print(f"{label}: compiled; {checks} checks, {failures} failures, exit {execution.returncode}", flush=True)
        if label == "current" and (execution.returncode != 0 or failures != 0):
            raise RuntimeError("Current source failed regression assertions")
        if label == "baseline" and (execution.returncode != 1 or "FAIL fullscreen/space-down" not in execution.stdout or "FAIL fullscreen/shift-space-up" not in execution.stdout):
            raise RuntimeError("Exact baseline must compile then fail both fullscreen-space assertions")
    results["base"] = BASE
    results["routing_source_sha256"] = hashlib.sha256(window.encode()).hexdigest()
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    if not sys.flags.isolated:
        raise SystemExit("Run with python3 -I")
    main()
