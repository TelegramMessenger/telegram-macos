import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BASE = "246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5"
SOURCE = "packages/TelegramMediaUtils/Sources/TelegramMediaUtils/NotificationSoundNames.swift"
LOCALIZATION = "packages/Localization/Sources/Localization/Localizable.swift"


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
    resource_marker = "public func fileNameForNotificationSound("
    if current.split(resource_marker, 1)[1] != baseline.split(resource_marker, 1)[1]:
        raise RuntimeError("Resource/playback function changed outside the language-only scope")
    localization = git_source(LOCALIZATION)
    properties = sorted(set(re.findall(r"strings\(\)\.([A-Za-z0-9_]+)", current + baseline)))
    accessors = []
    for name in properties:
        if name == "peerInfoNotificationsDefaultSound":
            match = re.search(r"  public static func peerInfoNotificationsDefaultSound\(_ p1: String\) -> String \{.*?\n  \}", localization, re.S)
        else:
            match = re.search(r"  public static var " + name + r": String[^\n]+", localization)
        if match is None:
            raise RuntimeError(f"Missing real localization accessor: {name}")
        accessors.append(match.group())
    template = Path(__file__).with_name("regression.swift.in").read_text()
    template = template.replace("@@LOCALIZATION@@", "\n".join(accessors))
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], env=env, cwd=output, text=True).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=env, cwd=output, text=True).strip()
    results = {}
    for label, source in (("current", current), ("baseline", baseline)):
        body = source[source.index("private "):source.index(resource_marker)]
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
        if label == "baseline" and (execution.returncode != 1 or "FAIL language-refresh/" not in execution.stdout):
            raise RuntimeError("Exact baseline must compile then fail language-refresh assertions")
    results["base"] = BASE
    results["resource_function_unchanged"] = True
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    if not sys.flags.isolated:
        raise SystemExit("Run with python3 -I")
    main()
