#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
private final class SelectedSliderView: NSView, MediaGroupSliderSelectionProviding {
    var currentMediaIndex: Int?
}

@available(macOS 12, *)
final class CanvasSliderSelectionTests: AppKitTestCase {
    private func slider() -> (DocumentCanvasView, SelectedSliderView) {
        let canvas = DocumentCanvasView()
        let view = SelectedSliderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.currentMediaIndex = 0
        canvas.mediaGroupSliderProvider = { _, _ in view }
        canvas.setModelBlocks([.mediaGroup(MediaGroupBlock(id: BlockID("slider"), kind: .slideshow, mediaIDs: ["a", "b", "c"]))], width: 320)
        canvas.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        canvas.layoutSubtreeIfNeeded()
        return (canvas, view)
    }

    func test_singleControlResolvesEachDisplayedSlide() {
        let (canvas, view) = slider()
        for index in 0..<3 {
            view.currentMediaIndex = index
            let actual = canvas.mediaTileIndex(forBlock: BlockID("slider"), controlIndex: 0)
            XCTAssertEqual(actual, index)
            XCTAssertEqual(canvas.mediaID(forBlock: BlockID("slider"), tileIndex: actual), ["a", "b", "c"][index])
        }
    }

    func test_unavailableOrStalePageDoesNotFallBackToFirstMedia() {
        let (canvas, view) = slider()
        view.currentMediaIndex = nil
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("slider"), controlIndex: 0))
        view.currentMediaIndex = 3
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("slider"), controlIndex: 0))
        view.currentMediaIndex = -1
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("slider"), controlIndex: 0))
        view.currentMediaIndex = 1
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("slider"), controlIndex: 1))
        canvas.replaceGroupMedia(groupID: "slider", index: 1, newMediaID: "new-b")
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("slider"), controlIndex: 0))
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.mediaTileIndex(forBlock: BlockID("slider"), controlIndex: 0), 1)
        canvas.removeMediaBlock(id: BlockID("slider"))
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("slider"), controlIndex: 0))
    }

    func test_collageAndSingleMediaKeepTheirControlIndex() {
        let canvas = DocumentCanvasView()
        canvas.setModelBlocks([
            .mediaGroup(MediaGroupBlock(id: BlockID("collage"), mediaIDs: ["a", "b", "c"])),
            .media(MediaBlock(id: BlockID("single"), kind: .image, mediaID: "image"))
        ], width: 320)
        XCTAssertEqual(canvas.mediaTileIndex(forBlock: BlockID("collage"), controlIndex: 2), 2)
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("collage"), controlIndex: 3))
        XCTAssertEqual(canvas.mediaTileIndex(forBlock: BlockID("single"), controlIndex: 0), 0)
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("single"), controlIndex: 1))
        XCTAssertNil(canvas.mediaTileIndex(forBlock: BlockID("missing"), controlIndex: 0))
    }

    func test_selectedSpoilerReplaceDeletePreserveOtherMedia() {
        let (canvas, view) = slider()
        let id = BlockID("slider")
        view.currentMediaIndex = 2
        guard let index = canvas.mediaTileIndex(forBlock: id, controlIndex: 0) else { return XCTFail() }
        let captured = canvas.mediaID(forBlock: id, tileIndex: index)
        canvas.setMediaSpoiler(blockID: id, tileIndex: index, spoiler: true)
        XCTAssertFalse(canvas.isMediaSpoiler(blockID: id, tileIndex: 0))
        XCTAssertTrue(canvas.isMediaSpoiler(blockID: id, tileIndex: 2))
        view.currentMediaIndex = 0
        XCTAssertEqual(canvas.mediaID(forBlock: id, tileIndex: index), captured)
        canvas.replaceGroupMedia(groupID: id.rawValue, index: index, newMediaID: "edited-c")
        XCTAssertNotEqual(canvas.mediaID(forBlock: id, tileIndex: index), captured)
        XCTAssertEqual(canvas.mediaID(forBlock: id, tileIndex: 0), "a")
        canvas.removeCollageTile(group: id, index: 1)
        XCTAssertNil(canvas.mediaID(forBlock: id, tileIndex: index))
        XCTAssertEqual((canvas.boxes.first as? MediaGroupBlockBox)?.mediaIDs, ["a", "edited-c"])
    }
}
#endif
