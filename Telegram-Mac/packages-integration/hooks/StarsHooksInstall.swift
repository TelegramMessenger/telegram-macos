import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import StarsUI
import GiftCraftingUI
import TelegramMedia
import InputView
import InputTextView
import WalletUI
import WalletContext

private func giftsContext(_ context: any AccountContextProtocol) -> AccountContext? {
    return context as? AccountContext
}

func installStarsUIHooks() {
    var hooks = StarsHooks(openChat: { context, peerId, action in
        guard let context = giftsContext(context) else { return }
        context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId), initialAction: action))
    }, openChatAt: { context, messageId in
        guard let context = giftsContext(context) else { return }
        context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(messageId.peerId), focusTarget: .init(messageId: messageId)))
    }, openChatIfNotCurrent: { context, peerId in
        guard let context = giftsContext(context) else { return }
        let controller = context.bindings.rootNavigation().controller as? ChatController
        if controller?.chatLocation.peerId != peerId {
            context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId)))
        }
    }, isBubbledServiceItem: { item in
        if let item = item as? ChatServiceItem {
            return item.isBubbled
        }
        return false
    }, wearGiftBoostLevel: { context in
        guard let context = giftsContext(context) else { return 0 }
        return BoostSubject.wearGift.requiredLevel(context: context, group: false, configuration: .with(appConfiguration: context.appConfiguration))
    }, openBoostForWear: { context, channel, stats, myStatus, window in
        guard let context = giftsContext(context), let stats = stats else { return }
        showModal(with: BoostChannelModalController(context: context, peer: channel, boosts: stats, myStatus: myStatus, infoOnly: false, source: .wearStatus, presentation: theme), for: window)
    }, makeGiftMessagePreview: { initialSize, stableId, context, gift, message, send in
        guard let context = giftsContext(context) else {
            preconditionFailure("gift message preview requires a concrete AccountContext")
        }
        return AddGiftMessagePreviewItem(initialSize, stableId: stableId, context: context, gift: gift, message: message, send: send)
    }, openInviteHash: { context, inviteHash, joined in
        guard let context = giftsContext(context) else { return }
        execute(inapp: .joinchat(link: "", inviteHash, context: context, callback: { peerId, _, _, _ in
            joined(peerId)
        }))
    }, showEmojiPicker: { context, control, insertAnimated, insertText in
        guard let context = giftsContext(context) else { return }
        let emojis = EmojiesController(context, ignorePremium: true)
        emojis._frameRect = NSMakeRect(0, 0, 350, 300)
        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        emojis.update(with: interactions, chatInteraction: ChatInteraction(chatLocation: .peer(context.peerId), context: context))
        interactions.sendAnimatedEmoji = { sticker, _, _, _, _ in
            let file = sticker.file._parse()
            insertAnimated(file, file.customEmojiText ?? file.stickerText ?? clown)
        }
        interactions.sendEmoji = { string, _ in
            insertText(string)
        }
        showPopover(for: control, with: emojis)
    }, makeInputTextRow: { initialSize, stableId, context, state, placeholder, limit, filter, updateState in
        guard let context = giftsContext(context) else {
            preconditionFailure("input text row requires a concrete AccountContext")
        }
        return InputTextDataRowItem(initialSize, stableId: stableId, context: context, state: state, viewType: .lastItem, placeholder: nil, inputPlaceholder: placeholder, filter: filter, updateState: updateState, limit: limit, hasEmoji: true)
    }, openPeerInfo: { context, peerId in
        guard let context = giftsContext(context) else { return }
        PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId)
    }, openGiftsProfile: { context, peerId, starGiftsProfile in
        guard let context = giftsContext(context) else { return }
        PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId, mediaMode: .gifts, shake: false, starGiftsProfile: starGiftsProfile)
    }, makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, applyMessageEntities: { entities, text, context, fontSize, openInfo, textColor, isDark, bubbled in
        guard let context = giftsContext(context) else { return NSAttributedString() }
        if let textColor = textColor {
            return ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: nil, context: context, fontSize: fontSize, openInfo: openInfo, textColor: textColor, isDark: isDark, bubbled: bubbled)
        }
        return ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: nil, context: context, fontSize: fontSize, openInfo: openInfo, isDark: isDark, bubbled: bubbled)
    }, applyGiftMessagePreviewEntities: { entities, text, context in
        return ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: nil, context: context, fontSize: theme.fontSize, openInfo: { _, _, _, _ in }, textColor: .white, linkColor: .white, isDark: theme.colors.isDark, bubbled: true)
    }, shareLink: { context, link, window in
        guard let context = giftsContext(context) else { return }
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: window)
    }, openLink: { context, url, openInfo in
        guard let context = giftsContext(context) else { return }
        execute(inapp: inApp(for: url.nsstring, context: context, openInfo: openInfo))
    }, inputTextViewSize: { view, width in
        guard let view = view as? UITextView else { return (.zero, 0) }
        return inputTextViewSize(view, width: width)
    }, openMiniApp: { context, peer in
        guard let context = giftsContext(context) else { return }
        BrowserStateContext.get(context).open(tab: .mainapp(bot: peer, source: .generic))
    }, makeAvatarMenuItem: { context, peer in
        guard let context = giftsContext(context) else { return nil }
        return GroupCallAvatarMenuItem(peer, context: context)
    }, openTonBalance: { context, tonAmount in
        guard let context = giftsContext(context) else { return }
        showModal(with: AddTonBalanceController(context: context, tonAmount: tonAmount ?? 0), for: context.window)
    }, giftTransferBlockchainOption: { context, window, gift, reference, profileGiftsContext in
        guard let context = giftsContext(context) else { return nil }
        return makeGiftTransferBlockchainOption(context: context, window: window, gift: gift, reference: reference, profileGiftsContext: profileGiftsContext)
    }, giftMoveToGiftsAction: { context, window, gift in
        guard let context = giftsContext(context) else { return nil }
        if #available(macOS 10.15, *), case let .address(address) = gift.owner, let walletContext = context.walletContext, WalletContext.isSelfTransfer(recipient: address, walletAddress: giftWalletAddress(context)) {
            return {
                walletMoveGiftToProfile(context: context, walletContext: walletContext, gift: gift, window: window)
            }
        }
        return nil
    }, selectContact: { context, window, title, confirmation in
        guard let context = giftsContext(context) else { return .single([]) }
        return selectModalPeers(window: window, context: context, title: title, behavior: SelectContactsBehavior(limit: 1), confirmation: confirmation)
    }, openMultigift: { context, starsOnly in
        guard let context = giftsContext(context) else { return }
        multigift(context: context, type: starsOnly ? .stars : .both)
    }, openStarMonetization: { context, peerId, revenueContext in
        guard let context = giftsContext(context) else { return }
        context.bindings.rootNavigation().push(FragmentStarMonetizationController(context: context, peerId: peerId, revenueContext: revenueContext))
    }, openMessagesPrivacy: { context, noPaidMessages, globalSettings, updated in
        guard let context = giftsContext(context) else { return }
        context.bindings.rootNavigation().push(MessagesPrivacyController(context: context, noPaidMessages: noPaidMessages, globalSettings: globalSettings, updated: updated))
    }, showGalleryMedia: { context, medias, parent, delegate in
        guard let context = giftsContext(context) else { return }
        showGalleryMedia(context: context, medias: medias, parent: parent, firstIndex: 0, firstStableId: ChatHistoryEntryId.mediaId(0, parent), delegate, nil)
    }, makeRecentPeerRow: { initialSize, peer, context, stableId, status, action in
        guard let context = giftsContext(context) else {
            preconditionFailure("recent peer row requires a concrete AccountContext")
        }
        return RecentPeerRowItem(initialSize, peer: peer, account: context.account, context: context, stableId: stableId, statusStyle: ControlStyle(font: .normal(.text), foregroundColor: theme.colors.grayText, highlightColor: .white), status: status, action: action)
    }, makeFilterChipRow: { initialSize, stableId, context, text, selected, select, contextMenu in
        guard let context = giftsContext(context) else {
            preconditionFailure("filter chip row requires a concrete AccountContext")
        }
        return FilterChipRowItem(initialSize, stableId: stableId, context: context, text: text, selected: selected, select: select, contextMenu: contextMenu)
    }, makeSelectGiftsModal: { context, collectionId, peerId, callback in
        guard let context = giftsContext(context) else {
            preconditionFailure("select gifts modal requires a concrete AccountContext")
        }
        return SelectGiftsModalController(context: context, collectionId: collectionId, peerId: peerId, callback: callback)
    }, applyMenuItemEmoji: { item, context, file in
        guard let context = giftsContext(context) else {
            return
        }
        ContextMenuItem.makeEmoji(item, context: context, file: file)
    }, makeLiveMessagePreviewRow: { initialSize, stableId, context, message in
        guard let context = giftsContext(context) else {
            preconditionFailure("live message preview requires a concrete AccountContext")
        }
        return StoryMessageItemRow(initialSize, stableId: stableId, message: message, reactions: nil, arguments: StoryMessageArguments.init(context: context, contextMenuItems: { _, _,_  in return [] }, focusMessage: { _ in }), preview: true)
    }, updateBirthday: { date, context in
        editAccountUpdateBirthday(date, context: context)
    }, openAffiliatePeer: { context, peerId, onlyDemo in
        context.bindings.rootNavigation().push(Affiliate_PeerController(context: context, peerId: peerId, onlyDemo: onlyDemo))
    }, makeCraftAboutFeatureItem: { initialSize, stableId, features in
        return CraftAboutFeatureItem(initialSize, stableId: stableId, features: features)
    }, makeCraftingAreaItem: { initialSize, stableId, data in
        return CraftingAreaItem(initialSize, stableId: stableId, data: data)
    })
    hooks.giftTransferBlockchainOptionWithContext = { context, window, gift, reference, profileGiftsContext in
        guard let context = giftsContext(context) else { return nil }
        return makeGiftTransferBlockchainOption(context: context, window: window, gift: gift, reference: reference, profileGiftsContext: profileGiftsContext)
    }
    installStarsHooks(hooks)
}

