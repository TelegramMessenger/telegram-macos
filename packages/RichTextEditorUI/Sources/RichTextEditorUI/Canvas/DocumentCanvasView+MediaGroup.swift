#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    /// Inserts a collage group (≤10 photos/videos) at the caret, replacing any selection. Mirrors
    /// `insertMediaBlock`: splits the caret's paragraph if mid-text, otherwise inserts before/after the
    /// caret's block; the caret lands in the group's (initially empty) caption. Tiles are realized in the
    /// next layout pass (`syncMediaGroupViews`).
    func insertMediaGroup(kind: MediaGroupKind, mediaIDs: [String]) {
        guard !boxes.isEmpty, !mediaIDs.isEmpty else { return }
        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            guard let pos = resolveBox(at: head) else { return }
            let group = MediaGroupBlock(id: BlockID.generate(), kind: kind, mediaIDs: mediaIDs)
            let box = MediaGroupBlockBox(group: group, mapper: mapper, width: effectiveWidth)
            box.mosaicProvider = mediaGroupMosaic
            var newBoxes = boxes
            if let p = pos.box as? BlockBox, pos.local > 0, pos.local < p.textLength {
                let (upper, lower) = p.currentParagraph().split(at: pos.local, newID: BlockID.generate())
                let upperBox = BlockBox(paragraph: upper, mapper: mapper, width: effectiveWidth)
                let lowerBox = BlockBox(paragraph: lower, mapper: mapper, width: effectiveWidth)
                let replacement: [any CanvasBlock] = [upperBox, box, lowerBox]
                newBoxes.replaceSubrange(pos.index...pos.index, with: replacement)
            } else if pos.local == 0 {
                newBoxes.insert(box, at: pos.index)            // before the caret's block
            } else {
                newBoxes.insert(box, at: pos.index + 1)        // after the caret's block
            }
            boxes = newBoxes
            recomputeSpans()
            anchor = box.textStart; head = box.textStart       // caret in the caption
        }
        needsLayout = true
    }

    func mediaGroupBoxesInSelection() -> [MediaGroupBlockBox] {
        guard selFrom != selTo else { return [] }
        return boxes.compactMap { $0 as? MediaGroupBlockBox }.filter { selFrom <= $0.nodeStart && $0.nodeStart < selTo }
    }

    func soleSelectedMediaGroupBlock() -> MediaGroupBlockBox? {
        let g = mediaGroupBoxesInSelection()
        guard g.count == 1, let box = g.first else { return nil }
        return (selFrom >= box.nodeStart && selTo <= box.textStart) ? box : nil
    }

    /// Selects the individual collage tile under the click (the media below the mouse), not the whole group.
    /// A second click on the same tile deselects. Backspace then removes just that tile.
    func selectCollageTile(group: BlockID, index: Int) {
        window?.makeFirstResponder(self)
        if let s = selectedCollageTile, s.group == group, s.index == index {
            selectedCollageTile = nil
        } else {
            selectedCollageTile = (group, index)
        }
        if let g = boxes.first(where: { $0.id == group }) as? MediaGroupBlockBox { anchor = g.nodeStart; head = g.nodeStart }
        needsDisplay = true
        notifySelectionChanged()
    }

    /// Removes the click-selected tile from its group (Backspace). Removing the last tile drops the group.
    func removeCollageTile(group: BlockID, index: Int) {
        guard let i = boxes.firstIndex(where: { $0.id == group }),
              let box = boxes[i] as? MediaGroupBlockBox, box.mediaIDs.indices.contains(index) else { return }
        selectedCollageTile = nil
        if box.mediaIDs.count <= 1 {
            editing { deleteMediaBox(at: i) }            // last tile → remove the whole group
        } else {
            editing {
                box.mediaIDs.remove(at: index)
                box.spoilers.remove(at: index)
            }
        }
        needsLayout = true
    }

    /// Tints collage tile overlays: the single click-selected tile, plus EVERY tile of a group whose atom
    /// is in the text selection (a drag passing through the collage). Called from `notifySelectionChanged`.
    func updateMediaGroupSelectionHighlight() {
        let active = selFrom != selTo
        let color = (window?.firstResponder === self ? editorAppearance.selectionFocused
                                                      : editorAppearance.selectionUnfocused).cgColor
        for case let g as MediaGroupBlockBox in boxes {
            let groupCovered = active && selFrom <= g.nodeStart && g.nodeStart < selTo
            for i in g.mediaIDs.indices {
                guard let overlay = mediaGroupOverlays["\(g.id.rawValue)#\(i)"] else { continue }
                let tileSelected = selectedCollageTile?.group == g.id && selectedCollageTile?.index == i
                overlay.layer?.backgroundColor = (groupCovered || tileSelected) ? color : NSColor.clear.cgColor
            }
        }
    }

    /// Removes any media block (image / file·audio·map·video / collage·slider group) by id. Undoable.
    func removeMediaBlock(id: BlockID) {
        guard let i = boxes.firstIndex(where: { $0.id == id }), boxes[i] is ImageBlockBox || boxes[i] is MediaBlockBox || boxes[i] is MediaGroupBlockBox else { return }
        editing { boxes[i] is ImageBlockBox ? deleteImageBox(at: i) : deleteMediaBox(at: i) }
        needsLayout = true
    }

    /// Appends media to an existing group (collage/slider), capped at 10. Undoable.
    func addMediaToGroup(groupID: BlockID, mediaIDs: [String]) {
        guard !mediaIDs.isEmpty, let box = boxes.first(where: { $0.id == groupID }) as? MediaGroupBlockBox else { return }
        editing {
            let newIDs = Array((box.mediaIDs + mediaIDs).prefix(10))
            // Keep the per-tile spoilers aligned to the tile count: existing tiles keep their spoiler,
            // added tiles default to not-spoilered.
            box.spoilers = (0 ..< newIDs.count).map { $0 < box.spoilers.count ? box.spoilers[$0] : false }
            box.mediaIDs = newIDs
        }
        needsLayout = true
    }

    func replaceGroupMedia(groupID: String, index: Int, newMediaID: String) {
        guard let box = boxes.first(where: { $0.id == BlockID(groupID) }) as? MediaGroupBlockBox,
              box.mediaIDs.indices.contains(index) else { return }
        editing { box.mediaIDs[index] = newMediaID }
        let key = "\(groupID)#\(index)"
        if let old = mediaGroupTileViews[key] { mediaBlockViewWillRemove?(old.view); old.view.removeFromSuperview(); mediaGroupTileViews[key] = nil }
        if let ov = mediaGroupOverlays[key] { ov.removeFromSuperview(); mediaGroupOverlays[key] = nil }
        mediaControlsViews[groupID]?.removeFromSuperview(); mediaControlsViews[groupID] = nil; mediaControlsSignatures[groupID] = nil
        needsLayout = true
    }

    func replaceMedia(blockID: String, newMediaID: String) {
        guard let i = boxes.firstIndex(where: { $0.id == BlockID(blockID) }) else { return }
        if let m = boxes[i] as? MediaBlockBox {
            editing { m.mediaID = newMediaID }
            if let old = mediaBlockViews[blockID] {
                mediaBlockViewWillRemove?(old.view); old.view.removeFromSuperview()
                old.interactionView?.removeFromSuperview()   // drop the hit-target overlay too (mirrors syncMediaBlockViews)
                mediaBlockViews[blockID] = nil
            }
        } else if let img = boxes[i] as? ImageBlockBox {
            editing { img.assetID = newMediaID }
        } else { return }
        mediaControlsViews[blockID]?.removeFromSuperview(); mediaControlsViews[blockID] = nil; mediaControlsSignatures[blockID] = nil
        needsLayout = true
    }

    /// Toggles a group between collage (mosaic) and slider (paging). Undoable; no-op if already that kind.
    func setMediaGroupKind(groupID: BlockID, kind: MediaGroupKind) {
        guard let box = boxes.first(where: { $0.id == groupID }) as? MediaGroupBlockBox, box.kind != kind else { return }
        editing { box.kind = kind }
        needsLayout = true
    }

    /// Whether the media at `blockID` — a single image/video/media block (`tileIndex == nil`) or a group's
    /// tile (`tileIndex`) — is currently a spoiler. `false` if not found.
    func isMediaSpoiler(blockID: BlockID, tileIndex: Int?) -> Bool {
        guard let box = boxes.first(where: { $0.id == blockID }) else { return false }
        if let g = box as? MediaGroupBlockBox {
            if let i = tileIndex, g.spoilers.indices.contains(i) { return g.spoilers[i] }
            return false
        }
        if let m = box as? MediaBlockBox { return m.spoiler }
        return false
    }

    /// Toggles the Telegram-style spoiler on the media at `blockID` — a single image/video/media block
    /// (`tileIndex == nil`) or a specific group tile (`tileIndex`). One undo step; re-renders the media view.
    func setMediaSpoiler(blockID: BlockID, tileIndex: Int?, spoiler: Bool) {
        guard let box = boxes.first(where: { $0.id == blockID }) else { return }
        if let g = box as? MediaGroupBlockBox {
            guard let i = tileIndex, g.spoilers.indices.contains(i), g.spoilers[i] != spoiler else { return }
            editing { g.spoilers[i] = spoiler }
            // Drop the cached tile view so the sync rebuilds it with the new spoiler (dust) state.
            let key = "\(blockID.rawValue)#\(i)"
            if let old = mediaGroupTileViews[key] { mediaBlockViewWillRemove?(old.view); old.view.removeFromSuperview(); mediaGroupTileViews[key] = nil }
        } else if let m = box as? MediaBlockBox {
            guard m.spoiler != spoiler else { return }
            editing { m.spoiler = spoiler }
            if let old = mediaBlockViews[blockID.rawValue] {
                mediaBlockViewWillRemove?(old.view); old.view.removeFromSuperview()
                old.interactionView?.removeFromSuperview(); mediaBlockViews[blockID.rawValue] = nil
            }
        } else {
            return
        }
        syncMediaBlockViews()
        syncMediaGroupViews()
        needsLayout = true
    }

    /// Converts a single image/video block into a group (collage/slider) — its media + the added media,
    /// inheriting its caption. Undoable. No-op if `blockID` isn't a single image or media block.
    func convertMediaToGroup(blockID: BlockID, kind: MediaGroupKind = .collage, addingMediaIDs: [String]) {
        guard let idx = boxes.firstIndex(where: { $0.id == blockID }) else { return }
        let sourceMediaID: String
        let sourceCaption: [TextRun]
        let sourceSpoiler: Bool
        if let img = boxes[idx] as? ImageBlockBox {
            sourceMediaID = img.assetID
            sourceCaption = mapper.runs(from: img.caption.attributedString)
            sourceSpoiler = img.spoiler
        } else if let m = boxes[idx] as? MediaBlockBox {
            sourceMediaID = m.mediaID
            sourceCaption = mapper.runs(from: m.caption.attributedString)
            sourceSpoiler = m.spoiler
        } else { return }
        editing {
            // Preserve the source medium's spoiler as the group's FIRST tile (added media default to
            // not-spoilered; the init pads the rest to false).
            let group = MediaGroupBlock(id: BlockID.generate(), kind: kind,
                                        mediaIDs: [sourceMediaID] + addingMediaIDs, caption: sourceCaption,
                                        spoilers: [sourceSpoiler])
            let box = MediaGroupBlockBox(group: group, mapper: mapper, width: effectiveWidth)
            box.mosaicProvider = mediaGroupMosaic
            var nb = boxes; nb[idx] = box; boxes = nb
            recomputeSpans()
            anchor = box.textStart; head = box.textStart
        }
        needsLayout = true
    }

    /// Returns the media id for a block. For a group, `tileIndex` selects the tile; for a single
    /// image/video block, `tileIndex` is ignored. Returns nil if the block or index is not found.
    func mediaID(forBlock id: BlockID, tileIndex: Int?) -> String? {
        guard let box = boxes.first(where: { $0.id == id }) else { return nil }
        if let g = box as? MediaGroupBlockBox, let i = tileIndex, g.mediaIDs.indices.contains(i) { return g.mediaIDs[i] }
        if let m = box as? MediaBlockBox { return m.mediaID }
        if let img = box as? ImageBlockBox { return img.assetID }
        return nil
    }

    /// Reconciles collage tile views: one host tile per `(group, index)`, positioned at its mosaic frame
    /// (offset by the group's bled media origin), pooled by `"groupID#index"`, rebuilt when the tile size
    /// changes (width reflow), removed (with host teardown) when the group/tile no longer exists. Called
    /// at the END of the layout pass, after `syncMediaBlockViews`.
    func syncMediaGroupViews() {
        var present = Set<String>()
        for case let box as MediaGroupBlockBox in boxes {
            // Slider: one hosted paging view, full-bleed; learn its height back into the box.
            if box.kind == .slideshow {
                let key = "\(box.id.rawValue)#slider"
                present.insert(key)
                let width = box.canvasWidth
                let hosted: HostedMediaBlock
                if let h = mediaGroupTileViews[key], h.mediaIDs == box.mediaIDs, h.spoilers == box.spoilers,
                   abs(h.canvasFrame.width - width) < 0.5 {
                    hosted = h
                } else {
                    let old = mediaGroupTileViews[key]
                    let view: NSView?
                    if let provider = mediaGroupSliderUpdateProvider {
                        view = provider(box.mediaIDs, box.spoilers, width, old?.view)
                    } else {
                        view = mediaGroupSliderProvider(box.mediaIDs, width)
                    }
                    if let old, old.view !== view {
                        mediaBlockViewWillRemove?(old.view)
                        old.view.removeFromSuperview()
                    }
                    guard let view else { mediaGroupTileViews[key] = nil; continue }
                    let h = old?.view === view ? old! : HostedMediaBlock(view: view, canvasFrame: .zero)
                    h.mediaIDs = box.mediaIDs
                    h.spoilers = box.spoilers
                    mediaGroupTileViews[key] = h
                    if view.superview !== mediaBlockHost { mediaBlockHost.addSubview(view) }
                    hosted = h
                }
                let viewH = hosted.view.frame.height
                if viewH > 0, box.hostHeight == nil || abs((box.hostHeight ?? 0) - viewH) > 0.5 {
                    box.hostHeight = viewH; needsLayout = true
                }
                // Clamp the slider to the (capped) reserved height — `box.mediaAreaHeight` caps at
                // `CanvasMetrics.maxMediaHeight`, so a tall slideshow fills 320 instead of overrunning.
                let h = box.mediaAreaHeight
                let frame = CGRect(x: box.frame.minX - box.contentMargin, y: box.mediaOrigin.y, width: width, height: h)
                hosted.view.frame = frame; hosted.canvasFrame = frame
                continue
            }
            let frames = box.tileFrames()
            let origin = box.mediaOrigin
            for (i, tile) in frames.enumerated() where i < box.mediaIDs.count {
                let key = "\(box.id.rawValue)#\(i)"
                present.insert(key)
                let frame = CGRect(origin: CGPoint(x: origin.x + tile.minX, y: origin.y + tile.minY), size: tile.size)
                let hosted: HostedMediaBlock
                if let h = mediaGroupTileViews[key], h.mediaID == box.mediaIDs[i],
                   h.spoiler == (box.spoilers.indices.contains(i) ? box.spoilers[i] : false),
                   abs(h.canvasFrame.width - tile.width) < 0.5, abs(h.canvasFrame.height - tile.height) < 0.5 {
                    hosted = h
                } else {
                    // New tile, or its size changed (a width reflow) → (re)build the host view at the new size.
                    if let old = mediaGroupTileViews[key] { mediaBlockViewWillRemove?(old.view); old.view.removeFromSuperview() }
                    guard let v = mediaGroupTileProvider(box.mediaIDs[i], box.spoilers.indices.contains(i) ? box.spoilers[i] : false, tile.size) else { mediaGroupTileViews[key] = nil; continue }
                    let h = HostedMediaBlock(view: v, canvasFrame: .zero)
                    h.mediaID = box.mediaIDs[i]
                    h.spoiler = box.spoilers.indices.contains(i) ? box.spoilers[i] : false
                    mediaGroupTileViews[key] = h
                    mediaBlockHost.addSubview(v)
                    hosted = h
                }
                hosted.view.frame = frame
                hosted.canvasFrame = frame
            }
        }
        for (k, h) in mediaGroupTileViews where !present.contains(k) {
            mediaBlockViewWillRemove?(h.view)      // host releases the content node's resources first
            h.view.removeFromSuperview(); mediaGroupTileViews[k] = nil
        }
        // One click-select overlay per collage TILE, ABOVE the tiles — clicking a tile selects THAT tile
        // (the media under the mouse), not the whole collage. (Slider has no tiles → no overlay; it pages.)
        var overlayPresent = Set<String>()
        for case let box as MediaGroupBlockBox in boxes where box.kind == .collage {
            let frames = box.tileFrames()
            let origin = box.mediaOrigin
            let group = box.id
            for (i, tile) in frames.enumerated() where i < box.mediaIDs.count {
                let key = "\(group.rawValue)#\(i)"
                overlayPresent.insert(key)
                let overlay = mediaGroupOverlays[key] ?? {
                    let v = MediaInteractionOverlayView(); v.wantsLayer = true
                    v.onMouseDown = { [weak self] in self?.selectCollageTile(group: group, index: i) }
                    mediaGroupOverlays[key] = v
                    return v
                }()
                overlay.frame = CGRect(origin: CGPoint(x: origin.x + tile.minX, y: origin.y + tile.minY), size: tile.size)
                mediaBlockHost.addSubview(overlay, positioned: .above, relativeTo: nil)
            }
        }
        for (k, v) in mediaGroupOverlays where !overlayPresent.contains(k) { v.removeFromSuperview(); mediaGroupOverlays[k] = nil }
        updateMediaGroupSelectionHighlight()
        syncMediaControlsViews()
    }

    /// Reconciles the host-provided controls overlay for every media block that wants chrome (collage /
    /// slider / single image·video). One view per block id, positioned over the media area ABOVE tiles and
    /// select overlays. Rebuilt when its layout signature (kind · tile count · area size · local tile
    /// frames) changes; just repositioned otherwise; removed (block gone, or no provider) with teardown.
    func syncMediaControlsViews() {
        guard let provider = mediaControlsProvider else {
            for (k, view) in mediaControlsViews { view.removeFromSuperview(); mediaControlsViews[k] = nil; mediaControlsSignatures[k] = nil }
            return
        }
        var present = Set<String>()
        for box in boxes {
            guard let media = box as? MediaControlsProviding, let kind = media.mediaControlsKind else { continue }
            let key = box.id.rawValue
            present.insert(key)
            let area = media.mediaAreaFrame
            let localTiles = media.mediaTileFrames().map { $0.offsetBy(dx: -area.minX, dy: -area.minY) }
            let signature = "\(kind)|\(localTiles.count)|\(Int(area.width))x\(Int(area.height))|"
                + localTiles.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))" }.joined(separator: ";")
            if mediaControlsViews[key] == nil || mediaControlsSignatures[key] != signature {
                mediaControlsViews[key]?.removeFromSuperview()
                let ctx = MediaControlsContext(blockID: key, kind: kind, areaSize: area.size, tileFrames: localTiles)
                guard let view = provider(ctx) else { mediaControlsViews[key] = nil; mediaControlsSignatures[key] = nil; continue }
                mediaControlsViews[key] = view
                mediaControlsSignatures[key] = signature
                mediaBlockHost.addSubview(view, positioned: .above, relativeTo: nil)
            } else if let view = mediaControlsViews[key] {
                mediaBlockHost.addSubview(view, positioned: .above, relativeTo: nil)
            }
            mediaControlsViews[key]?.frame = area
        }
        for (k, view) in mediaControlsViews where !present.contains(k) {
            view.removeFromSuperview(); mediaControlsViews[k] = nil; mediaControlsSignatures[k] = nil
        }
    }
}
#endif
