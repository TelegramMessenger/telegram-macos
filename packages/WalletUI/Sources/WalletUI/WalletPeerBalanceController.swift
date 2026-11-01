import Cocoa
import TGUIKit
import TelegramContext
import TelegramTheme
import Localization
import SwiftSignalKit
import Postbox
import TelegramCore
import WalletContext

private let walletPeerBalanceInset: CGFloat = 20
private let walletPeerBalanceCardWidth: CGFloat = 360
private let walletPeerBalanceHeaderGap: CGFloat = 12
private let walletPeerBalanceButtonGap: CGFloat = 12
private let walletPeerBalanceButtonHeight: CGFloat = 40

private var walletPeerBalanceCardHeight: CGFloat {
    return ceil(walletPeerBalanceCardWidth * walletCardReferenceSize.height / walletCardReferenceSize.width)
}

private final class WalletPeerBalanceBackdropView: View {
    private var frameObserver: NSObjectProtocol?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let frameObserver = frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
            self.frameObserver = nil
        }
        guard let superview = superview else {
            return
        }
        superview.postsFrameChangedNotifications = true
        updateFrame()
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: superview, queue: .main) { [weak self] _ in
            self?.updateFrame()
        }
    }

    deinit {
        if let frameObserver = frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
    }

    private func updateFrame() {
        guard let superview = superview else {
            return
        }
        let inset = (superview.window as? Window)?.modalInset ?? 0
        frame = superview.bounds.insetBy(dx: inset, dy: inset)
        layer?.cornerRadius = inset
        layer?.masksToBounds = true
    }

    func updateTheme() {
        backgroundColor = NSColor(0x000000, 0.6)
    }
}

private final class WalletPeerBalanceSource {
    weak var view: NSView?
    weak var window: NSWindow?
    let frame: NSRect
    private var wasClipped: Bool?
    private var contentTransforms: [(view: NSView, transform: CATransform3D)] = []

    init?(view: NSView?) {
        guard let view, let window = view.window, !view.bounds.isEmpty else { return nil }
        self.view = view
        self.window = window
        self.frame = view.convert(view.bounds, to: nil)
    }

    func hold() {
        guard let view, let layer = view.layer, wasClipped == nil else { return }
        wasClipped = layer.masksToBounds
        layer.masksToBounds = true
        contentTransforms = view.subviews.compactMap { content in
            content.layer.map { (view: content, transform: $0.transform) }
        }
    }

    func update(progress: CGFloat, dismissing: Bool) {
        guard let view, wasClipped != nil else { return }
        let lift = WalletPeerCardFlight.smooth(progress / (dismissing ? 0.4 : 0.3))
        let offset = (view.isFlipped ? -1.0 : 1.0) * view.bounds.height * lift
        for content in contentTransforms {
            content.view.layer?.transform = CATransform3DConcat(content.transform, CATransform3DMakeTranslation(0, offset, 0))
        }
    }

    func restore() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for content in contentTransforms {
            content.view.layer?.transform = content.transform
        }
        if let wasClipped { view?.layer?.masksToBounds = wasClipped }
        CATransaction.commit()
        contentTransforms.removeAll()
        wasClipped = nil
    }

    deinit {
        restore()
    }
}

