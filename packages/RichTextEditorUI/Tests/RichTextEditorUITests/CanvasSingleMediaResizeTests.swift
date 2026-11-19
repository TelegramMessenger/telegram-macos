#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
private final class ResizableMediaView: NSView, RichTextMediaBlockResizing {
    let content = NSView()
    let resource = NSObject()
    var widths: [CGFloat] = []
    var maximumHeights: [CGFloat] = []
    var resizedWhileAttached: [Bool] = []
    var acceptsResize = true
    private let sizeForWidth: (CGFloat) -> NSSize

    init(width: CGFloat, sizeForWidth: @escaping (CGFloat) -> NSSize) {
        self.sizeForWidth = sizeForWidth
        super.init(frame: CGRect(origin: .zero, size: sizeForWidth(width)))
        content.frame = bounds
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    func resizeMediaBlock(toWidth width: CGFloat, maxHeight: CGFloat) -> Bool {
        widths.append(width)
        maximumHeights.append(maxHeight)
        resizedWhileAttached.append(superview != nil)
        guard acceptsResize else { return false }
        var size = sizeForWidth(width)
        size.height = min(size.height, maxHeight)
        setFrameSize(size)
        content.frame = bounds
        return true
    }
}

@available(macOS 12, *)
final class CanvasSingleMediaResizeTests: AppKitTestCase {
    private func canvas(kind: RichTextEditorUI.MediaKind = .image, spoiler: Bool = false,
                        provider: @escaping (String, String, Bool, CGFloat) -> NSView?) -> DocumentCanvasView {
        let canvas = DocumentCanvasView()
        canvas.mediaBlockViewProvider = provider
        canvas.setModelBlocks([
            .media(MediaBlock(id: BlockID("media"), kind: kind, mediaID: "asset", caption: [TextRun(text: "caption")], spoiler: spoiler)),
            .core(.paragraph(ParagraphBlock(id: BlockID("after"), runs: [TextRun(text: "following text")]))),
        ], width: 640)
        layout(canvas, width: 640)
        return canvas
    }

    private func layout(_ canvas: DocumentCanvasView, width: CGFloat) {
        canvas.frame = CGRect(x: 0, y: 0, width: width, height: 900)
        canvas.setParagraphsWidthIfNeeded(width)
        canvas.layout()
        canvas.layout()
    }

