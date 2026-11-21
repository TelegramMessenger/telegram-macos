#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Overlay that hosts the (interactive) media-block views. Unlike the emoji/spoiler overlays, a hit
/// inside a hosted media view must REACH it (so the file/audio/map view handles clicks); a hit on an
/// empty area passes THROUGH to the canvas so text editing still works. (`hitTest`'s `point` is in the
/// superview's coords; a subview's `hitTest` expects the point in its superview's coords — i.e. ours.)
@available(macOS 12, *)
final class InteractiveMediaOverlayView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for sub in subviews.reversed() {
            if let hit = sub.hitTest(local) { return hit }
        }
        return nil
    }
}

/// A clickable, translucent overlay placed ON TOP of a hosted media view: clicking it selects the media
/// block, and it tints with the select colour while the block is selected. (The package can't use TGUIKit
/// `Control`, so this is a plain `NSView` that forwards `mouseDown`. It does not call `super`, so the click
/// is consumed as a "select" rather than reaching the media view's own — currently no-op — actions.)
@available(macOS 12, *)
final class MediaInteractionOverlayView: NSView {
    var onMouseDown: (() -> Void)?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }
}

/// One pooled host media view + its last placed canvas frame (used for culling) + the clickable
/// selection/interaction overlay sitting above it.
@available(macOS 12, *)
final class HostedMediaBlock {
    let view: NSView
    var canvasFrame: CGRect
    var interactionView: MediaInteractionOverlayView?
    var mediaID: String?
    var spoiler: Bool?
    var mediaIDs: [String]?
    var spoilers: [Bool]?
    init(view: NSView, canvasFrame: CGRect) { self.view = view; self.canvasFrame = canvasFrame }
}

