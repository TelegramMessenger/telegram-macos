import sys

if not sys.flags.isolated:
    raise SystemExit("Run this test with python3 -I")

import argparse
import fcntl
import hashlib
import json
import pathlib
import subprocess

BASE = "246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5"


def extract(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return "\n".join(line.split("//", 1)[0].rstrip() for line in text[start:end].splitlines())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--revision")
    parser.add_argument("--compiler-lock", type=pathlib.Path)
    args = parser.parse_args()
    harness = pathlib.Path(__file__).resolve().parents[3]
    root = args.source_root.resolve()
    output = args.output.resolve()
    compiler_lock = (args.compiler_lock or output / "compiler.lock").resolve()
    for target in (output, compiler_lock):
        if any(target == protected or protected in target.parents for protected in (root, harness)):
            parser.error("Output and compiler lock must be outside source and harness roots")
    output.mkdir(parents=True, exist_ok=True)
    hashes = {}

    def read(relative):
        if args.revision:
            text = subprocess.check_output(["git", "-C", str(harness), "show", args.revision + ":" + relative], text=True)
        else:
            text = (root / relative).read_text()
        hashes[relative] = hashlib.sha256(text.encode()).hexdigest()
        return text

    control = read("packages/TGUIKit/Sources/Control.swift")
    animation = read("packages/TGUIKit/Sources/CAAnimationUtils.swift")
    header = read("packages/PeerInfoUI/Sources/PeerInfoUI/PeerInfoHeadItem.swift")
    table = read("packages/TGUIKit/Sources/TableView.swift")
    if "view.set(item: item, animated: animated)" not in extract(table, "public func noteHeightOfRow(_ row:Int"):
        raise RuntimeError("The synchronous row-update boundary changed")
    if "photoContainer.scaleOnClick = !item.isAvatarExpanded" not in header:
        raise RuntimeError("The profile press-state binding changed")
    replacements = {
        "__STATE_UPDATE__": extract(control, "open func stateDidUpdate(_ state: ControlState)"),
        "__MOUSE_DOWN__": extract(control, "override open func mouseDown(with event: NSEvent)"),
        "__MOUSE_UP__": extract(control, "override open func mouseUp(with event: NSEvent)"),
        "__UPDATE_STATE__": extract(control, "public func updateState()"),
        "__SEND__": extract(control, "public func send(event:ControlEvent)"),
        "__SCALE_ANIMATION__": extract(animation, "func animateScaleSpring(from: CGFloat"),
        "__SPRING__": extract(animation, "public func makeSpringAnimation(_ path:String)"),
        "__BOUNCE__": extract(animation, "public func makeSpringBounceAnimation(_ path:String"),
        "__SET_EXPANDED__": extract(header, "private func setAvatarExpanded(_ expanded: Bool)"),
    }
    source = pathlib.Path(__file__).with_name("Regression.swift.template").read_text()
    for marker, value in replacements.items():
        if source.count(marker) != 1:
            raise RuntimeError("Template marker mismatch: " + marker)
        source = source.replace(marker, value)
    swift = output / "Regression.swift"
    swift.write_text(source)
    binary = output / "regression"
    command = ["xcrun", "swiftc", "-j1", "-module-cache-path", str(output / "module-cache"), str(swift), "-o", str(binary)]
    compiler_lock.parent.mkdir(parents=True, exist_ok=True)
    with compiler_lock.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            compiled = subprocess.run(command, cwd=output, capture_output=True, text=True)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
    (output / "compile.stdout").write_text(compiled.stdout)
    (output / "compile.stderr").write_text(compiled.stderr)
    result = {
        "source_root": str(root),
        "harness_root": str(harness),
        "source_origin": str(harness if args.revision else root),
        "source_revision": args.revision or "working-tree",
        "base_revision": BASE,
        "harness_head": subprocess.check_output(["git", "-C", str(harness), "rev-parse", "HEAD"], text=True).strip(),
        "compiler_lock": str(compiler_lock),
        "source_sha256": hashes,
        "compile_command": command,
        "compile_exit": compiled.returncode,
        "runtime_exit": None,
        "limits": "Source-extracted native AppKit/QuartzCore methods; synthetic NSEvent delivery and injected held-button state, no real input or visible app. No Telegram renderer, media, account, database, or full package build."
    }
    if compiled.returncode == 0:
        ran = subprocess.run([str(binary)], cwd=output, capture_output=True, text=True)
        (output / "run.stdout").write_text(ran.stdout)
        (output / "run.stderr").write_text(ran.stderr)
        result["runtime_exit"] = ran.returncode
        if ran.stdout.strip():
            result["native_results"] = json.loads(ran.stdout.strip().splitlines()[-1])
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0 if result["compile_exit"] == 0 and result["runtime_exit"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