extension StoryMessageItemRow: @retroactive StarsLiveMessagePreviewRow {

}

extension MediaAnimatedStickerView: @retroactive StarsStickerView {
    public var starsStickerReady: Signal<Bool, NoError> {
        return firstFrameReady
    }

    public func updateStarsSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, colors: [LottieColor], playback: StarsStickerPlayback, animated: Bool) {
        guard let context = context as? AccountContext else { return }
        let parameters: ChatAnimatedStickerMediaLayoutParameters?
        switch playback {
        case .standard:
            parameters = colors.isEmpty ? nil : ChatAnimatedStickerMediaLayoutParameters(playPolicy: .loop, alwaysAccept: true, media: file, colors: colors, noThumb: true)
        case .previewFrames:
            parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .framesCount(2), alwaysAccept: true, cache: .temporaryLZ4(.thumb), hidePlayer: false, media: file)
        case .onceEnd:
            parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .onceEnd, media: file)
        case .loopHidden:
            let value = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .loop, hidePlayer: true, media: file)
            value.colors = colors
            parameters = value
        }
        if let parameters = parameters {
            self.update(with: file, size: size, context: context, table: nil, parameters: parameters, animated: animated)
        } else {
            self.update(with: file, size: size, context: context, table: nil, animated: animated)
        }
    }
}

