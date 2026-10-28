import Cocoa
import CoreImage
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramContext
import WalletContext
import Localization

struct WalletStickerPose {
    var center: CGPoint
    var side: CGFloat
    var angle: CGFloat = 0
    var border: CGFloat = 1
    var lift: CGFloat = 0
    var tilt: CGFloat = 0
    var axis = CGVector(dx: 0, dy: 1)
    var wave: CGFloat? = nil
    var bend: CGFloat = 0
    var shade: CGFloat = 0
    var opacity: CGFloat = 1
    var blur: CGFloat = 0
    var overhang: CGFloat? = nil

    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }

    static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        return CGPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t))
    }

    static func mix(_ a: WalletStickerPose, _ b: WalletStickerPose, _ t: CGFloat) -> WalletStickerPose {
        var pose = a
        pose.center = mix(a.center, b.center, t)
        pose.side = mix(a.side, b.side, t)
        pose.angle = mix(a.angle, b.angle, t)
        pose.opacity = mix(a.opacity, b.opacity, t)
        return pose
    }
}

enum WalletCollectableImages {
    private static var rendered: [String: CGImage] = [:]
    private static let ciContext = CIContext(options: nil)

    private static func render(_ key: String, width: Int, height: Int, _ draw: (CGContext, CGRect) -> Void) -> CGImage? {
        if let cached = rendered[key] {
            return cached
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        draw(context, CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            return nil
        }
        rendered[key] = image
        return image
    }

    static func art(_ id: String) -> CGImage? {
        return WalletCollectibleArtworks.shared.current(id).art
    }

    static func cut(_ id: String) -> CGImage? {
        let key = "cut_\(id)"
        if let cached = rendered[key] {
            return cached
        }
        guard let art = art(id) else {
            return nil
        }
        let source = CIImage(cgImage: art)
        let mask = source
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: CGFloat(art.width) * 15 / 512])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: CGFloat(art.width) / 512])
            .cropped(to: source.extent)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: source.extent)
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: source.extent)
        let outline = white.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask])
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let image = ciContext.createCGImage(outline, from: source.extent, format: .RGBA8, colorSpace: space) else {
            return nil
        }
        rendered[key] = image
        return image
    }

    static func base(_ id: String) -> CGImage? {
        guard let cut = cut(id) else {
            return nil
        }
        return render("base_\(id)", width: cut.width, height: cut.height) { context, rect in
            context.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.008), blur: rect.width * 0.018, color: NSColor.black.withAlphaComponent(0.34).cgColor)
            context.draw(cut, in: rect)
        }
    }

    static func sticker(_ id: String) -> CGImage? {
        guard let base = base(id), let art = art(id) else {
            return nil
        }
        return render("sticker_\(id)", width: base.width, height: base.height) { context, rect in
            context.draw(base, in: rect)
            context.draw(art, in: rect)
        }
    }
}

@available(macOS 10.15, *)
protocol WalletCollectablesGrid: NSView {
    func tileFrame(_ id: String) -> NSRect?
    func updateTiles(animated: Bool)
    var visibleGiftIds: [String] { get }
    var isShown: Bool { get }
    func setModelWiggle(_ id: String, angle: CGFloat, scale: CGFloat)
    func setReturnScale(_ id: String, scale: CGFloat)
}

@available(macOS 10.15, *)
final class WalletCollectablesStage {
    static let artShare: CGFloat = 0.7 / (1 - WalletCollectibleArtworks.artInset * 2)
    static let liftScale: CGFloat = 1.4
    static let peelSpan: Double = 0.3
    static let raiseSpan: Double = 0.26
    static let bendAngle: CGFloat = 0.75
    static let homeLay: Double = 0.4
    static let settle: Double = 0.42
    static let handoffOverlap: Double = 0.08
    static let dragThreshold: CGFloat = 3
    static let limit = 10

    private struct Drag {
        let id: String
        let gift: WalletContext.Collectible
        let start: CFTimeInterval
        let origin: WalletStickerPose
        let fromCard: Bool
        let scale: CGFloat
        let grab: CGPoint
    }

    private struct Flight {
        enum Kind {
            case stick
            case back
            case vanish
        }
        let id: String
        let kind: Kind
        let start: CFTimeInterval
        let from: WalletStickerPose
        var to: WalletStickerPose
        var thrown = false
        var peelFirst = false
        var fast = false
        var contacted = false
        var handedOff = false
    }

    private struct Edit {
        enum Mode {
            case move
            case handle
            case twist
        }
        let original: WalletContext.CardSticker
        var mode: Mode
        var anchor: CGPoint
        var center: CGPoint
        var angle: CGFloat
        var scale: CGFloat
        var reach: CGFloat
        var grip: CGFloat
        var turn: CGFloat = 0
        var zoom: CGFloat = 1
        var snapped: Int?
        var moved = false
    }

    private struct Settle {
        let id: String
        let from: WalletContext.CardSticker
        let to: WalletContext.CardSticker
        let start: CFTimeInterval
    }

    private let context: any AccountContextProtocol
    private let environment: WalletUIEnvironment
    private let walletContext: WalletContext
    private lazy var tutorial = WalletStickerTutorial(context: context, environment: environment)
    private var configuration: WalletConfiguration
    private weak var cardView: WalletCardView?
    private weak var gridView: WalletCollectablesGrid?
    private var overlay: WalletStickerOverlayView?
    private var trash: WalletStickerTrashView?
    private var animator: ConstantDisplayLinkAnimator?
    private var drag: Drag?
    private var flights: [String: Flight] = [:]
    private var pointer: CGPoint?
    private var samples: [(time: CFTimeInterval, point: CGPoint)] = []
    private var gestureScale: CGFloat = 1
    private var gestureAngle: CGFloat = 0
    private var edit: Edit?
    private var settle: Settle?
    private var selectedId: String?
    private var selectionTimer: Foundation.Timer?

    private var address: String?
    private var canEdit = false
    private var placements: [WalletContext.CardSticker] = []
    private var pendingCommit: [WalletContext.CardSticker]?
    private var collectibles: [String: WalletContext.Collectible] = [:]
    private var suppressed: Set<String> = []
    private var restored = false
    private var artworkDisposables: [String: Disposable] = [:]
    private var patterns: [String: CGImage] = [:]
    private var styleFrom: WalletContext.CardGiftStyle?
    private var styleTo: WalletContext.CardGiftStyle?
    private var styleStart: CFTimeInterval?
    private var styleOrigin: CGPoint = .zero


    var limitReached: (() -> Void)?

    init(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext) {
        self.context = context
        self.environment = environment
        self.walletContext = walletContext
        self.configuration = WalletConfiguration.with(appConfiguration: context.appConfiguration)
    }

    deinit {
        selectionTimer?.invalidate()
        for disposable in artworkDisposables.values {
            disposable.dispose()
        }
    }

    func attach(card: WalletCardView) {
        if cardView !== card {
            if let previous = cardView {
                detachHandlers(from: previous)
            }
            cardView = card
            card.stickerTracking = { [weak self] id, event in
                return self?.track(fromCard: id, event: event) ?? false
            }
            card.stickerSelectionTracking = { [weak self] hit, event in
                self?.track(selection: hit, event: event)
            }
            card.stickerSelectionCleared = { [weak self] in
                self?.deselect()
            }
            card.stickerGesture = { [weak self] event in
                return self?.twist(event) ?? false
            }
            card.stickerAvailabilityChanged = { [weak self] in
                self?.availabilityChanged()
            }
            card.setStickerSelection(selectedId, animated: false)
            card.stickerMenu = { [weak self, weak card] id, event in
                guard let self, let card, let items = self.menuItems(for: id), !items.isEmpty else {
                    return
                }
                let menu = ContextMenu()
                for item in items {
                    menu.addItem(item)
                }
                AppMenu.show(menu: menu, event: event, for: card)
            }
            card.setGiftStyle(from: nil, to: styleTo, origin: styleOrigin, progress: 1, pattern: stylePattern(styleTo))
        }
        sync()
    }

