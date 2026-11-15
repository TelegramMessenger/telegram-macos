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
CONTROLLER = "packages/EntertainmentUI/Sources/EntertainmentUI/StickerPackPreviewModalController.swift"
EDITING = "packages/EntertainmentUI/Sources/EntertainmentUI/StickerPackEditing.swift"
CORE_REFERENCE = "submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaFile.swift"
CORE_INFO = "submodules/TelegramCore/Sources/SyncCore/SyncCore_StickerPackCollectionInfo.swift"
CORE_OPERATIONS = "submodules/TelegramCore/Sources/TelegramEngine/Stickers/StickerPackInteractiveOperations.swift"


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
    report = {"base": BASE, "core_pin": CORE_PIN, "core_sources": {}, "variants": {}}
    def core_source(path):
        value = subprocess.check_output(["git", "--git-dir=" + str(core_git), "show", CORE_PIN + ":" + path], env=env, cwd=output, text=True)
        report["core_sources"][path] = hashlib.sha256(value.encode()).hexdigest()
        return value
    reference = core_source(CORE_REFERENCE)
    reference = reference[reference.index("public enum StickerPackReference:"):reference.index("    public init(decoder:")] + "}"
    reference = reference.replace("PostboxCoding, ", "").replace(", Codable", "")
    flags = block(core_source(CORE_INFO), "public struct StickerPackCollectionInfoFlags:")
    remove_option = block(core_source(CORE_OPERATIONS), "public enum RemoveStickerPackOption")
    template = Path(__file__).with_name("Regression.swift.in").read_text()
    swiftc = shutil.which("swiftc")
    if not swiftc:
        raise SystemExit("swiftc not found")
    for variant in ("fixed", "baseline"):
        folder = output / variant
        folder.mkdir(exist_ok=True)
        def source(path):
            if variant == "baseline" or not (root / path).exists():
                return git("show", BASE + ":" + path)
            return (root / path).read_text()
        controller = source(CONTROLLER)
        entries = block(controller, "private func entries(")
        apply_state = block(controller, "    let applyState: (State) -> Void")
        footer = apply_state[apply_state.index("        let isInstalled:"):apply_state.index("        modalController?.modal?.interactions?.updateDone", apply_state.index("        let isInstalled:"))]
        replacements = {
            "@@MODELS@@": reference + "\n" + flags + "\n" + remove_option,
            "@@PREVIEW@@": "\n".join(block(controller, marker) for marker in ("private enum PreviewState {", "public enum StickerPackPreviewSource :", "public enum StickerPackPreviewModalSource {", "private struct State : Equatable", "private final class PreviewStateEquatable")),
            "@@OWN@@": block(source(EDITING), "func isOwnStickerPack("),
            "@@PACK_REFERENCE@@": block(controller, "    let packReference:"),
            "@@SET_EDITING@@": block(controller, "    let setEditing:"),
            "@@DELETE@@": block(controller, "    let deletePack:"),
            "@@ADD@@": block(controller, "}, addpack: {").split("}, addpack: ", 1)[1],
            "@@ADD_ALL@@": block(controller, "}, addAll: {").split("}, addAll: ", 1)[1],
            "@@MENU@@": block(controller, "}, contextMenu: {").split("}, contextMenu: ", 1)[1],
            "@@HEADER_STATUS@@": block(entries, "        let isInstalled:"),
            "@@HEADER_ADD@@": block(entries, "}, installPack: {").split("}, installPack: ", 1)[1],
            "@@FOOTER@@": footer,
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
