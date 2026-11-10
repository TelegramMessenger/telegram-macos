import Cocoa
import TGUIKit
import TelegramTheme
import TelegramContext
import TelegramCore
import Postbox
import Localization
import GeneralRows
import SwiftSignalKit
import WalletContext
import UniqueGiftRenderer

@available(macOS 10.15, *)
final class WalletCollectablesRowItem: GeneralRowItem {
    static let spacing: CGFloat = 10
    static let columns: Int = 3

    fileprivate let context: any AccountContextProtocol
    fileprivate let environment: WalletUIEnvironment
    fileprivate let collectibles: [WalletContext.Collectible]
    fileprivate let stage: WalletCollectablesStage
    fileprivate let open: (WalletContext.Collectible) -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, environment: WalletUIEnvironment, collectibles: [WalletContext.Collectible], stage: WalletCollectablesStage, viewType: GeneralViewType, open: @escaping (WalletContext.Collectible) -> Void) {
        self.context = context
        self.environment = environment
        self.collectibles = collectibles
        self.stage = stage
        self.open = open
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    var tileSide: CGFloat {
        return floor((blockWidth - WalletCollectablesRowItem.spacing * CGFloat(WalletCollectablesRowItem.columns - 1)) / CGFloat(WalletCollectablesRowItem.columns))
    }

    override var height: CGFloat {
        let rows = (collectibles.count + WalletCollectablesRowItem.columns - 1) / WalletCollectablesRowItem.columns
        return tileSide * CGFloat(rows) + WalletCollectablesRowItem.spacing * CGFloat(max(0, rows - 1))
    }

    override var instantlyResize: Bool {
        return true
    }

    override func viewClass() -> AnyClass {
        return WalletCollectablesRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().walletControllerCollectibles
    }
}

@available(macOS 10.15, *)
private final class WalletCollectablesRowView: TableRowView {
    private let gridView = WalletCollectablesGridView(frame: .zero)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        addSubview(gridView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletCollectablesRowItem else {
            return
        }
        gridView.set(collectibles: item.collectibles, context: item.context, environment: item.environment, stage: item.stage, open: item.open)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletCollectablesRowItem else {
            return
        }
        gridView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), 0, item.blockWidth, item.height)
        gridView.layout(tileSide: item.tileSide)
    }
}