    func gridDidUpdate() {
        guard canEdit, let card = cardView, card.acceptsStickers, let grid = gridView, grid.isShown else {
            tutorial.updateVisibility(false)
            return
        }
        tutorial.updateVisibility(true)
        guard placements.isEmpty, pendingCommit == nil, drag == nil, flights.isEmpty else { return }
        for id in grid.visibleGiftIds {
            if let gift = collectibles[id], canPick(id), let spot = solver(excluding: id)?.spread(aim: nil, scale: 1) {
                tutorial.start(card: card, grid: grid, gift: gift, spot: spot, canStart: { [weak self] in
                    guard let self else { return false }
                    return self.placements.isEmpty && self.drag == nil && self.flights.isEmpty
                })
                break
            }
        }
    }

    func attach(grid: WalletCollectablesGrid) {
        gridView = grid
        walletCardPrepareStickerMask()
    }

    func detach(grid: WalletCollectablesGrid) {
        if gridView === grid {
            gridView = nil
            tutorial.end()
        }
    }

    func update(state: WalletContext.State, suppressed: Set<String>) {
        let address = state.walletAddress
        if address != self.address {
            cancel()
            placements = []
            pendingCommit = nil
            styleFrom = nil
            styleTo = nil
            styleStart = nil
            restored = false
            cardView?.setGiftStyle(from: nil, to: nil, origin: .zero, progress: 1, pattern: nil)
        }
        self.address = address
        if case .wallet = state.phase {
            canEdit = true
        } else {
            canEdit = false
        }
        let stored = state.cardStickers
        for item in state.collectibles.items {
            collectibles[item.address] = item
        }
        self.suppressed = suppressed
        if pendingCommit == stored {
            pendingCommit = nil
        }
        let value = pendingCommit ?? stored
        if value != placements {
            let activeId = drag.flatMap { $0.fromCard ? $0.id : nil } ?? edit?.original.gift.address ?? settle?.id
            if let activeId, !value.contains(where: { $0.gift.address == activeId }) {
                cancel()
            }
            if let editedId = edit?.original.gift.address ?? settle?.id, let edited = placements.first(where: { $0.gift.address == editedId }), value.contains(where: { $0.gift.address == editedId }) {
                placements = value.map { $0.gift.address == editedId ? edited : $0 }
            } else {
                placements = value
            }
        }
        if !canEdit {
            finishEdit(cancelled: true)
            deselect(animated: false)
        } else if let selectedId, !placements.contains(where: { $0.gift.address == selectedId }) {
            deselect(animated: false)
        }
        for (id, flight) in flights where flight.kind == .stick && !placements.contains(where: { $0.gift.address == id }) {
            flights[id] = nil
        }
        if !restored {
            restored = true
            styleTo = placements.compactMap(\.style).last
            styleFrom = styleTo
            styleStart = nil
        }
        prepareArtworks()
        sync()
    }

    func isPlaced(_ id: String) -> Bool {
        return placements.contains(where: { $0.gift.address == id })
    }

    func isHeld(_ id: String) -> Bool {
        if drag?.id == id {
            return true
        }
        return flights[id].map { !$0.handedOff } ?? false
    }

    func canPick(_ id: String) -> Bool {
        return canEdit && drag == nil && !isPlaced(id) && !isHeld(id) && collectibles[id]?.kind == .gift && WalletCollectableImages.art(id) != nil
    }

    func invalidate() {
        cancel()
        if let card = cardView {
            detachHandlers(from: card)
        }
    }

    private func detachHandlers(from card: WalletCardView) {
        card.stickerTracking = nil
        card.stickerMenu = nil
        card.stickerSelectionTracking = nil
        card.stickerSelectionCleared = nil
        card.stickerGesture = nil
        card.stickerAvailabilityChanged = nil
        card.setStickerSelection(nil, animated: false)
    }

    private func cancel() {
        tutorial.end()
        finishEdit(cancelled: true)
        finishSettle()
        deselect(animated: false)
        if drag != nil {
            drag = nil
            NSCursor.pop()
        }
        for id in flights.keys { gridView?.setReturnScale(id, scale: 1) }
        flights.removeAll()
        styleStart = nil
        styleFrom = styleTo
        finishOverlay()
        stopAnimator()
        sync()
    }

    private func prepareArtworks() {
        let ids = Set(placements.map(\.gift.address))
        for (id, disposable) in artworkDisposables where !ids.contains(id) {
            disposable.dispose()
            artworkDisposables[id] = nil
        }
        for sticker in placements where artworkDisposables[sticker.gift.address] == nil {
            let id = sticker.gift.address
            artworkDisposables[id] = WalletCollectibleArtworks.shared.artwork(sticker.gift, context: context, modelFile: sticker.modelFile).start(next: { [weak self] artwork in
                self?.artworkUpdated(id, artwork)
            })
        }
    }

    private func artworkUpdated(_ id: String, _ artwork: WalletCollectibleArtwork) {
        if let style = artwork.style, let pattern = artwork.pattern {
            patterns[walletCardStyleKey(style)] = pattern
        }
        if let index = placements.firstIndex(where: { $0.gift.address == id }), let modelFile = artwork.modelFile, placements[index].modelFile != modelFile || (artwork.style != nil && walletCardStyleKey(placements[index].giftStyle) != walletCardStyleKey(artwork.style)) {
            let sticker = placements[index]
            placements[index] = WalletContext.CardSticker(gift: sticker.gift, x: sticker.x, y: sticker.y, angle: sticker.angle, scale: sticker.scale, modelFile: modelFile, geometryVersion: sticker.geometryVersion, style: sticker.style, giftStyle: artwork.style ?? sticker.giftStyle, aspectRatio: sticker.aspectRatio, cornerRadius: sticker.cornerRadius)
            if drag == nil {
                commit()
            }
        }
        sync()
    }

    private func sync() {
        guard let card = cardView else {
            gridView?.updateTiles(animated: true)
            return
        }
        card.updateStickers(placements, hidden: hiddenStickers)
        gridView?.updateTiles(animated: true)
        updateStyle()
        gridDidUpdate()
    }

    private func syncCard() {
        cardView?.updateStickers(placements, hidden: hiddenStickers)
    }

    private var hiddenStickers: Set<String> {
        var hidden = suppressed.intersection(placements.map(\.gift.address))
        if let drag {
            hidden.insert(drag.id)
        }
        for flight in flights.values where flight.kind == .stick && !flight.handedOff {
            hidden.insert(flight.id)
        }
        return hidden
    }

    private func commit() {
        guard canEdit, let address else {
            return
        }
        placements = WalletContext.CardSticker.validated(placements)
        pendingCommit = placements
        walletContext.updateCardStickers(placements, walletAddress: address)
    }

    private func solver(excluding id: String) -> WalletStickerPlacement? {
        guard let card = cardView, card.frame.width > 0 else {
            return nil
        }
        return WalletStickerPlacement(size: card.stickerSurfaceSize, obstacles: card.stickerObstacles, occupants: placements.filter { $0.gift.address != id })
    }

