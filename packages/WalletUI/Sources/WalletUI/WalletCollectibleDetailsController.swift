import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import CurrencyFormat
import WalletContext
import UniqueGiftRenderer
import InlineStickerLayer

private let _id_collectible_header = InputDataIdentifier("_id_collectible_header")
private let _id_collectible_details = InputDataIdentifier("_id_collectible_details")
private let _id_collectible_actions = InputDataIdentifier("_id_collectible_actions")

private let walletCollectibleGiftTraitKeys = ["model", "backdrop", "symbol"]

private struct WalletCollectibleGiftTrait: Equatable {
    let name: String
    let rarity: StarGift.UniqueGift.Attribute.Rarity?
}

enum WalletCollectibleTransferRoute: Equatable {
    case transfer
    case restoreSigningAccess
    case enterRecoveryPhrase
    case unavailable
}

@available(macOS 10.15, *)
func walletCollectibleTransferRoute(_ phase: WalletContext.Phase) -> WalletCollectibleTransferRoute {
    guard case let .wallet(info) = phase else {
        return .unavailable
    }
    if info.canSign {
        return .transfer
    } else if info.canExportPhrase {
        return .restoreSigningAccess
    } else {
        return .enterRecoveryPhrase
    }
}

@available(macOS 10.15, *)
private func walletCollectibleKindText(_ kind: WalletContext.Collectible.Kind) -> String {
    switch kind {
    case .gift:
        return strings().walletCollectibleDetailsControllerCollectibleGift
    case .username:
        return strings().walletCollectibleDetailsControllerUsername
    case .anonymousNumber:
        return strings().walletCollectibleDetailsControllerAnonymousNumber
    case .other:
        return strings().walletCollectibleDetailsControllerCollectible
    }
}

@available(macOS 10.15, *)
private struct WalletCollectibleDetailsState: Equatable {
    var collectibles: [WalletContext.Collectible]
    var currentAddress: String
    var collectiblesState: WalletContext.CollectiblesState
    var requestedPage: WalletContext.CollectiblesState.PageId? = nil
    var failedPage: WalletContext.CollectiblesState.PageId? = nil
    var giftTraits: [String: WalletCollectibleGiftTrait] = [:]
    var giftValue: String? = nil
    var uniqueGift: StarGift.UniqueGift? = nil
    var ownerAddress: String? = nil
    var ownerAvatar: CGImage? = nil
    var cardActions: [WalletCollectibleActionRowItem.Action] = []
    var profileVisibility = WalletGiftProfileVisibility()

    var displayedOnProfile: Bool? {
        return collectible?.giftSlug.flatMap { profileVisibility.displayed($0) }
    }

    var currentIndex: Int {
        collectibles.firstIndex(where: { $0.address == currentAddress }) ?? 0
    }

    var collectible: WalletContext.Collectible? {
        collectibles.indices.contains(currentIndex) ? collectibles[currentIndex] : nil
    }

    mutating func updateCollectiblesState(_ state: WalletContext.CollectiblesState) {
        if let requestedPage = self.requestedPage, state.nextPage != requestedPage || !state.canLoadMore {
            self.requestedPage = nil
            self.failedPage = nil
        }
        self.collectiblesState = state
    }

    mutating func resetFailedPageIfNeeded() {
        if self.failedPage == self.collectiblesState.nextPage {
            self.requestedPage = nil
            self.failedPage = nil
        }
    }
}

@available(macOS 10.15, *)
func walletCollectiblesPageToRequest(index: Int, count: Int, state: WalletContext.CollectiblesState, requestedPage: WalletContext.CollectiblesState.PageId?, failedPage: WalletContext.CollectiblesState.PageId?, hasActiveOperation: Bool) -> WalletContext.CollectiblesState.PageId? {
    guard count > 0,
          index >= max(0, count - 2),
          let page = state.nextPage,
          !state.isRefreshing,
          !state.isLoadingMore,
          state.error == nil || failedPage == nil,
          !hasActiveOperation else {
        return nil
    }
    guard requestedPage != page else {
        return nil
    }
    return page
}

@available(macOS 10.15, *)
private struct WalletCollectibleHeroData: Equatable {
    let collectible: WalletContext.Collectible
    let subtitle: String?
    let cardActions: [WalletCollectibleActionRowItem.Action]
}

private final class WalletCollectibleDetailsArguments {
    var updateHeader: (Bool, NSColor?) -> Void = { _, _ in }
    let transfer: () -> Void
    let wear: () -> Void
    let sell: () -> Void
    var toggleColor: () -> Void = {}
    var toggleCard: () -> Void = {}
    var toggleProfile: () -> Void = {}
    var openValue: () -> Void = {}
    var openTrait: (String) -> Void = { _ in }
    var restrictColor: (NSView) -> Void = { _ in }
    var modelSource: (NSView) -> Void = { _ in }
    var close: () -> Void = {}
    var menu: () -> [ContextMenuItem] = { [] }

    init(transfer: @escaping () -> Void, wear: @escaping () -> Void, sell: @escaping () -> Void) {
        self.transfer = transfer
        self.wear = wear
        self.sell = sell
    }
}