@available(macOS 10.15, *)
private final class WalletCollectablesGridView: View, WalletCollectablesGrid {
    private var tiles: [WalletCollectibleTileView] = []
    private var stage: WalletCollectablesStage?
    private var open: ((WalletContext.Collectible) -> Void)?
    private var scrollObserver: NSObjectProtocol?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }

    func set(collectibles: [WalletContext.Collectible], context: any AccountContextProtocol, environment: WalletUIEnvironment, stage: WalletCollectablesStage, open: @escaping (WalletContext.Collectible) -> Void) {
        self.open = open
        let existing = Dictionary(tiles.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let updated = collectibles.map { collectible -> WalletCollectibleTileView in
            let tile = existing[collectible.address] ?? WalletCollectibleTileView(collectible)
            tile.update(collectible: collectible, context: context, environment: environment)
            return tile
        }
        let ids = Set(updated.map(\.id))
        for tile in tiles where !ids.contains(tile.id) {
            tile.removeFromSuperview()
        }
        for tile in updated where tile.superview !== self {
            addSubview(tile)
        }
        tiles = updated

        if self.stage !== stage {
            self.stage?.detach(grid: self)
            self.stage = stage
        }
        if window != nil {
            stage.attach(grid: self)
        }
        updateTiles(animated: false)
        updateVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
        if window != nil {
            stage?.attach(grid: self)
            updateTiles(animated: false)
            if let clipView = enclosingScrollView?.contentView {
                scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: nil, using: { [weak self] _ in
                    self?.updateVisibility()
                })
            }
        } else {
            stage?.detach(grid: self)
        }
        updateVisibility()
    }

    func layout(tileSide: CGFloat) {
        for (index, tile) in tiles.enumerated() {
            let column = index % WalletCollectablesRowItem.columns
            let row = index / WalletCollectablesRowItem.columns
            tile.frame = NSMakeRect(CGFloat(column) * (tileSide + WalletCollectablesRowItem.spacing), CGFloat(row) * (tileSide + WalletCollectablesRowItem.spacing), tileSide, tileSide)
        }
        window?.invalidateCursorRects(for: self)
        updateVisibility()
    }

    private func updateVisibility() {
        let visible = window != nil ? visibleRect : .zero
        for tile in tiles {
            tile.setAnimationVisible(!visible.isEmpty && tile.frame.intersects(visible))
        }
        stage?.gridDidUpdate()
    }

    var visibleGiftIds: [String] {
        return tiles.filter { $0.collectible.kind == .gift && $0.frame.intersects(visibleRect) }.map(\.id)
    }

    var isShown: Bool {
        return window != nil && !visibleRect.isEmpty && !isHiddenOrHasHiddenAncestor
    }

    func setReturnScale(_ id: String, scale: CGFloat) {
        guard let tile = tiles.first(where: { $0.id == id }), let layer = tile.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = walletAmountCenteredTransform(CATransform3DMakeScale(scale, scale, 1), layer: layer)
        CATransaction.commit()
    }

    func setModelWiggle(_ id: String, angle: CGFloat, scale: CGFloat) {
        tiles.first(where: { $0.id == id })?.setModelWiggle(angle: angle, scale: scale)
    }

    func tileFrame(_ id: String) -> NSRect? {
        return tiles.first(where: { $0.id == id })?.frame
    }

    func updateTiles(animated: Bool) {
        guard let stage else {
            return
        }
        for tile in tiles {
            tile.update(isTaken: stage.isPlaced(tile.id) || stage.isHeld(tile.id), animated: animated)
        }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let stage else {
            return
        }
        for tile in tiles where stage.canPick(tile.id) {
            addCursorRect(tile.frame, cursor: .openHand)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    override func quickLook(with event: NSEvent) {
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let tile = tiles.first(where: { $0.frame.contains(point) }) else {
            super.mouseDown(with: event)
            return
        }
        tile.isHighlighted = true
        if let stage, stage.canPick(tile.id) {
            let dragged = stage.track(fromCell: tile.id, in: self, event: event)
            tile.isHighlighted = false
            if !dragged {
                openTile(tile)
            }
        } else {
            trackClick(on: tile, event: event)
        }
    }

    private func openTile(_ tile: WalletCollectibleTileView) {
        open?(tile.collectible)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let stage, let tile = tiles.first(where: { $0.frame.contains(point) }), let items = stage.menuItems(for: tile.id), !items.isEmpty else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = ContextMenu()
        for item in items {
            menu.addItem(item)
        }
        AppMenu.show(menu: menu, event: event, for: self)
    }

    private func trackClick(on tile: WalletCollectibleTileView, event: NSEvent) {
        guard let window = event.window else {
            tile.isHighlighted = false
            return
        }
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: Date(timeIntervalSinceNow: 0.1), inMode: .eventTracking, dequeue: true) else {
                guard NSEvent.pressedMouseButtons & 1 == 0 else {
                    continue
                }
                tile.isHighlighted = false
                if tile.frame.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
                    openTile(tile)
                }
                return
            }
            let inside = tile.frame.contains(convert(next.locationInWindow, from: nil))
            if next.type == .leftMouseUp {
                tile.isHighlighted = false
                if inside {
                    openTile(tile)
                }
                return
            }
            tile.isHighlighted = inside
        }
    }
}

@available(macOS 10.15, *)
private func walletCollectibleNumberText(_ collectible: WalletContext.Collectible, gift: StarGift.UniqueGift?) -> String? {
    if let gift {
        return "#\(gift.number)"
    }
    guard let range = collectible.name.range(of: "#[0-9]+$", options: .regularExpression) else {
        return nil
    }
    return String(collectible.name[range])
}

