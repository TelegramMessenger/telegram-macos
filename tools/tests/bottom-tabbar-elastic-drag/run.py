import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


parser = argparse.ArgumentParser(description="Compile real TabBarView and GlassTouchEffect with offscreen AppKit platform seams.")
parser.add_argument("--output", type=Path, required=True, help="New absolute evidence directory; symlinks and existing outputs are rejected.")
parser.add_argument("--revision", help="Full commit hash for the negative-control production sources.")
parser.add_argument("--source-root", type=Path, help="Read working production sources from an absolute materialized source root; Git revisions always use this test runner's worktree.")
parser.add_argument("--tab-bar-source", type=Path, help="Use a preserved TabBarView.swift for the previously tested negative control; other production sources stay at --source-root or this worktree.")
args = parser.parse_args()
if not sys.flags.isolated:
    parser.error("Use python3 -I")
root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
source_root = args.source_root or root
if not source_root.is_absolute() or not source_root.is_dir():
    parser.error("--source-root must be an existing absolute directory")
if args.revision and (args.source_root or args.tab_bar_source):
    parser.error("--revision cannot be combined with --source-root or --tab-bar-source")
if args.tab_bar_source and (not args.tab_bar_source.is_absolute() or not args.tab_bar_source.is_file()):
    parser.error("--tab-bar-source must be an existing absolute file")
output = args.output
if not output.is_absolute() or ".." in output.parts:
    parser.error("--output must be an absolute path without '..'")
if any(path.is_symlink() for path in [output, *output.parents]):
    parser.error("--output and its ancestors must not be symlinks")
if output.exists() or not output.parent.is_dir():
    parser.error("--output must be new and its parent must exist")
if args.revision and not re.fullmatch(r"[0-9a-f]{40}", args.revision):
    parser.error("--revision must be a full commit hash")
output.mkdir(mode=0o700)
env = {key: value for key, value in os.environ.items() if not key.startswith("GIT")}
paths = ["packages/TGUIKit/Sources/TabBarView.swift", "packages/TGUIKit/Sources/GlassTouchEffect.swift"]
paths += [str(path.relative_to(root)) for path in sorted((root / "packages/TGUIKit/Sources/LiquidGlassLens").glob("*.swift")) if path.name != "GlassSelectionLens.swift"]
manifest = {
    "revision": args.revision or "working-tree",
    "source_root": str(source_root),
    "git_authority": str(root),
    "tab_bar_override": str(args.tab_bar_source) if args.tab_bar_source else None,
    "production_sha256": {},
    "fixture_sha256": {},
    "seams": ["TGUIKit View/Control/TabItem and theme stand-ins", "LiquidGlassView material stand-in", "selection frame/alpha transition stand-ins", "event-monitor registration and dispatch", "cursor push/pop bookkeeping"],
    "native_sources": "Complete TabBarView, GlassTouchEffect and seven LiquidGlassLens source files; only event monitor and cursor calls redirected.",
    "boundaries": "Offscreen AppKit/Core Animation geometry, event callbacks and real spring objects. No app build, live GUI, compositor screenshot, account, network or manual acceptance.",
}
with tempfile.TemporaryDirectory(prefix="native-", dir=output) as temporary:
    directory = Path(temporary)
    scratch = directory / "tmp"
    scratch.mkdir(mode=0o700)
    env["TMPDIR"] = str(scratch) + "/"
    sources = []
    for relative in paths:
        data = subprocess.check_output(["git", "-C", str(root), "show", args.revision + ":" + relative], env=env) if args.revision else (source_root / relative).read_bytes()
        if relative.endswith("/TabBarView.swift") and args.tab_bar_source:
            data = args.tab_bar_source.read_bytes()
        manifest["production_sha256"][relative] = hashlib.sha256(data).hexdigest()
        text = data.decode()
        if relative.endswith("/TabBarView.swift"):
            for original, replacement in [("NSEvent.addLocalMonitorForEvents", "TestEventMonitor.addLocalMonitorForEvents"), ("NSEvent.removeMonitor", "TestEventMonitor.removeMonitor"), ("NSCursor.closedHand.push()", "TestCursor.push()"), ("NSCursor.pop()", "TestCursor.pop()")]:
                if original not in text:
                    raise ValueError("Missing platform seam: " + original)
                text = text.replace(original, replacement)
        path = directory / Path(relative).name
        path.write_text(text)
        sources.append(path)
    for name in ["Platform.swift.in", "main.swift.in"]:
        data = (fixtures / name).read_bytes()
        manifest["fixture_sha256"][name] = hashlib.sha256(data).hexdigest()
        path = directory / name.removesuffix(".in")
        path.write_bytes(data)
        sources.append(path)
    manifest["fixture_sha256"]["run.py"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    executable = directory / "BottomTabBarElasticTests"
    command = ["xcrun", "swiftc", "-j2", "-swift-version", "5", "-module-cache-path", str(directory / "module-cache"), *map(str, sources), "-o", str(executable)]
    compile_result = subprocess.run(command, cwd=directory, env=env, capture_output=True, text=True, timeout=180)
    (output / "compile.log").write_text(compile_result.stdout + compile_result.stderr)
    manifest["compile_exit"] = compile_result.returncode
    if compile_result.returncode == 0:
        result = subprocess.run([str(executable)], cwd=directory, env=env, capture_output=True, text=True, timeout=120)
        (output / "tests.log").write_text(result.stdout + result.stderr)
        manifest["test_exit"] = result.returncode
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="")
    else:
        result = compile_result
        print(compile_result.stdout + compile_result.stderr, end="")
manifest["temporary_build_removed"] = not directory.exists()
(output / "result.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("Evidence: " + str(output))
raise SystemExit(result.returncode)
