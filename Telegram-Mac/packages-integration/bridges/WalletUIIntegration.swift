import Cocoa
import WalletUI
import WalletContext
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramMedia
import GeneralRows
import InAppSettings
import BuildConfig
import PasscodeCore
import LocalAuthentication

@available(macOS 10.15, *)
func showWallet(context: AccountContext, for window: Window, morphSource: (() -> NSView?)? = nil, opensCollectibles: Bool = false) {
    WalletUI.showWallet(context: context, environment: AppWalletUIEnvironment(context), walletContext: context.walletContext, for: window, morphSource: morphSource, opensCollectibles: opensCollectibles)
}

@available(macOS 10.15, *)
func walletMoveGiftToProfile(context: AccountContext, walletContext: WalletContext, gift: StarGift.UniqueGift, window: Window) {
    WalletUI.walletMoveCollectibleToGifts(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, collectible: nil, slug: gift.slug, name: "\(gift.title) #\(gift.number)", window: window)
}

func walletCopyAddress(_ address: String, context: AccountContext, window: Window) {
    WalletUI.walletCopyAddress(address, environment: AppWalletUIEnvironment(context), window: window)
}

@available(macOS 10.15, *)
func walletTonAddressActions(context: AccountContext, walletContext: WalletContext, address: String) -> Signal<WalletTonAddressActions?, NoError> {
    WalletUI.walletTonAddressActions(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, address: address)
}

@available(macOS 10.15, *)
func WalletController(context: AccountContext, walletContext: WalletContext) -> InputDataModalController {
    WalletUI.WalletController(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext)
}

@available(macOS 10.15, *)
func WalletSendController(context: AccountContext, walletContext: WalletContext, initialAddress: String? = nil, initialAmount: Int64? = nil) -> InputDataModalController {
    WalletUI.WalletSendController(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, initialAddress: initialAddress, initialAmount: initialAmount)
}

@available(macOS 10.15, *)
func WalletSendController(context: AccountContext, walletContext: WalletContext, peer: Peer, initialAmount: Int64? = nil, transferAnimation: WalletSendTransferAnimation? = nil, transferAnimationWillStart: ((String) -> Void)? = nil, completed: (() -> Void)? = nil) -> InputDataModalController {
    WalletUI.WalletSendController(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, peer: peer, initialAmount: initialAmount, transferAnimation: transferAnimation, transferAnimationWillStart: transferAnimationWillStart, completed: completed)
}

@available(macOS 10.15, *)
func WalletSendController(context: AccountContext, walletContext: WalletContext, peer: Peer, address: String, publicKey: Data? = nil, initialAmount: Int64? = nil) -> InputDataModalController {
    WalletUI.WalletSendController(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, peer: peer, address: address, publicKey: publicKey, initialAmount: initialAmount)
}


@available(macOS 10.15, *)
func showWalletSendMoney(context: AccountContext, walletContext: WalletContext, peer: Peer) {
    WalletUI.showWalletSendMoney(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, peer: peer)
}


@available(macOS 10.15, *)
func showWalletPeerBalance(context: AccountContext, walletContext: WalletContext, peer: Peer, morphSource: (() -> NSView?)? = nil) {
    WalletUI.showWalletPeerBalance(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, peer: peer, morphSource: morphSource)
}


func walletLogoutConfirmationText(context: AccountContext) -> Signal<String, NoError> {
    guard #available(macOS 10.15, *) else {
        return .single(strings().accountConfirmLogoutText)
    }
    return WalletUI.walletLogoutConfirmationText(walletContext: context.walletContext, appConfiguration: context.appConfiguration, defaultText: strings().accountConfirmLogoutText)
}

@available(macOS 10.15, *)
func WalletTransactionController(context: AccountContext, walletContext: WalletContext, subject: WalletTransactionSubject, origin: WalletTransactionOrigin = .wallet, decryptCommentOnOpen: Bool = false, onSuccess: (() -> Void)? = nil) -> InputDataModalController {
    WalletUI.WalletTransactionController(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, subject: subject, origin: origin, decryptCommentOnOpen: decryptCommentOnOpen, onSuccess: onSuccess)
}