extension FilterChipRowItem: @retroactive StarsFilterChipRow {

}

@available(macOS 10.15, *)
private func giftWalletAddress(_ context: any AccountContextProtocol) -> String? {
    guard let context = giftsContext(context), let walletContext = context.walletContext, case let .wallet(info) = walletContext.stateValue.phase else {
        return nil
    }
    return info.address
}

private let moveGiftWalletPathSpacing: [CGFloat] = [3, 4, 4, 3, 4, 4, 3, 0]

private final class MoveGiftToWalletRowItem: TableRowItem {
    private let _stableId: AnyHashable
    override var stableId: AnyHashable {
        return _stableId
    }
    let textLayout: TextViewLayout
    let addressLayout: TextViewLayout
    let address: String
    let copyAddress: () -> Void
    let appearLayout: TextViewLayout
    let pathLayouts: [TextViewLayout]
    let chevronLayout: TextViewLayout
    let pathIconSize: CGFloat = 14

    init(_ initialSize: NSSize, stableId: AnyHashable, address: String, copyAddress: @escaping () -> Void) {
        self._stableId = stableId
        self.address = address
        self.copyAddress = copyAddress
        self.textLayout = TextViewLayout(.initialize(string: strings().giftMoveToWalletText, color: theme.colors.darkGrayText, font: .normal(.text)), alignment: .center)
        self.addressLayout = TextViewLayout(walletAddressGrid(address, font: .semiboldMonospace(15), secondaryColor: theme.colors.text.withMultipliedAlpha(0.32)), alignment: .center, lineSpacing: 4, alwaysStaticItems: true)
        self.appearLayout = TextViewLayout(.initialize(string: strings().giftMoveToWalletLocation, color: theme.colors.text, font: .normal(.text)), alignment: .center)
        self.pathLayouts = [strings().accountViewControllerTitle, strings().walletControllerMoney, strings().walletControllerCollectibles].map {
            TextViewLayout(.initialize(string: $0, color: theme.colors.text.withAlphaComponent(0.5), font: .normal(12)), maximumNumberOfLines: 1)
        }
        self.chevronLayout = TextViewLayout(.initialize(string: "›", color: theme.colors.text.withAlphaComponent(0.5), font: .normal(14)), maximumNumberOfLines: 1)
        super.init(initialSize)
        _ = makeSize(initialSize.width, oldWidth: 0)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: width - 40)
        addressLayout.measure(width: width - 72)
        appearLayout.measure(width: width - 40)
        chevronLayout.measure(width: .greatestFiniteMagnitude)
        for layout in pathLayouts {
            layout.measure(width: .greatestFiniteMagnitude)
        }
        let pathTextWidth = max(0, width - 24 - pathIconSize * 3 - chevronLayout.layoutSize.width * 2 - moveGiftWalletPathSpacing.reduce(0, +))
        let measuredPathTextWidth = pathLayouts.reduce(CGFloat(0)) { $0 + $1.layoutSize.width }
        if measuredPathTextWidth > pathTextWidth {
            for layout in pathLayouts {
                layout.measure(width: layout.layoutSize.width * pathTextWidth / measuredPathTextWidth)
            }
        }
        return result
    }

    var addressBlockHeight: CGFloat {
        return addressLayout.layoutSize.height + 24
    }

    var pathHeight: CGFloat {
        return max(pathIconSize, max(chevronLayout.layoutSize.height, pathLayouts.map { $0.layoutSize.height }.max() ?? 0))
    }

    override var height: CGFloat {
        return textLayout.layoutSize.height + 16 + addressBlockHeight + 16 + appearLayout.layoutSize.height + 4 + pathHeight + 8
    }

    override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    override func viewClass() -> AnyClass {
        return MoveGiftToWalletRowView.self
    }
}

