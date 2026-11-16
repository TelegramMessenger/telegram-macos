#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasLastMediaDeletionTests: AppKitTestCase {
    private func canvas(_ blocks: [CanvasModelBlock]) -> DocumentCanvasView {
        let canvas = DocumentCanvasView()
        canvas.setModelBlocks(blocks, width: 400)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    private func assertEditableEmptyParagraph(_ canvas: DocumentCanvasView, file: StaticString = #filePath,
                                              line: UInt = #line) throws {
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.boxes.count, 1, file: file, line: line)
        let paragraph = try XCTUnwrap(canvas.boxes.first as? BlockBox, file: file, line: line)
        XCTAssertEqual(paragraph.style, .body, file: file, line: line)
        XCTAssertNil(paragraph.listMembership, file: file, line: line)
        XCTAssertEqual(paragraph.textLength, 0, file: file, line: line)
        XCTAssertEqual(canvas.anchor, paragraph.textStart, file: file, line: line)
        XCTAssertEqual(canvas.head, paragraph.textStart, file: file, line: line)
        XCTAssertEqual(canvas.documentSize, paragraph.nodeSize, file: file, line: line)
        XCTAssertEqual(canvas.leafRegion(containingGlobal: canvas.head)?.0.ref, paragraph.textRef, file: file, line: line)
        let caret = canvas.caretRect(forGlobal: canvas.head)
        XCTAssertGreaterThan(caret.height, 0, file: file, line: line)
        XCTAssertGreaterThan(caret.width, 0, file: file, line: line)
    }

    private func assertRemovalRoundTrip(_ canvas: DocumentCanvasView, delete: (DocumentCanvasView) -> Void,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        let before = canvas.currentModelBlocks()
        let anchor = canvas.anchor, head = canvas.head
        let undo = UndoManager(); undo.groupsByEvent = false; canvas.undoManagerOverride = undo
        undo.beginUndoGrouping(); delete(canvas); undo.endUndoGrouping()
        try assertEditableEmptyParagraph(canvas, file: file, line: line)
        let empty = canvas.currentModelBlocks()
        undo.undo()
        XCTAssertEqual(canvas.currentModelBlocks(), before, file: file, line: line)
        XCTAssertEqual(canvas.anchor, anchor, file: file, line: line)
        XCTAssertEqual(canvas.head, head, file: file, line: line)
        XCTAssertFalse(undo.canUndo, file: file, line: line)
        undo.redo()
        XCTAssertEqual(canvas.currentModelBlocks(), empty, file: file, line: line)
        try assertEditableEmptyParagraph(canvas, file: file, line: line)
        undo.beginUndoGrouping(); canvas.commitText("New text"); undo.endUndoGrouping()
        XCTAssertEqual(canvas.currentParagraphs().map(\.text), ["New text"], file: file, line: line)
        XCTAssertEqual(canvas.head, canvas.boxes[0].textStart + 8, file: file, line: line)
        undo.undo()
        XCTAssertEqual(canvas.currentModelBlocks(), empty, file: file, line: line)
        try assertEditableEmptyParagraph(canvas, file: file, line: line)
        undo.undo()
        XCTAssertEqual(canvas.currentModelBlocks(), before, file: file, line: line)
        XCTAssertEqual(canvas.anchor, anchor, file: file, line: line)
        XCTAssertEqual(canvas.head, head, file: file, line: line)
    }

    func test_removeLastHostedMedia_leavesEditableParagraphAndUndoes() throws {
        for kind: RichTextEditorUI.MediaKind in [.image, .video, .file, .audio, .map] {
            let canvas = canvas([.media(MediaBlock(id: BlockID("m"), kind: kind, mediaID: "asset",
                                                   caption: [TextRun(text: "Caption", attributes: CharacterAttributes(bold: true))],
                                                   spoiler: true))])
            canvas.setCaret(global: canvas.boxes[0].textStart + 3)
            try assertRemovalRoundTrip(canvas) { $0.removeMediaBlock(id: BlockID("m")) }
        }
    }

    func test_removeLastLegacyImage_leavesEditableParagraphAndUndoes() throws {
        let canvas = canvas([])
        canvas.boxes = [ImageBlockBox(media: MediaBlock(id: BlockID("image"), kind: .image, mediaID: "asset"),
                                     mapper: canvas.mapper, width: 400)]
        canvas.recomputeSpans()
        canvas.setCaret(global: canvas.boxes[0].textStart)
        try assertRemovalRoundTrip(canvas) { $0.removeMediaBlock(id: BlockID("image")) }
    }

    func test_removeLastGroup_leavesEditableParagraphAndUndoes() throws {
        for kind: MediaGroupKind in [.collage, .slideshow] {
            let canvas = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("g"), kind: kind, mediaIDs: ["a", "b"],
                                                            caption: [TextRun(text: "Caption")], spoilers: [true, false]))])
            canvas.setCaret(global: canvas.boxes[0].textStart + 2)
            try assertRemovalRoundTrip(canvas) { $0.removeMediaBlock(id: BlockID("g")) }
        }
    }

    func test_removeLastCollageTile_leavesEditableParagraphAndUndoes() throws {
        let canvas = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("g"), mediaIDs: ["only"]))])
        canvas.selectCollageTile(group: BlockID("g"), index: 0)
        try assertRemovalRoundTrip(canvas) { $0.performDeleteBackward() }
        XCTAssertNil(canvas.selectedCollageTile)
    }

    func test_deleteSelectedLastMedia_leavesEditableParagraphAndUndoes() throws {
        for forward in [false, true] {
            let canvas = canvas([.media(MediaBlock(id: BlockID("m"), kind: .image, mediaID: "asset"))])
            canvas.selectMediaBlock(id: BlockID("m"))
            try assertRemovalRoundTrip(canvas) {
                if forward { $0.deleteForward(nil) } else { $0.performDeleteBackward() }
            }
        }
    }

    func test_backspaceAtLastMediaCaptionStart_leavesEditableParagraphAndUndoes() throws {
        for block: CanvasModelBlock in [
            .media(MediaBlock(id: BlockID("m"), kind: .video, mediaID: "asset")),
            .mediaGroup(MediaGroupBlock(id: BlockID("g"), mediaIDs: ["a", "b"]))
        ] {
            let canvas = canvas([block])
            canvas.setCaret(global: canvas.boxes[0].textStart)
            try assertRemovalRoundTrip(canvas) { $0.performDeleteBackward() }
        }
    }

    func test_removeMedia_preservesRemainingParagraphsAndCaretPlacement() {
        for index in 0...2 {
            var blocks: [CanvasModelBlock] = [
                .core(.paragraph(ParagraphBlock(id: BlockID("a"), style: .heading1, runs: [TextRun(text: "Before")]))),
                .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "After")]))),
            ]
            blocks.insert(.media(MediaBlock(id: BlockID("m"), kind: .file, mediaID: "asset")), at: index)
            let canvas = canvas(blocks)
            let remaining = canvas.boxes.enumerated().filter { $0.offset != index }.map(\.element)
            let expected = remaining.map { $0.currentModelBlock() }
            canvas.removeMediaBlock(id: BlockID("m"))
            XCTAssertEqual(canvas.currentModelBlocks(), expected)
            XCTAssertEqual(canvas.boxes.count, 2)
            XCTAssertTrue(canvas.boxes[0] === remaining[0])
            XCTAssertTrue(canvas.boxes[1] === remaining[1])
            let caret = index > 0 ? remaining[index - 1].textStart + remaining[index - 1].textLength : remaining[0].textStart
            XCTAssertEqual(canvas.anchor, caret)
            XCTAssertEqual(canvas.head, caret)
        }
    }

    func test_removeMedia_doesNotAddParagraphWhenAnotherMediaRemains() {
        let canvas = canvas([
            .media(MediaBlock(id: BlockID("a"), kind: .image, mediaID: "image")),
            .media(MediaBlock(id: BlockID("b"), kind: .file, mediaID: "file")),
        ])
        let remaining = canvas.boxes[1].currentModelBlock()
        canvas.removeMediaBlock(id: BlockID("a"))
        XCTAssertEqual(canvas.currentModelBlocks(), [remaining])
        XCTAssertEqual(canvas.anchor, canvas.boxes[0].textStart)
        XCTAssertEqual(canvas.head, canvas.boxes[0].textStart)
    }

    func test_removeNonfinalTile_doesNotAddParagraph() {
        let canvas = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("g"), mediaIDs: ["a", "b"]))])
        canvas.removeCollageTile(group: BlockID("g"), index: 0)
        XCTAssertEqual(canvas.boxes.count, 1)
        XCTAssertEqual((canvas.boxes[0] as? MediaGroupBlockBox)?.mediaIDs, ["b"])
    }

    func test_emptySeedAndUnrelatedEditing_areNotNormalized() {
        let canvas = canvas([])
        canvas.removeMediaBlock(id: BlockID("missing"))
        canvas.editing { }
        XCTAssertTrue(canvas.boxes.isEmpty)
    }
}
#endif