@available(macOS 10.15, *)
func WalletInfoController(context: AccountContext, walletContext: WalletContext, mode: WalletInfoMode, completion: (() -> Void)? = nil) -> InputDataModalController {
    WalletUI.WalletInfoController(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, mode: mode, completion: completion)
}

@available(macOS 10.15, *)
func WalletTonConnectController(context: AccountContext, walletContext: WalletContext, subject: WalletTonConnectSubject, approve: @escaping (@escaping (Result<Void, WalletContext.WalletError>) -> Void) -> Void, cancelled: @escaping () -> Void, closed: @escaping () -> Void) -> (InputDataModalController, () -> Void) {
    WalletUI.WalletTonConnectController(context: context, environment: AppWalletUIEnvironment(context), walletContext: walletContext, subject: subject, approve: approve, cancelled: cancelled, closed: closed)
}

private final class AppWalletUIEnvironment: WalletUIEnvironment {
    private let context: AccountContext

    init(_ context: AccountContext) {
        self.context = context
    }

    func shortTimestamp(hours: Int32, minutes: Int32) -> String {
        stringForShortTimestamp(hours: hours, minutes: minutes)
    }

    func peerTitle(_ peer: Peer, compact: Bool) -> String {
        compact ? peer.compactDisplayTitle : peer.displayTitle
    }

    func openChat(_ peerId: PeerId) {
        context.bindings.rootNavigation().push(ChatController(context: context, chatLocation: .peer(peerId)))
    }

    func openAccountProtection() {
        closeAllModals(window: context.window)
        context.bindings.rootNavigation().push(twoStepVerificationUnlockController(context: context, mode: .access(nil), presentController: { [context] controller, _, animated in
            let navigation = context.bindings.rootNavigation()
            if !animated {
                navigation.stackInsert(controller, at: navigation.stackCount)
            } else {
                navigation.push(controller)
            }
        }))
    }

    func openPasscodeSettings() {
        closeAllModals(window: context.window)
        let controller = PasscodeSettingsViewController(context)
        controller.installsForWallet = true
        context.bindings.rootNavigation().push(controller)
    }

    func rarityBadge(_ rarity: StarGift.UniqueGift.Attribute.Rarity) -> (text: String, color: NSColor?) {
        (text: rarity.badgeText, color: rarity.badgeColor)
    }

    func openGiftValue(_ gift: StarGift.UniqueGift) {
        let gifts = context.engine.payments.cachedStarGifts() |> take(1)
        let value = context.engine.payments.getUniqueStarGiftValueInfo(slug: gift.slug)
        _ = showModalProgress(signal: combineLatest(queue: .mainQueue(), gifts, value), for: context.window).start(next: { [context] gifts, value in
            if let generic = gifts?.first(where: { $0.generic?.id == gift.giftId })?.generic, let value {
                showModal(with: StarGift_NftValue_Controller(context: context, gift: generic, uniqueGift: gift, valueInfo: value), for: context.window)
            }
        })
    }

    func openGiftStore(_ gift: StarGift.Gift) {
        showModal(with: StarGift_MarketplaceController(context: context, peerId: context.peerId, gift: gift), for: context.window)
    }

    func openGift(_ gift: StarGift.UniqueGift) {
        showModal(with: StarGift_Nft_Controller(context: context, gift: .unique(gift), source: .previewWear(.init(context.myPeer!), gift)), for: context.window)
    }

    func openExternalURL(_ url: String) {
        execute(inapp: .external(link: url, false))
    }