private func walletCollectibleRibbonColor(_ rgb: Int32, hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> NSColor {
    let color = NSColor(rgb: UInt32(bitPattern: rgb) & 0xffffff).usingColorSpace(.sRGB) ?? NSColor(rgb: UInt32(bitPattern: rgb) & 0xffffff)
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return NSColor(hue: min(1, max(0, h * hue)), saturation: min(1, max(0, s * saturation)), brightness: min(1, max(0, b * brightness)), alpha: a)
}

private let walletCollectibleRibbonSide: CGFloat = 48

@available(macOS 10.15, *)
private func walletCollectibleCellImage(_ artwork: WalletCollectibleArtwork, side: CGFloat, silhouette: Bool, drawModel: Bool = true) -> CGImage? {
    guard side > 0, let source = artwork.styleSource, let art = artwork.art else {
        return nil
    }
    let scale = System.backingScale
    let colors = UniqueGiftColors(center: source.inner, edge: source.outer, pattern: source.pattern)
    let glyph = artwork.pattern.flatMap { UniqueGiftGlyph(image: $0) }?.mask
    guard let background = UniqueGiftBackgroundRenderer.makeImage(geometry: .item(size: NSMakeSize(side, side), giftCenterY: side / 2, cornerRadius: 0), colors: colors, glyph: glyph, scale: scale) else {
        return nil
    }
    let pixels = Int(ceil(side * scale))
    guard let space = CGColorSpace(name: CGColorSpace.sRGB), let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    ctx.draw(background, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    ctx.scaleBy(x: scale, y: scale)
    let icon = side * WalletCollectablesStage.artShare
    let frame = CGRect(x: (side - icon) / 2, y: (side - icon) / 2, width: icon, height: icon)
    if silhouette {
        let tint = walletCollectibleRibbonColor(source.outer, hue: 1, saturation: 1.1, brightness: 0.86)
        if let shape = WalletGiftPattern.tinted(art, color: Int32(bitPattern: UInt32(tint.rgb))) {
            ctx.draw(shape, in: frame)
        }
    } else if drawModel {
        ctx.draw(art, in: frame)
    }
    return ctx.makeImage()
}

private func walletCollectibleRibbonShape() -> CGImage? {
    return generateImage(NSMakeSize(walletCollectibleRibbonSide, walletCollectibleRibbonSide), rotatedContext: { size, ctx in
        ctx.clear(CGRect(origin: .zero, size: size))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 46.83, y: 24.5))
        path.addLine(to: CGPoint(x: 23.5, y: 1.17))
        path.addCurve(to: CGPoint(x: 20.68, y: 0), control1: CGPoint(x: 22.75, y: 0.42), control2: CGPoint(x: 21.73, y: 0))
        path.addCurve(to: CGPoint(x: 1.55, y: 0.05), control1: CGPoint(x: 19.62, y: 0), control2: CGPoint(x: 2.73, y: 0.05))
        path.addCurve(to: CGPoint(x: 0.6, y: 2.32), control1: CGPoint(x: 0.36, y: 0.05), control2: CGPoint(x: -0.23, y: 1.4885))
        path.addLine(to: CGPoint(x: 45.72, y: 47.44))
        path.addCurve(to: CGPoint(x: 48, y: 46.5), control1: CGPoint(x: 46.56, y: 48.28), control2: CGPoint(x: 48, y: 47.68))
        path.addCurve(to: CGPoint(x: 48, y: 27.32), control1: CGPoint(x: 48, y: 45.31), control2: CGPoint(x: 48, y: 28.38))
        path.addCurve(to: CGPoint(x: 46.82, y: 24.5), control1: CGPoint(x: 48, y: 26.26), control2: CGPoint(x: 47.5, y: 25.24))
        path.closeSubpath()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    })
}