@available(macOS 12, *)
extension DocumentCanvasView {
    /// Inserts a macOS-only media block (file/audio/map) at the caret, replacing any selection. Mirrors
    /// `insertImage`: splits a paragraph if mid-text, otherwise inserts before/after the caret's block;
    /// the caret lands in the block's (initially empty) caption so the user can type one immediately. The
    /// host media view is realized in the next layout pass (`syncMediaBlockViews`).
    func insertMediaBlock(kind: MediaKind, mediaID: String) {
        guard !boxes.isEmpty else { return }
        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            guard let pos = resolveBox(at: head) else { return }
            let media = MediaBlock(id: BlockID.generate(), kind: kind, mediaID: mediaID)
            let mediaBox = MediaBlockBox(media: media, mapper: mapper, width: effectiveWidth)
            var newBoxes = boxes
            if let p = pos.box as? BlockBox, pos.local > 0, pos.local < p.textLength {
                let (upper, lower) = p.currentParagraph().split(at: pos.local, newID: BlockID.generate())
                let upperBox = BlockBox(paragraph: upper, mapper: mapper, width: effectiveWidth)
                let lowerBox = BlockBox(paragraph: lower, mapper: mapper, width: effectiveWidth)
                let replacement: [any CanvasBlock] = [upperBox, mediaBox, lowerBox]
                newBoxes.replaceSubrange(pos.index...pos.index, with: replacement)
            } else if pos.local == 0 {
                newBoxes.insert(mediaBox, at: pos.index)            // before the caret's block
            } else {
                newBoxes.insert(mediaBox, at: pos.index + 1)        // after the caret's block
            }
            boxes = newBoxes
            recomputeSpans()
            anchor = mediaBox.textStart; head = mediaBox.textStart  // caret in the caption
        }
        needsLayout = true
    }

    /// Reconciles host media views against the `MediaBlockBox`es present: pools/realizes by block id,
    /// frames each to its box's content rect, learns the view's height back into the box (so it reserves
    /// the right space), and removes views whose block no longer exists. Called at the END of layout.
    func syncMediaBlockViews() {
        var present = Set<String>()
        var heightChanged = false
        for case let box as MediaBlockBox in boxes {
            let key = box.id.rawValue
            present.insert(key)
            // Video bleeds to the canvas edge (full width past both page margins); other media stay within
            // the content strip.
            let bleed = box.mediaBleeds ? box.contentMargin : 0
            let contentWidth = box.frame.width + bleed * 2
            let hosted: HostedMediaBlock
            if let h = mediaBlockViews[key] {
                hosted = h
            } else if let v = mediaBlockViewProvider(box.kind.rawValue, box.mediaID, box.spoiler, contentWidth) {
                let h = HostedMediaBlock(view: v, canvasFrame: .zero)
                mediaBlockViews[key] = h
                mediaBlockHost.addSubview(v)
                hosted = h
            } else {
                continue
            }
            // The host sized the view (e.g. a file chip narrower than the column); keep its natural size,
            // left-aligned in the media area above the caption.
            let viewSize = hosted.view.frame.size
            if box.hostHeight == nil || abs(box.hostHeight! - viewSize.height) > 0.5 {
                box.hostHeight = viewSize.height
                heightChanged = true
            }
            // Clamp the hosted view to the (capped) reserved media height so a tall video can't overflow
            // into the caption; `box.mediaAreaHeight` caps at `CanvasMetrics.maxMediaHeight`.
            let clampedSize = NSSize(width: viewSize.width, height: box.mediaAreaHeight)
            let frame = CGRect(origin: CGPoint(x: box.frame.minX - bleed, y: box.mediaOrigin.y), size: clampedSize)
            hosted.view.frame = frame
            hosted.canvasFrame = frame
            // Click-to-select overlay, always above the media view.
            let blockID = box.id
            let interaction = hosted.interactionView ?? {
                let v = MediaInteractionOverlayView(); v.wantsLayer = true
                v.onMouseDown = { [weak self] in self?.selectMediaBlock(id: blockID) }
                hosted.interactionView = v
                return v
            }()
            interaction.frame = frame
            mediaBlockHost.addSubview(interaction, positioned: .above, relativeTo: hosted.view)
        }
        for (k, h) in mediaBlockViews where !present.contains(k) {
            mediaBlockViewWillRemove?(h.view)      // host releases the content node's resources first
            h.interactionView?.removeFromSuperview()
            h.view.removeFromSuperview(); mediaBlockViews[k] = nil
        }
        // A learned height changes the box's height → re-lay out so neighbours reflow; the change-guard
        // and the post-layout content-height report converge it (no loop once heights match).
        if heightChanged { needsLayout = true }
        cullMediaBlockViews()
    }

    /// Media blocks whose media area lies inside the current text selection — i.e. the selection covers
    /// the block's atom (the gap before the caption). Matches the cross-block delete's "covered middle
    /// box" rule, so a media block highlighted by the selection is also the one removed on delete. A
    /// selection that only touches the caption text (starting at/after `textStart`) does NOT cover it.
    func mediaBoxesInSelection() -> [MediaBlockBox] {
        guard selFrom != selTo else { return [] }
        return boxes.compactMap { $0 as? MediaBlockBox }.filter { selFrom <= $0.nodeStart && $0.nodeStart < selTo }
    }

    /// Tints each media block's interaction overlay with the select colour while the block is inside the
    /// selection, clears it otherwise (the media view sits ABOVE the canvas, so the text-selection fill in
    /// `draw(_:)` can't reach it). Called on every selection change (`notifySelectionChanged`) and after
    /// layout, so it tracks live during a drag.
    func updateMediaSelectionHighlight() {
        let active = selFrom != selTo
        let color = (window?.firstResponder === self ? editorAppearance.selectionFocused
                                                       : editorAppearance.selectionUnfocused).cgColor
        for case let media as MediaBlockBox in boxes {
            guard let hosted = mediaBlockViews[media.id.rawValue] else { continue }
            let covered = active && selFrom <= media.nodeStart && media.nodeStart < selTo
            hosted.interactionView?.layer?.backgroundColor = covered ? color : NSColor.clear.cgColor
        }
    }

    /// Clicking a media block selects it (covers its atom, so it highlights and Backspace/Delete removes
    /// it via `soleSelectedMediaBlock`). The caption text is left unselected so a follow-up click into the
    /// caption still edits it. Clicking an already-selected block toggles the selection off (collapses to a
    /// caret before the atom), which is the native behaviour.
    func selectMediaBlock(id: BlockID) {
        guard let media = boxes.first(where: { $0.id == id }) as? MediaBlockBox else { return }
        window?.makeFirstResponder(self)
        if soleSelectedMediaBlock()?.id == id {
            setCaret(global: media.nodeStart)   // second click → deselect (clears the accent highlight)
            return
        }
        setCaret(global: media.nodeStart)
        setSelectionHead(global: media.textStart)
    }

    /// Media/table blocks that are ENTIRELY inside the selection (e.g. via select-all). These must be
    /// removed on delete: the cross-block text engine only drops MIDDLE boxes, and the multi-region clear
    /// deliberately preserves table structure — so a fully-covered block would otherwise survive as an
    /// emptied husk. A table counts as covered only when the selection STARTS at/before its node (which an
    /// in-table cell selection cannot — cell positions sit past `nodeStart`) and reaches its last cell's
    /// end: select-all, or a drag from before the table through it. A cell-to-cell selection, even one
    /// touching every cell, clears content but keeps the grid.
    func mediaBoxesFullyCovered() -> [CanvasBlock] {
        guard selFrom != selTo else { return [] }
        return boxes.filter { box in
            if box is MediaBlockBox || box is ImageBlockBox || box is MediaGroupBlockBox {
                return selFrom <= box.nodeStart && selTo >= box.textStart + box.textLength
            }
            if box is TableBlockBox {
                guard let last = box.leafRegions().last else { return false }
                return selFrom <= box.nodeStart && selTo >= last.globalStart + last.length
            }
            if box is ButtonRowBox {
                // A row's textStart + textLength collapses onto nodeStart (text-free), so coverage is
                // judged against its interior atom span instead.
                return selFrom <= box.nodeStart && selTo >= box.nodeStart + box.nodeSize - 2
            }
            return false
        }
    }

    /// The single media block the selection is confined to (a click-select "handle" — covers only the
    /// atom, not spanning into text). `nil` for a text/multi-block span (the cross-block delete handles
    /// those). Lets Backspace/Delete remove a click-selected media block.
    func soleSelectedMediaBlock() -> MediaBlockBox? {
        let media = mediaBoxesInSelection()
        guard media.count == 1, let m = media.first else { return nil }
        return (selFrom >= m.nodeStart && selTo <= m.textStart) ? m : nil
    }

    /// Hides media views whose canvas frame falls outside the visible viewport expanded by the margin.
    func cullMediaBlockViews() {
        let visible = enclosingScrollView?.contentView.bounds ?? bounds
        let expanded = visible.insetBy(dx: -mediaBlockCullMargin, dy: -mediaBlockCullMargin)
        for (_, h) in mediaBlockViews { h.view.isHidden = !expanded.intersects(h.canvasFrame) }
        for (_, h) in mediaGroupTileViews { h.view.isHidden = !expanded.intersects(h.canvasFrame) }
    }
}
#endif
