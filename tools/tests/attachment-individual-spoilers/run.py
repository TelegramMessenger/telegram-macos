import sys

if not sys.flags.isolated:
    raise SystemExit("Run this harness with python3 -I")

import argparse
import fcntl
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import shutil
import signal
import subprocess

BASELINE = "14a0ffe4d100136d4afdaa43a797d32699cb23f3"
CORE = "24638bc69bd083981b178dd1e7f921eebbf7fc46"
PREVIEW = "packages/PreviewSenderUI/Sources/PreviewSenderUI/"
CHAT = "packages/ChatUI/Sources/ChatUI/"
SENDER = "packages/ChatHistoryModel/Sources/ChatHistoryModel/SenderController.swift"
STORY = "packages/StoriesUI/Sources/StoriesUI/StoryModalController.swift"


def balanced(text, start, opening="{", closing="}"):
    begin = text.index(opening, start)
    depth = 0
    quoted = False
    escaped = False
    line_comment = False
    block_comment = False
    for i in range(begin, len(text)):
        c = text[i]
        pair = text[i:i + 2]
        if line_comment:
            if c == "\n":
                line_comment = False
            continue
        if block_comment:
            if text[i - 1:i + 1] == "*/":
                block_comment = False
            continue
        if quoted:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                quoted = False
            continue
        if pair == "//":
            line_comment = True
            continue
        if pair == "/*":
            block_comment = True
            continue
        if c == '"':
            quoted = True
        elif c == opening:
            depth += 1
        elif c == closing:
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    raise ValueError("Unbalanced extraction")