@available(macOS 10.15, *)
final class WalletCollectibleHeroRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let modelSource: (NSView) -> Void
    let environment: WalletUIEnvironment
    fileprivate let collectible: WalletContext.Collectible
    fileprivate let displaysGift: Bool
    fileprivate let collectionAction: (() -> Void)?
    fileprivate let titleLayout: TextViewLayout
    fileprivate let collectionLayout: TextViewLayout?
    fileprivate let descriptionLayout: TextViewLayout?
    fileprivate let image: TelegramMediaWebFile?
    fileprivate let lottie: TelegramMediaWebFile?
    fileprivate private(set) var mediaSide: CGFloat = 0
    private var contentHeight: CGFloat = 0
    fileprivate var detailsActions: WalletCollectibleActionRowItem?
    fileprivate private(set) var actionHeight: CGFloat = 58
    var close: (() -> Void)?
    fileprivate var menu: (() -> [ContextMenuItem])?
    var updateHeader: ((Bool, NSColor?) -> Void)?

    @available(macOS 10.15, *)
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, environment: WalletUIEnvironment, collectible: WalletContext.Collectible, displaysGift: Bool, subtitle: String?, image: WalletNftFile?, lottie: WalletNftFile?, collectionAction: (() -> Void)?, modelSource: @escaping (NSView) -> Void = { _ in }) {
        self.context = context
        self.modelSource = modelSource
        self.environment = environment
        self.collectible = collectible
        self.displaysGift = displaysGift
        self.collectionAction = collectionAction
        let title = NSMutableAttributedString(attributedString: walletCollectibleNameAttributedString(collectible.name, font: .medium(20)))
        if displaysGift {
            title.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: title.length))
            if let range = collectible.name.range(of: "#[0-9]+$", options: .regularExpression) {
                let nsRange = NSRange(range, in: collectible.name)
                title.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.6), range: nsRange)
                if Int(collectible.name[range].dropFirst()) ?? 0 >= 1000 {
                    title.addAttribute(.font, value: NSFont.medium(15), range: nsRange)
                }
            }
        }
        self.titleLayout = TextViewLayout(title, maximumNumberOfLines: 2, alignment: .center)
        if let subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
            self.collectionLayout = TextViewLayout(.initialize(string: subtitle, color: displaysGift ? NSColor.white.withAlphaComponent(0.6) : theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1, alignment: .center)
        } else {
            self.collectionLayout = nil
        }
        if !displaysGift, let description = collectible.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            self.descriptionLayout = TextViewLayout(.initialize(string: description, color: theme.colors.grayText, font: .normal(.text)), alignment: .center)
        } else {
            self.descriptionLayout = nil
        }
        self.image = walletCollectibleWebFile(image)
        self.lottie = walletCollectibleWebFile(lottie)
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    override var height: CGFloat {
        return contentHeight
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        mediaSide = min(displaysGift ? 136 : 164, max(0, blockWidth - 64))
        let textWidth = max(0, blockWidth - 48)
        titleLayout.measure(width: textWidth)
        collectionLayout?.measure(width: textWidth)
        descriptionLayout?.measure(width: textWidth)
        contentHeight = mediaSide + 18 + titleLayout.layoutSize.height
        if let collectionLayout {
            contentHeight += 6 + collectionLayout.layoutSize.height
        }
        if let descriptionLayout {
            contentHeight += 12 + descriptionLayout.layoutSize.height
        }
        if displaysGift {
            contentHeight = collectionLayout == nil ? 220 : 248
            actionHeight = 58
            if let detailsActions {
                let count = detailsActions.actions.count
                let buttonWidth = floor((width - 32 - CGFloat(count - 1) * 10) / CGFloat(max(1, count)))
                for action in detailsActions.actions {
                    let label = TextViewLayout(.initialize(string: action.title, color: .white, font: .normal(.text)), maximumNumberOfLines: 0, alignment: .center)
                    label.measure(width: max(1, buttonWidth - 16))
                    actionHeight = max(actionHeight, 36 + label.layoutSize.height + 8)
                }
                contentHeight += actionHeight + 16
            }
        } else if close != nil {
            contentHeight += 56
        }
        return true
    }

    override func viewClass() -> AnyClass {
        return WalletCollectibleHeroRowView.self
    }

    override var accessibilityLabel: String? {
        let title = titleLayout.attributedString.string
        return title.isEmpty ? nil : title
    }
}

