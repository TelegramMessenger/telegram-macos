import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description="Compile extracted folder drop handlers with inert boundary doubles; no app or account access.")
parser.add_argument("--revision")
parser.add_argument("--output", type=Path)
parser.add_argument("--source-root", type=Path)
parser.add_argument("--before-root", type=Path)
parser.add_argument("--sdk-typecheck", action="store_true")
args = parser.parse_args()
if not sys.flags.isolated:
    parser.error("Use python3 -I")
if args.revision and (args.source_root or args.before_root):
    parser.error("--revision cannot be combined with source directories")
root = Path(__file__).resolve().parents[3]
source_root = args.source_root.resolve() if args.source_root else root
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}

def git(*arguments):
    return subprocess.check_output(["git", "-C", str(root), *arguments], env=env, text=True)

def source(path):
    if args.revision:
        result = subprocess.run(["git", "-C", str(root), "show", args.revision + ":" + path], env=env, text=True, capture_output=True)
        return result.stdout if result.returncode == 0 else ""
    if args.before_root:
        before = args.before_root / path
        if before.exists():
            return before.read_text()
        if path.endswith(("ChatListFolderDragPresentation.swift", "ChatListFolderDropTarget.swift")):
            return ""
    path = source_root / path
    return path.read_text() if path.exists() else ""

def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]

chat = "packages/ChatListUI/Sources/ChatListUI/"
menu = source(chat + "SearchPeerContextMenu.swift")
drop = source(chat + "ChatListFolderDrop.swift")
row = source(chat + "ChatListRowView.swift")
top = source(chat + "ChatListRevealItem.swift")
sidebar = source("packages/SidebarUI/Sources/SidebarUI/LeftSidebarFolderItem.swift")
segment = source("packages/TGUIKit/Sources/ScrollableSegmentView.swift")
presentation = source(chat + "ChatListFolderDragPresentation.swift")
drop_target = source(chat + "ChatListFolderDropTarget.swift")
refined = bool(presentation and drop_target)
dock = "struct ChatListFolderDragMotion" in presentation
common = Path(git("rev-parse", "--git-common-dir").strip())
if not common.is_absolute():
    common = root / common
core_git = common / "modules/submodules/telegram-ios"
core_revision = git("rev-parse", (args.revision or "HEAD") + ":submodules/telegram-ios").strip()
def core(path):
    return subprocess.check_output(["git", "--git-dir=" + str(core_git), "show", core_revision + ":" + path], env=env, text=True)
models = core("submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift")
predicate = core("submodules/Postbox/Sources/ChatListView.swift")
utils = source("packages/TelegramUtils/Sources/TelegramUtils/ChatListFilterPredicate.swift")
parts = [block(models, marker) for marker in ["public struct ChatListFilterPeerCategories:", "public struct ChatListFilterIncludePeers:", "func isLocalOnlyChatListFilterPeer(", "public struct ChatListFilterData:"]]
parts += [block(predicate, "public struct ChatListFilterPredicate"), block(utils, "public func chatListFilterPredicate(")]
parts += [block(menu, marker) for marker in ["struct SearchPeerFolderState", "enum SearchPeerFolderUpdate", "func searchPeerFolderContains(", "func searchPeerFolderUpdate("]]
production = "\n".join(parts)
if drop:
    production += "\n" + "\n".join(line for line in drop.splitlines() if not line.startswith("import "))
row_markers = ["public override func mouseDown(", "public override func mouseDragged(", "public override func mouseUp(", "public override func scrollWheel(", "public override func hitTest("]
row_body = "\n".join(block(row, marker) for marker in row_markers if marker in row)
if drop:
    row_body = row[row.index("    private var avatarMouseDown:"):row.index("    override public func draggingEntered", row.index("    private var avatarMouseDown:"))]