@available(macOS 10.15, *)
private func walletCollectibleRibbonText(_ text: String) -> CGImage? {
    let textNode = TextNode.layoutText(.initialize(string: text, color: .white, font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    return generateImage(NSMakeSize(walletCollectibleRibbonSide, walletCollectibleRibbonSide), rotatedContext: { size, ctx in
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.translateBy(x: 29, y: 19)
        ctx.rotate(by: CGFloat.pi / 4)
        let fit = min(1, 40 / max(textNode.0.size.width, 1))
        ctx.scaleBy(x: fit, y: fit)
        textNode.1.draw(NSRect(x: -textNode.0.size.width / 2, y: -textNode.0.size.height / 2, width: textNode.0.size.width, height: textNode.0.size.height), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })
}

@available(macOS 10.15, *)
private final class WalletCollectibleTileView: View {
    static func cornerRadius(_ side: CGFloat) -> CGFloat {
        return floor(side * 0.2)
    }

    let id: String
    private(set) var collectible: WalletContext.Collectible
    private let mediaView = View()
    private let cellView = ImageView()
    private let modelView = ImageView()
    private let peeledView = ImageView()
    private var peeledKey: String?
    private let ribbonView = ImageView()
    private let ribbonTextView = View()
    private let ribbonTextMask = SimpleLayer()
    private let ribbonNumberView = ImageView()
    private var ribbonKey: String?
    private let imageView = TransformImageView(frame: .zero)
    private let lottieView = Control(frame: .zero)
    private let imageFetchDisposable = MetaDisposable()
    private let lottieFetchDisposable = MetaDisposable()
    private let lottieDataDisposable = MetaDisposable()
    private let artworkDisposable = MetaDisposable()
    private var context: (any AccountContextProtocol)?
    private var environment: WalletUIEnvironment?
    private var imageFile: TelegramMediaWebFile?
    private var lottieFile: TelegramMediaWebFile?
    private var lottieContents: Data?
    private var isAnimationVisible = false
    private var isTaken: Bool?

    var isHighlighted: Bool = false {
        didSet {
            if isHighlighted != oldValue {
                alphaValue = isHighlighted ? 0.7 : 1.0
            }
        }
    }

    init(_ collectible: WalletContext.Collectible) {
        self.id = collectible.address
        self.collectible = collectible
        super.init(frame: .zero)
        isEventLess = true

        mediaView.isEventLess = true
        mediaView.layer?.masksToBounds = true
        mediaView.layer?.cornerCurve = .continuous
        lottieView.isEventLess = true
        lottieView.isHidden = true
        lottieView.isAccessibilityDecorative = true

        mediaView.addSubview(imageView)
        mediaView.addSubview(lottieView)
        addSubview(mediaView)

        cellView.isEventLess = true
        cellView.isHidden = true
        cellView.isAccessibilityDecorative = true
        cellView.layer?.masksToBounds = true
        cellView.layer?.cornerCurve = .continuous
        addSubview(cellView)
        modelView.isEventLess = true
        modelView.isAccessibilityDecorative = true
        addSubview(modelView)

        peeledView.isEventLess = true
        peeledView.isAccessibilityDecorative = true
        peeledView.layer?.masksToBounds = true
        peeledView.layer?.cornerCurve = .continuous
        peeledView.layer?.opacity = 0
        addSubview(peeledView)

        ribbonView.isEventLess = true
        ribbonTextView.isEventLess = true
        ribbonNumberView.isEventLess = true
        ribbonView.isAccessibilityDecorative = true
        ribbonNumberView.isAccessibilityDecorative = true
        ribbonView.isHidden = true
        ribbonTextMask.contentsGravity = .resize
        ribbonTextView.layer?.mask = ribbonTextMask
        ribbonTextView.addSubview(ribbonNumberView)
        ribbonView.addSubview(ribbonTextView)
        addSubview(ribbonView)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(collectible.name)
        setAccessibilityValue(collectible.subtitle)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        imageFetchDisposable.dispose()
        lottieFetchDisposable.dispose()
        lottieDataDisposable.dispose()
        artworkDisposable.dispose()
    }

    func update(collectible: WalletContext.Collectible, context: any AccountContextProtocol, environment: WalletUIEnvironment) {
        self.collectible = collectible
        setAccessibilityLabel(collectible.name)
        setAccessibilityValue(collectible.subtitle)
        mediaView.backgroundColor = theme.colors.grayForeground

        let accountChanged = self.context?.account !== context.account
        self.context = context
        self.environment = environment

        let imageFile = walletCollectibleWebFile(collectible.image ?? collectible.thumbnail)
        if accountChanged || imageFile?.resource.id != self.imageFile?.resource.id {
            self.imageFile = imageFile
            imageFetchDisposable.set(nil)
            imageView.clear()
            imageView.isHidden = imageFile == nil
            if let imageFile {
                imageView.setSignal(environment.webFilePhoto(photo: imageFile, scale: backingScaleFactor, useActualDimensions: false))
                imageFetchDisposable.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: imageFile.resource)).start())
            }
        }

        let lottieFile = collectible.kind == .gift ? walletCollectibleWebFile(collectible.lottie) : nil
        if accountChanged || lottieFile?.resource.id != self.lottieFile?.resource.id {
            self.lottieFile = lottieFile
            lottieContents = nil
            lottieFetchDisposable.set(nil)
            lottieDataDisposable.set(nil)
            environment.setCollectibleAnimation(in: lottieView, contents: nil, key: "", size: lottieView.frame.size)
            lottieView.isHidden = true
            if let lottieFile {
                let mediaBox = context.account.postbox.mediaBox
                lottieFetchDisposable.set(fetchedMediaResource(mediaBox: mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: lottieFile.resource)).start())
                lottieDataDisposable.set((mediaBox.resourceData(lottieFile.resource, attemptSynchronously: false)
                |> filter { $0.complete }
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] data in
                    guard let self, self.lottieFile?.resource.id == lottieFile.resource.id,
                          data.size <= Int64(5 * 1024 * 1024),
                          let fileData = try? Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedIfSafe),
                          let contents = walletCollectibleLottieData(fileData) else {
                        return
                    }
                    self.lottieContents = contents
                    if self.isAnimationVisible {
                        self.playAnimation()
                    }
                }))
            }
        }

        if accountChanged {
            if collectible.kind == .gift {
                artworkDisposable.set(WalletCollectibleArtworks.shared.artwork(collectible, context: context).start(next: { [weak self] _ in
                    self?.updateRibbon()
                    self?.updatePeeled()
                    guard let grid = self?.superview else {
                        return
                    }
                    grid.window?.invalidateCursorRects(for: grid)
                }))
            } else {
                artworkDisposable.set(nil)
            }
        }
        updateRibbon()
        updatePeeled()
        needsLayout = true
    }

    private func updatePeeled() {
        let side = bounds.width
        let artwork = WalletCollectibleArtworks.shared.current(id)
        let key = "\(side)|\(artwork.styleSource != nil)|\(artwork.art != nil)|\(artwork.pattern != nil)"
        guard side > 0, key != peeledKey else {
            return
        }
        peeledKey = key
        let cell = walletCollectibleCellImage(artwork, side: side, silhouette: false, drawModel: false)
        cellView.image = cell
        modelView.image = artwork.art
        modelView.isHidden = cell == nil
        cellView.isHidden = cell == nil
        peeledView.image = cell == nil ? nil : walletCollectibleCellImage(artwork, side: side, silhouette: true)
        applyTakenState()
    }

    private func applyTakenState() {
        let taken = isTaken == true
        let peels = peeledView.image != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mediaView.layer?.opacity = taken && !peels ? 0.35 : 1
        cellView.layer?.opacity = taken && peels ? 0 : 1
        modelView.layer?.opacity = taken ? 0 : 1
        peeledView.layer?.opacity = taken && peels ? 1 : 0
        CATransaction.commit()
    }

    private func updateRibbon() {
        let artwork = WalletCollectibleArtworks.shared.current(id)
        guard collectible.kind == .gift, let number = walletCollectibleNumberText(collectible, gift: artwork.gift ?? collectible.nft?.gift) else {
            ribbonKey = nil
            ribbonView.isHidden = true
            return
        }
        let colors: [NSColor]
        if let source = artwork.styleSource {
            colors = [walletCollectibleRibbonColor(source.outer, hue: 0.97, saturation: 1.45, brightness: 0.89), walletCollectibleRibbonColor(source.outer, hue: 1.01, saturation: 1.22, brightness: 1.04)]
        } else {
            colors = [NSColor(rgb: 0x34a4fc), NSColor(rgb: 0x6fd3ff)]
        }
        let key = number + "|" + colors.map { $0.description }.joined(separator: "|")
        guard key != ribbonKey else {
            return
        }
        ribbonKey = key
        guard let background = generateGradientTintedImage(image: walletCollectibleRibbonShape(), colors: colors, direction: .mirroredDiagonal) else {
            ribbonView.isHidden = true
            return
        }
        ribbonView.isHidden = false
        ribbonView.image = background
        ribbonView.setFrameSize(NSMakeSize(walletCollectibleRibbonSide, walletCollectibleRibbonSide))
        ribbonTextView.frame = ribbonView.bounds
        ribbonTextMask.frame = ribbonTextView.bounds
        ribbonTextMask.contents = background
        ribbonNumberView.image = walletCollectibleRibbonText(number)
        ribbonNumberView.frame = ribbonTextView.bounds
        needsLayout = true
    }

    func setModelWiggle(angle: CGFloat, scale: CGFloat) {
        let transform = CATransform3DScale(CATransform3DMakeRotation(angle, 0, 0, 1), scale, scale, 1)
        for view in [modelView, lottieView, imageView] {
            if let layer = view.layer {
                layer.transform = walletAmountCenteredTransform(transform, layer: layer)
            }
        }
    }

    func setAnimationVisible(_ visible: Bool) {
        guard isAnimationVisible != visible else {
            return
        }
        isAnimationVisible = visible
        if visible {
            playAnimation()
        }
    }

    private func playAnimation() {
        guard let environment, let lottieContents, let lottieFile, lottieView.frame.width > 0 else {
            return
        }
        environment.setCollectibleAnimation(in: lottieView, contents: lottieContents, key: "wallet_collectible_tile_\(id)_\(lottieFile.resource.id.stringRepresentation)", size: lottieView.frame.size)
        lottieView.isHidden = false
    }

    func update(isTaken: Bool, animated: Bool) {
        guard self.isTaken != isTaken else {
            return
        }
        self.isTaken = isTaken
        applyTakenState()
    }

    override func layout() {
        super.layout()
        let side = bounds.width
        let sizeChanged = mediaView.frame.size != bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mediaView.frame = bounds
        mediaView.layer?.cornerRadius = WalletCollectibleTileView.cornerRadius(side)
        cellView.frame = bounds
        let modelSide = side * WalletCollectablesStage.artShare
        modelView.frame = NSMakeRect((side - modelSide) / 2, (side - modelSide) / 2, modelSide, modelSide)
        cellView.layer?.cornerRadius = WalletCollectibleTileView.cornerRadius(side)
        peeledView.frame = bounds
        peeledView.layer?.cornerRadius = WalletCollectibleTileView.cornerRadius(side)
        imageView.frame = bounds
        lottieView.frame = bounds
        ribbonView.setFrameOrigin(NSMakePoint(side - walletCollectibleRibbonSide, 0))
        CATransaction.commit()
        updatePeeled()
        if sizeChanged {
            imageView.set(arguments: TransformImageArguments(corners: ImageCorners(), imageSize: bounds.size, boundingSize: bounds.size, intrinsicInsets: NSEdgeInsets()))
            if isAnimationVisible {
                playAnimation()
            }
        }
    }
}