private final class MoveGiftToWalletRowView: TableRowView {
    private let textView = TextView()
    private let addressBlockView = WalletAddressControl(frame: .zero)
    private let appearView = TextView()
    private let pathIconViews = [ImageView(), ImageView(), ImageView()]
    private let pathTextViews = [TextView(), TextView(), TextView()]
    private let pathChevronViews = [TextView(), TextView()]

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [textView, appearView] + pathTextViews + pathChevronViews {
            view.userInteractionEnabled = false
            view.isSelectable = false
        }
        for view in pathIconViews {
            view.isEventLess = true
            view.contentGravity = .resizeAspect
            addSubview(view)
        }
        for view in pathTextViews + pathChevronViews {
            addSubview(view)
        }
        addSubview(textView)
        addSubview(addressBlockView)
        addSubview(appearView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? MoveGiftToWalletRowItem else {
            return
        }
        textView.update(item.textLayout)
        addressBlockView.update(address: item.address, layout: item.addressLayout, copyAddress: item.copyAddress)
        appearView.update(item.appearLayout)
        let pathIcons = [
            NSImage(named: "Wallet_PathSettings")?.precomposed(theme.colors.text.withAlphaComponent(0.5)),
            NSImage(named: "Wallet_PathGram")?.precomposed(),
            NSImage(named: "Wallet_PathGift")?.precomposed(theme.colors.text.withAlphaComponent(0.5))
        ]
        for (view, icon) in zip(pathIconViews, pathIcons) {
            view.image = icon
            view.setFrameSize(NSMakeSize(item.pathIconSize, item.pathIconSize))
        }
        for (view, layout) in zip(pathTextViews, item.pathLayouts) {
            view.update(layout)
        }
        for view in pathChevronViews {
            view.update(item.chevronLayout)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? MoveGiftToWalletRowItem else {
            return
        }
        textView.centerX(y: 0)
        addressBlockView.frame = NSMakeRect(20, textView.frame.maxY + 16, frame.width - 40, item.addressBlockHeight)
        appearView.centerX(y: addressBlockView.frame.maxY + 16)
        let pathViews: [NSView] = [pathIconViews[0], pathTextViews[0], pathChevronViews[0], pathIconViews[1], pathTextViews[1], pathChevronViews[1], pathIconViews[2], pathTextViews[2]]
        let pathWidth = pathViews.reduce(CGFloat(0)) { $0 + $1.frame.width } + moveGiftWalletPathSpacing.reduce(0, +)
        let pathY = appearView.frame.maxY + 4
        var pathX = floorToScreenPixels(backingScaleFactor, (frame.width - pathWidth) / 2)
        for (view, spacing) in zip(pathViews, moveGiftWalletPathSpacing) {
            view.setFrameOrigin(NSMakePoint(pathX, pathY + floorToScreenPixels(backingScaleFactor, (item.pathHeight - view.frame.height) / 2)))
            pathX += view.frame.width + spacing
        }
    }
}

@available(macOS 10.15, *)
private func confirmMoveGiftToWallet(context: AccountContext, window: Window, reference: StarGiftReference, giftsContext: ProfileGiftsContext, address: String) {
    guard giftWalletAddress(context) == address else {
        alert(for: window, header: strings().walletSettingsControllerWalletChanged, info: strings().walletSettingsControllerWalletChangedInfo)
        return
    }
    let data = ModalAlertData(title: strings().giftMoveToWalletTitle, info: "", ok: strings().giftMoveToWalletMove, mode: .confirm(text: strings().modalCancel, isThird: false), footer: .init(id: "content", value: { initialSize, stableId, _, _ in
        return MoveGiftToWalletRowItem(initialSize, stableId: stableId, address: address, copyAddress: {
            walletCopyAddress(address, context: context, window: window)
        })
    }), showCloseButton: true)
    let withdraw: (String?) -> Signal<Never, WithdrawStarGiftError> = { password in
        return context.engine.wallet.getState()
        |> mapError { _ -> WithdrawStarGiftError in .generic }
        |> deliverOnMainQueue
        |> mapToSignal { state -> Signal<Never, WithdrawStarGiftError> in
            guard case let .ready(_, _, _, currentAddress, _, _) = state,
                  currentAddress == address,
                  giftWalletAddress(context) == address else {
                return .fail(.serverProvided(text: strings().walletSettingsControllerWalletChangedInfo))
            }
            return giftsContext.withdrawStarGift(reference: reference, keepOnProfile: false, password: password)
        }
        |> deliverOnMainQueue
    }
    let errorValue: (WithdrawStarGiftError) -> InputPasswordValueError = { error in
        switch error {
        case .invalidPassword:
            return .wrong
        case .limitExceeded:
            return .custom(strings().twoStepAuthFloodError)
        case let .serverProvided(text):
            return .custom(text)
        default:
            return .custom(strings().unknownError)
        }
    }
    let moved = {
        presentGiftMovedToWalletToast(context: context, window: window)
    }
    let requestPassword = {
        let controller = InputPasswordController(context: context, title: strings().monetizationWithdrawEnterPasswordTitle, desc: strings().monetizationWithdrawEnterPasswordText, checker: { value in
            return (withdraw(value)
            |> mapError(errorValue)
            |> afterCompleted(moved))
        })
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
        }
        showModal(with: controller, for: window)
    }
    showModalAlert(for: window, data: data, completion: { _ in
        _ = (withdraw(nil)).start(error: { error in
            let mapped: RequestStarGiftWithdrawalError
            switch error {
            case .generic:
                mapped = .generic
            case .twoStepAuthMissing:
                mapped = .twoStepAuthMissing
            case let .twoStepAuthTooFresh(value):
                mapped = .twoStepAuthTooFresh(value)
            case let .authSessionTooFresh(value):
                mapped = .authSessionTooFresh(value)
            case .limitExceeded:
                mapped = .limitExceeded
            case .requestPassword:
                mapped = .requestPassword
            case .invalidPassword:
                mapped = .invalidPassword
            case let .serverProvided(text):
                mapped = .serverProvided(text: text)
            }
            guard case .requestPassword = mapped else {
                presentGiftWithdrawalError(context: context, window: window, error: mapped, requestPassword: requestPassword)
                return
            }
            _ = (context.engine.payments.checkStarGiftWithdrawalAvailability(reference: reference)
            |> deliverOnMainQueue).start(error: { error in
                presentGiftWithdrawalError(context: context, window: window, error: error, requestPassword: requestPassword)
            })
        }, completed: moved)
    }, presentation: walletAlertPresentation)
}