@available(macOS 10.15, *)
private final class WalletPeerBalanceView: View {
    private let ownershipView = TextView()
    private let ownershipBubble = View()
    private let ownershipShape = CAShapeLayer()
    private var ownership: (name: String, balance: Int64?)?
    private var noticeVisible = false
    var isOwnBalance = false
    let cardView = WalletCardView(frame: NSZeroRect)
    let sendButton = TextButton()
    var transitionSource: WalletPeerBalanceSource?
    var dismiss: (() -> Void)?
    var backgroundProgress: ((CGFloat) -> Void)?
    private let cardContainer = View()
    private let cardMask = CAShapeLayer()
    private var animator: ConstantDisplayLinkAnimator?
    private var progress: CGFloat = 0
    private var backdropProgress: CGFloat = 0
    private var isDismissing = false
    private var usesFlight = false
    private var sourceFrame: CGRect = .zero
    private var cardFrame: CGRect = .zero
    private var buttonFrame: CGRect = .zero
    private var transitionCompletion: (() -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        ownershipBubble.layer?.opacity = 0
        ownershipBubble.isEventLess = true
        ownershipBubble.layer?.masksToBounds = false
        ownershipShape.shadowColor = NSColor.black.cgColor
        ownershipShape.shadowOpacity = 0.2
        ownershipShape.shadowRadius = 10
        ownershipShape.shadowOffset = CGSize(width: 0, height: -3)
        ownershipBubble.layer?.addSublayer(ownershipShape)
        ownershipView.userInteractionEnabled = false
        ownershipView.isSelectable = false
        ownershipView.disableBackgroundDrawing = true
        ownershipView.backgroundColor = .clear
        ownershipView.layer?.isOpaque = false
        ownershipView.drawingLayer.isOpaque = false
        layer?.isOpaque = false
        addSubview(ownershipBubble)
        ownershipBubble.addSubview(ownershipView)
        addSubview(cardContainer)
        cardContainer.addSubview(cardView)
        cardContainer.layer?.masksToBounds = false
        cardContainer.alphaValue = 0
        addSubview(sendButton)
        sendButton.disableActions()
        sendButton.autoSizeToFit = false
        sendButton.scaleOnClick = true
        sendButton.animates = false
        sendButton.set(font: .medium(.text), for: .Normal)
        sendButton.set(text: strings().peerInfoHeadItemSendMoney, for: .Normal)
        updateButtonColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        updateButtonColors()
        if let ownership = ownership {
            updateOwnership(name: ownership.name, balance: ownership.balance)
        }
    }