    func updateConfiguration(_ configuration: WalletConfiguration) {
        self.configuration = configuration
    }

    func canCustomizeCard(for id: String) -> Bool {
        guard canEdit, let gift = placements.first(where: { $0.gift.address == id })?.gift ?? collectibles[id] else { return false }
        return gift.kind == .gift && WalletCollectableImages.art(id) != nil
    }

    func canApplyColor(for id: String) -> Bool {
        guard let gift = placements.first(where: { $0.gift.address == id })?.gift ?? collectibles[id] else { return false }
        let artwork = WalletCollectibleArtworks.shared.current(id)
        return artwork.style != nil && artwork.pattern != nil && configuration.allowsCardBackground(giftSlug: gift.giftSlug)
    }

    func isColorRestricted(for id: String) -> Bool {
        guard configuration.cardBackgroundGiftCollections != nil,
              let gift = placements.first(where: { $0.gift.address == id })?.gift ?? collectibles[id] else { return false }
        return !configuration.allowsCardBackground(giftSlug: gift.giftSlug)
    }

    func cardSticker(for id: String) -> WalletContext.CardSticker? {
        return placements.first(where: { $0.gift.address == id })
    }

    func menuItems(for id: String) -> [ContextMenuItem]? {
        guard canEdit, drag == nil, edit == nil, flights[id] == nil else {
            return nil
        }
        let sticker = placements.first(where: { $0.gift.address == id })
        guard let gift = sticker?.gift ?? collectibles[id], gift.kind == .gift, WalletCollectableImages.art(id) != nil else {
            return nil
        }
        let styled = sticker?.style != nil
        let canStyle = canApplyColor(for: id)
        var items: [ContextMenuItem] = []
        if canStyle || styled {
            items.append(ContextMenuItem(styled ? strings().walletCollectablesRemoveColor : strings().walletCollectablesApplyColor, handler: { [weak self] in self?.menuAction(id, color: true) }, itemImage: environment.menuImage(.menu_change_colors)))
        }
        items.append(ContextMenuItem(sticker != nil ? strings().walletCollectablesRemoveFromCard : strings().walletCollectablesAddToCard, handler: { [weak self] in self?.menuAction(id, color: false) }, itemImage: environment.menuImage(sticker != nil ? .menu_hide : .menu_add)))
        return items
    }

    func placeFromDetails(_ id: String, color: Bool, source: NSView) -> Bool {
        guard canEdit, drag == nil, edit == nil, flights[id] == nil,
              !placements.contains(where: { $0.gift.address == id }), placements.count < WalletCollectablesStage.limit,
              let gift = collectibles[id], let card = cardView, let window = card.window, source.window === window,
              WalletCollectableImages.art(id) != nil, !color || canApplyColor(for: id),
              let spot = solver(excluding: id)?.spread(aim: nil, scale: 1), let overlay = prepareOverlay(window) else { return false }
        let frame = overlay.convert(source.bounds, from: source)
        let origin = WalletStickerPose(center: NSMakePoint(frame.midX, frame.midY), side: frame.width, border: 0)
        place(gift, from: origin, spot: spot, angle: 0, thrown: true, style: color ? WalletCollectibleArtworks.shared.current(id).style : nil)
        return true
    }

    func menuAction(_ id: String, color: Bool) {
        guard canEdit, let card = cardView, let window = card.window else {
            return
        }
        let artwork = WalletCollectibleArtworks.shared.current(id)
        if color, placements.first(where: { $0.gift.address == id })?.style == nil {
            guard canApplyColor(for: id) else { return }
        }
        if let index = placements.firstIndex(where: { $0.gift.address == id }) {
            if color {
                let apply = placements[index].style == nil
                guard !apply || artwork.style != nil else {
                    return
                }
                styleOrigin = card.stickerCenter(placements[index])
                placements = placements.enumerated().map { i, sticker in sticker.withStyle(i == index && apply ? artwork.style : nil) }
            } else {
                if selectedId == id {
                    deselect()
                }
                let sticker = placements.remove(at: index)
                if let overlay = prepareOverlay(window), let from = card.stickerPose(sticker, in: overlay) {
                    returnGift(id, from: from, peelFirst: true)
                }
            }
            commit()
            sync()
        } else {
            guard let gift = collectibles[id], let grid = gridView, grid.window === window, let overlay = prepareOverlay(window), let tile = grid.tileFrame(id), let spot = solver(excluding: id)?.spread(aim: nil, scale: 1) else {
                WalletCollectablesStage.haptic()
                return
            }
            let cell = overlay.convert(tile, from: grid)
            let from = WalletStickerPose(center: NSMakePoint(cell.midX, cell.midY), side: cell.width * WalletCollectablesStage.artShare, border: 0)
            place(gift, from: from, spot: spot, angle: 0, thrown: true, style: color ? artwork.style : nil)
        }
    }

    func track(fromCell id: String, in grid: WalletCollectablesGrid, event: NSEvent) -> Bool {
        guard canPick(id), let gift = collectibles[id] else {
            return false
        }
        return track(event: event, begin: { [weak self, weak grid] point in
            guard let self, let grid, let window = grid.window, let overlay = self.prepareOverlay(window), let tile = grid.tileFrame(id) else {
                return false
            }
            let cell = overlay.convert(tile, from: grid)
            let origin = WalletStickerPose(center: NSMakePoint(cell.midX, cell.midY), side: cell.width * WalletCollectablesStage.artShare, border: 0)
            return self.pick(id, gift: gift, origin: origin, fromCard: false, scale: 1, windowPoint: point)
        })
    }

    private func track(fromCard id: String, event: NSEvent) -> Bool {
        guard canEdit else {
            return false
        }
        guard drag == nil, edit == nil, !isHeld(id) else {
            return true
        }
        finishSettle()
        let handled = track(event: event, holdDelay: 0.3, begin: { [weak self] point in
            guard let self, let card = self.cardView, let window = card.window, let overlay = self.prepareOverlay(window), let sticker = self.placements.first(where: { $0.gift.address == id }), let origin = card.stickerPose(sticker, in: overlay) else {
                return false
            }
            return self.pick(id, gift: sticker.gift, origin: origin, fromCard: true, scale: WalletCollectablesStage.scale(of: sticker), windowPoint: point)
        })
        if !handled, cardView?.acceptsStickers == true, placements.contains(where: { $0.gift.address == id }) {
            select(id)
            cardView?.playSticker(id, account: context.account, grow: 1.06)
        }
        return true
    }