    func testPhotoShrinksExpandsAndReturnsToOriginalWidthInPlace() throws {
        var providerWidths: [CGFloat] = []
        let canvas = canvas { _, _, _, width in
            providerWidths.append(width)
            return ResizableMediaView(width: width) { NSSize(width: $0, height: $0 / 4) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        let view = try XCTUnwrap(original.view as? ResizableMediaView)
        let content = view.content
        let resource = view.resource
        let interaction = try XCTUnwrap(original.interactionView)
        var removed = 0
        canvas.mediaBlockViewWillRemove = { _ in removed += 1 }
        let widths: [CGFloat] = [320, 800, 480, 640]
        for width in widths {
            layout(canvas, width: width)
            let hosted = try XCTUnwrap(canvas.mediaBlockViews["media"])
            XCTAssertTrue(hosted === original)
            XCTAssertTrue(hosted.view === view)
            XCTAssertTrue(view.content === content)
            XCTAssertTrue(view.resource === resource)
            XCTAssertTrue(hosted.interactionView === interaction)
            XCTAssertTrue(view.superview === canvas.mediaBlockHost)
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(view.frame.width, width, accuracy: 0.01)
            XCTAssertEqual(hosted.canvasFrame, view.frame)
            XCTAssertEqual(interaction.frame, view.frame)
            XCTAssertEqual(view.frame.minX, 0, accuracy: 0.01)
            XCTAssertEqual(view.frame.height, width / 4, accuracy: 0.01)
            XCTAssertEqual(content.frame.size, view.frame.size)
            XCTAssertEqual(hosted.availableWidth, width)
            XCTAssertEqual(canvas.mediaBlockHost.subviews.count, 2)
        }
        XCTAssertEqual(providerWidths, [640])
        XCTAssertEqual(view.widths, widths)
        XCTAssertTrue(view.resizedWhileAttached.allSatisfy { $0 })
        XCTAssertEqual(removed, 0)
    }

    func testVideoUsesNewFullBleedWidthWithoutReplacingView() throws {
        var count = 0
        let canvas = canvas(kind: .video) { _, _, _, width in
            count += 1
            return ResizableMediaView(width: width) { NSSize(width: $0, height: $0 / 2) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        layout(canvas, width: 360)
        let hosted = try XCTUnwrap(canvas.mediaBlockViews["media"])
        XCTAssertTrue(hosted === original)
        XCTAssertEqual(hosted.view.frame.width, 360, accuracy: 0.01)
        XCTAssertEqual(hosted.view.frame.height, 180, accuracy: 0.01)
        XCTAssertEqual(hosted.view.frame.minX, 0, accuracy: 0.01)
        XCTAssertEqual(count, 1)
    }

    func testLegacyMapUsesNewContentWidthAndHeight() throws {
        let canvas = canvas(kind: .map) { _, _, _, width in
            NSView(frame: CGRect(x: 0, y: 0, width: width, height: width * 0.375))
        }
        layout(canvas, width: 360)
        let box = try XCTUnwrap(canvas.boxes.first as? MediaBlockBox)
        let hosted = try XCTUnwrap(canvas.mediaBlockViews["media"])
        let width = 360 - canvas.contentMargin * 2
        XCTAssertEqual(hosted.view.frame.width, width, accuracy: 0.01)
        XCTAssertEqual(hosted.view.frame.height, width * 0.375, accuracy: 0.01)
        XCTAssertEqual(hosted.view.frame.minX, box.frame.minX, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(box.hostHeight), width * 0.375, accuracy: 0.01)
    }

    func testLegacyFileKeepsItsNaturalWidthWithoutRebuildingEveryLayout() throws {
        var widths: [CGFloat] = []
        let canvas = canvas(kind: .file) { _, _, _, width in
            widths.append(width)
            return NSView(frame: CGRect(x: 0, y: 0, width: min(180, width), height: 40))
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        for _ in 0..<5 { layout(canvas, width: 640) }
        XCTAssertTrue(canvas.mediaBlockViews["media"] === original)
        XCTAssertEqual(widths.count, 1)
        layout(canvas, width: 140)
        XCTAssertEqual(try XCTUnwrap(canvas.mediaBlockViews["media"]).view.frame.width,
                       140 - canvas.contentMargin * 2, accuracy: 0.01)
        layout(canvas, width: 500)
        XCTAssertEqual(try XCTUnwrap(canvas.mediaBlockViews["media"]).view.frame.width, 180, accuracy: 0.01)
        for _ in 0..<5 { layout(canvas, width: 500) }
        XCTAssertEqual(widths.count, 3)
    }

    func testLegacyAudioKeepsProviderNaturalSize() throws {
        var requestedWidth: CGFloat = 0
        let canvas = canvas(kind: .audio) { _, _, _, width in
            requestedWidth = width
            return NSView(frame: CGRect(x: 0, y: 0, width: min(220, width), height: 48))
        }
        layout(canvas, width: 200)
        let hosted = try XCTUnwrap(canvas.mediaBlockViews["media"])
        XCTAssertEqual(requestedWidth, 200 - canvas.contentMargin * 2, accuracy: 0.01)
        XCTAssertEqual(hosted.view.frame.width, requestedWidth, accuracy: 0.01)
        XCTAssertEqual(hosted.view.frame.height, 48, accuracy: 0.01)
    }

    func testLegacyResizeTearsDownOldViewAndInteractionOnce() throws {
        let canvas = canvas { _, _, _, width in
            NSView(frame: CGRect(x: 0, y: 0, width: width, height: 80))
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        let interaction = try XCTUnwrap(original.interactionView)
        var removed: [NSView] = []
        canvas.mediaBlockViewWillRemove = { removed.append($0) }
        layout(canvas, width: 300)
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.first === original.view)
        XCTAssertNil(original.view.superview)
        XCTAssertNil(interaction.superview)
        let replacement = try XCTUnwrap(canvas.mediaBlockViews["media"])
        XCTAssertFalse(replacement === original)
        XCTAssertTrue(replacement.view.superview === canvas.mediaBlockHost)
        XCTAssertEqual(replacement.interactionView?.frame, replacement.view.frame)
        XCTAssertEqual(canvas.mediaBlockHost.subviews.count, 2)
        layout(canvas, width: 300)
        XCTAssertEqual(removed.count, 1)
    }

    func testUnavailableLegacyReplacementRemovesStaleWideViewAndRetries() throws {
        var available = true
        let canvas = canvas { _, _, _, width in
            available ? NSView(frame: CGRect(x: 0, y: 0, width: width, height: 80)) : nil
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        var teardownCount = 0
        canvas.mediaBlockViewWillRemove = { _ in teardownCount += 1 }
        available = false
        layout(canvas, width: 300)
        XCTAssertNil(canvas.mediaBlockViews["media"])
        XCTAssertNil(original.view.superview)
        XCTAssertTrue(canvas.mediaBlockHost.subviews.isEmpty)
        XCTAssertEqual(teardownCount, 1)
        available = true
        layout(canvas, width: 300)
        XCTAssertEqual(try XCTUnwrap(canvas.mediaBlockViews["media"]).view.frame.width, 300, accuracy: 0.01)
        XCTAssertEqual(teardownCount, 1)
    }

    func testCaptionAndSelectionSurviveInPlaceResize() throws {
        let canvas = canvas { _, _, _, width in
            ResizableMediaView(width: width) { NSSize(width: $0, height: $0 / 4) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        let box = try XCTUnwrap(canvas.boxes.first as? MediaBlockBox)
        canvas.setCaret(global: box.textStart + 1)
        canvas.setSelectionHead(global: box.textStart + 5)
        let anchor = canvas.anchor
        let head = canvas.head
        layout(canvas, width: 300)
        XCTAssertTrue(canvas.boxes.first as? MediaBlockBox === box)
        XCTAssertTrue(canvas.mediaBlockViews["media"] === original)
        XCTAssertEqual(canvas.anchor, anchor)
        XCTAssertEqual(canvas.head, head)
        XCTAssertEqual(box.caption.attributedString.string, "caption")
        XCTAssertEqual(box.mediaID, "asset")
        XCTAssertEqual(box.id, BlockID("media"))
    }

    func testDeclinedSpoilerResizePreservesIdentityAndSpoilerInFallback() throws {
        var requests: [(String, String, Bool, CGFloat)] = []
        let canvas = canvas(kind: .video, spoiler: true) { kind, id, spoiler, width in
            requests.append((kind, id, spoiler, width))
            let view = ResizableMediaView(width: width) { NSSize(width: $0, height: 100) }
            view.acceptsResize = !spoiler
            return view
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        var removed: [NSView] = []
        canvas.mediaBlockViewWillRemove = { removed.append($0) }
        layout(canvas, width: 300)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.0, "video")
        XCTAssertEqual(requests.last?.1, "asset")
        XCTAssertEqual(requests.last?.2, true)
        XCTAssertEqual(requests.last?.3, 300)
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.first === original.view)
        XCTAssertEqual(canvas.mediaBlockViews["media"]?.spoiler, true)
    }

    func testInPlaceHeightReflowsFollowingParagraphAndRespectsCap() throws {
        let canvas = canvas { _, _, _, width in
            ResizableMediaView(width: width) { NSSize(width: $0, height: $0) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        let view = try XCTUnwrap(original.view as? ResizableMediaView)
        let oldY = canvas.boxes[1].frame.minY
        layout(canvas, width: 240)
        let box = try XCTUnwrap(canvas.boxes.first as? MediaBlockBox)
        XCTAssertTrue(canvas.mediaBlockViews["media"] === original)
        XCTAssertEqual(view.frame.height, 240, accuracy: 0.01)
        XCTAssertEqual(box.mediaAreaHeight, 240, accuracy: 0.01)
        XCTAssertLessThan(canvas.boxes[1].frame.minY, oldY)
        XCTAssertGreaterThan(box.textOrigin.y, view.frame.maxY)
        layout(canvas, width: 800)
        XCTAssertEqual(view.frame.height, CanvasMetrics.maxMediaHeight, accuracy: 0.01)
        XCTAssertEqual(view.content.frame.size, view.frame.size)
        XCTAssertEqual(view.maximumHeights, [CanvasMetrics.maxMediaHeight, CanvasMetrics.maxMediaHeight])
        XCTAssertGreaterThan(box.textOrigin.y, view.frame.maxY)
        let followingFrame = canvas.boxes[1].frame
        for _ in 0..<5 { layout(canvas, width: 800) }
        XCTAssertEqual(view.widths, [240, 800])
        XCTAssertEqual(canvas.boxes[1].frame, followingFrame)
        XCTAssertEqual(box.hostHeight, CanvasMetrics.maxMediaHeight)
    }

    func testSubpixelChangesAccumulateWithoutChurningOrSkippingRealResize() throws {
        var count = 0
        let canvas = canvas { _, _, _, width in
            count += 1
            return ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
        }
        let hosted = try XCTUnwrap(canvas.mediaBlockViews["media"])
        let view = try XCTUnwrap(hosted.view as? ResizableMediaView)
        for width: CGFloat in [640.2, 640.4] { layout(canvas, width: width) }
        XCTAssertTrue(view.widths.isEmpty)
        layout(canvas, width: 640.6)
        layout(canvas, width: 640.8)
        XCTAssertTrue(canvas.mediaBlockViews["media"] === hosted)
        XCTAssertEqual(view.widths, [640.6])
        XCTAssertEqual(count, 1)
    }

    func testRemovalAfterInPlaceResizeTearsDownOriginalViewOnlyOnce() throws {
        let canvas = canvas { _, _, _, width in
            ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        var removed: [NSView] = []
        var attachedAtTeardown: [Bool] = []
        canvas.mediaBlockViewWillRemove = {
            removed.append($0)
            attachedAtTeardown.append($0.superview != nil)
        }
        layout(canvas, width: 300)
        canvas.setBlocks([.paragraph(ParagraphBlock(id: BlockID("replacement")))], width: 300)
        layout(canvas, width: 300)
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.first === original.view)
        XCTAssertEqual(attachedAtTeardown, [true])
        XCTAssertNil(original.view.superview)
        XCTAssertNil(original.interactionView?.superview)
        XCTAssertTrue(canvas.mediaBlockViews.isEmpty)
        XCTAssertTrue(canvas.mediaBlockHost.subviews.isEmpty)
    }

    func testReusableViewDoesNotNeedProviderDuringResize() throws {
        var providerAvailable = true
        var count = 0
        let canvas = canvas { _, _, _, width in
            count += 1
            guard providerAvailable else { return nil }
            return ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        providerAvailable = false
        layout(canvas, width: 300)
        XCTAssertTrue(canvas.mediaBlockViews["media"] === original)
        XCTAssertEqual(original.view.frame.width, 300, accuracy: 0.01)
        XCTAssertEqual(count, 1)
    }

    func testDeclinedResizeAndUnavailableProviderTearDownAndRetry() throws {
        var available = true
        let canvas = canvas { _, _, _, width in
            guard available else { return nil }
            let view = ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
            view.acceptsResize = false
            return view
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        var teardownCount = 0
        canvas.mediaBlockViewWillRemove = { _ in teardownCount += 1 }
        available = false
        layout(canvas, width: 300)
        XCTAssertNil(canvas.mediaBlockViews["media"])
        XCTAssertTrue(canvas.mediaBlockHost.subviews.isEmpty)
        XCTAssertEqual(teardownCount, 1)
        XCTAssertEqual((original.view as? ResizableMediaView)?.widths, [300])
        available = true
        layout(canvas, width: 300)
        XCTAssertEqual(canvas.mediaBlockViews["media"]?.view.frame.width, 300)
        XCTAssertEqual(teardownCount, 1)
    }

    func testReusableNaturalWidthIsSeparateFromAvailableWidth() throws {
        var count = 0
        let canvas = canvas(kind: .file) { _, _, _, width in
            count += 1
            return ResizableMediaView(width: width) { NSSize(width: min(180, $0), height: 40) }
        }
        let hosted = try XCTUnwrap(canvas.mediaBlockViews["media"])
        let view = try XCTUnwrap(hosted.view as? ResizableMediaView)
        layout(canvas, width: 140)
        XCTAssertEqual(view.frame.width, 140 - canvas.contentMargin * 2, accuracy: 0.01)
        layout(canvas, width: 500)
        XCTAssertEqual(view.frame.width, 180, accuracy: 0.01)
        for _ in 0..<5 { layout(canvas, width: 500) }
        XCTAssertTrue(canvas.mediaBlockViews["media"] === hosted)
        XCTAssertEqual(view.widths, [140 - canvas.contentMargin * 2, 500 - canvas.contentMargin * 2])
        XCTAssertEqual(count, 1)
    }

    func testSpoilerAwareReusableProviderKeepsSpoilerAndInteraction() throws {
        var spoilers: [Bool] = []
        let canvas = canvas(spoiler: true) { _, _, spoiler, width in
            spoilers.append(spoiler)
            return ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
        }
        let hosted = try XCTUnwrap(canvas.mediaBlockViews["media"])
        canvas.selectMediaBlock(id: BlockID("media"))
        let interaction = try XCTUnwrap(hosted.interactionView)
        layout(canvas, width: 300)
        XCTAssertTrue(canvas.mediaBlockViews["media"] === hosted)
        XCTAssertEqual(hosted.spoiler, true)
        XCTAssertEqual(spoilers, [true])
        XCTAssertTrue(hosted.interactionView === interaction)
        XCTAssertEqual(canvas.soleSelectedMediaBlock()?.id, BlockID("media"))
        XCTAssertEqual(interaction.frame, hosted.view.frame)
    }

    func testModelReplacementWithSameBlockIDDoesNotReuseDifferentMedia() throws {
        var ids: [String] = []
        let canvas = canvas { _, id, _, width in
            ids.append(id)
            return ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        var removed: [NSView] = []
        canvas.mediaBlockViewWillRemove = { removed.append($0) }
        layout(canvas, width: 300)
        layout(canvas, width: 640)
        canvas.setModelBlocks([.media(MediaBlock(id: BlockID("media"), kind: .image, mediaID: "replacement"))], width: 640)
        layout(canvas, width: 640)
        let replacement = try XCTUnwrap(canvas.mediaBlockViews["media"])
        XCTAssertFalse(replacement === original)
        XCTAssertEqual(ids, ["asset", "replacement"])
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.first === original.view)
        layout(canvas, width: 300)
        XCTAssertTrue(canvas.mediaBlockViews["media"] === replacement)
        XCTAssertEqual(replacement.view.frame.width, 300, accuracy: 0.01)
        XCTAssertEqual(ids.count, 2)
    }

    func testModelSpoilerChangeCannotReuseUnspoileredView() throws {
        var spoilers: [Bool] = []
        let canvas = canvas { _, _, spoiler, width in
            spoilers.append(spoiler)
            return ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        canvas.setModelBlocks([.media(MediaBlock(id: BlockID("media"), kind: .image, mediaID: "asset", spoiler: true))], width: 640)
        layout(canvas, width: 640)
        XCTAssertFalse(canvas.mediaBlockViews["media"] === original)
        XCTAssertEqual(spoilers, [false, true])
        XCTAssertEqual(canvas.mediaBlockViews["media"]?.spoiler, true)
        XCTAssertNil(original.view.superview)
        XCTAssertNil(original.interactionView?.superview)
    }

    func testModelKindChangeCannotReuseOldRenderer() throws {
        var kinds: [String] = []
        let canvas = canvas { kind, _, _, width in
            kinds.append(kind)
            return ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        canvas.setModelBlocks([.media(MediaBlock(id: BlockID("media"), kind: .video, mediaID: "asset"))], width: 640)
        layout(canvas, width: 640)
        XCTAssertFalse(canvas.mediaBlockViews["media"] === original)
        XCTAssertEqual(kinds, ["image", "video"])
    }

    func testSpoilerToggleTearsDownOnceAndThenReusesNewView() throws {
        var spoilers: [Bool] = []
        let canvas = canvas { _, _, spoiler, width in
            spoilers.append(spoiler)
            return ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
        }
        let original = try XCTUnwrap(canvas.mediaBlockViews["media"])
        var removed: [NSView] = []
        canvas.mediaBlockViewWillRemove = { removed.append($0) }
        layout(canvas, width: 300)
        canvas.setMediaSpoiler(blockID: BlockID("media"), tileIndex: nil, spoiler: true)
        layout(canvas, width: 300)
        let replacement = try XCTUnwrap(canvas.mediaBlockViews["media"])
        layout(canvas, width: 500)
        XCTAssertTrue(canvas.mediaBlockViews["media"] === replacement)
        XCTAssertEqual(spoilers, [false, true])
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.first === original.view)
        XCTAssertEqual(replacement.spoiler, true)
    }

    func testCanvasDeinitCleansReusedViewExactlyOnce() throws {
        weak var weakCanvas: DocumentCanvasView?
        var view: NSView?
        var removed: [NSView] = []
        try autoreleasepool {
            let canvas = self.canvas { _, _, _, width in
                ResizableMediaView(width: width) { NSSize(width: $0, height: 80) }
            }
            weakCanvas = canvas
            view = try XCTUnwrap(canvas.mediaBlockViews["media"]?.view)
            canvas.mediaBlockViewWillRemove = { removed.append($0) }
            layout(canvas, width: 300)
            layout(canvas, width: 640)
        }
        XCTAssertNil(weakCanvas)
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.first === view)
    }
}
#endif