func presentGiftMovedToWalletToast(context: AccountContext, window: Window) {
    closeAllModals(window: window)
    showModalText(for: window, text: strings().giftMoveToWalletSuccess, button: strings().alertView, callback: { _ in
        if #available(macOS 10.15, *) {
            showWallet(context: context, for: window, opensCollectibles: true)
        }
    })
}

private func makeGiftTransferBlockchainOption(context: AccountContext, window: Window, gift: StarGift.UniqueGift, reference: StarGiftReference, profileGiftsContext: ProfileGiftsContext) -> (title: String, icon: NSImage, action: () -> Void)? {
    if #available(macOS 10.15, *), let walletAddress = giftWalletAddress(context) {
        let icon = WalletUI.walletMoveActionIcon("Icon_MoveToWallet").map { NSImage(cgImage: $0, size: NSMakeSize(40, 40)) } ?? NSImage(resource: .iconMoveToWallet)
        return (title: strings().giftTransferMoveToWallet, icon: icon, action: {
            confirmMoveGiftToWallet(context: context, window: window, reference: reference, giftsContext: profileGiftsContext, address: walletAddress)
        })
    }
    return (title: strings().giftTransferSendViaBlockchain, icon: NSImage(resource: .iconSendViaTon), action: {
        let data = ModalAlertData(title: nil, info: strings().giftWithdrawText(gift.title + " #\(gift.number)"), description: nil, ok: strings().giftWithdrawProceed, options: [], header: .init(id: "header", value: { initialSize, stableId, _ in
            return TransferUniqueGiftHeaderItem(initialSize, stableId: stableId, gift: gift, toPeer: .init(context.myPeer!), context: context)
        }), footer: ModalAlertData.Footer.init(id: "footer", value: { initialSize, stableId, presentation, action in
            return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: getTransferAttributesRows(gift: gift), context: context)
        }), width: 340, showCloseButton: true)
        showModalAlert(for: window, data: data, completion: { _ in
            let requestPassword = {
                let controller = InputPasswordController(context: context, title: strings().giftWithdrawTitle, desc: strings().monetizationWithdrawEnterPasswordText, checker: { value in
                    return (context.engine.payments.requestStarGiftWithdrawalUrl(reference: reference, password: value)
                    |> deliverOnMainQueue
                    |> afterNext { url in
                        execute(inapp: .external(link: url, false))
                    }
                    |> ignoreValues
                    |> mapError { error in
                        switch error {
                        case .invalidPassword:
                            return .wrong
                        case .limitExceeded:
                            return .custom(strings().loginFloodWait)
                        case .generic:
                            return .generic
                        default:
                            return .custom(strings().monetizationWithdrawErrorText)
                        }
                    })
                })
                let onDeinit = controller.onDeinit
                controller.onDeinit = {
                    onDeinit?()
                }
                showModal(with: controller, for: context.window)
            }
            _ = (context.engine.payments.requestStarGiftWithdrawalUrl(reference: reference, password: nil)
            |> deliverOnMainQueue).start(next: { url in
                execute(inapp: .external(link: url, false))
            }, error: { error in
                switch error {
                case .limitExceeded:
                    showGiftTransferError(window: window, info: strings().loginFloodWait)
                case let .serverProvided(text):
                    showGiftTransferError(window: window, info: text)
                default:
                    requestPassword()
                }
            })
        })
    })
}