    private func track(selection hit: WalletCardStickerSelectionHit, event: NSEvent) {
        guard canEdit, drag == nil, edit == nil, let card = cardView, card.acceptsStickers, let window = event.window, let id = selectedId, let sticker = placements.first(where: { $0.gift.address == id }) else {
            return
        }
        selectionTimer?.invalidate()
        selectionTimer = nil
        finishSettle()
        let start = card.convert(event.locationInWindow, from: nil)
        if hit == .handle {
            beginEdit(sticker, mode: .handle, at: start)
        }
        var detached = false
        var moved = false
        tracking: while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .pressure, .magnify, .rotate], until: Date(timeIntervalSinceNow: 0.1), inMode: .eventTracking, dequeue: true) else {
                guard NSEvent.pressedMouseButtons & 1 == 0 else {
                    continue
                }
                if detached, drag != nil {
                    move(to: window.mouseLocationOutsideOfEventStream)
                    release()
                }
                break tracking
            }
            switch next.type {
            case .leftMouseDragged:
                if detached {
                    move(to: next.locationInWindow)
                    continue
                }
                let point = card.convert(next.locationInWindow, from: nil)
                if edit == nil {
                    guard hypot(point.x - start.x, point.y - start.y) > WalletCollectablesStage.dragThreshold, let current = placements.first(where: { $0.gift.address == id }) else {
                        continue
                    }
                    beginEdit(current, mode: .move, at: start)
                    moved = true
                    NSCursor.closedHand.set()
                }
                if !updateEdit(at: point) {
                    detached = detach(at: next.locationInWindow)
                    if !detached {
                        break tracking
                    }
                }
            case .magnify, .rotate:
                if detached {
                    adjustDrag(with: next)
                }
            case .leftMouseUp:
                if detached {
                    move(to: next.locationInWindow)
                    release()
                }
                break tracking
            default:
                break
            }
        }
        if !detached {
            finishEdit(cancelled: false)
            scheduleDeselection()
            if hit == .body, !moved {
                card.playSticker(id, account: context.account, grow: 1.06)
            }
        }
        card.refreshStickerCursor()
    }

    private func track(event: NSEvent, holdDelay: Double = 0.25, begin: (NSPoint) -> Bool) -> Bool {
        guard let window = event.window else {
            return false
        }
        let start = event.locationInWindow
        let pressedAt = CACurrentMediaTime()
        var started = false
        var refused = false
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .pressure, .magnify, .rotate], until: Date(timeIntervalSinceNow: 0.1), inMode: .eventTracking, dequeue: true) else {
                guard NSEvent.pressedMouseButtons & 1 == 0 else {
                    if !started, !refused, CACurrentMediaTime() - pressedAt >= holdDelay {
                        started = begin(start)
                        refused = !started
                    }
                    if started { move(to: window.mouseLocationOutsideOfEventStream) }
                    continue
                }
                if started {
                    move(to: window.mouseLocationOutsideOfEventStream)
                    release()
                }
                return started || refused
            }
            switch next.type {
            case .leftMouseDragged:
                if refused {
                    continue
                }
                if !started {
                    guard hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > WalletCollectablesStage.dragThreshold else {
                        continue
                    }
                    started = begin(start)
                    refused = !started
                }
                if started {
                    move(to: next.locationInWindow)
                }
            case .magnify, .rotate:
                if started {
                    adjustDrag(with: next)
                }
            case .leftMouseUp:
                if started {
                    move(to: next.locationInWindow)
                    release()
                }
                return started || refused
            default:
                break
            }
        }
    }

    private func adjustDrag(with event: NSEvent) {
        switch event.type {
        case .magnify:
            let limit = gestureLimit
            gestureScale = min(max(gestureScale * (1 + event.magnification), limit.lowerBound), limit.upperBound)
        case .rotate:
            gestureAngle -= CGFloat(event.rotation) * .pi / 180
        default:
            break
        }
    }

    private var gestureLimit: ClosedRange<CGFloat> {
        let base = max(drag?.scale ?? 1, 0.01)
        return (WalletStickerPlacement.minimum / base) ... (WalletStickerPlacement.maximum / base)
    }

    private static func scale(of sticker: WalletContext.CardSticker) -> CGFloat {
        return WalletStickerPlacement.clamp(CGFloat(sticker.renderedWidthFraction / WalletContext.CardSticker.widthFraction))
    }

    private func select(_ id: String) {
        selectionTimer?.invalidate()
        selectionTimer = nil
        if selectedId != id {
            selectedId = id
            cardView?.setStickerSelection(id, animated: true)
        }
        scheduleDeselection()
    }

    private func deselect(animated: Bool = true) {
        selectionTimer?.invalidate()
        selectionTimer = nil
        guard selectedId != nil else {
            return
        }
        selectedId = nil
        cardView?.setStickerSelection(nil, animated: animated)
    }

    private func scheduleDeselection() {
        selectionTimer?.invalidate()
        selectionTimer = nil
        guard selectedId != nil else {
            return
        }
        let timer = Foundation.Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            self.selectionTimer = nil
            guard self.edit == nil else {
                return
            }
            if self.cardView?.isPointerOverStickerSelection == true {
                self.scheduleDeselection()
            } else {
                self.deselect()
            }
        }
        selectionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func availabilityChanged() {
        guard cardView?.acceptsStickers != true else {
            return
        }
        finishEdit(cancelled: false)
        deselect()
    }

    private func beginEdit(_ sticker: WalletContext.CardSticker, mode: Edit.Mode, at point: CGPoint) {
        guard let card = cardView else {
            return
        }
        let center = card.stickerCenter(sticker)
        edit = Edit(original: sticker, mode: mode, anchor: point, center: center, angle: CGFloat(sticker.angle), scale: WalletCollectablesStage.scale(of: sticker), reach: max(1, hypot(point.x - center.x, point.y - center.y)), grip: atan2(point.y - center.y, point.x - center.x))
        selectionTimer?.invalidate()
        selectionTimer = nil
    }

    private func updateEdit(at point: CGPoint) -> Bool {
        guard var edit, let card = cardView, let index = placements.firstIndex(where: { $0.gift.address == edit.original.gift.address }) else {
            return true
        }
        let size = card.stickerSurfaceSize
        guard size.width > 0, size.height > 0 else {
            return true
        }
        let sticker = placements[index]
        var center = card.stickerCenter(sticker)
        var angle = CGFloat(sticker.angle)
        var scale = WalletCollectablesStage.scale(of: sticker)
        switch edit.mode {
        case .handle:
            let dx = point.x - edit.center.x, dy = point.y - edit.center.y
            let a = atan2(dy, dx)
            edit.turn += atan2(sin(a - edit.grip), cos(a - edit.grip))
            edit.grip = a
            angle = edit.angle + edit.turn
            scale = WalletStickerPlacement.clamp(edit.scale * hypot(dx, dy) / edit.reach)
            center = edit.center
        case .move:
            guard NSRect(origin: .zero, size: size).insetBy(dx: -28, dy: -28).contains(point) else {
                return false
            }
            center = CGPoint(x: edit.center.x + point.x - edit.anchor.x, y: edit.center.y + point.y - edit.anchor.y)
        case .twist:
            break
        }
        applyEdit(&edit, index: index, center: center, angle: angle, scale: scale)
        return true
    }

    private func applyEdit(_ edit: inout Edit, index: Int, center: CGPoint, angle: CGFloat, scale: CGFloat) {
        guard let card = cardView else {
            return
        }
        let size = card.stickerSurfaceSize
        let center = CGPoint(x: min(size.width, max(0, center.x)), y: min(size.height, max(0, center.y)))
        var angle = angle
        if edit.mode != .move {
            let quarter = Int((angle / (.pi / 2)).rounded())
            let snap = CGFloat(quarter) * .pi / 2
            if abs(angle - snap) < 5 * .pi / 180 {
                if edit.snapped != quarter {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                edit.snapped = quarter
                angle = snap
            } else {
                edit.snapped = nil
            }
        }
        edit.moved = true
        placements[index] = placements[index].updated(x: Double(center.x / size.width), y: Double(center.y / size.height), angle: Double(angle), scale: Double(scale), geometryVersion: 1)
        self.edit = edit
        syncCard()
    }

    private func twist(_ event: NSEvent) -> Bool {
        guard canEdit, drag == nil, let card = cardView, card.acceptsStickers, let id = selectedId else {
            return false
        }
        guard let index = placements.firstIndex(where: { $0.gift.address == id }) else {
            return false
        }
        let ending = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        if edit == nil {
            guard !ending else {
                return true
            }
            finishSettle()
            beginEdit(placements[index], mode: .twist, at: card.stickerCenter(placements[index]))
        }
        guard var edit, edit.mode == .twist else {
            return true
        }
        switch event.type {
        case .magnify:
            let base = max(edit.scale, 0.01)
            edit.zoom = min(max(edit.zoom * (1 + event.magnification), WalletStickerPlacement.minimum / base), WalletStickerPlacement.maximum / base)
        case .rotate:
            edit.turn -= CGFloat(event.rotation) * .pi / 180
        default:
            break
        }
        applyEdit(&edit, index: index, center: edit.center, angle: edit.angle + edit.turn, scale: WalletStickerPlacement.clamp(edit.scale * edit.zoom))
        if ending || event.phase.isEmpty {
            finishEdit(cancelled: false)
            scheduleDeselection()
        }
        return true
    }

    private func detach(at windowPoint: NSPoint) -> Bool {
        guard let edit, let card = cardView, let window = card.window, let overlay = prepareOverlay(window), let index = placements.firstIndex(where: { $0.gift.address == edit.original.gift.address }), let pose = card.stickerPose(placements[index], in: overlay) else {
            return false
        }
        let current = placements[index]
        placements[index] = edit.original
        self.edit = nil
        deselect()
        guard pick(current.gift.address, gift: current.gift, origin: pose, fromCard: true, scale: WalletCollectablesStage.scale(of: current), windowPoint: windowPoint) else {
            syncCard()
            return false
        }
        return true
    }

    private func finishEdit(cancelled: Bool) {
        guard let edit else {
            return
        }
        self.edit = nil
        guard let index = placements.firstIndex(where: { $0.gift.address == edit.original.gift.address }) else {
            return
        }
        if cancelled {
            placements[index] = edit.original
            syncCard()
            return
        }
        guard edit.moved else {
            return
        }
        let sticker = placements[index]
        guard let card = cardView, card.frame.width > 0 else {
            commit()
            sync()
            return
        }
        let size = card.stickerSurfaceSize
        let center = card.stickerCenter(sticker)
        let scale = WalletCollectablesStage.scale(of: sticker)
        let solver = WalletStickerPlacement(size: size, obstacles: card.stickerObstacles, occupants: [])
        if solver.fits(center, scale: scale) {
            commit()
            sync()
            return
        }
        let target: WalletContext.CardSticker
        if let spot = solver.drop(near: center, scale: scale) {
            target = sticker.updated(x: Double(spot.center.x / size.width), y: Double(spot.center.y / size.height), scale: Double(spot.scale), geometryVersion: 1)
        } else {
            target = edit.original
        }
        placements[index] = target
        commit()
        if let settled = placements.firstIndex(where: { $0.gift.address == target.gift.address }) {
            placements[settled] = sticker
            settle = Settle(id: sticker.gift.address, from: sticker, to: target, start: CACurrentMediaTime())
            startAnimator()
        }
        sync()
    }

    private func tickSettle(_ now: CFTimeInterval) {
        guard let settle else {
            return
        }
        guard let index = placements.firstIndex(where: { $0.gift.address == settle.id }) else {
            self.settle = nil
            return
        }
        let elapsed = now - settle.start
        guard elapsed < 0.28 else {
            finishSettle()
            return
        }
        let t = WalletCollectablesStage.ease(elapsed / 0.28)
        let a = settle.from, b = settle.to
        let fromScale = WalletCollectablesStage.scale(of: a), toScale = WalletCollectablesStage.scale(of: b)
        let angle = CGFloat(a.angle) + atan2(sin(CGFloat(b.angle - a.angle)), cos(CGFloat(b.angle - a.angle))) * t
        placements[index] = a.updated(x: a.x + (b.x - a.x) * Double(t), y: a.y + (b.y - a.y) * Double(t), angle: Double(angle), scale: Double(fromScale + (toScale - fromScale) * t), geometryVersion: 1)
        syncCard()
    }

    private func finishSettle() {
        guard let settle else {
            return
        }
        self.settle = nil
        if let index = placements.firstIndex(where: { $0.gift.address == settle.id }) {
            placements[index] = settle.to
        }
        sync()
    }

    private func prepareOverlay(_ window: NSWindow) -> WalletStickerOverlayView? {
        guard let list = cardView?.enclosingScrollView ?? gridView?.enclosingScrollView, list.window === window, let host = list.superview else {
            return nil
        }
        if let overlay, overlay.superview === host {
            return overlay
        }
        overlay?.removeFromSuperview()
        let view = WalletStickerOverlayView(frame: host.bounds)
        view.autoresizingMask = [.width, .height]
        host.addSubview(view, positioned: .above, relativeTo: list)
        overlay = view
        return view
    }

    private func pick(_ id: String, gift: WalletContext.Collectible, origin: WalletStickerPose, fromCard: Bool, scale: CGFloat, windowPoint: NSPoint) -> Bool {
        guard drag == nil, let overlay else {
            return false
        }
        tutorial.picked(id)
        deselect()
        finishSettle()
        let point = overlay.convert(windowPoint, from: nil)
        drag = Drag(id: id, gift: gift, start: CACurrentMediaTime(), origin: origin, fromCard: fromCard, scale: scale, grab: CGPoint(x: origin.center.x - point.x, y: origin.center.y - point.y))
        pointer = point
        samples = []
        gestureScale = 1
        gestureAngle = 0
        cardView?.setStickerInteraction(true)
        NSCursor.closedHand.push()
        WalletCollectablesStage.haptic()
        if fromCard {
            showTrash()
        }
        startAnimator()
        tick()
        sync()
        return true
    }

    private func showTrash() {
        guard let overlay else {
            return
        }
        let view = trash ?? WalletStickerTrashView(frame: .zero)
        if view.superview !== overlay {
            overlay.addSubview(view)
        }
        trash = view
        view.place(at: NSMakePoint(overlay.bounds.midX, overlay.bounds.height - 64))
        view.setShown(true)
    }

    private func updateTrashHot() {
        guard let trash, let drag, drag.fromCard, let pointer else {
            return
        }
        let hot = hypot(pointer.x - trash.anchor.x, pointer.y - trash.anchor.y) < WalletStickerTrashView.reach
        if hot != trash.isHot {
            trash.setHot(hot)
            WalletCollectablesStage.haptic()
        }
    }

    private func move(to windowPoint: NSPoint) {
        guard drag != nil, let overlay else {
            return
        }
        let point = overlay.convert(windowPoint, from: nil)
        let now = CACurrentMediaTime()
        pointer = point
        samples.append((now, point))
        samples.removeAll(where: { now - $0.time > 0.12 })
        updateTrashHot()
    }

    private func cardRect(in overlay: NSView) -> NSRect? {
        guard let card = cardView, card.window === overlay.window, card.frame.width > 0 else {
            return nil
        }
        return overlay.convert(card.bounds, from: card)
    }

    private func velocity(at now: CFTimeInterval) -> CGVector {
        guard let first = samples.first, let last = samples.last, last.time - first.time > 0.008 else {
            return .zero
        }
        let dt = CGFloat(last.time - first.time)
        let fade = CGFloat(exp(-max(0, now - last.time) / 0.09))
        return CGVector(dx: (last.point.x - first.point.x) / dt * fade, dy: (last.point.y - first.point.y) / dt * fade)
    }

    private func dragPose(at now: CFTimeInterval) -> WalletStickerPose? {
        guard let drag, let overlay else {
            return nil
        }
        let t = now - drag.start
        let peel = WalletCollectablesStage.ease(t / WalletCollectablesStage.peelSpan)
        let raise = WalletCollectablesStage.ease((t - WalletCollectablesStage.peelSpan * 0.75) / WalletCollectablesStage.raiseSpan)
        let cardWidth = cardRect(in: overlay)?.width ?? walletCardReferenceSize.width
        let handSide = cardWidth * CGFloat(WalletContext.CardSticker.widthFraction) * drag.scale * gestureScale * WalletCollectablesStage.liftScale
        let side = WalletStickerPose.mix(drag.origin.side, handSide, raise)
        let pointer = self.pointer ?? CGPoint(x: drag.origin.center.x - drag.grab.x, y: drag.origin.center.y - drag.grab.y)
        let grabScale = side / max(drag.origin.side, 1)
        let center = CGPoint(x: pointer.x + drag.grab.x * grabScale, y: pointer.y + drag.grab.y * grabScale)
        let v = velocity(at: now)
        let swing = max(-0.25, min(0.25, v.dx * 0.00035)) * raise
        let speed = hypot(v.dx, v.dy)
        let moveTilt = min(14, speed * 0.009) * raise
        var axis = CGVector(dx: 0, dy: 1)
        if speed > 1 {
            axis = CGVector(dx: -v.dy / speed, dy: v.dx / speed)
        }
        var pose = WalletStickerPose(center: center, side: side, angle: drag.origin.angle + gestureAngle + swing, border: drag.fromCard ? 1 : min(1, peel * 1.3), lift: raise, tilt: moveTilt, axis: axis)
        if raise < 1 {
            pose.wave = 1 - peel
            pose.bend = WalletCollectablesStage.bendAngle * (1 - raise)
            pose.shade = 1 - raise
        }
        return pose
    }

    private func release() {
        guard let drag, let overlay, let pose = dragPose(at: CACurrentMediaTime()) else {
            return
        }
        let now = CACurrentMediaTime()
        let v = velocity(at: now)
        let scale = WalletStickerPlacement.clamp(drag.scale * gestureScale)
        self.drag = nil
        NSCursor.pop()
        let trashed = drag.fromCard && trash?.isHot == true
        trash?.setShown(false)
        if trashed, let trash {
            placements.removeAll { $0.gift.address == drag.id }
            flights[drag.id] = Flight(id: drag.id, kind: .vanish, start: now, from: pose, to: WalletStickerPose(center: trash.anchor, side: pose.side * 0.25, angle: pose.angle + 0.5))
            WalletCollectablesStage.haptic()
            commit()
            sync()
            startAnimator()
            return
        }
        let tossed = v.dy < -600 && hypot(v.dx, v.dy) > 700
        if let card = cardView, card.acceptsStickers, let rect = cardRect(in: overlay), rect.width > 0 {
            let k = rect.width / card.frame.width
            let local = CGPoint(x: (pose.center.x - rect.minX) / k, y: (pose.center.y - rect.minY) / k)
            let nearCard = card.bounds.insetBy(dx: -30, dy: -30).contains(local)
            let solver = self.solver(excluding: drag.id)
            let surface = card.stickerSurfaceSize
            let dropped = WalletStickerPlacement.Spot(center: CGPoint(x: min(surface.width, max(0, local.x)), y: min(surface.height, max(0, local.y))), scale: scale)
            let spot = tossed ? solver?.spread(aim: local, scale: scale) : (nearCard ? dropped : nil)
            if let spot {
                place(drag.gift, from: pose, spot: spot, angle: WalletCollectablesStage.wrapped(pose.angle), thrown: tossed)
                return
            }
            if nearCard || tossed {
                WalletCollectablesStage.haptic()
            }
            if drag.fromCard, nearCard || tossed, let original = placements.first(where: { $0.gift.address == drag.id }), let to = card.stickerPose(original, in: overlay) {
                flights[drag.id] = Flight(id: drag.id, kind: .stick, start: now, from: pose, to: to)
                sync()
                return
            }
        }
        placements.removeAll { $0.gift.address == drag.id }
        returnGift(drag.id, from: pose, fast: v.dy > 650)
        if drag.fromCard {
            commit()
        }
        sync()
    }

    private func place(_ gift: WalletContext.Collectible, from: WalletStickerPose, spot: WalletStickerPlacement.Spot, angle: CGFloat, thrown: Bool, style: WalletContext.CardGiftStyle? = nil) {
        guard let card = cardView, card.frame.width > 0 else {
            return
        }
        let id = gift.address
        let size = card.stickerSurfaceSize
        let previous = placements.first(where: { $0.gift.address == id })
        guard previous != nil || placements.count < WalletCollectablesStage.limit else {
            returnGift(id, from: from)
            limitReached?()
            return
        }
        let artwork = WalletCollectibleArtworks.shared.current(id)
        let sticker = WalletContext.CardSticker(gift: gift, x: Double(spot.center.x / size.width), y: Double(spot.center.y / size.height), angle: Double(angle), scale: Double(spot.scale), modelFile: artwork.modelFile ?? previous?.modelFile, geometryVersion: 1, style: style ?? previous?.style, giftStyle: artwork.style ?? previous?.giftStyle, aspectRatio: previous?.aspectRatio, cornerRadius: previous?.cornerRadius)
        placements.removeAll { $0.gift.address == id }
        if style != nil {
            placements = placements.map { $0.withStyle(nil) }
        }
        placements.append(sticker)
        var flight = Flight(id: id, kind: .stick, start: CACurrentMediaTime(), from: from, to: from)
        flight.thrown = thrown
        flights[id] = flight
        styleOrigin = spot.center
        commit()
        sync()
        startAnimator()
    }

    private func returnGift(_ id: String, from: WalletStickerPose, peelFirst: Bool = false, fast: Bool = false) {
        var target = WalletStickerPose(center: from.center, side: from.side * 0.6, angle: from.angle)
        target.opacity = 0
        var kind = Flight.Kind.vanish
        if let overlay, let grid = gridView, grid.window === overlay.window, let tile = grid.tileFrame(id) {
            let cell = overlay.convert(tile, from: grid)
            target = WalletStickerPose(center: NSMakePoint(cell.midX, cell.midY), side: cell.width * WalletCollectablesStage.artShare, border: 0)
            kind = .back
            WalletCollectablesStage.haptic()
        }
        var flight = Flight(id: id, kind: kind, start: CACurrentMediaTime(), from: from, to: target)
        flight.peelFirst = peelFirst
        flight.fast = fast
        flights[id] = flight
        startAnimator()
    }

    private func startAnimator() {
        if animator == nil {
            animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] _ in
                self?.tick()
            })
        }
        animator?.isPaused = false
    }

    private func stopAnimator() {
        animator?.invalidate()
        animator = nil
    }

    private func finishOverlay() {
        overlay?.removeFromSuperview()
        overlay = nil
        trash = nil
        cardView?.setStickerInteraction(false)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if let overlay {
            var faces: [WalletStickerOverlayView.Face] = []
            let card = cardRect(in: overlay)
            for id in Array(flights.keys) {
                guard var flight = flights[id] else {
                    continue
                }
                let elapsed = max(0, now - flight.start)
                let contact = flight.thrown ? 0.5 : 0.18
                let travel = flight.peelFirst ? 0.5 : (flight.fast ? 0.32 : 0.44)
                let lead = flight.peelFirst ? 0.225 : 0
                let settle = WalletCollectablesStage.settle
                let duration: Double
                switch flight.kind {
                case .stick:
                    duration = contact + settle + WalletCollectablesStage.handoffOverlap
                case .back:
                    duration = lead + travel + WalletCollectablesStage.homeLay
                case .vanish:
                    duration = 0.25
                }
                var target = flight.to
                if flight.kind == .stick, let cardView, let sticker = placements.first(where: { $0.gift.address == id }), let projected = cardView.stickerPose(sticker, in: overlay) {
                    target = projected
                    target.angle = flight.from.angle + atan2(sin(projected.angle - flight.from.angle), cos(projected.angle - flight.from.angle))
                } else if flight.kind == .back, let grid = gridView, grid.window === overlay.window, let tile = grid.tileFrame(id) {
                    let cell = overlay.convert(tile, from: grid)
                    target = WalletStickerPose(center: NSMakePoint(cell.midX, cell.midY), side: cell.width * WalletCollectablesStage.artShare, border: 0)
                }
                let a = flight.from
                var pose = a
                var clip: (rect: NSRect, radius: CGFloat)?
                switch flight.kind {
                case .stick:
                    let u = CGFloat(min(1, elapsed / contact))
                    let e = flight.thrown ? 1 - pow(1 - u, 3) : WalletCollectablesStage.ease(elapsed / contact)
                    pose = WalletStickerPose.mix(a, target, e)
                    if flight.thrown {
                        let dx = target.center.x - a.center.x, dy = target.center.y - a.center.y
                        let length = max(1, hypot(dx, dy)), direction: CGFloat = dx >= 0 ? -1 : 1
                        let bow = min(110, length * 0.32), arc = sin(.pi * u)
                        pose.center.x += -dy / length * bow * direction * arc
                        pose.center.y += (dx / length * bow * direction - bow * 0.5) * arc
                        pose.side *= 1 + 0.12 * arc
                        pose.border = min(1, u * 3)
                        pose.lift = 0.9 * arc
                        let tip = WalletCollectablesStage.ease(Double((u - 0.6) / 0.4))
                        pose.bend = WalletCollectablesStage.bendAngle * tip
                        pose.shade = tip
                    } else {
                        pose.border = a.border + (1 - a.border) * e
                        pose.tilt = a.tilt * (1 - e)
                        pose.axis = a.axis
                        pose.lift = a.lift * (1 - e)
                        pose.bend = WalletCollectablesStage.bendAngle * e
                        pose.shade = e
                    }
                    let lay = WalletCollectablesStage.ease((elapsed - contact) / settle)
                    pose.wave = lay
                    if elapsed >= contact {
                        pose.overhang = 1 - lay
                    }
                    if elapsed >= contact + settle {
                        pose.wave = nil
                        pose.bend = 0
                        pose.shade = 0
                        pose.overhang = 0
                    }
                    if elapsed >= contact, !flight.contacted {
                        flight.contacted = true
                        flights[id] = flight
                        WalletCollectablesStage.haptic()
                        updateStyle()
                    }
                    if elapsed >= contact + settle, !flight.handedOff {
                        flight.handedOff = true
                        flights[id] = flight
                        tutorial.finish()
                        sync()
                    }
                    if let card {
                        clip = (card, 20.0 * card.width / 336.0)
                    }
                case .back:
                    let u = CGFloat(min(1, max(0, (elapsed - lead) / travel)))
                    let e = flight.peelFirst ? (u < 0.5 ? 2 * u * u : 1 - 2 * (1 - u) * (1 - u)) : 1 - (1 - u) * (1 - u)
                    let distance = hypot(target.center.x - a.center.x, target.center.y - a.center.y)
                    let c = CGPoint(x: (a.center.x + target.center.x) / 2, y: (a.center.y + target.center.y) / 2 - min(90, distance * 0.28))
                    let w = 1 - e, arc = sin(.pi * e)
                    pose = WalletStickerPose.mix(a, target, e)
                    pose.center = CGPoint(x: w * w * a.center.x + 2 * w * e * c.x + e * e * target.center.x, y: w * w * a.center.y + 2 * w * e * c.y + e * e * target.center.y)
                    pose.side *= 1 + 0.05 * arc
                    pose.angle = a.angle * (1 - e)
                    pose.lift = 0.8 * arc
                    let landed = elapsed - lead - travel
                    if landed >= 0 {
                        let lay = WalletCollectablesStage.ease(landed / WalletCollectablesStage.homeLay)
                        pose = target
                        pose.border = a.border * (1 - WalletCollectablesStage.ease(Double((lay - 0.55) / 0.45)))
                        pose.wave = lay
                        pose.bend = lay < 1 ? WalletCollectablesStage.bendAngle : 0
                        pose.shade = lay < 1 ? 1 - lay : 0
                    } else {
                        pose.border = a.border
                        let raise = WalletCollectablesStage.ease((elapsed - lead) / WalletCollectablesStage.raiseSpan)
                        if flight.peelFirst && raise < 1 {
                            pose.wave = 1 - WalletCollectablesStage.ease(elapsed / WalletCollectablesStage.peelSpan)
                            pose.bend = WalletCollectablesStage.bendAngle * (1 - raise)
                            pose.shade = 1 - raise
                        } else {
                            let tip = WalletCollectablesStage.ease(Double((u - 0.55) / 0.45))
                            pose.wave = 0
                            pose.bend = WalletCollectablesStage.bendAngle * tip
                            pose.shade = tip
                        }
                    }
                    let k = min(1, max(0, landed / WalletCollectablesStage.homeLay))
                    gridView?.setReturnScale(id, scale: 1 - 0.022 * sin(.pi * k))
                case .vanish:
                    let u = CGFloat(min(1, elapsed / duration))
                    pose = WalletStickerPose.mix(a, target, u)
                    pose.opacity = 1 - u
                }
                if elapsed >= duration {
                    gridView?.setReturnScale(id, scale: 1)
                    flights[id] = nil
                    sync()
                } else {
                    flights[id] = flight
                    faces.append(.init(id: id, pose: pose, clip: clip))
                }
            }
            if drag != nil, let pose = dragPose(at: now), let drag {
                faces.append(.init(id: drag.id, pose: pose, clip: nil))
            }
            overlay.render(faces)
            if drag == nil && flights.isEmpty {
                finishOverlay()
            }
        }
        tickStyle(now)
        tickSettle(now)
        if drag == nil && flights.isEmpty && styleStart == nil && settle == nil {
            stopAnimator()
        }
    }

    private func stylePattern(_ style: WalletContext.CardGiftStyle?) -> CGImage? {
        guard let style else {
            return nil
        }
        let key = walletCardStyleKey(style)
        if let cached = patterns[key] {
            return cached
        }
        for sticker in placements where walletCardStyleKey(sticker.giftStyle) == key {
            if let pattern = WalletCollectibleArtworks.shared.current(sticker.gift.address).pattern {
                patterns[key] = pattern
                return pattern
            }
        }
        return nil
    }

    private func updateStyle() {
        guard let card = cardView else {
            return
        }
        let source = placements.last(where: { $0.style != nil })
        let target = source?.style
        if let source, let flight = flights[source.gift.address], flight.kind == .stick, !flight.contacted {
            return
        }
        if styleStart == nil || walletCardStyleKey(target) != walletCardStyleKey(styleTo), let source {
            styleOrigin = card.stickerCenter(source)
        }
        if walletCardStyleKey(target) != walletCardStyleKey(styleTo) {
            styleFrom = styleTo
            styleTo = target
            let visible = card.window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            styleStart = visible ? CACurrentMediaTime() : nil
            if styleStart != nil {
                startAnimator()
            }
        }
        if styleStart == nil {
            styleFrom = styleTo
            card.setGiftStyle(from: nil, to: target, origin: styleOrigin, progress: 1, pattern: stylePattern(target))
        }
    }

    private func tickStyle(_ now: CFTimeInterval) {
        guard let start = styleStart else {
            return
        }
        guard let card = cardView, card.window != nil else {
            styleStart = nil
            styleFrom = styleTo
            cardView?.setGiftStyle(from: nil, to: styleTo, origin: styleOrigin, progress: 1, pattern: stylePattern(styleTo))
            return
        }
        let progress = min(1, (now - start) / (styleTo == nil ? 0.6 : 1.05))
        card.setGiftStyle(from: styleFrom, to: styleTo, origin: styleOrigin, progress: progress, pattern: stylePattern(styleTo ?? styleFrom))
        if progress >= 1 {
            styleStart = nil
            styleFrom = styleTo
        }
    }

    static func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    static func ease(_ x: Double) -> CGFloat {
        let u = CGFloat(min(1, max(0, x)))
        return u * u * (3 - 2 * u)
    }

    static func wrapped(_ angle: CGFloat) -> CGFloat {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi {
            value -= 2 * .pi
        } else if value < -.pi {
            value += 2 * .pi
        }
        return value
    }
}