    private func updateButtonColors() {
        ownershipShape.fillColor = (theme.colors.isDark ? NSColor(0x343840) : NSColor(0x252a33)).cgColor
        ownershipShape.strokeColor = NSColor.white.withAlphaComponent(theme.colors.isDark ? 0.18 : 0.08).cgColor
        ownershipShape.lineWidth = 0.5
        let accent = walletClassicAccent
        sendButton.set(background: accent, for: .Normal)
        sendButton.set(background: accent, for: .Highlight)
        sendButton.set(color: accent.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff), for: .Normal)
    }

    private var headerHeight: CGFloat {
        guard let layout = ownershipView.textLayout else {
            return 0
        }
        return layout.layoutSize.height + 27 + walletPeerBalanceHeaderGap
    }

    var contentSize: NSSize {
        return NSMakeSize(walletPeerBalanceCardWidth + walletPeerBalanceInset * 2, walletPeerBalanceInset + headerHeight + walletPeerBalanceCardHeight + walletPeerBalanceButtonGap + walletPeerBalanceButtonHeight + walletPeerBalanceInset)
    }

    func setNoticeVisible(_ visible: Bool, animated: Bool) {
        guard visible != noticeVisible else { return }
        noticeVisible = visible
        let previous = ownershipBubble.layer?.presentation()?.opacity ?? ownershipBubble.layer?.opacity ?? 0
        ownershipBubble.layer?.opacity = visible ? 1 : 0
        if animated {
            ownershipBubble.layer?.animateAlpha(from: CGFloat(previous), to: visible ? 1 : 0, duration: visible ? 0.2 : 0.06)
        }
    }

    func updateOwnership(name: String, balance: Int64?) {
        ownership = (name, balance)
        if balance != nil || isOwnBalance {
            let text: String
            if isOwnBalance {
                text = strings().walletPeerBalanceControllerPublicBalanceNotice
            } else {
                text = strings().walletPeerBalanceControllerPeerBalanceNotice(name, formatGramsText(balance ?? 0, maxDecimalPositions: 2))
            }
            let attributedText = NSAttributedString(string: text, font: .medium(13), textColor: .white)
            guard ownershipView.textLayout?.attributedString.isEqual(to: attributedText) != true else {
                return
            }
            let layout = TextViewLayout(attributedText, alignment: .center)
            walletMeasureBalanced(layout, width: walletPeerBalanceCardWidth - 48)
            ownershipView.update(layout)
        } else {
            ownershipView.update(nil)
        }
        ownershipBubble.isHidden = balance == nil && !isOwnBalance
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = min(walletPeerBalanceCardWidth, max(1, bounds.width - walletPeerBalanceInset * 2))
        let height = ceil(width * walletCardReferenceSize.height / walletCardReferenceSize.width)
        if let layout = ownershipView.textLayout {
            walletMeasureBalanced(layout, width: max(1, width - 48))
            ownershipView.update(layout)
        }
        let groupHeight = headerHeight + height + walletPeerBalanceButtonGap + walletPeerBalanceButtonHeight
        let top = floor((bounds.height - groupHeight) / 2)
        let bubbleWidth = ownershipView.frame.width + 28
        let bodyHeight = ownershipView.frame.height + 20
        ownershipBubble.frame = NSRect(x: floorToScreenPixels(backingScaleFactor, (bounds.width - bubbleWidth) / 2), y: top, width: bubbleWidth, height: bodyHeight + 7)
        ownershipView.setFrameOrigin(NSPoint(x: 14, y: 10))
        let outline = CGMutablePath()
        let radius: CGFloat = 10
        let tip = bubbleWidth / 2
        outline.move(to: CGPoint(x: radius, y: 0))
        outline.addLine(to: CGPoint(x: bubbleWidth - radius, y: 0))
        outline.addArc(tangent1End: CGPoint(x: bubbleWidth, y: 0), tangent2End: CGPoint(x: bubbleWidth, y: radius), radius: radius)
        outline.addLine(to: CGPoint(x: bubbleWidth, y: bodyHeight - radius))
        outline.addArc(tangent1End: CGPoint(x: bubbleWidth, y: bodyHeight), tangent2End: CGPoint(x: bubbleWidth - radius, y: bodyHeight), radius: radius)
        outline.addLine(to: CGPoint(x: tip + 9, y: bodyHeight))
        outline.addLine(to: CGPoint(x: tip + 1.4, y: bodyHeight + 6.2))
        outline.addQuadCurve(to: CGPoint(x: tip - 1.4, y: bodyHeight + 6.2), control: CGPoint(x: tip, y: bodyHeight + 7.4))
        outline.addLine(to: CGPoint(x: tip - 9, y: bodyHeight))
        outline.addLine(to: CGPoint(x: radius, y: bodyHeight))
        outline.addArc(tangent1End: CGPoint(x: 0, y: bodyHeight), tangent2End: CGPoint(x: 0, y: bodyHeight - radius), radius: radius)
        outline.addLine(to: CGPoint(x: 0, y: radius))
        outline.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: radius, y: 0), radius: radius)
        outline.closeSubpath()
        ownershipShape.frame = ownershipBubble.bounds
        ownershipShape.path = outline
        ownershipShape.shadowPath = outline
        cardFrame = NSMakeRect(floor((bounds.width - width) / 2), top + headerHeight, width, height)
        buttonFrame = NSMakeRect(cardFrame.minX, cardFrame.maxY + walletPeerBalanceButtonGap, width, walletPeerBalanceButtonHeight)
        cardView.frame = NSRect(origin: .zero, size: cardFrame.size)
        cardView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        cardView.layer?.position = CGPoint(x: width / 2, y: height / 2)
        sendButton.layer?.cornerRadius = walletPeerBalanceButtonHeight / 2
        applyProgress()
    }

    override func mouseDown(with event: NSEvent) {
        dismiss?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelTransition() }
    }

    deinit {
        animator?.invalidate()
        transitionSource?.restore()
    }

    private func prepareSource(initial: Bool) -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let source = transitionSource, let sourceView = source.view,
              sourceView.window === window, window != nil else { return false }
        sourceFrame = initial ? convert(source.frame, from: nil) : convert(sourceView.bounds, from: sourceView)
        guard !sourceFrame.isEmpty, bounds.intersects(sourceFrame) else { return false }
        source.hold()
        return true
    }

    func animateIn() {
        layoutSubtreeIfNeeded()
        usesFlight = prepareSource(initial: true)
        isDismissing = false
        applyProgress()
        animate(to: 1, duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.25 : (usesFlight ? 0.79 : 0.65)) { [weak self] in
            self?.setNoticeVisible(true, animated: true)
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        sendButton.userInteractionEnabled = false
        cardView.userInteractionEnabled = false
        setNoticeVisible(false, animated: true)
        let canReturn = prepareSource(initial: false)
        isDismissing = progress >= 1
        if canReturn {
            usesFlight = true
            animate(to: 0, duration: max(0.06, 0.3 * Double(progress)), completion: completion)
        } else {
            animator?.invalidate()
            animator = nil
            transitionSource?.restore()
            backgroundProgress?(0)
            self.layer?.animateAlpha(from: 1, to: 0, duration: 0.15, removeOnCompletion: false, completion: { _ in completion() })
        }
    }

    func cancelTransition() {
        animator?.invalidate()
        animator = nil
        transitionSource?.restore()
        let completion = transitionCompletion
        transitionCompletion = nil
        completion?()
    }

    private func animate(to target: CGFloat, duration: Double, completion: @escaping () -> Void) {
        animator?.invalidate()
        transitionCompletion = completion
        let from = progress
        let initialBackground = backdropProgress
        let start = CACurrentMediaTime()
        let animator = ConstantDisplayLinkAnimator(update: { [weak self] in
            guard let self else { return }
            let elapsed = CACurrentMediaTime() - start
            let fraction = min(1, elapsed / duration)
            self.progress = from + (target - from) * CGFloat(fraction)
            self.applyProgress()
            let backgroundFraction = CGFloat(min(1, elapsed / (target == 0 ? min(0.32, duration) : 0.25)))
            self.backdropProgress = initialBackground + (target - initialBackground) * backgroundFraction
            self.backgroundProgress?(self.backdropProgress)
            if target == 1, elapsed >= 0.3 { self.setNoticeVisible(true, animated: true) }
            if fraction >= 1 {
                self.animator?.invalidate()
                self.animator = nil
                if target == 0 { self.transitionSource?.restore() }
                let completion = self.transitionCompletion
                self.transitionCompletion = nil
                completion?()
            }
        }, fps: 120)
        self.animator = animator
        animator.isPaused = false
    }

    private func applyProgress() {
        guard !cardFrame.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let motion = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var buttonProgress = 1 - pow(1 - min(1, progress / 0.77), 3)
        if usesFlight {
            let flight = WalletPeerCardFlight.frame(progress: progress, dismissing: isDismissing, source: sourceFrame, card: cardFrame)
            cardContainer.frame = CGRect(x: flight.center.x - cardFrame.width / 2, y: flight.center.y - cardFrame.height / 2, width: cardFrame.width, height: cardFrame.height)
            cardView.layer?.transform = flight.transform
            cardContainer.alphaValue = flight.alpha
            if let edge = flight.maskEdge {
                let span = max(bounds.width, bounds.height) * 3
                cardMask.path = CGPath(rect: CGRect(x: -span, y: edge, width: span * 2, height: span), transform: nil)
                cardContainer.layer?.mask = cardMask
            } else {
                cardContainer.layer?.mask = nil
            }
            transitionSource?.update(progress: progress, dismissing: isDismissing)
            buttonProgress = flight.buttonProgress
        } else {
            cardContainer.frame = cardFrame
            cardContainer.layer?.mask = nil
            cardView.layer?.transform = CATransform3DIdentity
            cardContainer.alphaValue = progress
        }
        sendButton.frame = buttonFrame.offsetBy(dx: 0, dy: motion ? walletPeerBalanceButtonGap * (1 - buttonProgress) : 0)
        sendButton.alphaValue = motion ? min(1, max(0, buttonProgress)) : progress
        cardView.userInteractionEnabled = !isDismissing && progress >= (usesFlight ? 0.6 : 1)
    }

}