@available(macOS 10.15, *)
private final class WalletCollectibleHeroRowView: TableRowView {
    private let compositionView = ImageView()
    private var actionViews: [WalletCollectibleActionControl] = []
    private let giftView = ImageView()
    private let giftControl = Control()
    private var giftPlayer: InlineStickerItemLayer?
    private var giftModelId: MediaId?
    private let artworkDisposable = MetaDisposable()
    private var artwork = WalletCollectibleArtwork()
    private let placeholderView = View(frame: .zero)
    private let imageView = TransformImageView(frame: .zero)
    private let lottieView = Control(frame: .zero)
    private let titleView = TextView()
    private let collectionButton = Control()
    private let collectionView = TextView()
    private let collectionNextView = ImageView()
    private let descriptionView = TextView()
    private let imageFetchDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private let lottieDisposable = MetaDisposable()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        compositionView.isEventLess = true
        giftView.isEventLess = true
        addSubview(compositionView)
        placeholderView.layer?.cornerRadius = 16
        lottieView.layer?.cornerRadius = 16
        lottieView.layer?.masksToBounds = true
        for textView in [titleView, collectionView, descriptionView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        collectionNextView.isEventLess = true
        collectionNextView.isAccessibilityDecorative = true
        collectionView.isAccessibilityDecorative = true
        titleView.isAccessibilityDecorative = true
        lottieView.isAccessibilityDecorative = true
        collectionButton.addSubview(collectionView)
        collectionButton.addSubview(collectionNextView)
        addSubview(placeholderView)
        addSubview(imageView)
        addSubview(lottieView)
        addSubview(giftView)
        addSubview(giftControl)
        giftControl.set(handler: { [weak self] _ in
            self?.giftPlayer?.playAgain()
        }, for: .Click)
        addSubview(titleView)
        addSubview(collectionButton)
        addSubview(descriptionView)

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        artworkDisposable.dispose()
        imageFetchDisposable.dispose()
        fetchDisposable.dispose()
        lottieDisposable.dispose()
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func updateColors() {
        placeholderView.backgroundColor = theme.colors.grayForeground
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        let previousItem = self.item as? WalletCollectibleHeroRowItem
        super.set(item: item, animated: animated)
        guard let item = item as? WalletCollectibleHeroRowItem else {
            return
        }
        titleView.update(item.titleLayout)
        let actions = item.detailsActions?.actions ?? []
        while actionViews.count < actions.count {
            let view = WalletCollectibleActionControl(frame: .zero)
            actionViews.append(view)
            addSubview(view)
        }
        for (index, view) in actionViews.enumerated() {
            view.isHidden = index >= actions.count
            view.reset()
            if index < actions.count, let details = item.detailsActions {
                let action = actions[index]
                view.update(action: action, onGiftBackground: true, callback: { source in
                    if action == .restrictedColor { details.restrictColor(source) }
                    else { details.callbacks[action]?() }
                })
            }
        }

        collectionButton.removeAllHandlers()
        if let collectionLayout = item.collectionLayout {
            collectionView.update(collectionLayout)
            collectionButton.setAccessibilityLabel(collectionLayout.attributedString.string)
            collectionButton.isHidden = false
            if item.collectionAction != nil {
                collectionNextView.isHidden = false
                collectionNextView.image = theme.icons.generalNext
                collectionNextView.sizeToFit()
                collectionButton.userInteractionEnabled = true
                collectionButton.scaleOnClick = true
                collectionButton.set(cursor: .pointingHand, for: .Hover)
                collectionButton.set(handler: { _ in item.collectionAction?() }, for: .Click)
            } else {
                collectionNextView.isHidden = true
                collectionButton.userInteractionEnabled = false
                collectionButton.scaleOnClick = false
                collectionButton.set(cursor: .arrow, for: .Hover)
            }
        } else {
            collectionButton.isHidden = true
        }
        if let descriptionLayout = item.descriptionLayout {
            descriptionView.update(descriptionLayout)
            descriptionView.isHidden = false
        } else {
            descriptionView.isHidden = true
        }

        imageFetchDisposable.set(nil)
        imageView.clear()
        imageView.isHidden = true
        if !item.displaysGift, let image = item.image {
            imageView.isHidden = false
            imageView.set(arguments: TransformImageArguments(corners: ImageCorners(radius: 16), imageSize: NSMakeSize(item.mediaSide, item.mediaSide), boundingSize: NSMakeSize(item.mediaSide, item.mediaSide), intrinsicInsets: NSEdgeInsetsZero))
            imageView.setSignal(item.environment.webFilePhoto( photo: image, scale: backingScaleFactor, useActualDimensions: true))
            imageFetchDisposable.set(fetchedMediaResource(mediaBox: item.context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: image.resource)).start())
        }

        if previousItem?.context.account !== item.context.account || previousItem?.collectible.address != item.collectible.address || previousItem?.lottie?.resource.id != item.lottie?.resource.id || previousItem?.displaysGift != item.displaysGift {
            fetchDisposable.set(nil)
            lottieDisposable.set(nil)
            item.environment.setCollectibleAnimation(in: lottieView, contents: nil, key: "", size: NSMakeSize(item.mediaSide, item.mediaSide))
            lottieView.isHidden = true
            if !item.displaysGift, let lottie = item.lottie {
                fetchDisposable.set(fetchedMediaResource(mediaBox: item.context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: lottie.resource)).start())
                lottieDisposable.set((item.context.account.postbox.mediaBox.resourceData(lottie.resource, attemptSynchronously: true)
                |> filter { $0.complete }
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] data in
                    guard let self, let item = self.item as? WalletCollectibleHeroRowItem,
                          item.lottie?.resource.id == lottie.resource.id,
                          data.size <= Int64(5 * 1024 * 1024),
                          let fileData = try? Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedIfSafe),
                          let contents = walletCollectibleLottieData(fileData) else {
                        return
                    }
                    item.environment.setCollectibleAnimation(in: self.lottieView, contents: contents, key: "wallet_collectible_hero_\(item.collectible.address)_\(contents.hashValue)", size: NSMakeSize(item.mediaSide, item.mediaSide))
                    self.lottieView.isHidden = false
                }))
            }
        }
        if previousItem?.context.account !== item.context.account || previousItem?.collectible.address != item.collectible.address || previousItem?.displaysGift != item.displaysGift {
            giftPlayer?.removeFromSuperlayer()
            giftPlayer = nil
            giftModelId = nil
        }
        giftControl.isHidden = !item.displaysGift
        artworkDisposable.set(nil)
        artwork = WalletCollectibleArtwork()
        compositionView.image = nil
        compositionView.layer?.backgroundColor = walletClassicAccent.cgColor
        compositionView.isHidden = !item.displaysGift
        giftView.isHidden = true
        if item.displaysGift {
            placeholderView.isHidden = true
            artworkDisposable.set((WalletCollectibleArtworks.shared.artwork(item.collectible, context: item.context)
            |> deliverOnMainQueue).start(next: { [weak self] artwork in
                guard let self else { return }
                self.artwork = artwork
                self.giftView.image = artwork.art
                if let data = artwork.modelFile, let file = walletDecodedMediaFile(data), self.giftModelId != file.fileId {
                    self.giftPlayer?.removeFromSuperlayer()
                    self.giftModelId = file.fileId
                    let size = NSMakeSize(item.mediaSide, item.mediaSide)
                    let player = InlineStickerItemLayer(account: item.context.account, file: file, size: size, playPolicy: .onceEnd, ignorePreview: true)
                    player.contentDidUpdate = { [weak self, weak player] _ in
                        guard let self, let player, self.giftPlayer === player else { return }
                        self.giftView.isHidden = true
                    }
                    self.giftPlayer = player
                    player.superview = self.giftControl
                    self.giftControl.layer?.addSublayer(player)
                    player.isPlayable = true
                }
                self.giftView.isHidden = artwork.art == nil || self.giftPlayer?.contents != nil
                self.needsLayout = true
            }))
        } else {
            placeholderView.isHidden = false
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletCollectibleHeroRowItem else {
            return
        }
        compositionView.frame = NSMakeRect(0, 0, frame.width, item.height)
        if item.displaysGift, let source = artwork.styleSource {
            compositionView.image = UniqueGiftBackgroundRenderer.makeImage(geometry: .header(size: compositionView.frame.size, patternCenterY: 88), colors: UniqueGiftColors(center: source.inner, edge: source.outer, pattern: source.pattern), glyph: artwork.pattern.flatMap { UniqueGiftGlyph(image: $0)?.mask }, scale: backingScaleFactor)
        }
        let tint = artwork.styleSource.map { NSColor(rgb: UInt32(bitPattern: $0.outer) & 0xffffff) }
        item.updateHeader?(item.displaysGift, tint)
        let actionCount = item.detailsActions?.actions.count ?? 0
        if actionCount > 0 {
            let width = floor((frame.width - 32 - CGFloat(actionCount - 1) * 10) / CGFloat(actionCount))
            for (index, view) in actionViews.enumerated() where index < actionCount {
                view.frame = NSMakeRect(16 + CGFloat(index) * (width + 10), item.height - item.actionHeight - 16, width, item.actionHeight)
                if let source = artwork.styleSource {
                    let outer = NSColor(rgb: UInt32(bitPattern: source.outer) & 0xffffff)
                    let inner = NSColor(rgb: UInt32(bitPattern: source.inner) & 0xffffff)
                    view.updateGlassTint(over: outer.interpolateTo(inner, fraction: 0.1) ?? outer)
                }
            }
        }
        let mediaY: CGFloat = item.displaysGift ? 88 - item.mediaSide / 2 : item.close == nil ? 0 : 56
        let mediaFrame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.mediaSide) / 2), mediaY, item.mediaSide, item.mediaSide)
        placeholderView.frame = mediaFrame
        imageView.frame = mediaFrame
        lottieView.frame = mediaFrame
        giftView.frame = mediaFrame
        giftControl.frame = mediaFrame
        giftPlayer?.frame = giftControl.bounds
        if item.displaysGift {
            item.modelSource(giftPlayer?.contents != nil ? giftControl : giftView)
        } else {
            item.modelSource(lottieView.isHidden ? imageView : lottieView)
        }
        giftView.isHidden = !item.displaysGift || artwork.art == nil || giftPlayer?.contents != nil
        titleView.centerX(y: item.displaysGift ? floorToScreenPixels(backingScaleFactor, 190 - titleView.frame.height / 2) : mediaFrame.maxY + 18)
        var textY = titleView.frame.maxY
        if item.collectionLayout != nil {
            let chevronWidth = collectionNextView.isHidden ? 0 : collectionNextView.frame.width + 2
            collectionButton.setFrameSize(NSMakeSize(collectionView.frame.width + chevronWidth, collectionView.frame.height))
            collectionButton.centerX(y: textY + 6)
            collectionView.setFrameOrigin(.zero)
            collectionNextView.centerY(x: collectionView.frame.maxX + 2)
            textY = collectionButton.frame.maxY
        }
        if item.descriptionLayout != nil {
            descriptionView.centerX(y: textY + 12)
        }
    }
}