@available(macOS 10.15, *)
final class WalletStickerOverlayView: View {
    struct Face {
        let id: String
        let pose: WalletStickerPose
        let clip: (rect: NSRect, radius: CGFloat)?
    }

    private var faceLayers: [String: WalletStickerFaceLayer] = [:]

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func render(_ faces: [Face]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let ids = Set(faces.map(\.id))
        for (id, faceLayer) in faceLayers where !ids.contains(id) {
            faceLayer.removeFromSuperlayer()
            faceLayers[id] = nil
        }
        let scale = window?.backingScaleFactor ?? 2
        let colorSpace = window?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        for face in faces {
            let faceLayer: WalletStickerFaceLayer
            if let current = faceLayers[face.id] {
                faceLayer = current
            } else {
                faceLayer = WalletStickerFaceLayer(id: face.id)
                faceLayers[face.id] = faceLayer
                layer?.addSublayer(faceLayer)
            }
            faceLayer.frame = bounds
            faceLayer.apply(face.pose, clip: face.clip, scale: scale, colorSpace: colorSpace)
        }
        CATransaction.commit()
    }
}

@available(macOS 10.15, *)
private final class WalletStickerFaceLayer: SimpleLayer {
    private let body = SimpleLayer()
    private let waveLayer: WalletStickerWaveLayer?
    private let baseLayer = SimpleLayer()
    private let artLayer = SimpleLayer()
    private let clipLayer = SimpleLayer()
    private let clipOutside = SimpleLayer()
    private let clipCard = SimpleLayer()

