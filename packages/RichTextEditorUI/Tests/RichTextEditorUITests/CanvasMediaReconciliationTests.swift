#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasMediaReconciliationTests: AppKitTestCase {
    private final class Preview: NSView {
        var mediaIDs: [String] = []
        var spoilers: [Bool] = []
        var kind: String?
    }

    private func canvas(_ blocks: [CanvasModelBlock]) -> DocumentCanvasView {
        let canvas = DocumentCanvasView()
        canvas.mediaBlockViewProvider = { kind, id, spoiler, width in
            let view = Preview(frame: CGRect(x: 0, y: 0, width: width, height: 100))
            view.mediaIDs = [id]
            view.spoilers = [spoiler]
            view.kind = kind
            return view
        }
        canvas.mediaGroupMosaic = { ids, width in
            ids.indices.map { CGRect(x: 0, y: CGFloat($0) * 60, width: width, height: 60) }
        }
        canvas.mediaGroupTileProvider = { id, spoiler, size in
            let view = Preview(frame: CGRect(origin: .zero, size: size))
            view.mediaIDs = [id]
            view.spoilers = [spoiler]
            return view
        }
        canvas.mediaGroupSliderProvider = { ids, width in
            let view = Preview(frame: CGRect(x: 0, y: 0, width: width, height: 150))
            view.mediaIDs = ids
            return view
        }
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        canvas.setModelBlocks(blocks, width: 400)
        layout(canvas)
        return canvas
    }

    private func layout(_ canvas: DocumentCanvasView) {
        canvas.layoutSubtreeIfNeeded()
        canvas.layoutSubtreeIfNeeded()
    }

    private func undoManager(_ canvas: DocumentCanvasView) -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        canvas.undoManagerOverride = manager
        return manager
    }

    private func edit(_ manager: UndoManager, _ body: () -> Void) {
        manager.beginUndoGrouping()
        body()
        manager.endUndoGrouping()
    }

    private func single(_ id: String = "a", kind: RichTextEditorUI.MediaKind = .image, spoiler: Bool = false) -> CanvasModelBlock {
        .media(MediaBlock(id: BlockID("single"), kind: kind, mediaID: id, spoiler: spoiler))
    }

    private func group(_ kind: MediaGroupKind, ids: [String] = ["a", "b"], spoilers: [Bool] = []) -> CanvasModelBlock {
        .mediaGroup(MediaGroupBlock(id: BlockID("group"), kind: kind, mediaIDs: ids, spoilers: spoilers))
    }

    func test_singleReplacementUndoRedoReconcilesPreviewAndOverlay() throws {
        let canvas = canvas([single()])
        let manager = undoManager(canvas)
        var removed: [NSView] = []
        canvas.mediaBlockViewWillRemove = { removed.append($0) }
        let original = try XCTUnwrap(canvas.mediaBlockViews["single"])
        let overlay = try XCTUnwrap(original.interactionView)
        edit(manager) { canvas.replaceMedia(blockID: "single", newMediaID: "b") }
        layout(canvas)
        XCTAssertEqual((canvas.mediaBlockViews["single"]?.view as? Preview)?.mediaIDs, ["b"])
        XCTAssertNil(original.view.superview)
        XCTAssertNil(overlay.superview)
        manager.undo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaBlockViews["single"]?.view as? Preview)?.mediaIDs, ["a"])
        manager.redo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaBlockViews["single"]?.view as? Preview)?.mediaIDs, ["b"])
        XCTAssertEqual(removed.count, 3)
        XCTAssertEqual(Set(removed.map(ObjectIdentifier.init)).count, 3)
        layout(canvas)
        XCTAssertEqual(removed.count, 3)
    }

    func test_singleSpoilerUndoRedoReconcilesPreview() {
        let canvas = canvas([single()])
        let manager = undoManager(canvas)
        edit(manager) { canvas.setMediaSpoiler(blockID: BlockID("single"), tileIndex: nil, spoiler: true) }
        layout(canvas)
        XCTAssertEqual((canvas.mediaBlockViews["single"]?.view as? Preview)?.spoilers, [true])
        manager.undo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaBlockViews["single"]?.view as? Preview)?.spoilers, [false])
        manager.redo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaBlockViews["single"]?.view as? Preview)?.spoilers, [true])
    }

    func test_singleSameIdentityDifferentKindRebuildsPreview() {
        let canvas = canvas([single(kind: .image)])
        canvas.setModelBlocks([single(kind: .video)], width: 400)
        layout(canvas)
        XCTAssertEqual((canvas.mediaBlockViews["single"]?.view as? Preview)?.kind, "video")
    }

    func test_captionUndoAndSnapshotReuseUnchangedPreviews() throws {
        let canvas = canvas([single(), group(.collage)])
        let manager = undoManager(canvas)
        let singleView = try XCTUnwrap(canvas.mediaBlockViews["single"])
        let tile = try XCTUnwrap(canvas.mediaGroupTileViews["group#0"])
        var removed = 0
        canvas.mediaBlockViewWillRemove = { _ in removed += 1 }
        canvas.setCaret(global: canvas.boxes[0].textStart)
        edit(manager) { canvas.commitText("caption") }
        layout(canvas)
        manager.undo()
        layout(canvas)
        canvas.setModelBlocks(canvas.currentModelBlocks(), width: 400)
        layout(canvas)
        XCTAssertTrue(canvas.mediaBlockViews["single"] === singleView)
        XCTAssertTrue(canvas.mediaGroupTileViews["group#0"] === tile)
        XCTAssertEqual(removed, 0)
    }

    func test_singleMissingReplacementDropsStaleViewAndRetries() throws {
        let canvas = canvas([single()])
        let old = try XCTUnwrap(canvas.mediaBlockViews["single"])
        var removed = 0
        canvas.mediaBlockViewWillRemove = { _ in removed += 1 }
        let provider = canvas.mediaBlockViewProvider
        canvas.mediaBlockViewProvider = { _, _, _, _ in nil }
        canvas.setModelBlocks([single("missing")], width: 400)
        layout(canvas)
        XCTAssertNil(canvas.mediaBlockViews["single"])
        XCTAssertNil(old.view.superview)
        XCTAssertNil(old.interactionView?.superview)
        XCTAssertEqual(removed, 1)
        canvas.mediaBlockViewProvider = provider
        canvas.syncMediaBlockViews()
        XCTAssertEqual((canvas.mediaBlockViews["single"]?.view as? Preview)?.mediaIDs, ["missing"])
        XCTAssertEqual(removed, 1)
    }

    func test_collageReplacementUndoRedoReusesUnaffectedTile() throws {
        let canvas = canvas([group(.collage)])
        let manager = undoManager(canvas)
        let unchanged = try XCTUnwrap(canvas.mediaGroupTileViews["group#1"])
        var removed = 0
        canvas.mediaBlockViewWillRemove = { _ in removed += 1 }
        edit(manager) { canvas.replaceGroupMedia(groupID: "group", index: 0, newMediaID: "c") }
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#0"]?.view as? Preview)?.mediaIDs, ["c"])
        manager.undo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#0"]?.view as? Preview)?.mediaIDs, ["a"])
        manager.redo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#0"]?.view as? Preview)?.mediaIDs, ["c"])
        XCTAssertTrue(canvas.mediaGroupTileViews["group#1"] === unchanged)
        XCTAssertEqual(removed, 3)
    }

    func test_collageSpoilerUndoRedoReusesUnaffectedTile() throws {
        let canvas = canvas([group(.collage)])
        let manager = undoManager(canvas)
        let unchanged = try XCTUnwrap(canvas.mediaGroupTileViews["group#1"])
        edit(manager) { canvas.setMediaSpoiler(blockID: BlockID("group"), tileIndex: 0, spoiler: true) }
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#0"]?.view as? Preview)?.spoilers, [true])
        manager.undo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#0"]?.view as? Preview)?.spoilers, [false])
        manager.redo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#0"]?.view as? Preview)?.spoilers, [true])
        XCTAssertTrue(canvas.mediaGroupTileViews["group#1"] === unchanged)
    }

    func test_collageRemovalUndoReconcilesShiftedTiles() {
        let canvas = canvas([group(.collage, ids: ["a", "b", "c"])])
        let manager = undoManager(canvas)
        edit(manager) { canvas.removeCollageTile(group: BlockID("group"), index: 0) }
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#0"]?.view as? Preview)?.mediaIDs, ["b"])
        XCTAssertEqual((canvas.mediaGroupTileViews["group#1"]?.view as? Preview)?.mediaIDs, ["c"])
        XCTAssertNil(canvas.mediaGroupTileViews["group#2"])
        manager.undo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#0"]?.view as? Preview)?.mediaIDs, ["a"])
        XCTAssertEqual((canvas.mediaGroupTileViews["group#2"]?.view as? Preview)?.mediaIDs, ["c"])
    }

    func test_sliderAddReplaceRemoveUndoRedoReconcilesLegacyProvider() {
        let canvas = canvas([group(.slideshow)])
        let manager = undoManager(canvas)
        var removed: [NSView] = []
        canvas.mediaBlockViewWillRemove = { removed.append($0) }
        edit(manager) { canvas.addMediaToGroup(groupID: BlockID("group"), mediaIDs: ["c"]) }
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Preview)?.mediaIDs, ["a", "b", "c"])
        manager.undo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Preview)?.mediaIDs, ["a", "b"])
        manager.redo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Preview)?.mediaIDs, ["a", "b", "c"])
        edit(manager) { canvas.replaceGroupMedia(groupID: "group", index: 1, newMediaID: "d") }
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Preview)?.mediaIDs, ["a", "d", "c"])
        manager.undo()
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Preview)?.mediaIDs, ["a", "b", "c"])
        edit(manager) { canvas.removeCollageTile(group: BlockID("group"), index: 0) }
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Preview)?.mediaIDs, ["b", "c"])
        XCTAssertEqual(removed.count, 6)
        XCTAssertTrue(removed.allSatisfy { $0.superview == nil })
    }

    func test_sliderSnapshotReorderReconcilesAndUnchangedSnapshotReuses() throws {
        let canvas = canvas([group(.slideshow)])
        let original = try XCTUnwrap(canvas.mediaGroupTileViews["group#slider"])
        canvas.setModelBlocks(canvas.currentModelBlocks(), width: 400)
        layout(canvas)
        XCTAssertTrue(canvas.mediaGroupTileViews["group#slider"] === original)
        canvas.setModelBlocks([group(.slideshow, ids: ["b", "a"])], width: 400)
        layout(canvas)
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Preview)?.mediaIDs, ["b", "a"])
    }

    func test_sliderUnavailableReplacementDropsStaleViewAndRetries() throws {
        let canvas = canvas([group(.slideshow)])
        let original = try XCTUnwrap(canvas.mediaGroupTileViews["group#slider"])
        let provider = canvas.mediaGroupSliderProvider
        var removed = 0
        canvas.mediaBlockViewWillRemove = { _ in removed += 1 }
        canvas.mediaGroupSliderProvider = { _, _ in nil }
        canvas.addMediaToGroup(groupID: BlockID("group"), mediaIDs: ["c"])
        layout(canvas)
        XCTAssertNil(canvas.mediaGroupTileViews["group#slider"])
        XCTAssertNil(original.view.superview)
        XCTAssertEqual(removed, 1)
        canvas.mediaGroupSliderProvider = provider
        canvas.syncMediaGroupViews()
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Preview)?.mediaIDs, ["a", "b", "c"])
        XCTAssertEqual(removed, 1)
    }

    func test_groupKindAndDeletionTearDownHostedPreviewsOnce() {
        let canvas = canvas([group(.slideshow)])
        var removed: [NSView] = []
        canvas.mediaBlockViewWillRemove = { removed.append($0) }
        canvas.setMediaGroupKind(groupID: BlockID("group"), kind: .collage)
        layout(canvas)
        XCTAssertNil(canvas.mediaGroupTileViews["group#slider"])
        XCTAssertEqual(removed.count, 1)
        canvas.setMediaGroupKind(groupID: BlockID("group"), kind: .slideshow)
        layout(canvas)
        XCTAssertEqual(removed.count, 3)
        XCTAssertTrue(canvas.mediaGroupOverlays.isEmpty)
        canvas.removeMediaBlock(id: BlockID("group"))
        layout(canvas)
        XCTAssertEqual(removed.count, 4)
        XCTAssertTrue(canvas.mediaGroupTileViews.isEmpty)
        XCTAssertEqual(Set(removed.map(ObjectIdentifier.init)).count, 4)
    }

    func test_canvasDeinitTearsDownSingleCollageAndSlider() {
        for kind in [MediaGroupKind.collage, .slideshow] {
            var removed = 0
            weak var released: DocumentCanvasView?
            autoreleasepool {
                let canvas = canvas([single(), group(kind)])
                released = canvas
                canvas.mediaBlockViewWillRemove = { _ in removed += 1 }
            }
            XCTAssertNil(released)
            XCTAssertEqual(removed, kind == .collage ? 3 : 2)
        }
    }
}
#endif