func walletCollectibleModalHeader(controller: InputDataController, close: @escaping () -> Void, menu: @escaping () -> [ContextMenuItem]) -> (Bool, NSColor?) -> Void {
    let closeButton = ImageButton(frame: NSMakeRect(16, 16, 36, 36))
    let menuButton = ImageButton(frame: NSMakeRect(348, 16, 36, 36))
    closeButton.setAccessibilityLabel(strings().voiceOverCommonClose)
    menuButton.setAccessibilityLabel(strings().voiceOverCommonMore)
    closeButton.set(handler: { _ in close() }, for: .Click)
    menuButton.contextMenu = {
        let result = ContextMenu()
        menu().forEach { result.addItem($0) }
        return result
    }
    controller.didLoad = { controller, _ in
        controller.tableView.verticalScrollElasticity = .none
        menuButton.frame.origin.x = controller.view.frame.width - 52
        menuButton.autoresizingMask = [.minXMargin]
        controller.view.addSubview(closeButton)
        controller.view.addSubview(menuButton)
    }
    return { [weak closeButton, weak menuButton] gift, tint in
        closeButton?.set(image: gift ? TelegramThemeHooks.shared.image(.iconPipClose).precomposed(.white) : theme.icons.modalClose, for: .Normal)
        menuButton?.set(image: gift ? TelegramThemeHooks.shared.image(.iconChatActions).precomposed(.white) : theme.icons.chatActionsActive, for: .Normal)
        for button in [closeButton, menuButton].compactMap({ $0 }) {
            button.setGlassEffect(size: NSMakeSize(36, 36), tintColor: tint, forceAppearance: gift ? .forceLight : nil)
            button.glassTintColor = tint
        }
    }
}

private final class WalletCollectibleActionRowItem: GeneralRowItem {
    fileprivate enum Action: CaseIterable {
        case transfer
        case wear
        case sell
        case applyColor
        case restrictedColor
        case removeColor
        case addToCard
        case removeFromCard

        var title: String {
            switch self {
            case .transfer: return strings().walletCollectibleDetailsControllerActionTransfer
            case .wear: return strings().walletCollectibleDetailsControllerActionWear
            case .sell: return strings().walletCollectibleDetailsControllerActionSell
            case .applyColor, .restrictedColor: return strings().walletCollectibleHeaderApplyColor
            case .removeColor: return strings().walletCollectibleHeaderRemoveColor
            case .addToCard: return strings().walletCollectibleHeaderAddToCard
            case .removeFromCard: return strings().walletCollectibleHeaderRemoveFromCard
            }
        }

        var image: NSImage? {
            switch self {
            case .transfer: return NSImage(named: "Icon_NFT_Transfer")
            case .wear: return NSImage(named: "Icon_NFT_Wear")
            case .sell: return NSImage(named: "Icon_Nft_Sell")
            case .applyColor, .restrictedColor: return NSImage(named: "Wallet_Collectible_ApplyColor")
            case .removeColor: return NSImage(named: "Wallet_Collectible_RemoveColor")
            case .addToCard: return NSImage(named: "Wallet_Collectible_AddToCard")
            case .removeFromCard: return NSImage(named: "Wallet_Collectible_RemoveFromCard")
            }
        }
    }

    fileprivate let actions: [Action]
    fileprivate let callbacks: [Action: () -> Void]
    fileprivate let restrictColor: (NSView) -> Void

