import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

BASE = "246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5"
TEXT = "packages/TGUIKit/Sources/TextView.swift"
PREPARED = "packages/TGUIKit/Sources/TextViewPreparedText.swift"
FOLDING = "packages/InputTextView/Sources/InputTextView/FoldingTextView.swift"


def block(text, marker):
    if text.count(marker) != 1:
        raise ValueError("Ambiguous source marker: " + marker)
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 0
    for end in range(opening, len(text)):
        depth += (text[end] == "{") - (text[end] == "}")
        if depth == 0:
            return text[start:end + 1]
    raise ValueError("Unclosed source marker: " + marker)


def main():
    if not sys.flags.isolated:
        raise SystemExit("Run with python3 -I")
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compiler-lock", type=Path)
    args = parser.parse_args()
    root = args.source_root.resolve()
    repository = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    if any(output == path or path in output.parents for path in (root, repository)):
        raise SystemExit("Output must be outside source and harness worktrees")
    output.mkdir(parents=True, exist_ok=True)
    compiler_lock = (args.compiler_lock or output / "native-compiler.lock").resolve()
    if any(compiler_lock == path or path in compiler_lock.parents for path in (root, repository)):
        raise SystemExit("Compiler lock must be outside source and harness worktrees")
    compiler_lock.parent.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    for name in ("tmp", "module-cache"):
        (output / name).mkdir(exist_ok=True)
    env.update(TMPDIR=str(output / "tmp") + "/", CLANG_MODULE_CACHE_PATH=str(output / "module-cache"), SWIFT_MODULECACHE_PATH=str(output / "module-cache"))
    template = Path(__file__).with_name("Regression.swift.in").read_text()
    swiftc = shutil.which("swiftc")
    if not swiftc:
        raise SystemExit("swiftc not found")
    report = {"base": BASE, "source_root": str(root), "variants": {}}
    for variant in ("baseline", "current"):
        folder = output / variant
        folder.mkdir(exist_ok=True)

        def source(path):
            if variant == "baseline":
                return subprocess.check_output(["git", "-C", str(repository), "show", BASE + ":" + path], env=env, cwd=output, text=True)
            return (root / path).read_text()

        text = source(TEXT)
        prepared = source(PREPARED)
        folding = source(FOLDING)
        fold_method = block(folding, "        func updated(width:")
        fold_geometry = fold_method[:fold_method.index("            let arrowDown: CGImage?")] + "            return (size, isRevealed)\n        }"
        fold_geometry = fold_geometry.replace("-> ViewLayout", "-> (NSSize, Bool)")
        definitions = "\n".join(block(text, marker) for marker in (
            "private func combineIntersectingRectangles(",
            "public struct TextInputAttributes",
            "public final class TextViewBlockQuote {",
            "public final class TextViewBlockQuoteData:",
            "private final class TextViewEmbeddedItem",
            "struct TextViewStrikethrough",
            "struct TextViewUnderline",
            "public final class TextViewLine",
            "public struct TextViewCutout",
        ))
        replacements = {
            "@@DEFINITIONS@@": definitions,
            "@@PREPARED@@": prepared,
            "@@LAST_QUOTE@@": block(text, "    private static func lastBlockQuote(in range:"),
            "@@CALCULATE@@": block(text, "    func calculateLayout(isBigEmoji:"),
            "@@FOLD_GEOMETRY@@": fold_geometry,
            "@@BREAK_STRING@@": block(folding, "    public static func breakString("),
        }
        generated = template
        for key, value in replacements.items():
            if generated.count(key) != 1:
                raise ValueError("Template marker: " + key)
            generated = generated.replace(key, value)
        path = folder / "main.swift"
        path.write_text(generated)
        binary = folder / "regression"
        command = [swiftc, "-j1", "-module-cache-path", str(output / "module-cache"), str(path), "-o", str(binary)]
        with compiler_lock.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            compiled = subprocess.run(command, env=env, cwd=folder, text=True, capture_output=True)
        (folder / "compile.log").write_text(compiled.stdout + compiled.stderr)
        result = {"compiled": compiled.returncode == 0, "command": command, "source_sha256": hashlib.sha256(text.encode()).hexdigest(), "prepared_sha256": hashlib.sha256(prepared.encode()).hexdigest(), "folding_sha256": hashlib.sha256(folding.encode()).hexdigest(), "generated_sha256": hashlib.sha256(generated.encode()).hexdigest()}
        report["variants"][variant] = result
        if compiled.returncode:
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            raise SystemExit("Compilation failed, not behavioral evidence: " + str(folder / "compile.log"))
        run = subprocess.run([str(binary)], env=env, cwd=folder, text=True, capture_output=True)
        (folder / "run.log").write_text(run.stdout + run.stderr)
        passed = sum(line.startswith("PASS ") for line in run.stdout.splitlines())
        failed = sum(line.startswith("FAIL ") for line in run.stdout.splitlines())
        result.update(exit=run.returncode, passed=passed, failed=failed)
        print(variant, "compiled;", passed, "passed;", failed, "failed")
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    baseline = report["variants"]["baseline"]
    current = report["variants"]["current"]
    if baseline["exit"] != 1 or not baseline["failed"]:
        raise SystemExit("Baseline must compile then fail behavioral assertions")
    if current["exit"] != 0 or current["failed"] or not current["passed"]:
        raise SystemExit("Current regression failed: " + str(output / "current" / "run.log"))


if __name__ == "__main__":
    main()