@available(macOS 10.15, *)
private final class WalletPeerBalanceController: ModalViewController {
    private let context: any AccountContextProtocol
    private let environment: WalletUIEnvironment
    private let walletContext: WalletContext
    private let peerId: PeerId
    private let name: String
    private let sendMoney: () -> Void
    private let transitionSource: WalletPeerBalanceSource?
    private var closing = false
    private var card: WalletCard?
    private var stickers: [WalletContext.CardSticker] = []
    private var artworkDisposables: [String: Disposable] = [:]
    private var walletState: WalletContext.State
    private var backdropView: WalletPeerBalanceBackdropView?
    private var isDisappearing = false
    private let disposables = DisposableSet()

    private var address: String {
        return card?.address ?? ""
    }

    init(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, peer: Peer, source: NSView?) {
        self.context = context
        self.environment = environment
        self.walletContext = walletContext
        self.transitionSource = WalletPeerBalanceSource(view: source)
        self.peerId = peer.id
        self.name = environment.peerTitle(peer, compact: false)
        self.walletState = walletContext.stateValue
        self.sendMoney = {
            showWalletSendMoney(context: context, environment: environment, walletContext: walletContext, peer: peer)
        }
        super.init(frame: NSMakeRect(0, 0, walletPeerBalanceCardWidth + walletPeerBalanceInset * 2, walletPeerBalanceInset + walletPeerBalanceCardHeight + walletPeerBalanceButtonGap + walletPeerBalanceButtonHeight + walletPeerBalanceInset))
        self.bar = .init(height: 0)
    }

