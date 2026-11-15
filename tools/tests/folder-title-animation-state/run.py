import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

BASE = "246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5"
CORE_PIN = "24638bc69bd083981b178dd1e7f921eebbf7fc46"
CONTROLLER = "packages/SidebarUI/Sources/SidebarUI/ChatListFilterController.swift"
MODEL = "packages/SidebarUI/Sources/SidebarUI/SidebarFolderModel.swift"
VALIDATION = "packages/SidebarUI/Sources/SidebarUI/SidebarValidation.swift"
PREFERENCES = "packages/InAppSettings/Sources/InAppSettings/ChatListFilterPreferences.swift"
CORE_MODEL = "submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift"


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 0
    for end in range(opening, len(text)):
        depth += (text[end] == "{") - (text[end] == "}")
        if depth == 0:
            return text[start:end + 1]
    raise ValueError(marker)


def main():
    if not sys.flags.isolated:
        raise SystemExit("Run with python3 -I")
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--core-git-dir", type=Path)
    args = parser.parse_args()
    root = args.source_root.resolve()
    repository = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    if any(output == path or path in output.parents for path in (root, repository)):
        raise SystemExit("Output must be outside the source and harness worktrees")
    output.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    for name in ("tmp", "module-cache"):
        (output / name).mkdir(exist_ok=True)
    env.update(TMPDIR=str(output / "tmp") + "/", CLANG_MODULE_CACHE_PATH=str(output / "module-cache"), SWIFT_MODULECACHE_PATH=str(output / "module-cache"))

    def git(*args):
        return subprocess.check_output(["git", "-C", str(repository), *args], env=env, cwd=output, text=True)

    common = Path(git("rev-parse", "--git-common-dir").strip())
    if not common.is_absolute():
        common = (repository / common).resolve()
    core_git = args.core_git_dir or common / "modules/submodules/telegram-ios"
    core = subprocess.check_output(["git", "--git-dir=" + str(core_git), "show", CORE_PIN + ":" + CORE_MODEL], env=env, cwd=output, text=True)
    title_model = block(core, "public struct ChatFolderTitle:")
    filter_cases = core[core.index("public enum ChatListFilter:"):core.index("    public var id: Int32", core.index("public enum ChatListFilter:"))] + "}"
    filter_cases = filter_cases.replace("Codable, Equatable", "Equatable")
    template = Path(__file__).with_name("Regression.swift.in").read_text()
    swiftc = shutil.which("swiftc")
    if not swiftc:
        raise SystemExit("swiftc not found")
    report = {"base": BASE, "core_pin": CORE_PIN, "core_model_sha256": hashlib.sha256(core.encode()).hexdigest(), "variants": {}}
    for variant in ("fixed", "baseline"):
        folder = output / variant
        folder.mkdir(exist_ok=True)
        def source(path):
            if variant == "baseline" or not (root / path).exists():
                return git("show", BASE + ":" + path)
            return (root / path).read_text()
        controller = source(CONTROLLER)
        model = source(MODEL)
        validation = source(VALIDATION)
        new_filter = block(source(PREFERENCES), "    static func new(excludeIds:")
        default_title = new_filter.split("title: ", 1)[1].split(", emoticon:", 1)[0]
        initial = next(line for line in controller.splitlines() if "let initialState = State(filter:" in line)
        title_update = block(controller, "}, updateState: { state in").split("}, updateState: ", 1)[1]
        toggle = block(controller, "}, toggleNameAnimation: {").split("}, toggleNameAnimation: ", 1)[1]
        replacements = {
            "@@CORE_MODELS@@": title_model + "\n" + filter_cases,
            "@@STATE@@": block(controller, "private struct State: Equatable"),
            "@@MODEL_HELPERS@@": "\n".join(block(model, marker) for marker in ("    var enableAnimations:", "    func withUpdatedTitle(string:")),
            "@@UPDATE_HELPER@@": block(validation, "func sidebarUpdatingTitle("),
            "@@INITIAL@@": initial,
            "@@TITLE_UPDATE@@": title_update,
            "@@TOGGLE@@": toggle,
            "@@NEW_TITLE@@": default_title,
        }
        generated = template
        for key, value in replacements.items():
            if generated.count(key) != 1:
                raise ValueError("template marker " + key)
            generated = generated.replace(key, value)
        path = folder / "main.swift"
        path.write_text(generated)
        binary = folder / "regression"
        command = [swiftc, "-j1", "-module-cache-path", str(output / "module-cache"), str(path), "-o", str(binary)]
        compiled = subprocess.run(command, env=env, cwd=folder, text=True, capture_output=True)
        (folder / "compile.log").write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise SystemExit("Compilation failed, not regression evidence: " + str(folder / "compile.log"))
        run = subprocess.run([str(binary)], env=env, cwd=folder, text=True, capture_output=True)
        (folder / "run.log").write_text(run.stdout + run.stderr)
        passed = sum(line.startswith("PASS ") for line in run.stdout.splitlines())
        failed = sum(line.startswith("FAIL ") for line in run.stdout.splitlines())
        report["variants"][variant] = {"compiled": True, "command": command, "exit": run.returncode, "passed": passed, "failed": failed, "source_sha256": hashlib.sha256(controller.encode()).hexdigest(), "generated_sha256": hashlib.sha256(generated.encode()).hexdigest()}
        print(variant, "compiled;", passed, "passed;", failed, "failed")
        if variant == "fixed" and (run.returncode != 0 or failed or not passed):
            raise SystemExit("Fixed regression failed: " + str(folder / "run.log"))
        if variant == "baseline" and (run.returncode != 1 or failed == 0):
            raise SystemExit("Baseline must compile and fail assertions")
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