    init(id: String) {
        waveLayer = WalletStickerWaveLayer.isSupported ? WalletStickerWaveLayer(id: id) : nil
        super.init()
        if let waveLayer {
            body.addSublayer(waveLayer)
        } else {
            baseLayer.contents = WalletCollectableImages.base(id)
            artLayer.contents = WalletCollectableImages.art(id)
            baseLayer.contentsGravity = .resize
            artLayer.contentsGravity = .resize
            body.addSublayer(baseLayer)
            body.addSublayer(artLayer)
        }
        body.shadowColor = NSColor.black.cgColor
        addSublayer(body)
        clipOutside.backgroundColor = NSColor.black.cgColor
        clipCard.backgroundColor = NSColor.black.cgColor
        clipCard.cornerCurve = .continuous
        clipLayer.addSublayer(clipOutside)
        clipLayer.addSublayer(clipCard)
    }

    override init(layer: Any) {
        waveLayer = nil
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ pose: WalletStickerPose, clip: (rect: NSRect, radius: CGFloat)?, scale: CGFloat, colorSpace: CGColorSpace) {
        let side = max(1, pose.side)
        let pad = side * 0.3
        body.transform = CATransform3DIdentity
        body.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        body.position = pose.center
        if let waveLayer {
            waveLayer.frame = body.bounds.insetBy(dx: -pad, dy: -pad)
            waveLayer.apply(side: side, pad: pad, pose: pose, scale: scale, colorSpace: colorSpace)
        } else {
            baseLayer.frame = body.bounds
            artLayer.frame = body.bounds
            baseLayer.opacity = Float(pose.border)
        }
        var transform = CATransform3DMakeRotation(pose.angle, 0, 0, 1)
        if pose.tilt > 0.01 {
            transform = CATransform3DConcat(transform, CATransform3DMakeRotation(pose.tilt * .pi / 180, pose.axis.dx, pose.axis.dy, 0))
            var perspective = CATransform3DIdentity
            perspective.m34 = -0.55 / (side + pad * 2)
            transform = CATransform3DConcat(transform, perspective)
        }
        body.transform = transform
        body.shadowOpacity = Float(0.3 * pose.lift)
        body.shadowRadius = 3 + 15 * pose.lift
        body.shadowOffset = CGSize(width: 0, height: 2 + 18 * pose.lift)
        body.opacity = Float(pose.opacity)
        if pose.blur > 0.01, let filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: pose.blur * scale]) {
            body.filters = [filter]
        } else if body.filters != nil {
            body.filters = nil
        }
        if let clip, let overhang = pose.overhang, overhang < 1 {
            clipLayer.frame = bounds
            clipOutside.frame = bounds
            clipOutside.opacity = Float(max(0, overhang))
            clipCard.frame = clip.rect
            clipCard.cornerRadius = clip.radius
            mask = clipLayer
        } else {
            mask = nil
        }
    }
}