top_body = "\n".join(block(top, marker) for marker in ["private func folderDropTarget(", "private func folderDropTargets()", "public override func draggingEntered(", "public override func draggingUpdated(", "public override func performDragOperation("] if marker in top)
side_body = "\n".join(block(sidebar, marker) for marker in ["override func draggingEntered(", "override func draggingUpdated(", "override func performDragOperation("] if marker in sidebar)
if refined:
    top_body = "private var folderDrop: ChatListFolderDropTarget?; func configure(_ context: Context) { folderDrop = ChatListFolderDropTarget(context: context, scrollView: segmentView.scrollView, horizontal: true, target: { [weak self] in self?.folderDropTarget($0) }) }\n" + top_body
    controller = source("packages/SidebarUI/Sources/SidebarUI/LeftSidebarController.swift")
    side_body = "private var folderDrop: ChatListFolderDropTarget?; let scroll = ScrollView(); func configure(_ context: Context) { folderDrop = ChatListFolderDropTarget(context: context, scrollView: scroll, horizontal: false, target: { [weak self] _ in guard let self, let item = self.item as? LeftSidebarFolderItem, !self.isResorting else { return nil }; return (item.folder, self) }) }\n" + "\n".join(block(controller, marker) for marker in ["public override func draggingEntered(", "public override func draggingUpdated(", "public override func performDragOperation("])
    if dock:
        top_body = top_body.replace("self?.folderDropTarget($0) })", "self?.folderDropTarget($0) }, visibleTargets: { [weak self] in self?.folderDropTargets() ?? [] })")
        side_body = side_body.replace("return (item.folder, self) })", "return (item.folder, self) }, visibleTargets: { [weak self] in guard let self, let item = self.item as? LeftSidebarFolderItem else { return [] }; return [(item.folder, self, [])] })")
        production += "\n" + block(presentation, "struct ChatListFolderDragMotion")
    production += "\n" + block(presentation, "struct ChatListFolderDragCompletion")
    production += "\n" + "\n".join(line for line in drop_target.splitlines() if not line.startswith("import ")).replace("private func tick()", "func tick()").replace("Foundation.Timer", "TestTimer")
segment_body = block(segment, "public func item(at point:") if "public func item(at point:" in segment else ""
if "public var visibleItems:" in segment:
    segment_body += "\n" + block(segment, "public var visibleItems:")
fixture = Path(__file__).with_name("Checks.swift.in").read_text()
fixture = fixture.replace("__PEER_GROUP_ID__", block(core("submodules/Postbox/Sources/PeerGroup.swift"), "public enum PeerGroupId:"))
fixture = fixture.replace("__STATE_BOUNDARY__", Path(__file__).with_name("StateBoundary.swift.in").read_text())
fixture = fixture.replace("__MEMBERSHIP_CHECKS__", Path(__file__).with_name("MembershipChecks.swift.in").read_text() if drop else 'check(false, "Membership-aware drop unavailable")')
fixture = fixture.replace("__IMPACT_TARGETS__", ", visibleTargets: { [(filter, view, [content])] }" if dock else "")
if dock:
    motion_checks = Path(__file__).with_name("MotionChecks.swift.in").read_text()
    duration_checks = '''let shortDuration = ChatListFolderDragMotion.returnDuration(from: start, to: start.offsetBy(dx: 20, dy: 0))
    let longDuration = ChatListFolderDragMotion.returnDuration(from: start, to: start.offsetBy(dx: 2000, dy: 0))
    check(shortDuration >= 0.30 && shortDuration < 0.32 && abs(longDuration - 0.45) < 0.000001, "return duration adapts to distance and stays bounded")'''
    motion_checks = motion_checks.replace("__SMOOTH_DURATION_CHECKS__", duration_checks if "static func returnDuration(" in presentation else 'check(false, "Distance-aware smooth return unavailable")')
    fixture = fixture.replace("__DOCK__", motion_checks)
else:
    fixture = fixture.replace("__DOCK__", 'check(false, "Dock progressive geometry and motion unavailable")')
if refined:
    presentation_class = block(presentation, "final class ChatListFolderDragPresentation")
    presentation_class = presentation_class.replace("ChatListFolderDragPresentation", "ExtractedDragPresentation").replace("Foundation.Timer", "TestTimer").replace("self.image = origin.snapshot", "self.image = NSImage(size: origin.bounds.size)")
    presentation_class = presentation_class.replace("let layer = CALayer()", "let layer = TestMotionLayer()")
    fixture = fixture.replace("__PRESENTATION_CHECKS__", Path(__file__).with_name("PresentationChecks.swift.in").read_text().replace("__ACTUAL_PRESENTATION__", presentation_class))