    @available(macOS 10.15, *)
    init(_ initialSize: NSSize, stableId: AnyHashable, collectible: WalletContext.Collectible, cardActions: [Action], arguments: WalletCollectibleDetailsArguments) {
        self.restrictColor = arguments.restrictColor
        self.actions = cardActions.isEmpty ? [.transfer, .sell] : [.transfer] + cardActions
        self.callbacks = [.transfer: arguments.transfer, .wear: arguments.wear, .sell: arguments.sell, .applyColor: arguments.toggleColor, .removeColor: arguments.toggleColor, .addToCard: arguments.toggleCard, .removeFromCard: arguments.toggleCard]
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    override var height: CGFloat {
        return 104
    }

    override func viewClass() -> AnyClass {
        return WalletCollectibleActionRowView.self
    }

    override var accessibilityLabel: String? {
        return actions.map { $0.title }.joined(separator: ", ")
    }
}

private final class WalletCollectibleActionControl: Control {
    private var onGiftBackground = false
    private var titleLayout: TextViewLayout?
    private var glassView: LiquidGlassView?
    private let imageView = ImageView()
    private let titleView = TextView()
    private var callback: ((NSView) -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 20
        imageView.contentGravity = .center
        imageView.animates = true
        imageView.isEventLess = true
        imageView.isAccessibilityDecorative = true
        titleView.isEventLess = true
        titleView.isAccessibilityDecorative = true
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        controlOpacityEventIgnored = true
        addSubview(imageView)
        addSubview(titleView)

        set(handler: { control in
            control.change(opacity: 0.8, animated: true)
        }, for: .Highlight)
        set(handler: { control in
            control.change(opacity: 1.0, animated: true)
        }, for: .Normal)
        set(handler: { control in
            control.change(opacity: 1.0, animated: true)
        }, for: .Hover)
        set(handler: { [weak self] _ in
            guard let self else { return }
            self.callback?(self)
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(action: WalletCollectibleActionRowItem.Action, onGiftBackground: Bool = false, callback: @escaping (NSView) -> Void) {
        self.callback = callback
        self.onGiftBackground = onGiftBackground
        imageView.alphaValue = action == .restrictedColor ? 0.5 : 1
        titleView.alphaValue = action == .restrictedColor ? 0.5 : 1
        setAccessibilityLabel(action.title)
        if onGiftBackground && System.liquidGlass {
            if glassView == nil {
                let glass = LiquidGlassView(frame: bounds, cornerRadius: 20, hasShadow: true, hasBorder: true, forceAppearance: .forceLight)
                glassView = glass
                addSubview(glass, positioned: .below, relativeTo: imageView)
                stretchReferenceView = glass
            }
            backgroundColor = .clear
            layer?.cornerRadius = 0
            layer?.masksToBounds = false
        } else {
            glassView?.removeFromSuperview()
            glassView = nil
            stretchReferenceView = nil
            backgroundColor = onGiftBackground ? NSColor.white.withAlphaComponent(0.2) : theme.colors.background
            layer?.cornerRadius = 20
        }
        let foreground = onGiftBackground ? NSColor.white : walletClassicAccent
        imageView.image = action.image?.precomposed(foreground)
        imageView.sizeToFit()
        let titleLayout = TextViewLayout(.initialize(string: action.title, color: foreground, font: .normal(.text)), maximumNumberOfLines: onGiftBackground ? 0 : 2, alignment: .center)
        self.titleLayout = titleLayout
        needsLayout = true
    }

    func updateGlassTint(over background: NSColor) {
        let base = background.usingColorSpace(.sRGB) ?? background
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        base.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let blend: CGFloat = theme.colors.isDark ? 0 : 1
        func overlay(_ channel: CGFloat) -> CGFloat {
            let value = channel < 0.5 ? 2 * channel * blend : 1 - 2 * (1 - channel) * (1 - blend)
            return channel + (max(0, min(1, value)) - channel) * 0.25
        }
        glassView?.customTint = NSColor(srgbRed: overlay(red), green: overlay(green), blue: overlay(blue), alpha: 1)
    }

    func reset() {
        callback = nil
    }

    override func layout() {
        super.layout()
        glassView?.frame = bounds
        glassView?.updateLayout(size: bounds.size, transition: .immediate)
        if let titleLayout {
            titleLayout.measure(width: max(0, bounds.width - 16))
            titleView.update(titleLayout)
        }
        if onGiftBackground {
            imageView.centerX(y: floorToScreenPixels(backingScaleFactor, 22 - imageView.frame.height / 2))
            titleView.centerX(y: 36)
        } else {
            let spacing: CGFloat = 4
            let contentHeight = imageView.frame.height + spacing + titleView.frame.height
            let top = floor((bounds.height - contentHeight) / 2)
            imageView.centerX(y: top)
            titleView.centerX(y: top + imageView.frame.height + spacing)
        }
    }
}

private final class WalletCollectibleActionRowView: TableRowView {
    private var actionViews: [WalletCollectibleActionControl] = []

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletCollectibleActionRowItem else {
            return
        }
        while actionViews.count < item.actions.count {
            let view = WalletCollectibleActionControl(frame: .zero)
            actionViews.append(view)
            addSubview(view)
        }
        for (index, view) in actionViews.enumerated() {
            guard index < item.actions.count else {
                view.reset()
                view.isHidden = true
                continue
            }
            let action = item.actions[index]
            view.isHidden = false
            view.update(action: action, callback: { source in
                if action == .restrictedColor {
                    item.restrictColor(source)
                } else {
                    item.callbacks[action]?()
                }
            })
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletCollectibleActionRowItem else {
            return
        }
        let sideInset: CGFloat = 20
        let spacing: CGFloat = 10
        let width = floor((frame.width - sideInset * 2 - spacing * CGFloat(item.actions.count - 1)) / CGFloat(item.actions.count))
        for (index, view) in actionViews.enumerated() where index < item.actions.count {
            view.frame = NSMakeRect(sideInset + CGFloat(index) * (width + spacing), 28, width, 76)
        }
    }
}

func walletCollectibleExplorerUrl(explorerUrl: String, address: String) -> String? {
    guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !encodedAddress.isEmpty else {
        return nil
    }
    let baseUrl = explorerUrl.hasSuffix("/") ? explorerUrl : explorerUrl + "/"
    return baseUrl + encodedAddress
}

@available(macOS 10.15, *)
private func walletCollectibleExplorerUrl(context: any AccountContextProtocol, environment: WalletUIEnvironment, address: String) -> String? {
    return walletCollectibleExplorerUrl(explorerUrl: WalletConfiguration.with(appConfiguration: context.appConfiguration).explorerUrl, address: address)
}

@available(macOS 10.15, *)
private func walletCollectibleFragmentUrl(_ collectible: WalletContext.Collectible) -> String? {
    let path: String
    var value: String
    switch collectible.kind {
    case .username:
        path = "username"
        value = collectible.name.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if value.lowercased().hasSuffix(".t.me") {
            value.removeLast(".t.me".count)
        }
    case .anonymousNumber:
        path = "number"
        value = collectible.name.filter(\.isNumber)
    case .gift:
        path = "gift"
        value = collectible.giftSlug ?? ""
    case .other:
        return nil
    }
    guard !value.isEmpty else {
        return nil
    }
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")
    guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
        return nil
    }
    return "https://fragment.com/\(path)/\(encoded)"
}

@available(macOS 10.15, *)
private func walletCollectibleDetailsEntries(_ state: WalletCollectibleDetailsState, context: any AccountContextProtocol, environment: WalletUIEnvironment, arguments: WalletCollectibleDetailsArguments) -> [InputDataEntry] {
    guard let collectible = state.collectible else {
        return []
    }
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0
    let header = WalletCollectibleHeroData(collectible: collectible, subtitle: collectible.kind == .other ? collectible.collectionName : nil, cardActions: state.cardActions)
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_header, equatable: .init(header), comparable: nil, item: { initialSize, stableId in
        let item = WalletCollectibleHeroRowItem(initialSize, stableId: stableId, context: context, environment: environment, collectible: collectible, displaysGift: collectible.kind == .gift, subtitle: header.subtitle, image: collectible.image, lottie: collectible.lottie, collectionAction: collectible.kind == .gift ? nil : collectible.collectionUrl.map { url in
            { environment.openExternalURL(url) }
        }, modelSource: arguments.modelSource)
        item.updateHeader = { arguments.updateHeader($0, $1) }
        item.close = { arguments.close() }
        item.menu = { arguments.menu() }
        if collectible.kind == .gift {
            item.detailsActions = WalletCollectibleActionRowItem(initialSize, stableId: stableId, collectible: collectible, cardActions: state.cardActions, arguments: arguments)
        }
        return item
    }))
    index += 1

