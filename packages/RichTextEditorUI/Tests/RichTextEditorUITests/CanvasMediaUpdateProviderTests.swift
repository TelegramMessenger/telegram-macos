#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasMediaUpdateProviderTests: AppKitTestCase {
    private final class Slider: NSView {
        var mediaIDs: [String] = []
        var spoilers: [Bool] = []
        var currentPage = 0
    }

    private func layout(_ canvas: DocumentCanvasView) {
        canvas.layoutSubtreeIfNeeded()
        canvas.layoutSubtreeIfNeeded()
    }

    private func seed(_ canvas: DocumentCanvasView) {
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        canvas.setModelBlocks([.mediaGroup(MediaGroupBlock(id: BlockID("group"), kind: .slideshow, mediaIDs: ["a", "b"]))], width: 400)
        layout(canvas)
    }

    func test_updateProviderRebindsSameViewAcrossEditsAndUndoRedo() throws {
        let canvas = DocumentCanvasView()
        var updates = 0
        var removals = 0
        canvas.mediaBlockViewWillRemove = { _ in removals += 1 }
        canvas.mediaGroupSliderUpdateProvider = { ids, spoilers, width, existing in
            updates += 1
            let view = (existing as? Slider) ?? Slider(frame: .zero)
            view.mediaIDs = ids
            view.spoilers = spoilers
            view.frame.size = CGSize(width: width, height: 150)
            return view
        }
        seed(canvas)
        let hosted = try XCTUnwrap(canvas.mediaGroupTileViews["group#slider"])
        let slider = try XCTUnwrap(hosted.view as? Slider)
        slider.currentPage = 1
        let manager = UndoManager()
        manager.groupsByEvent = false
        canvas.undoManagerOverride = manager
        manager.beginUndoGrouping()
        canvas.addMediaToGroup(groupID: BlockID("group"), mediaIDs: ["c"])
        manager.endUndoGrouping()
        layout(canvas)
        XCTAssertEqual(slider.mediaIDs, ["a", "b", "c"])
        manager.undo()
        layout(canvas)
        XCTAssertEqual(slider.mediaIDs, ["a", "b"])
        manager.redo()
        layout(canvas)
        XCTAssertEqual(slider.mediaIDs, ["a", "b", "c"])
        manager.beginUndoGrouping()
        canvas.replaceGroupMedia(groupID: "group", index: 0, newMediaID: "d")
        manager.endUndoGrouping()
        layout(canvas)
        XCTAssertEqual(slider.mediaIDs, ["d", "b", "c"])
        XCTAssertEqual(slider.currentPage, 1)
        XCTAssertTrue(canvas.mediaGroupTileViews["group#slider"] === hosted)
        XCTAssertEqual(updates, 5)
        canvas.setModelBlocks(canvas.currentModelBlocks(), width: 400)
        layout(canvas)
        XCTAssertEqual(updates, 5)
        XCTAssertEqual(removals, 0)
    }

    func test_updateProviderReceivesRestoredSpoilersAndWidth() throws {
        let canvas = DocumentCanvasView()
        var updates = 0
        canvas.mediaGroupSliderUpdateProvider = { ids, spoilers, width, existing in
            updates += 1
            let view = (existing as? Slider) ?? Slider(frame: .zero)
            view.mediaIDs = ids
            view.spoilers = spoilers
            view.frame.size = CGSize(width: width, height: 160)
            return view
        }
        seed(canvas)
        let slider = try XCTUnwrap(canvas.mediaGroupTileViews["group#slider"]?.view as? Slider)
        let manager = UndoManager()
        manager.groupsByEvent = false
        canvas.undoManagerOverride = manager
        manager.beginUndoGrouping()
        canvas.setMediaSpoiler(blockID: BlockID("group"), tileIndex: 1, spoiler: true)
        manager.endUndoGrouping()
        layout(canvas)
        XCTAssertEqual(slider.spoilers, [false, true])
        manager.undo()
        layout(canvas)
        XCTAssertEqual(slider.spoilers, [false, false])
        manager.redo()
        layout(canvas)
        XCTAssertEqual(slider.spoilers, [false, true])
        canvas.frame.size.width = 520
        canvas.needsLayout = true
        layout(canvas)
        XCTAssertEqual(slider.frame.width, 520, accuracy: 0.5)
        XCTAssertEqual(updates, 5)
        XCTAssertTrue(canvas.mediaGroupTileViews["group#slider"]?.view === slider)
    }

    func test_updateProviderReplacementAndFailureTearDownExactlyOnce() throws {
        let canvas = DocumentCanvasView()
        var fail = false
        var removed: [NSView] = []
        canvas.mediaBlockViewWillRemove = { removed.append($0) }
        canvas.mediaGroupSliderUpdateProvider = { ids, spoilers, width, _ in
            guard !fail else { return nil }
            let view = Slider(frame: CGRect(x: 0, y: 0, width: width, height: 140))
            view.mediaIDs = ids
            view.spoilers = spoilers
            return view
        }
        seed(canvas)
        let original = try XCTUnwrap(canvas.mediaGroupTileViews["group#slider"]?.view)
        canvas.addMediaToGroup(groupID: BlockID("group"), mediaIDs: ["c"])
        layout(canvas)
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.first === original)
        XCTAssertNil(original.superview)
        fail = true
        canvas.replaceGroupMedia(groupID: "group", index: 0, newMediaID: "d")
        layout(canvas)
        XCTAssertNil(canvas.mediaGroupTileViews["group#slider"])
        XCTAssertEqual(removed.count, 2)
        canvas.syncMediaGroupViews()
        XCTAssertEqual(removed.count, 2)
        fail = false
        canvas.syncMediaGroupViews()
        XCTAssertEqual((canvas.mediaGroupTileViews["group#slider"]?.view as? Slider)?.mediaIDs, ["d", "b", "c"])
    }

    func test_legacyRegistrationReplacesUpdateProvider() {
        let editor = RichTextEditorView()
        editor.registerMediaGroupSliderProvider { _, _, _, _ in nil }
        XCTAssertNotNil(editor.canvas.mediaGroupSliderUpdateProvider)
        editor.registerMediaGroupSliderProvider { _, width in NSView(frame: CGRect(x: 0, y: 0, width: width, height: 160)) }
        XCTAssertNil(editor.canvas.mediaGroupSliderUpdateProvider)
    }
}
#endif