    func prepareOnrampNavigation(_ url: String) -> (() -> Void)? {
        let link = inApp(for: url.nsstring, context: context, openInfo: { [context] peerId, _, messageId, initialAction in
            context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: .init(messageId: messageId), initialAction: initialAction))
        })
        guard case .followResolvedName = link else { return nil }
        return { [context] in execute(inapp: link, window: context.window) }
    }

    func presentAlert(window: Window, header: String?, text: String?, ok: String, onClose: (() -> Void)?) {
        alert(for: window, header: header, info: text, ok: ok, onDeinit: onClose, presentation: walletAlertPresentation)
    }

    func presentAlert(window: Window, header: String?, ok: String, content: @escaping (NSSize, AnyHashable) -> TableRowItem) {
        showModalAlert(for: window, data: ModalAlertData(title: header, info: "", ok: ok, footer: .init(id: "content", value: { initialSize, stableId, _, _ in
            content(initialSize, stableId)
        })), completion: { _ in }, presentation: walletAlertPresentation)
    }

    func presentDismissableAlert(window: Window, header: String?, text: String?, ok: String) -> () -> Void {
        showDismissableModalAlert(for: window, data: ModalAlertData(title: header, info: text ?? "", ok: ok), presentation: walletAlertPresentation)
    }

    func presentConfirmation(window: Window, header: String, ok: String, cancel: String, content: @escaping (NSSize, AnyHashable, @escaping () -> Void) -> TableRowItem, confirmed: @escaping () -> Void) {
        let data = ModalAlertData(title: header, info: "", ok: ok, mode: .confirm(text: cancel, isThird: false), footer: .init(id: "content", value: { initialSize, stableId, _, updateSize in
            content(initialSize, stableId, updateSize)
        }))
        showModalAlert(for: window, data: data, completion: { _ in confirmed() }, presentation: walletAlertPresentation)
    }

    func presentConfirmation(window: Window, header: String, text: String?, ok: String, cancel: String, buttonStyle: Bool, confirmed: @escaping () -> Void, cancelled: @escaping () -> Void) {
        if buttonStyle {
            verifyAlert_button(for: window, header: header, information: text, ok: ok, cancel: cancel, successHandler: { _ in confirmed() }, cancelHandler: cancelled, presentation: walletAlertPresentation)
        } else {
            verifyAlert(for: window, header: header, information: text, ok: ok, cancel: cancel, successHandler: { _ in confirmed() }, cancelHandler: cancelled, presentation: walletAlertPresentation)
        }
    }

    func presentConfirmation(window: Window, header: String, text: String?, ok: String, cancel: String, option: String, optionIsSelected: Bool, confirmed: @escaping (Bool) -> Void, cancelled: @escaping () -> Void) {
        verifyAlert(for: window, header: header, information: text, ok: ok, cancel: cancel, option: option, optionIsSelected: optionIsSelected, successHandler: { result in
            confirmed(result == .thrid)
        }, cancelHandler: cancelled, presentation: walletAlertPresentation)
    }

    func presentText(window: Window, text: String, title: String?, button: String?, callback: ((String) -> Void)?) {
        showModalText(for: window, text: text, title: title, button: button, callback: callback)
    }

    func clipboardString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func copyToClipboard(_ text: String) {
        walletUICopyToClipboard(text)
    }

    func menuImage(_ image: WalletUIMenuImage) -> ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)? {
        switch image {
        case .menu_folder_coin: return MenuAnimation.menu_folder_coin.value
        case .menu_folder_lock: return MenuAnimation.menu_folder_lock.value
        case .menu_apps: return MenuAnimation.menu_apps.value
        case .menu_show_info: return MenuAnimation.menu_show_info.value
        case .menu_open_with: return MenuAnimation.menu_open_with.value
        case .menu_plus: return MenuAnimation.menu_plus.value
        case .menu_message: return MenuAnimation.menu_message.value
        case .menu_lock: return MenuAnimation.menu_lock.value
        case .menu_cloud: return MenuAnimation.menu_cloud.value
        case .menu_gram: return MenuAnimation.menu_gram.value
        case .menu_globe: return MenuAnimation.menu_globe.value
        case .menu_change_colors: return MenuAnimation.menu_change_colors.value
        case .menu_add: return MenuAnimation.menu_add.value
        case .menu_hide: return MenuAnimation.menu_hide.value
        }
    }

    func makeLoadingRow(_ size: NSSize, stableId: AnyHashable, height: CGFloat, viewType: GeneralViewType) -> TableRowItem {
        LoadingTableItem(size, height: height, stableId: stableId, viewType: viewType)
    }

    func makePeerRow(_ size: NSSize, stableId: AnyHashable, peer: Peer, status: String?, isResolving: Bool, viewType: GeneralViewType, action: @escaping () -> Void, deselect: (() -> Void)?) -> TableRowItem {
        ShortPeerRowItem(size, peer: peer, account: context.account, context: context, stableId: stableId, height: 44, photoSize: NSMakeSize(30, 30), status: status, inset: NSEdgeInsets(left: 20, right: 20), generalType: isResolving ? .loading : .none, viewType: viewType, action: action, rightActions: deselect.map { callback in
            ShortPeerRowItem.RightActions(actions: [.init(icon: theme.icons.recentDismiss, index: 0)], callback: { _, _ in callback() })
        } ?? .init(actions: [], callback: { _, _ in }))
    }

    func makeAnimatedHeader(_ size: NSSize, stableId: AnyHashable, sticker: WalletUIAnimation?, text: NSAttributedString, infoText: NSAttributedString, stickerSize: NSSize, image: CGImage?, infoLinkHandler: ((String) -> Void)?, viewType: GeneralViewType) -> TableRowItem {
        let animation: LocalAnimatedSticker?
        switch sticker {
        case .wallet_word_list: animation = .wallet_word_list
        case .wallet_word_check: animation = .wallet_word_check
        case nil: animation = nil
        }
        let interactions: TextViewInteractions
        if let infoLinkHandler {
            interactions = TextViewInteractions(processURL: { value in
                if let value = value as? String {
                    infoLinkHandler(value)
                }
            })
        } else {
            interactions = globalLinkExecutor
        }
        return AnimatedStickerHeaderItem(size, stableId: stableId, context: context, sticker: animation, text: text, infoText: infoText, stickerSize: stickerSize, image: image, viewType: viewType, interactions: interactions)
    }

    func webFilePhoto(photo: TelegramMediaWebFile, scale: CGFloat, useActualDimensions: Bool) -> Signal<ImageDataTransformation, NoError> {
        chatMessageWebFilePhoto(account: context.account, photo: photo, scale: scale, useActualDimensions: useActualDimensions)
    }

    func ownerAvatar(_ peer: Peer, size: NSSize, font: NSFont) -> Signal<CGImage?, NoError> {
        peerAvatarImage(account: context.account, photo: .peer(peer, peer.smallProfileImage, peer.namePeerColor, peer.displayLetters, nil, nil), displayDimensions: size, font: font, genCap: true, synchronousLoad: false) |> map { $0.0 }
    }

    func makeAvatar(font: NSFont) -> WalletUIAvatarView {
        AppWalletUIAvatarView(account: context.account, font: font)
    }

    func setCollectibleAnimation(in view: Control, contents: Data?, key: String, size: NSSize) {
        let player: LottiePlayerView
        if let existing = view.subviews.first as? LottiePlayerView {
            player = existing
        } else {
            view.autoresizesSubviews = true
            player = LottiePlayerView(frame: view.bounds)
            player.autoresizingMask = [.width, .height]
            player.isEventLess = true
            view.addSubview(player)
            view.set(handler: { [weak player] _ in
                guard let player, let animation = player.animation else {
                    return
                }
                player.set(animation, reset: true, saveContext: false, animated: false)
            }, for: .Click)
        }
        guard let contents else {
            player.set(nil, animated: false)
            return
        }
        let animation = LottieAnimation(compressed: contents, key: LottieAnimationEntryKey(key: .bundle(key), size: size), type: .lottie, cachePurpose: .none, playPolicy: .onceEnd, maximumFps: 60, colors: [], metalSupport: false)
        player.set(animation, reset: true, saveContext: false, animated: false)
    }
}

