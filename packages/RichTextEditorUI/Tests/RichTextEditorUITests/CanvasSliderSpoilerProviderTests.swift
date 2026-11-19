#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasSliderSpoilerProviderTests: AppKitTestCase {
    func test_providerReceivesFlags_andReusesViewForChanges() {
        let canvas = DocumentCanvasView()
        let id = BlockID("slider")
        var updates: [([String], [Bool])] = []
        var reused: [Bool] = []
        var removals = 0
        canvas.mediaBlockViewWillRemove = { _ in removals += 1 }
        canvas.mediaGroupSliderUpdateProvider = { ids, spoilers, width, existing in
            updates.append((ids, spoilers))
            reused.append(existing != nil)
            return existing ?? NSView(frame: CGRect(x: 0, y: 0, width: width, height: 180))
        }
        canvas.setModelBlocks([.mediaGroup(MediaGroupBlock(id: id, kind: .slideshow, mediaIDs: ["a", "b"], spoilers: [true, false]))], width: 320)
        canvas.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        canvas.layoutSubtreeIfNeeded()
        let original = canvas.mediaGroupTileViews["slider#slider"]?.view
        XCTAssertNotNil(original)
        XCTAssertEqual(updates.last?.1, [true, false])
        canvas.setMediaSpoiler(blockID: id, tileIndex: 1, spoiler: true)
        XCTAssertEqual(updates.last?.1, [true, true])
        XCTAssertTrue(original === canvas.mediaGroupTileViews["slider#slider"]?.view)
        XCTAssertEqual(reused.last, true)
        XCTAssertEqual(removals, 0)
        canvas.replaceGroupMedia(groupID: "slider", index: 1, newMediaID: "c")
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(updates.last?.0, ["a", "c"])
        XCTAssertEqual(updates.last?.1, [true, true])
        canvas.removeCollageTile(group: id, index: 0)
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(updates.last?.0, ["c"])
        XCTAssertEqual(updates.last?.1, [true])
    }

    func test_facadeRegistersSpoilerAwareProvider() {
        let editor = RichTextEditorView()
        var received: [Bool]?
        editor.registerMediaGroupSliderProvider { _, spoilers, width, view in
            received = spoilers
            return view ?? NSView(frame: CGRect(x: 0, y: 0, width: width, height: 180))
        }
        editor.setOutgoingBlocks([.mediaGroup(kind: "slideshow", mediaIDs: ["a", "b"], caption: [], spoilers: [false, true])])
        editor.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        editor.layoutSubtreeIfNeeded()
        XCTAssertEqual(received, [false, true])
    }
}
#endif