private func showGiftTransferError(window: Window, info: String) {
    alert(for: window, info: info)
}

private func presentGiftWithdrawalError(context: AccountContext, window: Window, error: RequestStarGiftWithdrawalError, requestPassword: @escaping () -> Void) {
    switch error {
    case .requestPassword:
        requestPassword()
    case let .serverProvided(text):
        alert(for: window, info: text)
    case .limitExceeded:
        alert(for: window, info: strings().twoStepAuthFloodError)
    case .twoStepAuthTooFresh, .authSessionTooFresh:
        alert(for: window, header: strings().giftWithdrawSecurityCheck, info: strings().giftWithdrawSecurityRequirements + strings().giftWithdrawComeBackLater)
    case .twoStepAuthMissing:
        verifyAlert(for: window, header: strings().giftWithdrawSecurityCheck, information: strings().giftWithdrawSecurityRequirements, ok: strings().giftWithdrawSetupTwoStepAuth, cancel: strings().modalCancel, successHandler: { _ in
            closeAllModals(window: window)
            let controller = twoStepVerificationUnlockController(context: context, mode: .access(nil), presentController: { controller, _, animated in
                let navigation = context.bindings.rootNavigation()
                if !animated {
                    navigation.stackInsert(controller, at: navigation.stackCount)
                } else {
                    navigation.push(controller)
                }
            })
            context.bindings.rootNavigation().push(controller)
        })
    case .generic, .invalidPassword:
        alert(for: window, info: strings().unknownError)
    }
}