@available(macOS 10.15, *)
private func makeWalletPasscodePrompt(rootPath: String, namespace: String, lifetime: PasscodeSession.Lifetime, biometrics: Bool, session: Atomic<PasscodeSession?>) -> WalletUIAuthorizationPrompt {
    let verify: (String, @escaping (WalletUIPasscodeVerification) -> Void) -> Void = { code, completion in
        Queue.concurrentDefaultQueue().async {
            let result: WalletUIPasscodeVerification
            do {
                syncPasscodeCredential(code: code, rootPath: rootPath)
                let value = try PasscodeCredentialStore.shared.verify(code, scope: .resource(namespace: namespace), lifetime: lifetime)
                session.swap(value)?.invalidate()
                result = .authorized
            } catch PasscodeError.invalidCode {
                result = .invalidCode
            } catch let PasscodeError.cooldown(seconds) {
                result = .cooldown(seconds)
            } catch {
                result = .unavailable
            }
            Queue.mainQueue().async {
                completion(result)
            }
        }
    }
    let authenticateBiometrics: ((@escaping (WalletUIPasscodeVerification) -> Void) -> Void)?
    if biometrics {
        authenticateBiometrics = { completion in
            let laContext = LAContext()
            laContext.localizedReason = strings().walletBiometricsConfirmAccess
            laContext.localizedFallbackTitle = ""
            laContext.touchIDAuthenticationAllowableReuseDuration = 0
            laContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: strings().walletBiometricsConfirmAccess) { success, _ in
                Queue.concurrentDefaultQueue().async {
                    let result: WalletUIPasscodeVerification
                    if success {
                        do {
                            let value = try authenticateWalletBiometrics(namespace: namespace, lifetime: lifetime, context: laContext)
                            session.swap(value)?.invalidate()
                            result = .authorized
                        } catch {
                            result = .cancelled
                        }
                    } else {
                        result = .cancelled
                    }
                    laContext.invalidate()
                    Queue.mainQueue().async {
                        completion(result)
                    }
                }
            }
        }
    } else {
        authenticateBiometrics = nil
    }
    return WalletUIAuthorizationPrompt(verify: verify, authenticateBiometrics: authenticateBiometrics)
}