final class WalletCardStickerLayer: SimpleLayer {
    private let gloss = SimpleGradientLayer()
    private let glossMask = SimpleLayer()
    private let id: String

    init(id: String) {
        self.id = id
        super.init()
        contents = WalletCollectableImages.sticker(id)
        contentsGravity = .resize
        gloss.startPoint = CGPoint(x: 0, y: 0)
        gloss.endPoint = CGPoint(x: 1, y: 1)
        gloss.colors = [0, 0, 0.12, 0, 0].map { NSColor.white.withAlphaComponent($0).cgColor }
        glossMask.contents = WalletCollectableImages.cut(id)
        glossMask.contentsGravity = .resize
        gloss.mask = glossMask
        addSublayer(gloss)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.4
        gloss.add(fade, forKey: "opacity")
    }

    override init(layer: Any) {
        self.id = (layer as? WalletCardStickerLayer)?.id ?? ""
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshImage() -> Bool {
        guard contents == nil, let image = WalletCollectableImages.sticker(id) else {
            return false
        }
        contents = image
        glossMask.contents = WalletCollectableImages.cut(id)
        return true
    }

    func layoutGloss() {
        gloss.frame = bounds
        glossMask.frame = gloss.bounds
    }

    func shine(at center: CGFloat) {
        let width: CGFloat = 0.14
        gloss.locations = [0, center - width, center, center + width, 1].map { NSNumber(value: Double(min(1, max(0, $0)))) }
    }
}