else:
    fixture = fixture.replace("__PRESENTATION_CHECKS__", "")
fixture = fixture.replace("__VISIBILITY_CALL__", "updateFolderDragVisibility()" if "private func updateFolderDragVisibility()" in row else "")
if refined:
    fixture = fixture.replace("__PRESENTATION__", "\n".join(block(presentation, marker) for marker in ["func lift()", "private func restore()", "func invalidate()"] ))
else:
    fixture = fixture.replace("__PRESENTATION__", "func lift() { origin.alphaValue = 0 }; func invalidate() { origin.alphaValue = 1 }")
for key, value in {"PRODUCTION": production, "ROW": row_body, "TOP": top_body, "SIDE": side_body, "SEGMENT": segment_body, "FEATURE": "true" if drop else "false"}.items():
    fixture = fixture.replace("__" + key + "__", value)
if not drop:
    start = fixture.index("func featureChecks() {")
    end = fixture.index("\nfeatureChecks()", start)
    fixture = fixture[:start] + "func featureChecks() {}\n" + fixture[end:]
    fixture = fixture.replace("__SOURCE__", "nil")
else:
    fixture = fixture.replace("__SOURCE__", "ChatListFolderDragSource(context: context, peer: peer)")

if not refined:
    fixture = fixture.replace("top.configure(context)", "").replace("side.configure(context); ", "")
    fixture = fixture.replace("\nrefinementChecks()", "")
    if "func refinementChecks() {" in fixture:
        start = fixture.index("func refinementChecks() {")
        fixture = fixture[:start] + fixture[fixture.index("\nfeatureChecks()", start):]
else:
    fixture = fixture.replace("__REFINED__", "true")
checks = {
    "top_registered": "registerForDraggedTypes([ChatListFolderDrop.pasteboardType])" in top,
    "sidebar_registered": "registerForDraggedTypes(environment?.folderDropTypes ?? [])" in source("packages/SidebarUI/Sources/SidebarUI/LeftSidebarController.swift") if refined else "registerForDraggedTypes(item.environment.folderDropTypes)" in sidebar,
    "reuse_cancels_drag": "folderDragSource?.consume()" in row,
    "sidebar_app_bridge": (("return ChatListFolderDropTarget(context: accountContext, scrollView: scrollView, horizontal: false, target: target, visibleTargets: visibleTargets)" if dock else "return ChatListFolderDropTarget(context: accountContext, scrollView: scrollView, horizontal: false, target: target)") if refined else "return ChatListFolderDrop.perform(sender, context: accountContext, filter: filter)") in source("Telegram-Mac/packages-integration/bridges/SidebarUIIntegration.swift"),
    "dock_explicit_geometry_bridge": "visibleTargets: visibleTargets" in source("Telegram-Mac/packages-integration/bridges/SidebarUIIntegration.swift") and "enumerateVisibleViews" in source("packages/SidebarUI/Sources/SidebarUI/LeftSidebarController.swift") and "segment.contentViews" in top,
    "dock_plate_is_eventless_overlay": "view.addSubview(overlay, positioned: .above, relativeTo: nil)" in drop_target and "private final class ChatListFolderDropPlateView: NSView" in drop_target,
    "dock_only_content_is_scaled": 'let animation = CABasicAnimation(keyPath: "transform")' in drop_target and "layer.animateScaleSpring(from: 0.96" not in drop_target and "return [imageView]" in sidebar,
    "dock_native_screen_frame": "for: nil, classes: [NSPasteboardItem.self]" in drop and "presentation?.dragFrame = item.draggingFrame" in drop and "dragFrame.isEmpty ? fallback : dragFrame" in presentation,
    "dock_handoff_no_second_bounce": "restore()" in presentation and "animateScaleSpring(from: 1.07" not in presentation,
    "smooth_compositor_interpolation": "let group = CAAnimationGroup()" in presentation and "group.delegate = self" in presentation and "panel.setFrame(value.frame" not in presentation,
    "lift_and_hidden_slot": "presentation.lift()" in row,
    "native_cancel_return_disabled": "animatesToStartingPositionsOnCancelOrFail = false" in row,
    "scroll_both_axes": "origin.x = chatListFolderDropScrollOffset" in drop_target and "origin.y = chatListFolderDropScrollOffset" in drop_target,
    "reduced_motion": "accessibilityDisplayShouldReduceMotion" in presentation and "accessibilityDisplayShouldReduceMotion" in drop_target,
    "existing_visibility_hook": "updateFolderDragVisibility()" in block(row[row.index("public class ChatListRowView:"):], "public override func updateAnimatableContent()") and "open func updateAnimatableContent()" in source("packages/TGUIKit/Sources/TableRowView.swift") and "override func updateIsVisible" not in row[row.index("public class ChatListRowView:"):],
}
fixture = fixture.replace("__VALIDATE__", "return ChatListFolderDrop.validate(sender, context: context, filter: filter)" if drop else "return []")
fixture = fixture.replace("__PERFORM__", "return ChatListFolderDrop.perform(sender, context: context, filter: filter)" if drop else "return false")
fixture = fixture.replace("__WIRING__", "\n".join("check(" + str(value).lower() + ", " + json.dumps(key) + ")" for key, value in checks.items()))
if args.output:
    output = args.output.absolute()
    if output.exists() or output.is_symlink() or any(p.is_symlink() for p in output.parents):
        raise SystemExit("Output must be a new directory with no symlink ancestors")
    output.mkdir(mode=0o700)
    temporary = None