    deinit {
        backdropView?.removeFromSuperview()
        disposables.dispose()
        for disposable in artworkDisposables.values {
            disposable.dispose()
        }
    }

    private var genericView: WalletPeerBalanceView {
        return self.view as! WalletPeerBalanceView
    }

    override func viewClass() -> AnyClass {
        return WalletPeerBalanceView.self
    }

    override var background: NSColor {
        return .clear
    }

    override var containerBackground: NSColor {
        return .clear
    }

    override var isFullScreen: Bool { true }

    override var hasBorder: Bool {
        return false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isDisappearing = false
        modal?.containerView.shadow = nil
        modal?.containerView.layer?.shouldRasterize = false
        view.superview?.layer?.isOpaque = false
        guard backdropView == nil, let host = context.window.contentView else {
            return
        }
        let backdrop = WalletPeerBalanceBackdropView(frame: host.bounds)
        backdrop.updateTheme()
        backdrop.layer?.opacity = 0
        host.addSubview(backdrop)
        backdropView = backdrop
        genericView.backgroundProgress = { [weak backdrop] progress in
            backdrop?.alphaValue = progress
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        genericView.animateIn()
    }

    override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        guard !closing else { return }
        closing = true
        genericView.animateOut { [weak self] in
            self?.modal?.close(animationType: .noneDelayed(duration: 0))
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isDisappearing = true
        genericView.setNoticeVisible(false, animated: animated)
        guard let backdrop = backdropView else {
            return
        }
        let opacity = backdrop.layer?.presentation()?.opacity ?? backdrop.layer?.opacity ?? 1
        backdrop.layer?.opacity = 0
        if animated {
            backdrop.layer?.animateAlpha(from: CGFloat(opacity), to: 0, duration: 0.25)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        genericView.cancelTransition()
        backdropView?.removeFromSuperview()
        backdropView = nil
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backdropView?.updateTheme()
    }

    override func returnKeyAction() -> KeyHandlerResult {
        performAction()
        return .invoked
    }

    private var isOwnWallet: Bool {
        return peerId == context.peerId
    }

    private var showsWalletInfo: Bool {
        return !isOwnWallet && walletState.walletAddress == nil
    }

    private var actionTitle: String {
        if isOwnWallet {
            return strings().walletTransactionControllerOpenMyMoney
        } else if showsWalletInfo {
            return strings().walletPeerBalanceControllerHowDoesItWork
        } else {
            return strings().peerInfoHeadItemSendMoney
        }
    }

    private func performAction() {
        if isOwnWallet {
            showWallet(context: context, environment: environment, walletContext: walletContext, for: context.window)
        } else if showsWalletInfo {
            showModal(with: WalletInfoController(context: context, environment: environment, walletContext: walletContext, mode: .wallet), for: context.window)
        } else {
            sendMoney()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        genericView.transitionSource = transitionSource
        genericView.dismiss = { [weak self] in self?.close() }
        genericView.sendButton.set(handler: { [weak self] _ in
            self?.performAction()
        }, for: .Click)
        genericView.cardView.receiveAction = { [weak self] in
            self?.openReceive()
        }
        let account = context.account
        genericView.cardView.stickerDragAllowed = {
            return false
        }
        genericView.cardView.stickerTracking = { [weak cardView = genericView.cardView] id, _ in
            cardView?.playSticker(id, account: account, grow: 1.22)
            return true
        }

        disposables.add(appearanceSignal.start(next: { [weak self] appearance in
            self?.updateLocalizationAndTheme(theme: appearance.presentation)
        }))

        let peerId = self.peerId
        disposables.add((context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.CachedData(id: peerId))
        |> map { cachedData -> WalletCard? in
            return (cachedData as? CachedUserData)?.walletCard
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] card in
            self?.updateWalletCard(card)
        }))

        disposables.add((walletContext.state
        |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.walletState = state
            self?.updateCard()
        }))

        updateCard()
        readyOnce()
    }