    if collectible.kind != .gift {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_actions, equatable: .init("\(collectible.address)_\(collectible.kind)_\(state.cardActions)"), comparable: nil, item: { initialSize, stableId in
            WalletCollectibleActionRowItem(initialSize, stableId: stableId, collectible: collectible, cardActions: state.cardActions, arguments: arguments)
        }))
        index += 1
    }

    let displayAddress = WalletContext.transferAddress(from: collectible.address) ?? collectible.address
    var rows: [WalletDetailsTableRowItem.Row] = [
        .init(label: strings().walletCollectibleDetailsControllerType, value: walletCollectibleKindText(collectible.kind)),
        .init(label: strings().walletCollectibleDetailsControllerAddress, value: displayAddress, isAddress: true, onClick: { walletCopyAddress(displayAddress, environment: environment, window: context.window) })
    ]
    if let collectionName = collectible.collectionName, !collectionName.isEmpty {
        rows.append(.init(label: strings().walletCollectibleDetailsControllerCollection, value: collectionName, onClick: collectible.collectionUrl.map { url in { environment.openExternalURL(url) } }))
    }
    if collectible.kind == .gift {
        if let ownerAddress = state.ownerAddress {
            let address = WalletContext.transferAddress(from: ownerAddress) ?? ownerAddress
            rows.append(.init(label: strings().walletCollectibleDetailsControllerOwner, value: address, isAddress: true, onClick: { walletCopyAddress(address, environment: environment, window: context.window) }))
        }
    }
    var remainingAttributeKeys = Set(collectible.attributes.keys)
    if collectible.kind == .gift {
        let traitLabels: [String: String] = ["model": strings().walletCollectibleDetailsControllerModel, "symbol": strings().walletCollectibleDetailsControllerSymbol, "backdrop": strings().walletCollectibleDetailsControllerBackdrop]
        for key in walletCollectibleGiftTraitKeys {
            remainingAttributeKeys.remove(key)
            let trait = state.giftTraits[key]
            let value = trait?.name ?? collectible.attributes[key] ?? "—"
            var badge: (text: String, color: NSColor?)? = nil
            if let rarity = trait?.rarity {
                badge = environment.rarityBadge(rarity)
            }
            rows.append(.init(label: traitLabels[key] ?? key.capitalized, value: value, badge: badge, onClick: state.uniqueGift == nil && collectible.nft?.gift == nil ? nil : { arguments.openTrait(key) }))
        }
    }
    for key in remainingAttributeKeys.sorted() {
        rows.append(.init(label: key.capitalized, value: collectible.attributes[key] ?? "—"))
    }
    if collectible.kind == .gift, let gift = state.uniqueGift {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let issued = formatter.string(from: NSNumber(value: gift.availability.issued)) ?? "\(gift.availability.issued)"
        let total = formatter.string(from: NSNumber(value: gift.availability.total)) ?? "\(gift.availability.total)"
        rows.append(.init(label: strings().giftUniqueAvailability, value: strings().giftUniqueIssued("\(issued)/\(total)")))
        if let value = state.giftValue {
            let learnMore = strings().genericErrorMoreInfo
            rows.append(.init(label: strings().starGiftValueRowLabel, value: value, onClick: arguments.openValue, action: (title: learnMore, handler: arguments.openValue)))
        }
    }
    let rowsSignature = rows.map { "\($0.label):\($0.value):\($0.badge?.text ?? "")" }.joined(separator: "|") + "|avatar:\(state.ownerAvatar != nil)"
    entries.append(.sectionId(sectionId, type: .customModern(30)))
    sectionId += 1
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_details, equatable: .init(rowsSignature), comparable: nil, item: { initialSize, stableId in
        WalletDetailsTableRowItem(initialSize, stableId: stableId, rows: rows, viewType: .singleItem)
    }))
    index += 1

    if let displayed = state.displayedOnProfile {
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1
        let profileTitle = strings().walletCollectibleAlsoShowInMyGifts
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier("collectible_profile"), data: .init(name: profileTitle, color: theme.colors.text, type: .switchable(displayed), viewType: .singleItem, action: arguments.toggleProfile)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
public func WalletCollectibleDetailsController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, collectible: WalletContext.Collectible, collectibleSent: ((String) -> Void)? = nil) -> InputDataModalController {
    return WalletCollectibleDetailsController(context: context, environment: environment, walletContext: walletContext, collectible: collectible, cardStage: nil, collectibleSent: collectibleSent)
}