else:
    temporary = tempfile.TemporaryDirectory(prefix="folder-drop-")
    output = Path(temporary.name)
try:
    for name in ("tmp", "cache"):
        (output / name).mkdir(mode=0o700)
    env.update(TMPDIR=str(output / "tmp"), CLANG_MODULE_CACHE_PATH=str(output / "cache"), SWIFT_MODULECACHE_PATH=str(output / "cache"))
    swift = output / "main.swift"
    if args.sdk_typecheck:
        fixture = Path(__file__).with_name("SDKBoundary.swift.in").read_text()
        fixture = fixture.replace("__PRESENTATION__", "\n".join(line for line in presentation.splitlines() if not line.startswith("import ")))
        fixture = fixture.replace("__TARGET__", "\n".join(line for line in drop_target.splitlines() if not line.startswith("import ")))
        for key, marker in {"CONTENT_VIEWS": "    var contentViews:", "ITEM_CONTENT_VIEWS": "    public var contentViews:", "VISIBLE_ITEMS": "public var visibleItems:", "ITEM_AT_POINT": "public func item(at point:"}.items():
            fixture = fixture.replace("__" + key + "__", block(segment, marker) if marker in segment else "")
    swift.write_text(fixture)
    command = ["xcrun", "swiftc", "-j2", "-module-cache-path", str(output / "cache"), str(swift), "-o", str(output / "checks")]
    if args.sdk_typecheck:
        command = command[:-2] + ["-typecheck"]
    compiled = subprocess.run(command, env=env, text=True, capture_output=True)
    (output / "compile.log").write_text(compiled.stdout + compiled.stderr)
    result = {"revision": args.revision or git("rev-parse", "HEAD").strip(), "core_revision": core_revision, "feature_present": bool(drop), "compiled": compiled.returncode == 0, "fixture_sha256": hashlib.sha256(fixture.encode()).hexdigest(), "wiring": checks}
    if compiled.returncode:
        print(compiled.stderr)
        result["status"] = "COMPILE_ERROR_NOT_A_REGRESSION_RESULT"
        code = 2
    elif args.sdk_typecheck:
        result.update(status="TYPECHECK_PASS", exit_code=0)
        code = 0
        print("SDK typecheck passed")
    else:
        ran = subprocess.run([str(output / "checks")], env=env, text=True, capture_output=True)
        (output / "tests.log").write_text(ran.stdout + ran.stderr)
        print(ran.stdout, end="")
        print(ran.stderr, end="")
        result.update(status="PASS" if ran.returncode == 0 else "ASSERTION_FAILURE", exit_code=ran.returncode)
        for line in ran.stdout.splitlines():
            if line.startswith("checks="):
                result.update({key: int(value) for key, value in (part.split("=") for part in line.split())})
        code = ran.returncode
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
finally:
    if temporary:
        temporary.cleanup()
raise SystemExit(code)