def compile_checked(command, out, root, compiler_lock):
    with compiler_lock.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        volumes = [out, root]
        before = [shutil.disk_usage(path).free for path in volumes]
        if min(before) < 8 * 1024 ** 3:
            raise RuntimeError("Compiler requires at least 8 GiB free disk space")
        temporary = out / "tmp"
        temporary.mkdir(exist_ok=True)
        env = dict(os.environ, TMPDIR=str(temporary) + "/")
        process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, env=env)
        aborted = False
        minimum = min(before)
        while True:
            free = min(shutil.disk_usage(path).free for path in volumes)
            minimum = min(minimum, free)
            if free < 4 * 1024 ** 3:
                os.killpg(process.pid, signal.SIGTERM)
                aborted = True
            try:
                stdout, stderr = process.communicate(timeout=1)
                break
            except subprocess.TimeoutExpired:
                if aborted:
                    os.killpg(process.pid, signal.SIGKILL)
                    stdout, stderr = process.communicate()
                    break
        (out / ("disk-" + ("parse" if "-parse" in command else "compile") + ".json")).write_text(json.dumps({"free_before": before, "minimum_free": minimum, "aborted": aborted, "process_group": process.pid}) + "\n")
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--core-git-dir", type=Path)
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--reviewer-baseline", action="store_true")
    parser.add_argument("--filtered-baseline", action="store_true")
    parser.add_argument("--extract-only", action="store_true")
    parser.add_argument("--compiler-lock", type=Path)
    args = parser.parse_args()
    root = args.source_root.resolve()
    harness_root = Path(__file__).resolve().parents[3]
    out = args.output.resolve()
    compiler_lock = (args.compiler_lock or out / "compiler.lock").resolve()
    for protected in (root, harness_root):
        if out == protected or protected in out.parents:
            parser.error("--output must be outside both source and harness repositories")
        if compiler_lock == protected or protected in compiler_lock.parents:
            parser.error("--compiler-lock must be outside both source and harness repositories")
    out.mkdir(parents=True, exist_ok=True)
    inputs = {}
    extracts = {}
    input_texts = {}
    input_origins = {}

    if sum([args.baseline, args.reviewer_baseline, args.filtered_baseline]) > 1:
        parser.error("Choose one baseline")
    baseline = "4b5b09c4fc6192240404ec14113adb512f6f502a" if args.filtered_baseline else "adf9afc783c7b83ca49c746862304286fb7d317a" if args.reviewer_baseline else BASELINE
    baseline_requested = args.baseline or args.reviewer_baseline or args.filtered_baseline

    def read(path):
        file = root / path
        if baseline_requested or not file.is_file():
            revision = baseline if baseline_requested else subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
            text = subprocess.check_output(["git", "-C", str(root), "show", revision + ":" + path], text=True)
            input_origins[path] = revision
        else:
            text = file.read_text()
            input_origins[path] = str(file)
        inputs[path] = hashlib.sha256(text.encode()).hexdigest()
        input_texts[path] = text
        return text

    def excerpt(name, path, text):
        extracts[name] = {"path": path, "sha256": hashlib.sha256(text.encode()).hexdigest(), "lines": len(text.splitlines())}
        return re.sub(r"\b(public|fileprivate|private|open)\s+", "", text)

    controller = read(PREVIEW + "PreviewSenderController.swift")
    single = read(PREVIEW + "MediaPreviewRowItem.swift")
    group = read(PREVIEW + "MediaGroupPreviewRowItem.swift")
    sender = read(SENDER)
    interaction = read(CHAT + "ChatInterfaceInteraction.swift")
    chat = read(CHAT + "ChatController.swift")
    story = read(STORY)
    enhanced = "spoilerOverrides" in controller
    pieces = {}

    def block(name, path, text, marker):
        pieces[name] = excerpt(name, path, balanced(text, text.index(marker)))

    block("STATE", PREVIEW + "PreviewSenderController.swift", controller, "fileprivate struct PreviewSendingState")
    block("ARGUMENTS", PREVIEW + "PreviewSenderController.swift", controller, "private final class SenderPreviewArguments")
    block("ENTRY_ID", PREVIEW + "PreviewSenderController.swift", controller, "private enum PreviewEntryId")
    block("ENTRY", PREVIEW + "PreviewSenderController.swift", controller, "private enum PreviewEntry :")
    block("ENTRY_EQUAL", PREVIEW + "PreviewSenderController.swift", controller, "private func == (lhs: PreviewEntry,")
    block("ENTRY_LESS", PREVIEW + "PreviewSenderController.swift", controller, "private func < (lhs: PreviewEntry,")
    block("ENTRIES", PREVIEW + "PreviewSenderController.swift", controller, "private func previewMediaEntries(")
    block("SINGLE", PREVIEW + "MediaPreviewRowItem.swift", single, "class MediaPreviewRowItem:")
    block("GROUP", PREVIEW + "MediaGroupPreviewRowItem.swift", group, "class MediaGroupPreviewRowItem:")
    block("REORDER", PREVIEW + "MediaGroupPreviewRowItem.swift", group, "override func mouseUp(with event: NSEvent)")
    control_marker = "                let url = item.urls[i]" if "                let url = item.urls[i]" in group else "                self.editControl.set(edit:"
    control_start = group.index(control_marker)
    control_end = group.index("                self.editControl.setFrameOrigin(", control_start)
    pieces["EDIT_CONTROL"] = excerpt("EDIT_CONTROL", PREVIEW + "MediaGroupPreviewRowItem.swift", group[control_start:control_end])
    rendering_start = group.index("updateMediaPreviewRendering(")
    rendering_end = group.index(", in: contents[i], animated: animated)", rendering_start)
    pieces["RENDERING"] = excerpt("RENDERING", PREVIEW + "MediaGroupPreviewRowItem.swift", group[rendering_start + len("updateMediaPreviewRendering("):rendering_end])
    layout = read(CHAT + "GroupedLayout.swift")
    block("LAYOUT_INIT", CHAT + "GroupedLayout.swift", layout, "public init(_ messages: [Message], type:")
    block("LAYOUT_MOVE", CHAT + "GroupedLayout.swift", layout, "public func moveItemIfNeeded(")
    predicates_path = "packages/TelegramMediaUtils/Sources/TelegramMediaUtils/MediaPredicates.swift"
    predicates = read(predicates_path)
    block("INTERACTIVE_MEDIA", predicates_path, predicates, "var isInteractiveMedia:")
    image_start = sender.index("                    let dimension: CGFloat = FastSettings.photoDimension")
    image_end = sender.index('                } else if mimeType.hasPrefix("video")', image_start)
    pieces["PREPARE_IMAGE"] = excerpt("PREPARE_IMAGE", SENDER, sender[image_start:image_end])
    block("VIDEO_EDITABLE", PREVIEW + "PreviewSenderController.swift", controller, "func canEditPreviewVideo(")
    block("URLS", PREVIEW + "PreviewSenderController.swift", controller, "fileprivate var urls:[URL]")
    block("ARGUMENT_CREATION", PREVIEW + "PreviewSenderController.swift", controller, "let arguments = SenderPreviewArguments(")
    argument_start = controller.index("let arguments = SenderPreviewArguments(")
    pieces["ARGUMENT_CREATION"] = excerpt("ARGUMENT_CREATION", PREVIEW + "PreviewSenderController.swift", balanced(controller, argument_start, "(", ")"))
    block("GLOBAL_MENU", PREVIEW + "PreviewSenderController.swift", controller, "if canSpoiler {")
    resort_start = controller.index("complete: {", controller.index("TableResortController(resortRange:"))
    pieces["TABLE_REORDER"] = excerpt("TABLE_REORDER", PREVIEW + "PreviewSenderController.swift", balanced(controller, resort_start + len("complete: ")))
    if "self.getPreviewState = {" in controller:
        block("CURRENT_STATE_BINDING", PREVIEW + "PreviewSenderController.swift", controller, "self.getPreviewState = {")
        pieces["CURRENT_STATE_BINDING"] += "\nself.isMediaStateCurrent = { [weak self] in self?.currentPreviewState != nil }"
    elif "self.isMediaStateCurrent = {" in controller:
        block("CURRENT_STATE_BINDING", PREVIEW + "PreviewSenderController.swift", controller, "self.isMediaStateCurrent = {")
    else:
        pieces["CURRENT_STATE_BINDING"] = "self.isMediaStateCurrent = { true }"
    for name, marker in [("PREVIEW_SNAPSHOT", "private var currentPreviewState:"), ("SEND_ELIGIBILITY", "private func canSendAsSpoiler(")]:
        if marker in controller:
            block(name, PREVIEW + "PreviewSenderController.swift", controller, marker)
        else:
            pieces[name] = ""
    menu_start = controller.index("                        if let preview = self.currentPreviewState", controller.index("contextChatInteraction.sendMessageMenu")) if "if let preview = self.currentPreviewState" in controller else controller.index("items.append(ContextMenuItem(strings().previewSenderSendAsSpoiler")
    menu = balanced(controller, menu_start) if "if let preview = self.currentPreviewState" in controller else balanced(controller, menu_start, "(", ")")
    pieces["SEND_MENU"] = excerpt("SEND_MENU", PREVIEW + "PreviewSenderController.swift", menu)
    entry_start = controller.index("self.sendCurrentMedia = { [weak self] silent, atDate, asSpoiler, via in")
    entry_end = controller.index("                var permissions:", entry_start)
    pieces["SEND_ENTRY"] = excerpt("SEND_ENTRY", PREVIEW + "PreviewSenderController.swift", controller[entry_start:entry_end])
    input_start = controller.index("                var input:ChatTextInputState", entry_end)
    input_end = controller.index("                if additionalMessage != nil", input_start)
    pieces["SEND_INPUT"] = excerpt("SEND_INPUT", PREVIEW + "PreviewSenderController.swift", controller[input_start:input_end])
    send_start = controller.index("    func send(_ silent:")
    send_end = controller.index("        let text =", send_start)
    pieces["SEND_GATE"] = excerpt("SEND_GATE", PREVIEW + "PreviewSenderController.swift", controller[send_start:send_end])
    block("FLUSH_PENDING", PREVIEW + "PreviewSenderController.swift", controller, "private func flushPendingRenderSend()")
    block("PREVIEW_STATE", PREVIEW + "PreviewSenderController.swift", controller, "private struct PreviewState :")
    block("PREVIEW_STATE_EQUAL", PREVIEW + "PreviewSenderController.swift", controller, "private func == (lhs: PreviewState,")
    block("APPLY_PREPARED", PREVIEW + "PreviewSenderController.swift", controller, "let applyPreparedMedias: () -> Void = {")
    block("MEDIA_BINDING", PREVIEW + "PreviewSenderController.swift", controller, "self.getMedias = {")
    if "self.getMediaUrls = {" in controller:
        block("URL_BINDING", PREVIEW + "PreviewSenderController.swift", controller, "self.getMediaUrls = {")
    else:
        pieces["URL_BINDING"] = ""
    block("INTERACTIVE_BINDING", PREVIEW + "PreviewSenderController.swift", controller, "self.genericView.stateValueInteractiveUpdate = {")
    block("MEDIA_WRAPPING", PREVIEW + "PreviewSenderController.swift", controller, "let makeMedia:([Media], Bool)->[Media]")
    send_start = controller.index("if state.isCollage && medias.count > 1 {")
    grouped = balanced(controller, send_start)
    else_start = send_start + len(grouped)
    send_block = grouped + balanced(controller, else_start)
    pieces["SEND_BRANCH"] = excerpt("SEND_BRANCH", PREVIEW + "PreviewSenderController.swift", send_block)
    spoilers = re.search(r"                let spoilers = medias.enumerated\(\).map \{", controller)
    pieces["SPOILER_SNAPSHOT"] = excerpt("SPOILER_SNAPSHOT", PREVIEW + "PreviewSenderController.swift", balanced(controller, spoilers.start())) if spoilers else ""
    for name, marker in [("ALL_SPOILERS", "fileprivate var allMediaHaveSpoilers:"), ("REPLACE_URL", "private func replaceAttachmentUrl("), ("ELIGIBLE", "public static func canHaveSpoiler(")]:
        text, path = (sender, SENDER) if name == "ELIGIBLE" else (controller, PREVIEW + "PreviewSenderController.swift")
        if marker in text:
            block(name, path, text, marker)
        elif name == "REPLACE_URL":
            original = re.search(r"self\.urls\[index\] = new", controller).group()
            pieces[name] = "func replaceAttachmentUrl(at index: Int, with new: URL) { " + excerpt(name, path, original) + " }"
        else:
            pieces[name] = ""
    enqueue_starts = [m.start() for m in re.finditer(r"public static func enqueue\(media:\[Media\],", sender)]
    if len(enqueue_starts) != 2:
        raise ValueError("Expected both media enqueue overloads")
    pieces["ENQUEUE"] = excerpt("ENQUEUE", SENDER, "\n".join(balanced(sender, start) for start in enqueue_starts))
    interaction_start = interaction.index("    public var sendMedias:")
    interaction_end = interaction.index("    public var focusInputField", interaction_start)
    pieces["INTERACTION"] = excerpt("INTERACTION", CHAT + "ChatInterfaceInteraction.swift", interaction[interaction_start:interaction_end])
    for name, text, path in [("CHAT", chat, CHAT + "ChatController.swift"), ("STORY", story, STORY)]:
        start = text.index("chatInteraction.sendMediasWithAnalytics = {")
        prefix = text[start:text.index(" in\n", start) + len(" in\n")]
        call_start = text.index("Sender.enqueue(media: medias", start)
        call = balanced(text, call_start, "(", ")")
        pieces[name + "_PREFIX"] = excerpt(name + "_PREFIX", path, prefix)
        pieces[name + "_CALL"] = excerpt(name + "_CALL", path, call)
    extension_text = read("packages/TGUIKit/Sources/Extensions.swift")
    pieces["ARRAY"] = excerpt("ARRAY", "packages/TGUIKit/Sources/Extensions.swift", "\n".join(balanced(extension_text, extension_text.index(marker)) for marker in ["mutating func move(at", "func chunks(_ chunkSize:"]))
    core_git = args.core_git_dir
    if core_git is None:
        common = subprocess.check_output(["git", "-C", str(harness_root), "rev-parse", "--path-format=absolute", "--git-common-dir"], text=True).strip()
        core_git = Path(common) / "modules/submodules/telegram-ios"
    core_path = "submodules/TelegramCore/Sources/SyncCore/SyncCore_MediaSpoilerMessageAttribute.swift"
    attribute = subprocess.check_output(["git", "--git-dir=" + str(core_git), "show", CORE + ":" + core_path], text=True)
    pieces["SPOILER_ATTRIBUTE"] = excerpt("SPOILER_ATTRIBUTE", CORE + ":" + core_path, balanced(attribute, attribute.index("public class MediaSpoilerMessageAttribute")))
    pieces["BASELINE_MODE"] = "false" if enhanced else "true"
    pieces["EDITOR_WIRING"] = str(controller.count("self.replaceAttachmentUrl(at: index, with: new)"))
    pieces["SEND_STATE_GUARD"] = "true" if ("getMediaUrls() != urls || !isMediaStateCurrent()" in controller or "appFile == nil && preview == nil" in controller) and "self.genericView.state = state\n            let isPreparing" not in controller else "false"
    pieces["SNAPSHOT_BINDING"] = "true" if "arguments.reorder(urls[from], urls[to])" in controller else "false"
    pieces["TABLE_REORDER_GUARD"] = "true" if "guard urls.indices.contains(from), urls.indices.contains(to)" in pieces["TABLE_REORDER"] else "false"
    template = (Path(__file__).parent / "Tests.swift.in").read_text()
    reviewer_tests = (Path(__file__).parent / "ReviewerTests.swift.in").read_text()
    template = template.replace("let basic = fixture(3)", (reviewer_tests if enhanced else "") + "\nlet basic = fixture(3)")
    for name, text in pieces.items():
        template = template.replace("@@" + name + "@@", text)
    unexpanded = re.findall(r"@@[A-Z_]+@@", template)
    if unexpanded:
        raise ValueError("Unexpanded markers: " + str(unexpanded))
    materialized = out / "Tests.swift"
    materialized.write_text(template)
    manifest = {"baseline": baseline, "pinned_core": CORE, "source_root": str(root), "baseline_requested": baseline_requested, "input_origins": input_origins, "inputs": inputs, "extracts": extracts, "visibility_only_rewrite": True, "fixture_sha256": hashlib.sha256(template.encode()).hexdigest()}
    (out / "extraction.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.extract_only:
        print(json.dumps(manifest, indent=2))
        return 0
    report = {"source_root": str(root), "baseline_adapter": not enhanced, "compiler_lock": str(compiler_lock), "compiled": False, "passed": False}
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    target = platform.machine() + "-apple-macosx13.0"
    compiler_lock.parent.mkdir(parents=True, exist_ok=True)
    parse_files = []
    for path in [PREVIEW + "PreviewSenderController.swift", PREVIEW + "MediaPreviewRowItem.swift", PREVIEW + "MediaGroupPreviewRowItem.swift", SENDER, CHAT + "ChatController.swift", CHAT + "ChatInterfaceInteraction.swift", STORY]:
        parse_file = out / "source" / path
        parse_file.parent.mkdir(parents=True, exist_ok=True)
        parse_file.write_text(input_texts[path])
        parse_files.append(parse_file)
    parse_command = [compiler, "-j1", "-parse"] + [str(path) for path in parse_files]
    parse = compile_checked(parse_command, out, root, compiler_lock)
    (out / "parse.log").write_text(parse.stdout + parse.stderr)
    report["parse_command"] = parse_command
    report["parse_exit"] = parse.returncode
    command = [compiler, "-j1", "-Onone", "-sdk", sdk, "-target", target, "-module-cache-path", str(out / "module-cache"), str(materialized), "-o", str(out / "Tests")]
    result = compile_checked(command, out, root, compiler_lock)
    (out / "compile.log").write_text(result.stdout + result.stderr)
    report["compile_command"] = command
    report["compile_exit"] = result.returncode
    report["compiled"] = result.returncode == 0
    if report["compiled"]:
        temporary = out / "tmp"
        temporary.mkdir(exist_ok=True)
        env = dict(os.environ, TMPDIR=str(temporary) + "/")
        run = subprocess.run([str(out / "Tests")], text=True, capture_output=True, env=env)
        (out / "runtime.log").write_text(run.stdout + run.stderr)
        report["runtime_exit"] = run.returncode
        try:
            report["behavior"] = json.loads(run.stdout)
        except json.JSONDecodeError:
            report["behavior"] = {"error": "No JSON behavior result"}
        if enhanced:
            deletion = subprocess.run([str(out / "Tests"), "--queued-deletion"], text=True, capture_output=True, env=env)
            (out / "queued-deletion.log").write_text(deletion.stdout + deletion.stderr)
            report["queued_deletion_exit"] = deletion.returncode
        report["passed"] = parse.returncode == 0 and run.returncode == 0 and report.get("queued_deletion_exit", 0) == 0
    (out / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