@available(macOS 10.15, *)
func WalletCollectibleDetailsController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, collectible: WalletContext.Collectible, cardStage: WalletCollectablesStage?, collectibleSent: ((String) -> Void)? = nil) -> InputDataModalController {
    let initialCollectibles = walletContext.stateValue.collectibles.items.contains(where: { $0.address == collectible.address }) ? walletContext.stateValue.collectibles.items : [collectible] + walletContext.stateValue.collectibles.items
    let initialState = WalletCollectibleDetailsState(
        collectibles: initialCollectibles,
        currentAddress: collectible.address,
        collectiblesState: walletContext.stateValue.collectibles,
        ownerAddress: walletContext.stateValue.walletAddress
    )
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletCollectibleDetailsState) -> WalletCollectibleDetailsState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    let disposables = DisposableSet()
    let loadMoreDisposable = MetaDisposable()
    let giftDisposable = MetaDisposable()
    let artworkDisposable = MetaDisposable()
    disposables.add(artworkDisposable)
    disposables.add(loadMoreDisposable)
    disposables.add(giftDisposable)

    var isActive = true
    weak var giftSource: NSView?
    var close: (() -> Void)?
    let loadMoreIfNeeded: () -> Void = {
        let state = stateValue.with { $0 }
        guard let page = walletCollectiblesPageToRequest(index: state.currentIndex, count: state.collectibles.count, state: state.collectiblesState, requestedPage: state.requestedPage, failedPage: state.failedPage, hasActiveOperation: walletContext.stateValue.activeOperation != nil) else {
            return
        }
        updateState { current in
            var current = current
            current.requestedPage = page
            return current
        }
        loadMoreDisposable.set((walletContext.loadMoreCollectibles()
        |> deliverOnMainQueue).start(error: { _ in
            updateState { current in
                var current = current
                if current.requestedPage == page {
                    current.failedPage = page
                }
                return current
            }
        }))
    }
    let refreshCardActions: () -> Void = {
        updateState { current in
            var current = current
            current.cardActions = []
            if let gift = current.collectible, let cardStage, cardStage.canCustomizeCard(for: gift.address) {
                let sticker = cardStage.cardSticker(for: gift.address)
                if sticker?.style != nil {
                    current.cardActions.append(.removeColor)
                } else if cardStage.isColorRestricted(for: gift.address) {
                    current.cardActions.append(.restrictedColor)
                } else if cardStage.canApplyColor(for: gift.address) {
                    current.cardActions.append(.applyColor)
                }
                current.cardActions.append(sticker == nil ? .addToCard : .removeFromCard)
            }
            return current
        }
    }
    disposables.add((context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.App())
    |> deliverOnMainQueue).start(next: { configuration in
        cardStage?.updateConfiguration(WalletConfiguration.with(appConfiguration: configuration))
        refreshCardActions()
    }))
    var fetchGiftTraits: (() -> Void)?
    let previous = {
        updateState { current in
            var current = current
            current.resetFailedPageIfNeeded()
            guard current.currentIndex > 0 else { return current }
            current.currentAddress = current.collectibles[current.currentIndex - 1].address
            return current
        }
        fetchGiftTraits?()
    }
    let next = {
        updateState { current in
            var current = current
            current.resetFailedPageIfNeeded()
            guard current.currentIndex + 1 < current.collectibles.count else { return current }
            current.currentAddress = current.collectibles[current.currentIndex + 1].address
            return current
        }
        fetchGiftTraits?()
        loadMoreIfNeeded()
    }
    let presentTransfer: (WalletContext.Collectible) -> Void = { current in
        showModal(with: makeWalletRecipientController(context: context, environment: environment, walletContext: walletContext, initialQuery: nil, initialAmount: nil, mode: .collectible(current), onSuccess: {
            collectibleSent?(current.address)
            close?()
        }), for: context.window)
    }
    let restoreAuthorization = WalletFlowAuthorization(walletContext: walletContext, reason: walletRestoreFlowReason)
    let restoreDisposable = MetaDisposable()
    disposables.add(restoreDisposable)
    var transfer: (() -> Void)?
    transfer = {
        guard isActive, let current = stateValue.with({ $0.collectible }) else { return }
        if case let .wallet(info) = walletContext.stateValue.phase,
           let balance = walletContext.stateValue.balance.currentValue, balance < 100_000_000 {
            environment.verifyAlert(for: context.window, header: strings().walletTransactionControllerNotEnoughGramsTitle, information: strings().walletTransactionControllerCollectibleTopUpInfo, ok: strings().walletSettingsControllerTopUp, cancel: strings().walletSettingsControllerCancel, successHandler: { _ in
                guard isActive, walletContext.stateValue.walletAddress == info.address else { return }
                showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: info.address), for: context.window)
            })
            return
        }
        switch walletCollectibleTransferRoute(walletContext.stateValue.phase) {
        case .transfer:
            restoreAuthorization.end()
            presentTransfer(current)
        case .restoreSigningAccess:
            restoreDisposable.set(walletRestoreSigningAccess(context: context, environment: environment, window: context.window, walletContext: walletContext, authorization: restoreAuthorization, retry: {
                transfer?()
            }, next: {
                guard isActive, stateValue.with({ $0.collectible?.address }) == current.address else { return }
                presentTransfer(current)
            }, failed: {}))
        case .enterRecoveryPhrase:
            showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enterRecoveryPhrase, onImported: {}), for: context.window)
        case .unavailable:
            environment.showModalText(for: context.window, text: strings().walletCollectibleDetailsControllerStillSyncing)
        }
    }
    let wear = {
        guard let current = stateValue.with({ $0.collectible }), current.kind == .gift, let slug = current.giftSlug else { return }
        _ = showModalProgress(signal: context.engine.payments.getUniqueStarGift(slug: slug), for: context.window).start(next: { gift in
            environment.openGift(gift)
        })
    }
    let sell = {
        guard let current = stateValue.with({ $0.collectible }), let url = walletCollectibleFragmentUrl(current) else { return }
        environment.openExternalURL(url)
    }
    let arguments = WalletCollectibleDetailsArguments(transfer: { transfer?() }, wear: wear, sell: sell)
    arguments.modelSource = { source in giftSource = source }
    arguments.openTrait = { key in
        guard isActive, let gift = stateValue.with({ $0.uniqueGift ?? $0.collectible?.nft?.gift }) else { return }
        WalletUIHooks.shared.openGiftVariants(context, gift, key)
    }
    let performCardAction: (Bool) -> Void = { color in
        guard let gift = stateValue.with({ $0.collectible }) else { return }
        if let source = giftSource, cardStage?.placeFromDetails(gift.address, color: color, source: source) == true {
            source.isHidden = true
            close?()
        } else {
            close?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                cardStage?.menuAction(gift.address, color: color)
            }
        }
    }
    arguments.toggleColor = { performCardAction(true) }
    arguments.toggleCard = { performCardAction(false) }
    arguments.restrictColor = { [weak source = context.window.contentView] button in
        let collections = WalletConfiguration.with(appConfiguration: context.appConfiguration).cardBackgroundGiftCollections ?? []
        disposables.add((context.engine.payments.cachedStarGifts()
        |> take(1)
        |> deliverOnMainQueue).start(next: { gifts in
            guard isActive else { return }
            var available: [String: StarGift.Gift] = [:]
            let found = collections.compactMap { collection -> (String, StarGift.Gift)? in
                guard let gift = gifts?.compactMap({ $0.generic }).first(where: { ($0.title ?? "").filter { $0.isLetter || $0.isNumber } == collection }) else { return nil }
                return (collection, gift)
            }
            guard !found.isEmpty else { return }
            let names = NSMutableAttributedString()
            for (index, item) in found.enumerated() {
                let (collection, gift) = item
                if index > 0 {
                    names.append(NSAttributedString(string: index == found.count - 1 ? strings().autoDownloadSettingsLastDelimeter : strings().autoDownloadSettingsDelimeter, font: .normal(.text), textColor: .white))
                }
                available[collection] = gift
                names.append(NSAttributedString(string: strings().walletStickerColorRestrictedCollection(gift.title ?? collection), attributes: [.font: NSFont.medium(.text), .foregroundColor: NSColor(0x64d2ff), .link: collection]))
            }
            let placeholder = "\u{FFFC}"
            let text = NSMutableAttributedString(string: strings().walletStickerColorRestricted(placeholder), font: .normal(.text), textColor: .white)
            let placeholderRange = text.mutableString.range(of: placeholder)
            if placeholderRange.location != NSNotFound {
                text.replaceCharacters(in: placeholderRange, with: names)
            } else {
                text.append(names)
            }
            let interactions = TextViewInteractions(processURL: { value in
                guard let key = value as? String, let gift = available[key] else { return }
                close?()
                environment.openGiftStore(gift)
            })
            if let anchor = button.window != nil ? button : source {
                tooltip(for: anchor, text: text.string, attributedText: text, interactions: interactions, maxWidth: 320, timeout: 8)
            }
        }))
    }
    arguments.openValue = {
        guard let gift = stateValue.with({ $0.uniqueGift }) else { return }
        environment.openGiftValue(gift)
    }
    arguments.toggleProfile = {
        guard let slug = stateValue.with({ $0.collectible?.giftSlug }) else { return }
        var change: WalletGiftProfileVisibility.Update?
        updateState { current in
            var current = current
            change = current.profileVisibility.begin(slug: slug)
            return current
        }
        guard let change else { return }
        disposables.add((context.engine.payments.displayStarGift(peerId: change.displayed ? context.peerId : nil, slug: slug)
        |> deliverOnMainQueue).start(error: { _ in
            updateState { current in
                var current = current
                current.profileVisibility.finish(change, succeeded: false)
                return current
            }
            environment.showModalText(for: context.window, text: strings().unknownError)
        }, completed: {
            updateState { current in
                var current = current
                current.profileVisibility.finish(change, succeeded: true)
                return current
            }
            let text = change.displayed ? strings().giftDisplayedNewText : strings().giftHiddenNewText
            environment.showModalText(for: context.window, text: text)
            if stateValue.with({ $0.collectible?.giftSlug }) == slug {
                fetchGiftTraits?()
            }
        }))
    }

    disposables.add((walletContext.state
    |> deliverOnMainQueue).start(next: { walletState in
        updateState { current in
            var current = current
            var items = walletState.collectibles.items
            if !items.contains(where: { $0.address == current.currentAddress }), let selected = current.collectible {
                items.insert(selected, at: min(current.currentIndex, items.count))
            }
            current.collectibles = items
            current.updateCollectiblesState(walletState.collectibles)
            current.ownerAddress = walletState.walletAddress
            return current
        }
        refreshCardActions()
        loadMoreIfNeeded()
    }))

    fetchGiftTraits = {
        artworkDisposable.set(nil)
        if let gift = stateValue.with({ $0.collectible }) {
            artworkDisposable.set((WalletCollectibleArtworks.shared.artwork(gift, context: context)
            |> deliverOnMainQueue).start(next: { _ in refreshCardActions() }))
        }
        refreshCardActions()
        updateState { current in
            var current = current
            current.giftTraits = [:]
            current.giftValue = nil
            current.uniqueGift = current.collectible?.nft?.gift
            if let gift = current.collectible?.nft?.gift {
                current.profileVisibility.receive(slug: gift.slug, displayed: gift.hostPeerId == context.peerId)
            }
            return current
        }
        guard let current = stateValue.with({ $0.collectible }), current.kind == .gift, let slug = current.giftSlug else {
            giftDisposable.set(nil)
            return
        }
        let remote = context.engine.payments.getUniqueStarGift(slug: slug)
        |> map(Optional.init)
        |> `catch` { _ -> Signal<StarGift.UniqueGift?, NoError> in .single(nil) }
        giftDisposable.set((context.engine.payments.cachedUniqueStarGift(slug: slug)
        |> then(remote)
        |> deliverOnMainQueue).start(next: { gift in
            guard let gift else { return }
            var traits: [String: WalletCollectibleGiftTrait] = [:]
            for attribute in gift.attributes {
                switch attribute {
                case let .model(name, _, rarity, _): traits["model"] = .init(name: name, rarity: rarity)
                case let .pattern(name, _, rarity): traits["symbol"] = .init(name: name, rarity: rarity)
                case let .backdrop(name, _, _, _, _, _, rarity): traits["backdrop"] = .init(name: name, rarity: rarity)
                default: break
                }
            }
            updateState { current in
                var current = current
                guard current.collectible?.giftSlug == slug else { return current }
                guard current.uniqueGift != gift || current.giftTraits.isEmpty else { return current }
                current.uniqueGift = gift
                current.giftTraits = traits
                current.profileVisibility.receive(slug: slug, displayed: gift.hostPeerId == context.peerId)
                if let amount = gift.valueAmount, let currency = gift.valueCurrency {
                    current.giftValue = "~\(formatCurrencyAmount(amount, currency: currency))"
                } else {
                    current.giftValue = nil
                }
                return current
            }
        }))
    }
    fetchGiftTraits?()

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        InputDataSignalValue(entries: walletCollectibleDetailsEntries(state, context: context, environment: environment, arguments: arguments))
    }
    let controller = InputDataController(dataSignal: signal, title: "", hasDone: false)
    arguments.updateHeader = walletCollectibleModalHeader(controller: controller, close: { arguments.close() }, menu: { arguments.menu() })
    let interactions = ModalInteractions(acceptTitle: strings().walletCollectibleDetailsControllerOK, accept: { close?() }, singleButton: true, customTheme: { walletModalTheme })
    let result = WalletModalController(controller, modalInteractions: interactions, size: NSMakeSize(400, 0))
    result.allowsVerticalScrollElasticity = false
    close = { [weak result] in
        result?.close()
    }
    controller.willDisappear = { _ in
        isActive = false
        disposables.dispose()
    }
    let eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .swipe]) { [weak result] event in
        guard isActive, result?.modal != nil, event.window === context.window else {
            return event
        }
        switch event.type {
        case .keyDown:
            switch event.keyCode {
            case 123:
                previous()
                return nil
            case 124:
                next()
                return nil
            default:
                return event
            }
        case .swipe:
            if event.deltaX > 0 {
                previous()
                return nil
            } else if event.deltaX < 0 {
                next()
                return nil
            }
            return event
        default:
            return event
        }
    }
    arguments.close = { close?() }
    arguments.menu = { [weak controller, weak arguments] in
        guard let controller, let arguments else { return [] }
        let state = stateValue.with { $0 }
        guard let current = state.collectible else { return [] }
        var items: [ContextMenuItem] = []
        for action in state.cardActions {
            switch action {
            case .applyColor, .removeColor:
                items.append(ContextMenuItem(action.title, handler: arguments.toggleColor))
            case .addToCard, .removeFromCard:
                items.append(ContextMenuItem(action.title, handler: arguments.toggleCard))
            case .restrictedColor:
                items.append(ContextMenuItem(action.title, handler: {
                    arguments.restrictColor(controller.tableView)
                }))
            default: break
            }
        }
        if !items.isEmpty { items.append(ContextSeparatorItem()) }
        if current.kind == .gift, let slug = current.giftSlug {
            let link = "https://t.me/nft/\(slug)"
            let copyLink = strings().modalCopyLink
            let share = strings().modalShare
            items.append(ContextMenuItem(copyLink, handler: {
                environment.copyToClipboard(link)
                environment.showModalText(for: context.window, text: strings().shareLinkCopied)
            }))
            items.append(ContextMenuItem(share, handler: {
                FeatureNavigationHooks.shared.shareLink(context, context.window, link)
            }))
        }
        if let displayed = state.displayedOnProfile {
            let title = displayed ? strings().giftViewContextHideFromProfile : strings().giftViewContextShowOnProfile
            items.append(ContextMenuItem(title, handler: arguments.toggleProfile))
        }
        if current.kind == .gift {
            items.append(ContextMenuItem(strings().walletCollectibleDetailsControllerActionTransfer, handler: arguments.transfer))
        }
        if let url = walletCollectibleExplorerUrl(context: context, environment: environment, address: current.address) {
            items.append(ContextMenuItem(strings().walletCollectibleDetailsControllerViewInExplorer, handler: { environment.openExternalURL(url) }))
        }
        if current.kind == .gift {
            items.append(ContextMenuItem(strings().walletCollectibleDetailsControllerActionSell, handler: sell))
        }
        return items
    }
    controller.onDeinit = {
        NSEvent.removeMonitor(eventMonitor as Any)
        disposables.dispose()
        transfer = nil
    }
    return result
}