@available(macOS 10.15, *)
func requestWalletPasscodeAuthorization(context: AccountContext?, request: WalletAuthorizationRequest) async throws -> PasscodeSession {
    guard let context else {
        throw PasscodeError.cancelled
    }
    if request.reason == "TON Connect", !WalletConfiguration.with(appConfiguration: context.appConfiguration).isAvailable {
        throw PasscodeError.cancelled
    }
    let settings = try walletProtectionSettings()
    guard settings.passcode != nil else {
        throw PasscodeError.authenticationRequired
    }
    let rootPath = context.sharedContext.accountManager.basePath.nsstring.deletingLastPathComponent
    let window = context.window
    let session = Atomic<PasscodeSession?>(value: nil)
    let prompt = makeWalletPasscodePrompt(rootPath: rootPath, namespace: request.namespace, lifetime: request.lifetime, biometrics: settings.enabled && settings.biometricsEnabled, session: session)
    let presentation = Atomic<(cancelled: Bool, dismiss: (() -> Void)?)>(value: (false, nil))
    return try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PasscodeSession, Error>) in
            Queue.mainQueue().async {
                if presentation.with({ $0.cancelled }) {
                    continuation.resume(throwing: PasscodeError.cancelled)
                    return
                }
                let dismiss = presentWalletAuthorization(prompt, window: window, completion: { authorized in
                    _ = presentation.modify { ($0.cancelled, nil) }
                    if authorized, let value = session.swap(nil) {
                        continuation.resume(returning: value)
                    } else {
                        session.swap(nil)?.invalidate()
                        continuation.resume(throwing: PasscodeError.cancelled)
                    }
                })
                _ = presentation.modify { ($0.cancelled, dismiss) }
            }
        }
    }, onCancel: {
        let dismiss = presentation.modify { (true, $0.dismiss) }.dismiss
        Queue.mainQueue().async {
            dismiss?()
        }
    })
}

private final class AppWalletUIAvatarView: WalletUIAvatarView {
    private let avatar: AvatarControl
    private let account: Account

    init(account: Account, font: NSFont) {
        self.account = account
        self.avatar = AvatarControl(font: font)
        super.init(frame: .zero)
        autoresizesSubviews = true
        avatar.autoresizingMask = [.width, .height]
        avatar.userInteractionEnabled = false
        addSubview(avatar)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        avatar.frame = bounds
    }

    override func update(peer: Peer?, synchronousLoad: Bool) {
        avatar.attemptLoadNextSynchronous = synchronousLoad
        avatar.setPeer(account: account, peer: peer)
    }
}

private func walletUICopyToClipboard(_ text: String) {
    copyToClipboard(text)
}

@available(macOS 10.15, *)
func preloadWalletPeerCard(context: AccountContext, card: WalletCard) {
    WalletUI.preloadWalletPeerCard(context: context, card: card)
}
