#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Media GROUP (collage) blocks: inserting a group of ≤10 photos/videos, mosaic-driven media-area height,
/// editable caption, round-trip, and select/delete. Tiles are host-provided; tests fake the mosaic.
@available(macOS 12, *)
final class CanvasMediaGroupTests: AppKitTestCase {
    /// A fake mosaic that stacks each tile full-width, 100pt tall — so the media area = count × 100.
    private static let stackedMosaic: ([String], CGFloat) -> [CGRect] = { ids, w in
        ids.enumerated().map { i, _ in CGRect(x: 0, y: CGFloat(i) * 100, width: w, height: 100) }
    }
    private func seeded(mosaic: (([String], CGFloat) -> [CGRect])? = stackedMosaic) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        if let m = mosaic { v.mediaGroupMosaic = m }
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "hi")]))], width: 400)
        _ = hostInWindow(v); v.frame = CGRect(x: 0, y: 0, width: 400, height: 600); v.layoutSubtreeIfNeeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        return v
    }
    private func groups(_ v: DocumentCanvasView) -> [MediaGroupBlockBox] { v.boxes.compactMap { $0 as? MediaGroupBlockBox } }

    func test_insertCollage_buildsGroupBox() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b", "c"])
        XCTAssertEqual(groups(v).first?.mediaIDs, ["a", "b", "c"])
        XCTAssertEqual(groups(v).first?.kind, .collage)
    }

    func test_mosaicDrivesMediaAreaHeight() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b", "c"])
        XCTAssertEqual(groups(v).first?.mediaAreaHeight ?? 0, 300, accuracy: 0.5, "media area = tallest tile bottom (3×100)")
    }

    func test_noMosaic_usesPlaceholderHeight() {
        let v = seeded(mosaic: nil)
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b"])
        XCTAssertEqual(groups(v).first?.mediaAreaHeight ?? 0, MediaGroupBlockBox.placeholderHeight, accuracy: 0.5)
    }

    func test_collageRoundTripsThroughModel() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b"])
        let found = v.currentModelBlocks().contains {
            if case .mediaGroup(let g) = $0 { return g.mediaIDs == ["a", "b"] && g.kind == .collage } else { return false }
        }
        XCTAssertTrue(found, "the group round-trips through the canvas model")
    }

    func test_outgoingBlocks_preserveCollageAndCaption() {
        let v = seeded()
        v.insertMediaGroup(kind: .slideshow, mediaIDs: ["a", "b", "c"])
        v.commitText("hi")   // caption
        let group = v.outgoingBlocks().compactMap { block -> (String, [String], String)? in
            if case let .mediaGroup(kind, mediaIDs, caption, _) = block { return (kind, mediaIDs, caption.map(\.text).joined()) }
            return nil
        }.first
        XCTAssertEqual(group?.0, "slideshow", "outgoingBlocks carries the group kind as a string")
        XCTAssertEqual(group?.1, ["a", "b", "c"], "…the ordered mediaIDs")
        XCTAssertEqual(group?.2, "hi", "…and the caption runs")
    }

    func test_capsAtTenItems() {
        let g = MediaGroupBlock(id: BlockID("g"), mediaIDs: (0..<15).map { "m\($0)" })
        XCTAssertEqual(g.mediaIDs.count, 10, "an album is capped at 10")
    }

    func test_captionIsEditable() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a"])   // caret lands in the caption
        v.commitText("hey")
        let cap = v.currentModelBlocks().compactMap {
            if case .mediaGroup(let g) = $0 { return g.caption.map(\.text).joined() } else { return nil }
        }.first
        XCTAssertEqual(cap, "hey")
    }

    func test_addMediaToGroup_appends_andCaps() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b"])
        let id = groups(v).first!.id
        v.addMediaToGroup(groupID: id, mediaIDs: ["c", "d"])
        XCTAssertEqual(groups(v).first?.mediaIDs, ["a", "b", "c", "d"])
        v.addMediaToGroup(groupID: id, mediaIDs: (0..<20).map { "x\($0)" })
        XCTAssertEqual(groups(v).first?.mediaIDs.count, 10, "capped at 10")
    }

    func test_setMediaGroupKind_toggles() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b"])
        let id = groups(v).first!.id
        v.setMediaGroupKind(groupID: id, kind: .slideshow)
        XCTAssertEqual(groups(v).first?.kind, .slideshow)
        v.setMediaGroupKind(groupID: id, kind: .collage)
        XCTAssertEqual(groups(v).first?.kind, .collage)
    }

    func test_convertSingleMediaToGroup() {
        let v = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .file, mediaID: "solo")   // a single media block
        let mediaID = v.boxes.compactMap { ($0 as? MediaBlockBox)?.id }.first!
        v.convertMediaToGroup(blockID: mediaID, kind: .collage, addingMediaIDs: ["extra1", "extra2"])
        XCTAssertEqual(groups(v).first?.mediaIDs, ["solo", "extra1", "extra2"], "the single media + added become a collage")
        XCTAssertTrue(v.boxes.compactMap { $0 as? MediaBlockBox }.isEmpty, "the single media block is replaced by the group")
    }

    func test_sliderKind_hostsOneSliderView_andLearnsHeight() {
        let v = seeded()
        v.mediaGroupSliderProvider = { _, width in NSView(frame: CGRect(x: 0, y: 0, width: width, height: 250)) }
        v.insertMediaGroup(kind: .slideshow, mediaIDs: ["a", "b", "c"])
        v.layoutSubtreeIfNeeded()   // runs syncMediaGroupViews → builds the slider, learns its height
        XCTAssertEqual(groups(v).first?.kind, .slideshow)
        XCTAssertEqual(groups(v).first?.hostHeight ?? 0, 250, accuracy: 0.5, "the box learns the slider's height")
        XCTAssertEqual(groups(v).first?.mediaAreaHeight ?? 0, 250, accuracy: 0.5)
    }

    func test_collageEmptyCaption_showsAddCaptionPlaceholder() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b"])
        v.layoutSubtreeIfNeeded()
        XCTAssertTrue(v.placeholderDraws().map(\.text).contains("Add caption…"), "an empty collage caption prompts")
    }

    func test_clickTile_selectsThatTile_togglesOff_andBackspaceRemovesJustIt() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b", "c"])
        let g = groups(v).first!
        v.selectCollageTile(group: g.id, index: 1)
        XCTAssertEqual(v.selectedCollageTile?.index, 1, "clicking a tile selects that tile, not the group")
        v.selectCollageTile(group: g.id, index: 1)
        XCTAssertNil(v.selectedCollageTile, "second click on the same tile deselects")
        v.selectCollageTile(group: g.id, index: 1)
        v.performDeleteBackward()
        XCTAssertEqual(groups(v).first?.mediaIDs, ["a", "c"], "Backspace removes just the selected tile")
        XCTAssertNil(v.selectedCollageTile)
    }

    private func pressShiftReturn(_ v: DocumentCanvasView) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
                                 windowNumber: v.window?.windowNumber ?? 0, context: nil,
                                 characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        v.keyDown(with: e)
    }

    func test_shiftEnterInCollageCaption_exitsIntoNewParagraph() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a"])   // caret lands in the collage caption
        let before = v.boxes.count
        pressShiftReturn(v)
        XCTAssertEqual(v.boxes.count, before + 1, "Shift+Enter adds a paragraph after the collage")
        guard let g = groups(v).first, let gi = v.boxes.firstIndex(where: { $0.id == g.id }) else { return XCTFail() }
        XCTAssertTrue(v.boxes[gi + 1] is BlockBox, "the new block after the collage is a paragraph")
        XCTAssertEqual(v.head, v.boxes[gi + 1].textStart, "caret lands in the new paragraph")
    }

    func test_removeLastTile_dropsTheGroup() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["only"])
        let g = groups(v).first!
        v.selectCollageTile(group: g.id, index: 0)
        v.performDeleteBackward()
        XCTAssertTrue(groups(v).isEmpty, "removing the last tile drops the whole group")
    }

    func test_clickElsewhere_clearsTileSelection() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b"])
        let g = groups(v).first!
        v.selectCollageTile(group: g.id, index: 0)
        XCTAssertNotNil(v.selectedCollageTile)
        v.setCaret(global: v.boxes[0].textStart)   // (typing also clears; explicit click handled in mouseDown)
        v.commitText("x")
        XCTAssertNil(v.selectedCollageTile, "typing clears the tile selection")
    }

    func test_mediaContext_resolvesCollageGroup() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b"])
        v.layoutSubtreeIfNeeded()
        let g = groups(v).first!
        let ctx = v.mediaContext(atCanvasPoint: CGPoint(x: g.frame.midX, y: g.frame.minY + 5))   // media-area band
        XCTAssertEqual(ctx?.kind, "collage")
        XCTAssertEqual(ctx?.blockID, g.id.rawValue)
    }

    func test_contextMenuHandler_suppressesNativeMenu() {
        let v = seeded()
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: v.window?.windowNumber ?? 0, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1)!
        v.contextMenuRequested = { _, _, _, _ in true }
        XCTAssertNil(v.menu(for: event), "host handled → native menu suppressed")
        v.contextMenuRequested = { _, _, _, _ in false }
        XCTAssertNotNil(v.menu(for: event), "host declined → native menu falls back")
    }

    func test_backspaceAtCaptionStart_deletesGroup() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a"])
        XCTAssertEqual(groups(v).count, 1)
        v.setCaret(global: groups(v).first!.textStart)   // caption start
        v.performDeleteBackward()
        XCTAssertEqual(groups(v).count, 0, "Backspace at the caption start removes the whole group")
    }

    func test_mediaID_forGroupTile_andSingleMedia() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["img1", "img2"])
        let g = groups(v).first!
        XCTAssertEqual(v.mediaID(forBlock: g.id, tileIndex: 0), "img1")
        XCTAssertEqual(v.mediaID(forBlock: g.id, tileIndex: 1), "img2")
        XCTAssertNil(v.mediaID(forBlock: g.id, tileIndex: 5), "out-of-range index returns nil")
        XCTAssertNil(v.mediaID(forBlock: BlockID("nonexistent"), tileIndex: 0), "unknown block returns nil")
    }

    func test_removeCollageTile_facade_removesAndDropsGroup() {
        let v = seeded()
        v.insertMediaGroup(kind: .collage, mediaIDs: ["a", "b", "c"])
        let gid = groups(v).first!.id
        v.removeCollageTile(group: gid, index: 1)
        XCTAssertEqual(groups(v).first?.mediaIDs, ["a", "c"], "middle tile removed")
        v.removeCollageTile(group: gid, index: 0)
        v.removeCollageTile(group: gid, index: 0)
        XCTAssertTrue(groups(v).isEmpty, "removing last tile drops the group")
    }

    func test_replaceGroupMedia_swapsId_dropsPooledTile_andUndoes() {
        let v = DocumentCanvasView()
        var built: [String] = []
        v.mediaGroupMosaic = { ids, w in ids.enumerated().map { i, _ in CGRect(x: 0, y: CGFloat(i) * 50, width: w, height: 50) } }
        v.mediaGroupTileProvider = { id, _, size in built.append(id); let view = NSView(); view.frame = CGRect(origin: .zero, size: size); return view }
        v.setModelBlocks([.mediaGroup(MediaGroupBlock(id: BlockID("c"), kind: .collage, mediaIDs: ["a", "b"]))], width: 200)
        v.frame = CGRect(x: 0, y: 0, width: 200, height: 400); v.layoutSubtreeIfNeeded()
        XCTAssertNotNil(v.mediaGroupTileViews["c#0"])

        let um = UndoManager(); um.groupsByEvent = false; v.undoManagerOverride = um
        um.beginUndoGrouping(); v.replaceGroupMedia(groupID: "c", index: 0, newMediaID: "z"); um.endUndoGrouping()
        XCTAssertEqual((v.boxes[0] as! MediaGroupBlockBox).mediaIDs, ["z", "b"], "tile 0 media id swapped")
        XCTAssertNil(v.mediaGroupTileViews["c#0"], "pooled tile view dropped so it rebuilds from the provider")
        v.layoutSubtreeIfNeeded()
        XCTAssertTrue(built.contains("z"), "the new media id was realized")

        um.undo()
        XCTAssertEqual((v.boxes[0] as! MediaGroupBlockBox).mediaIDs, ["a", "b"], "undo restores the original id")
    }

    func test_sliderSpoilerChange_reconcilesHostedPreview() {
        let v = DocumentCanvasView()
        let id = BlockID("slider-spoilers")
        var states: [[Bool]] = []
        v.mediaGroupSliderProvider = { [weak v] _, width in
            let group = v?.boxes.first as? MediaGroupBlockBox
            states.append(group?.spoilers ?? [])
            return NSView(frame: CGRect(x: 0, y: 0, width: width, height: 180))
        }
        v.setModelBlocks([.mediaGroup(MediaGroupBlock(id: id, kind: .slideshow, mediaIDs: ["a", "b"], spoilers: [true, false]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(states.last, [true, false])
        let initialBuilds = states.count
        v.setMediaSpoiler(blockID: id, tileIndex: 1, spoiler: true)
        XCTAssertEqual(states.count, initialBuilds + 1)
        XCTAssertEqual(states.last, [true, true])
        v.setMediaSpoiler(blockID: id, tileIndex: 0, spoiler: false)
        XCTAssertEqual(states.last, [false, true])
        v.syncMediaGroupViews()
        XCTAssertEqual(states.count, initialBuilds + 2)
    }

    func test_sliderSpoilerUndo_reconcilesRestoredState() {
        let v = DocumentCanvasView()
        let id = BlockID("slider-undo")
        var states: [[Bool]] = []
        v.mediaGroupSliderProvider = { [weak v] _, width in
            states.append((v?.boxes.first as? MediaGroupBlockBox)?.spoilers ?? [])
            return NSView(frame: CGRect(x: 0, y: 0, width: width, height: 180))
        }
        v.setModelBlocks([.mediaGroup(MediaGroupBlock(id: id, kind: .slideshow, mediaIDs: ["a", "b"]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        v.layoutSubtreeIfNeeded()
        let manager = UndoManager()
        manager.groupsByEvent = false
        v.undoManagerOverride = manager
        manager.beginUndoGrouping()
        v.setMediaSpoiler(blockID: id, tileIndex: 0, spoiler: true)
        manager.endUndoGrouping()
        XCTAssertEqual(states.last, [true, false])
        manager.undo()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(states.last, [false, false])
        manager.redo()
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(states.last, [true, false])
    }

    func test_sliderKindRoundTrip_preservesOutgoingSpoilers() {
        let v = DocumentCanvasView()
        let id = BlockID("slider-round-trip")
        v.setModelBlocks([.mediaGroup(MediaGroupBlock(id: id, kind: .collage, mediaIDs: ["a", "b"], spoilers: [true, false]))], width: 320)
        for kind in [MediaGroupKind.slideshow, .collage, .slideshow] {
            v.setMediaGroupKind(groupID: id, kind: kind)
            guard case let .mediaGroup(actualKind, ids, _, spoilers)? = v.outgoingBlocks().first else { return XCTFail() }
            XCTAssertEqual(actualKind, kind.rawValue)
            XCTAssertEqual(ids, ["a", "b"])
            XCTAssertEqual(spoilers, [true, false])
        }
    }

    func test_replaceMedia_swapsSingleMediaId() {
        let v = DocumentCanvasView()
        v.mediaBlockViewProvider = { _, _, _, _ in NSView() }
        v.setModelBlocks([.media(MediaBlock(id: BlockID("v"), kind: .video, mediaID: "a"))], width: 200)
        v.frame = CGRect(x: 0, y: 0, width: 200, height: 400); v.layoutSubtreeIfNeeded()
        v.replaceMedia(blockID: "v", newMediaID: "z")
        XCTAssertEqual((v.boxes[0] as! MediaBlockBox).mediaID, "z")
    }
}
#endif