    private func openReceive() {
        guard !address.isEmpty else {
            return
        }
        showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: address, isOwnWallet: false), for: context.window)
    }

    private func updateWalletCard(_ card: WalletCard?) {
        self.card = card
        stickers = (card?.stickers ?? []).compactMap { WalletContext.CardSticker(serverSticker: $0, backgroundNftAddress: card?.backgroundNft?.address) }
        let ids = Set(stickers.map(\.gift.address))
        for (id, disposable) in artworkDisposables where !ids.contains(id) {
            disposable.dispose()
            artworkDisposables[id] = nil
        }
        for sticker in stickers where artworkDisposables[sticker.gift.address] == nil {
            artworkDisposables[sticker.gift.address] = WalletCollectibleArtworks.shared.artwork(sticker.gift, context: context, modelFile: sticker.modelFile).start(next: { [weak self] _ in
                self?.updateStickers()
            })
        }
        updateCard()
    }

    private func updateStickers() {
        guard isLoaded() else {
            return
        }
        genericView.cardView.updateStickers(stickers, hidden: [])
        let source = stickers.last(where: { $0.style != nil })
        let pattern = source.flatMap { WalletCollectibleArtworks.shared.current($0.gift.address).pattern }
        genericView.cardView.setGiftStyle(from: source?.style, to: source?.style, origin: .zero, progress: 1, pattern: pattern)
    }

    private func updateCard() {
        guard isLoaded() else {
            return
        }
        let balance = card?.balance ?? 0
        genericView.isOwnBalance = isOwnWallet
        genericView.sendButton.set(text: actionTitle, for: .Normal)
        genericView.updateOwnership(name: name, balance: card?.balance)
        genericView.needsLayout = true
        genericView.cardView.update(balance: balance, fiatText: walletFiatText(walletState, balance: balance), name: name.uppercased(), address: address, animated: false)
        updateStickers()
    }
}

@available(macOS 10.15, *)

@available(macOS 10.15, *)
public func showWalletPeerBalance(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, peer: Peer, morphSource: (() -> NSView?)? = nil) {
    let controller = WalletPeerBalanceController(context: context, environment: environment, walletContext: walletContext, peer: peer, source: morphSource?())
    let onDeinit = controller.onDeinit
    controller.onDeinit = {
        onDeinit?()
    }
    showModal(with: controller, for: context.window, animated: false, animationType: .none, morphSource: { nil })
}

@available(macOS 10.15, *)
public func preloadWalletPeerCard(context: any AccountContextProtocol, card: WalletCard) {
    var addresses = Set<String>()
    for serverSticker in card.stickers.prefix(10) {
        guard let sticker = WalletContext.CardSticker(serverSticker: serverSticker, backgroundNftAddress: card.backgroundNft?.address), addresses.insert(sticker.gift.address).inserted else {
            continue
        }
        WalletCollectibleArtworks.shared.preload(sticker.gift, context: context, modelFile: sticker.modelFile)
    }
}
