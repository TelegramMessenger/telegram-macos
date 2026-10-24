import Foundation
import WebKit
import UserNotifications
import TGUIKit
import InputDataUI
import SwiftSignalKit
import Postbox
import TelegramCore
import Localization
import InAppSettings
import IOKit
import CodeSyntax
import SettingsUI
import StoriesUI
import PrivateCallScreen
import DetectSpeech
import WalletContext
import AppKit


/// Opens a community — a container peer, not a conversation — as its chat list in the left controller.
/// The universal counterpart to navigating into a chat; mirrors the chat-list row behaviour so every
/// `navigateToChat` caller routes communities correctly.
func openCommunity(_ communityId: PeerId, context: AccountContext) {
    context.bindings.mainViewController.chatList.navigationController?.push(CommunityListController(context, communityId: communityId))
}


func navigateToChat(navigation: NavigationViewController?, context: AccountContext, chatLocation:ChatLocation, mode: ChatMode = .history, focusTarget:ChatFocusTarget? = nil, initialAction: ChatInitialAction? = nil, chatLocationContextHolder: Atomic<ChatLocationContextHolder?>? = nil, additional: Bool = false, animated: Bool = true, navigationStyle: ViewControllerStyle? = nil, callback:@escaping(ChatController)->Void = { _ in }) {
        
    let context = appDelegate?.supportAccountContextValue?.getExternalContext(peerId: chatLocation.peerId, accountId: context.account.id) ?? context
    
    let navigation = context.isExternal ? context.bindings.rootNavigation() : navigation
    
    context.window.makeKeyAndOrderFront(nil)
    
    let open:(ChatLocation, ChatInitialAction?, ChatMode)->Void = { [weak navigation] location, initialAction, mode in
        
        guard let navigation else { return }
        let current = navigation.controller as? ChatController
        
        if current?.chatLocation == location, additional {
            current?.scrollup(force: true)
            current?.chatInteraction.invokeInitialAction(action: initialAction)
            return
        }
        let controller: ChatController = chatNavigationChild() {
            if additional {
                return ChatAdditionController(context: context, chatLocation: location, mode: mode, focusTarget: focusTarget, initialAction: initialAction, chatLocationContextHolder: chatLocationContextHolder)
            } else if mode == .scheduled {
                return ChatScheduleController(context: context, chatLocation: location, mode: mode, focusTarget: focusTarget, initialAction: initialAction, chatLocationContextHolder: chatLocationContextHolder)
            } else {
                return ChatController(context: context, chatLocation: location, mode: mode, focusTarget: focusTarget, initialAction: initialAction, chatLocationContextHolder: chatLocationContextHolder)
            }
        }
        navigation.push(controller, animated, style: navigationStyle)
        callback(controller)

    }
    
    let signal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: chatLocation.peerId)) |> take(1) |> deliverOnMainQueue
    
    _ = signal.start(next: { peer in
        
        let checkNext:(Peer)->Void = { peer in
            open(chatLocation, initialAction, mode)
        }
        
        if let peer = peer?._asPeer() {
            if peer.isCommunity {
                let controller = chatNavigationChild() {
                    CommunityListController(context, communityId: peer.id)
                }
                context.bindings.mainViewController.chatList.navigationController?.push(controller)
                return
            }
            if peer.hasSensitiveContent(platform: "ios") {
                if !context.contentConfig.sensitiveContentEnabled, context.contentConfig.canAdjustSensitiveContent {
                    let need_verification = context.appConfiguration.getBoolValue("need_age_video_verification", orElse: false)
                    
                    if need_verification {
                        let controller = chatNavigationChild() {
                            VerifyAgeAlertController(context: context)
                        }
                        showModal(with: controller, for: context.window)
                        return
                    }
                }
                if context.contentConfig.sensitiveContentEnabled {
                    checkNext(peer)
                } else {
                    let consent = ChatNavigationConsent()
                    verifyAlert(for: context.window, header: strings().chatSensitiveContent, information: strings().chatSensitiveContentConfirm, ok: strings().chatSensitiveContentConfirmOk, option: context.contentConfig.canAdjustSensitiveContent ? strings().chatSensitiveContentConfirmThird : nil, optionIsSelected: false, successHandler: { result in
                        consent.resolve {
                            if result == .thrid {
                                let _ = updateRemoteContentSettingsConfiguration(postbox: context.account.postbox, network: context.account.network, sensitiveContentEnabled: true).start()
                            }
                            checkNext(peer)
                        }
                    }, cancelHandler: {
                        consent.resolve {}
                    }, onDeinit: {
                        consent.dismissed()
                    })
                }
            } else {
                checkNext(peer)
            }
        }
    })
}

private func chatNavigationChild<T: ViewController>( create: () -> T) -> T {
    return create()
}

private final class ChatNavigationConsent {

    private var resolved = false
    private var dismissalScheduled = false


    func resolve(_ action: () -> Void) {
        guard !resolved else { return }
        resolved = true
        action()
    }

    func dismissed() {
        guard !dismissalScheduled else { return }
        dismissalScheduled = true
        DispatchQueue.main.async {
            self.resolved = true
        }
    }
}

private final class AuthModalController : ModalController {
    override var background: NSColor {
        return theme.colors.background
    }
    override var dynamicSize: Bool {
        return true
    }
    override var closable: Bool {
        return false
    }
    
    override func measure(size: NSSize) {
        self.modal?.resize(with: NSMakeSize(size.width, size.height), animated: false)
    }
}





final class UnauthorizedApplicationContext {
    let account: UnauthorizedAccount
    let rootController: MajorNavigationController
    let window:Window
    let modal: ModalController
    let sharedContext: SharedAccountContext
    
    private let updatesDisposable: DisposableSet = DisposableSet()
    private let authController: AuthController
    
    var rootView: NSView {
        return rootController.view
    }
    
    
    init(window:Window, sharedContext: SharedAccountContext, account: UnauthorizedAccount, otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)])) {

        
        window.maxSize = NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
        window.minSize = NSMakeSize(380, 550)
        
        updatesDisposable.add(managedAppConfigurationUpdates(accountManager: sharedContext.accountManager, network: account.network).start())
                        
        
        if window.frame.height < window.minSize.height || window.frame.width < window.minSize.width {
            window.setFrame(NSMakeRect(window.frame.minX, window.frame.minY, window.minSize.width, window.minSize.height), display: true)
            window.center()
        }


        self.authController = AuthController(account, sharedContext: sharedContext, otherAccountPhoneNumbers: otherAccountPhoneNumbers)
        self.account = account
        self.window = window
        self.sharedContext = sharedContext
        self.rootController = MajorNavigationController(AuthController.self, self.authController, window)
        rootController._frameRect = NSMakeRect(0, 0, window.frame.width, window.frame.height)

        self.modal = AuthModalController(rootController)
        rootController.alwaysAnimate = true

        account.shouldBeServiceTaskMaster.set(.single(.now))
        
    }
    
    func applyExternalLoginCode(_ code: String) {
        authController.applyExternalLoginCode(code)
    }
    
    deinit {
        account.shouldBeServiceTaskMaster.set(.single(.never))
        updatesDisposable.dispose()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    
}


enum ApplicationContextLaunchAction {
    case navigate(ViewController)
    case preferences
    case story(PeerId)
}


let leftSidebarWidth: CGFloat = 90

private final class ApplicationContainerView: View {
    fileprivate let splitView: SplitView
    fileprivate let backgroundView: BackgroundView

    required init(frame frameRect: NSRect) {
        splitView = SplitView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height))
        backgroundView = BackgroundView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height))
        backgroundView.useSharedAnimationPhase = false
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(splitView)
        autoresizingMask = [.width, .height]

        splitView.layer?.cornerRadius = 0
        splitView.backgroundColor = .clear
    }

    var backgroundMode: TableBackgroundMode {
        get { return backgroundView.backgroundMode }
        set { backgroundView.backgroundMode = newValue }
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        splitView.backgroundColor = .clear
        backgroundColor = .clear
    }

    private func matchSuperviewBounds() {
        guard let superview = self.superview else {
            return
        }
        if !NSEqualRects(self.frame, superview.bounds) {
            self.frame = superview.bounds
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        matchSuperviewBounds()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        matchSuperviewBounds()
        backgroundView.frame = bounds
        splitView.frame = bounds
    }
}

final class AuthorizedApplicationContext: NSObject, SplitViewDelegate {
    
        
    var rootView: View {
        return view
    }
    
    let context: AccountContext
    private let window:Window
    private let view:ApplicationContainerView
    private let leftController:MainViewController
    private let rightController:MajorNavigationController
    private let emptyController:EmptyChatViewController
    
    private var entertainment: EntertainmentViewController?
    private var entertainmentSidebar: EntertainmentSidebarController?

    private var leftSidebarController: LeftSidebarController?
    
    private let loggedOutDisposable = MetaDisposable()
    private let altTabPreloadDisposable = MetaDisposable()
    
    private let settingsDisposable = MetaDisposable()
    private let suggestedLocalizationDisposable = MetaDisposable()
    private let alertsDisposable = MetaDisposable()
    private let audioDisposable = MetaDisposable()
    private let termDisposable = MetaDisposable()
    private let someActionsDisposable = DisposableSet()
    private let clearReadNotifiesDisposable = MetaDisposable()
    private let appUpdateDisposable = MetaDisposable()
    private let updateFoldersDisposable = MetaDisposable()
    private let globalPeerDisposable = MetaDisposable()
    private let tonConnectPresentationDisposable = MetaDisposable()
    private let tonConnectOperationDisposable = MetaDisposable()
    private var tonConnectRequestId: String?
    private var tonConnectDismiss: (() -> Void)?
    private var tonConnectDiagnosticId: UUID?
    private var tonConnectClosing = false
    private var tonConnectCancelled = false
    private var tonConnectHolderStorage: Any?
    private var isInFullScreenTransition: Bool = false
    private var pendingApplyWindowChrome: Bool = false

    private var appliedChromeMode: Window.ChromeMode?
    private let _ready:Promise<Bool> = Promise()
    var ready: Signal<Bool, NoError> {
        return _ready.get() |> filter { $0 } |> take (1)
    }
    
    func applyNewTheme() {
        rightController.backgroundColor = .clear
        applyEffectiveBackgroundMode()
        view.updateLocalizationAndTheme(theme: theme)
    }

    /// The most recently pushed chat background mode (from the active ChatController).
    private var currentChatBackgroundMode: TableBackgroundMode?
    /// Whether a chat is currently selected (driven by `globalPeerHandler`). When
    /// false, the chat-specific background is ignored and we fall back to the
    /// global theme background — even if a ChatController is still on the
    /// navigation stack underneath some other pushed controller (PeerInfo etc).
    private var hasSelectedChatPeer: Bool = false

    /// Called by ChatController to push its effective background up to the
    /// window-level BackgroundView. The push is REMEMBERED but only takes effect
    /// while a chat is selected (`hasSelectedChatPeer == true`).
    func setGlobalBackgroundMode(_ mode: TableBackgroundMode?) {
        currentChatBackgroundMode = mode
        applyEffectiveBackgroundMode()
    }

    private func applyEffectiveBackgroundMode() {
        if hasSelectedChatPeer, let mode = currentChatBackgroundMode {
            view.backgroundMode = mode
        } else {
            view.backgroundMode = theme.controllerBackgroundMode
        }
    }
    
    @available(macOS 10.15, *)
    private final class TonConnectHolder {
        var completion: ((Result<Void, WalletContext.WalletError>) -> Void)?
        var latestState: WalletContext.TonConnectState?
        var returnTarget: WalletContext.TonConnectReturn?
    }

    @available(macOS 10.15, *)
    private var tonConnectHolder: TonConnectHolder {
        if let existing = self.tonConnectHolderStorage as? TonConnectHolder {
            return existing
        }
        let holder = TonConnectHolder()
        self.tonConnectHolderStorage = holder
        return holder
    }

    private var launchAction: ApplicationContextLaunchAction?
    
    init(window: Window, context: AccountContext, launchSettings: LaunchSettings, callSession: PCallSession?, groupCallContext: GroupCallContext?, inlinePlayerContext: InlineAudioPlayerView.ContextObject?, folders: ChatListFolders?) {
        
        self.context = context
        emptyController = EmptyChatViewController(context)
        
        self.window = window
        
        if !window.initFromSaver {
            window.setFrame(NSMakeRect(0, 0, 800, 650), display: true)
            window.center()
        }
        
        window.maxSize = NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
        window.minSize = NSMakeSize(380, 550)

        
        context.account.importableContacts.set(.single([:]))
        
        self.view = ApplicationContainerView(frame: window.contentView!.bounds)
        
      
        self.view.splitView.setProportion(proportion: SplitProportion(min:300+350, max:300+350+600), state: .dual)
        
        
        
        rightController = MajorNavigationController(ChatController.self, emptyController, context.window);
        rightController.set(header: NavigationHeader(52, initializer: { header, contextObject, view -> (NavigationHeaderView, CGFloat) in
            let newView = view ?? InlineAudioPlayerView(header)
            newView.update(with: contextObject)
            return (newView, 52)
        }))
        
        
        rightController.set(callHeader: CallNavigationHeader(47, initializer: { header, contextObject, view -> (NavigationHeaderView, CGFloat) in
            let newView: NavigationHeaderView
            if contextObject is GroupCallContext {
                if let view = view, view.className == GroupCallNavigationHeaderView.className() {
                    newView = view
                } else {
                    newView = GroupCallNavigationHeaderView(header)
                }
            } else if contextObject is PCallSession {
                if let view = view, view.className == CallNavigationHeaderView.className() {
                    newView = view
                } else {
                    newView = CallNavigationHeaderView(header)
                }
            } else {
                fatalError("not supported")
            }
            newView.update(with: contextObject)
            return (newView, 47)
        }))
        
        window.rootViewController = rightController
        
        leftController = MainViewController(context);

                
        
        super.init()
        

                
        context.bindings = AccountContextBindings(rootNavigation: { [weak self] () -> MajorNavigationController in
            guard let `self` = self else {
                return MajorNavigationController(ViewController.self, ViewController(), window)
            }
            return self.rightController
        }, mainController: { [weak self] () -> MainViewController in
            guard let `self` = self else {
                fatalError("Cannot use bindings. Application context is not exists")
            }
            return self.leftController
        }, globalSearch: { [weak self] search, peerId, cached in
            guard let `self` = self else {
                fatalError("Cannot use bindings. Application context is not exists")
            }
            self.leftController.tabController.select(index: self.leftController.chatIndex)
            self.leftController.globalSearch(search, peerId: peerId, cached: cached)
        }, entertainment: { [weak self, weak context] () -> EntertainmentViewController in
            guard let context = context else {
                fatalError("Cannot use bindings. Account context is not exists")
            }
            guard let `self` = self else {
                return EntertainmentViewController.init(size: NSZeroSize, context: context)
            }
            if self.entertainment == nil {
                self.entertainment = EntertainmentViewController(size: NSMakeSize(350, 350), context: self.context)
            }
            return self.entertainment!
        }, switchSplitLayout: { [weak self] state in
            guard let `self` = self else {
                fatalError("Cannot use bindings. Application context is not exists")
            }
            self.view.splitView.state = state
        }, needFullsize: { [weak self] in
            self?.view.splitView.needFullsize()
        }, displayUpgradeProgress: { progress in

        })

        context.bindings.setGlobalBackgroundMode = { [weak self] mode in
            self?.setGlobalBackgroundMode(mode)
        }
        context.bindings.doGlobalBackgroundAction = { [weak self] in
            self?.view.backgroundView.doAction()
        }

        // Track the currently selected chat peer. The window-level background
        // follows the chat's wallpaper while a chat is selected and reverts to
        // the global theme background when the user leaves the chat (chat list,
        // empty controller, contacts, etc.). Pushing PeerInfo *on top* of a chat
        // does NOT reset globalPeerHandler, so the chat wallpaper persists.
        globalPeerDisposable.set((context.globalPeerHandler.get() |> deliverOnMainQueue).start(next: { [weak self] location in
            guard let self else { return }
            self.hasSelectedChatPeer = location != nil
            if !self.hasSelectedChatPeer {
                self.currentChatBackgroundMode = nil
            }
            self.applyEffectiveBackgroundMode()
            self.updateEntertainmentSidebar()
        }))

        termDisposable.set((context.account.stateManager.termsOfServiceUpdate |> deliverOnMainQueue).start(next: { terms in
            if let terms = terms {
                showModal(with: TermsModalController(context, terms: terms), for: context.window)
            } else {
                closeModal(TermsModalController.self)
            }
        }))
        
        closeAllPopovers(for: context.window)
        closeAllModals(window: context.window)
        AppMenu.closeAll()

        if #available(macOS 10.15, *), let walletContext = context.walletContext {
            tonConnectPresentationDisposable.set((walletContext.tonConnectState
            |> deliverOnMainQueue).start(next: { [weak self] state in
                self?.handleTonConnectState(state, walletContext: walletContext)
            }))
        }
      
       // var forceNotice:Bool = false
        if FastSettings.isMinimisize {
            self.view.splitView.mustMinimisize = true
           // forceNotice = true
        } else {
            self.view.splitView.mustMinimisize = false
        }

        rightController.empty = emptyController

        self.view.splitView.delegate = self
        self.view.splitView.update(false)

        NotificationCenter.default.addObserver(self, selector: #selector(handleFullScreenWillChange(_:)), name: NSWindow.willEnterFullScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFullScreenWillChange(_:)), name: NSWindow.willExitFullScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFullScreenDidChange(_:)), name: NSWindow.didEnterFullScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFullScreenDidChange(_:)), name: NSWindow.didExitFullScreenNotification, object: window)

        let accountId = context.account.id
        self.loggedOutDisposable.set(context.account.loggedOut.start(next: { value in
            if value {
                let _ = logoutFromAccount(id: accountId, accountManager: context.sharedContext.accountManager, alreadyLoggedOutRemotely: false).start()
                FastSettings.clear_uuid(context.account.id.int64)
                BrowserStateContext.cleanup(context.account.id)
                closePipVideo(accountId: accountId)
                if let groupCall = context.sharedContext.getCrossAccountGroupCall(), groupCall.call.account.id == accountId {
                    _ = context.sharedContext.endGroupCall(terminate: false).start()
                }
                Queue.mainQueue().async {
                    if let session = context.sharedContext.getCrossAccountCallSession(), session.account.id == accountId {
                        session.hangUpCurrentCall()
                    }
                }
            }
        }))
        
        
        alertsDisposable.set((context.account.stateManager.displayAlerts |> deliverOnMainQueue).start(next: { alerts in
            for text in alerts {
                
                let alert:NSAlert = NSAlert()
                alert.window.appearance = theme.appearance
                alert.alertStyle = .informational
                alert.messageText = appName
                alert.informativeText = text.text

                if text.isDropAuth {
                    alert.addButton(withTitle: strings().editAccountLogout)
                    alert.addButton(withTitle: strings().modalCancel)

                }

                alert.beginSheetModal(for: window, completionHandler: { result in
                    if result.rawValue == 1000 && text.isDropAuth {
                        let _ = logoutFromAccount(id: context.account.id, accountManager: context.sharedContext.accountManager, alreadyLoggedOutRemotely: false).start()
                    }
                })
            }
        }))
        

        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.rightController.push(ChatController(context: context, chatLocation: .peer(context.peerId)))
            return .invoked
        }, with: self, for: .Zero, priority: .low, modifierFlags: [.command])
        
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(0, false)
            return .invoked
        }, with: self, for: .One, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(1, false)
            return .invoked
            }, with: self, for: .Two, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(2, false)
            return .invoked
        }, with: self, for: .Three, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(3, false)
            return .invoked
        }, with: self, for: .Four, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(4, false)
            return .invoked
        }, with: self, for: .Five, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(5, false)
            return .invoked
        }, with: self, for: .Six, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(6, false)
            return .invoked
        }, with: self, for: .Seven, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(7, false)
            return .invoked
        }, with: self, for: .Eight, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(8, false)
            return .invoked
        }, with: self, for: .Nine, priority: .low, modifierFlags: [.command])
        
        window.set(handler: { _ -> KeyHandlerResult in
            
            
            appDelegate?.sharedApplicationContextValue?.notificationManager.updatePasslock(context.sharedContext.accountManager.transaction { transaction -> Bool in
                switch transaction.getAccessChallengeData() {
                case .none:
                    return false
                default:
                    return true
                }
            })
            
            let hasPasscode = context.sharedContext.accountManager.transaction { $0.getAccessChallengeData() != .none } |> deliverOnMainQueue
            
            _ = hasPasscode.startStandalone(next: { value in
                if !value {
                    context.bindings.rootNavigation().push(PasscodeSettingsViewController(context))
                }
            })
                        
            return .invoked
        }, with: self, for: .L, priority: .supreme, modifierFlags: [.command])

    

        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(0, true)
            return .invoked
        }, with: self, for: .One, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(1, true)
            return .invoked
        }, with: self, for: .Two, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(2, true)
            return .invoked
        }, with: self, for: .Three, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(3, true)
            return .invoked
        }, with: self, for: .Four, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(4, true)
            return .invoked
        }, with: self, for: .Five, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(5, true)
            return .invoked
        }, with: self, for: .Six, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(6, true)
            return .invoked
        }, with: self, for: .Seven, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(7, true)
            return .invoked
        }, with: self, for: .Eight, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(8, true)
            return .invoked
        }, with: self, for: .Nine, priority: .low, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.openChat(9, true)
            return .invoked
        }, with: self, for: .Minus, priority: .low, modifierFlags: [.command, .option])
        
    
        
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(1, true)
            return .invoked
        }, with: self, for: .One, priority: .low, modifierFlags: [.control])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(2, true)
            return .invoked
        }, with: self, for: .Two, priority: .low, modifierFlags: [.control])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(3, true)
            return .invoked
        }, with: self, for: .Three, priority: .low, modifierFlags: [.control])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(4, true)
            return .invoked
        }, with: self, for: .Four, priority: .low, modifierFlags: [.control])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(5, true)
            return .invoked
        }, with: self, for: .Five, priority: .low, modifierFlags: [.control])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(6, true)
            return .invoked
        }, with: self, for: .Six, priority: .low, modifierFlags: [.control])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(7, true)
            return .invoked
        }, with: self, for: .Seven, priority: .low, modifierFlags: [.control])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(8, true)
            return .invoked
        }, with: self, for: .Eight, priority: .low, modifierFlags: [.control])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.switchAccount(9, true)
            return .invoked
        }, with: self, for: .Nine, priority: .low, modifierFlags: [.control])
              
        self.context.window.set(handler: { _ -> KeyHandlerResult in
                        
            showModal(with: QuickSwitcherModalController(context, source: .accounts), for: window)
            
            return .invoked
        }, with: self, for: .M, priority: .supreme, modifierFlags: [.shift, .command])

        // Alt-Tab style switcher (Ctrl+Tab / Ctrl+Shift+Tab)
        weak var altTabController: AltTabSwitcherController? = nil
        var altTabData: AltTabSwitcherData? = nil

        altTabPreloadDisposable.set(
            (preloadAltTabSwitcherData(context: context)
                |> deliverOnMainQueue
            ).start(next: { data in
                altTabData = data
            })
        )

        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard self != nil else { return .rejected }

            if let existing = altTabController, existing.isLoaded() {
                existing.selectNext()
                return .invoked
            }

            guard let data = altTabData, !data.isEmpty else {
                return .rejected
            }

            altTabController = showAltTabSwitcher(context: context, data: data, window: window)
            return .invoked
        }, with: self, for: .Tab, priority: .supreme, modifierFlags: [.control])

        self.context.window.set(handler: { _ -> KeyHandlerResult in
            if let existing = altTabController, existing.isLoaded() {
                existing.selectPrevious()
                return .invoked
            }
            return .rejected
        }, with: self, for: .Tab, priority: .supreme, modifierFlags: [.control, .shift])


        #if DEBUG


        self.context.window.set(handler: { _ -> KeyHandlerResult in
            

            return .invoked
        }, with: self, for: .Y, priority: .supreme, modifierFlags: [.command])


        #endif
        
        
//        window.set(handler: { [weak self] _ -> KeyHandlerResult in
//            self?.leftController.focusSearch(animated: true)
//            return .invoked
//        }, with: self, for: .F, priority: .supreme, modifierFlags: [.command, .shift])
        
        window.set(handler: { _ -> KeyHandlerResult in
            context.bindings.rootNavigation().push(ShortcutListController(context: context))
            return .invoked
        }, with: self, for: .Slash, priority: .low, modifierFlags: [.command])
        
      
        
        appUpdateDisposable.set((context.account.stateManager.appUpdateInfo |> deliverOnMainQueue).start(next: { info in
            
        }))
        
        
        suggestedLocalizationDisposable.set(( context.account.postbox.preferencesView(keys: [PreferencesKeys.suggestedLocalization]) |> mapToSignal { preferences -> Signal<SuggestedLocalizationInfo, NoError> in
            
            let preferences = preferences.values[PreferencesKeys.suggestedLocalization]?.get(SuggestedLocalizationEntry.self)
            if preferences == nil || !preferences!.isSeen, preferences?.languageCode != appCurrentLanguage.languageCode, preferences?.languageCode != "en" {
                let current = Locale.preferredLanguages[0]
                let split = current.split(separator: "-")
                let lan: String = !split.isEmpty ? String(split[0]) : "en"
                if lan != "en" {
                    return context.engine.localization.suggestedLocalizationInfo(languageCode: lan, extractKeys: ["Suggest.Localization.Header", "Suggest.Localization.Other"]) |> take(1)
                }
            }
            return .complete()
        } |> deliverOnMainQueue).start(next: { suggestionInfo in
            if suggestionInfo.availableLocalizations.count >= 2 {
                showModal(with: SuggestionLocalizationViewController(context, suggestionInfo: suggestionInfo), for: window)
            }
        }))
        

        someActionsDisposable.add(context.engine.peers.managedUpdatedRecentPeers().start())
        
                
        clearReadNotifiesDisposable.set(context.account.stateManager.appliedIncomingReadMessages.start(next: { msgIds in
            UNUserNotifications.current?.clearNotifies(by: msgIds)
        }))
        

        
        someActionsDisposable.add(applyUpdateTextIfNeeded(context.account.postbox).start())
        
        if let folders = folders {
            self.updateLeftSidebar(with: folders, layout: context.layout, animated: false)
        }
        
        
        self.view.splitView.layout()

        
   
        
        if let navigation = launchSettings.navigation {
            switch navigation {
            case .settings:
                self.launchAction = .preferences
                _ready.set(leftController.settings.ready.get())
                leftController.tabController.select(index: leftController.settingsIndex)
            case let .profile(peer, necessary):
                
                _ready.set(leftController.chatList.ready.get())
                self.leftController.tabController.select(index: self.leftController.chatIndex)

                if (necessary || context.layout != .single) {
                    let controller = PeerInfoController(context: context, peer: peer._asPeer())
                    controller.navigationController = self.rightController
                    controller.loadViewIfNeeded(self.rightController.bounds)

                    self.launchAction = .navigate(controller)

                    self._ready.set(combineLatest(self.leftController.chatList.ready.get(), controller.ready.get()) |> map { $0 && $1 })
                    self.leftController.tabController.select(index: self.leftController.chatIndex)
                } else {
                    _ready.set(leftController.chatList.ready.get())
                    self.leftController.tabController.select(index: self.leftController.chatIndex)
                }
            case let .chat(peerId, necessary):
                
                _ready.set(leftController.chatList.ready.get())
                self.leftController.tabController.select(index: self.leftController.chatIndex)
                
                if (necessary || context.layout != .single) {
                    let controller = ChatController(context: context, chatLocation: .peer(peerId))
                    controller.navigationController = self.rightController
                    controller.loadViewIfNeeded(self.rightController.bounds)

                    self.launchAction = .navigate(controller)

                    self._ready.set(combineLatest(self.leftController.chatList.ready.get(), controller.ready.get()) |> map { $0 && $1 })
                    self.leftController.tabController.select(index: self.leftController.chatIndex)
                } else {
                   // self._ready.set(.single(true))
                    _ready.set(leftController.chatList.ready.get())
                    self.leftController.tabController.select(index: self.leftController.chatIndex)
                }
            case let .story(peerId):
                self.launchAction = .story(peerId)
                _ready.set(leftController.chatList.ready.get())
                self.leftController.tabController.select(index: self.leftController.chatIndex)
            case let .thread(threadId, fromId, threadData, _):
                self.leftController.tabController.select(index: self.leftController.chatIndex)
                self._ready.set(self.leftController.chatList.ready.get())
                
                if let fromId = fromId {
                    context.navigateToThread(threadId, fromId: fromId)
                } else if let _ = threadData {
                    _ = (ForumUI.openTopic(Int64(threadId.id), peerId: threadId.peerId, context: context) |> take(1)).start()
                }
            }
        } else {
           // self._ready.set(.single(true))
            _ready.set(leftController.chatList.ready.get())
            leftController.tabController.select(index: leftController.chatIndex)
          //  _ready.set(leftController.ready.get())
        }
        
        if let session = callSession {
            rightController.callHeader?.show(true, contextObject: session)
        }
        
        if let groupCallContext = groupCallContext {
            rightController.callHeader?.show(true, contextObject: groupCallContext)
        }
        if let inlinePlayerContext = inlinePlayerContext {
            rightController.header?.show(true, contextObject: inlinePlayerContext)
        }
        self.updateFoldersDisposable.set(combineLatest(queue: .mainQueue(), chatListFilterPreferences(engine: context.engine), context.layoutValue).start(next: { [weak self] value, layout in
            self?.updateLeftSidebar(with: value, layout: layout, animated: true)
        }))
        
       // _ready.set(.single(true))
    }
    
    private var folders: ChatListFolders?
    private var previousLayout: SplitViewState?
    private let foldersReadyDisposable = MetaDisposable()
    private func updateLeftSidebar(with folders: ChatListFolders, layout: SplitViewState, animated: Bool) -> Void {
        
        if self.window is AppWindow {
            if (folders.sidebar && !folders.isEmpty) || layout == .minimisize {
                self.context.bindings.rootNavigation().navigationBarLeftPosition = 0
            } else {
                self.context.bindings.rootNavigation().navigationBarLeftPosition = layout == .single ? Window.controlsInset : 0
            }
        }

                
        let currentSidebar = !folders.isEmpty && (folders.sidebar)
        let previousSidebar = self.folders == nil ? nil : !self.folders!.isEmpty && (self.folders!.sidebar)

        let readySignal: Signal<Bool, NoError>
        
        if currentSidebar != previousSidebar {
            self.view.splitView.collapseToSingle = true
            if !currentSidebar {
                if let existing = leftSidebarController {
                    self.view.splitView.removeController(controller: existing)
                }
                leftSidebarController = nil
                readySignal = .single(true)
            } else {
                let controller = LeftSidebarController(context, filterData: leftController.chatList.filterSignal, updateFilter: leftController.chatList.updateFilter)
                controller._frameRect = NSMakeRect(0, 0, leftSidebarWidth, window.frame.height)
                controller.loadViewIfNeeded()
                self.leftSidebarController = controller
                readySignal = controller.ready.get() |> take(1)
            }
            let enlarge: CGFloat

            if currentSidebar && previousSidebar != nil {
                enlarge = leftSidebarWidth
            } else {
                if previousSidebar == true {
                    enlarge = -leftSidebarWidth
                } else {
                    enlarge = 0
                }
            }

            foldersReadyDisposable.set(readySignal.start(next: { [weak self] _ in
                guard let `self` = self else {
                    return
                }
                if let sidebar = self.leftSidebarController, sidebar.view.superview !== self.view.splitView {
                    self.view.splitView.insertController(controller: sidebar, proportion: SplitProportion(min: leftSidebarWidth, max: leftSidebarWidth), at: 0)
                    self.view.splitView.setFixed(controller: sidebar, fixed: true)
                }
                self.view.splitView.needsLayout = true
                if !self.window.isFullScreen, let screen = self.window.screen {
                    self.window.setFrame(NSMakeRect(max(0, self.window.frame.minX - enlarge), self.window.frame.minY, min(self.window.frame.width + enlarge, screen.frame.width), self.window.frame.height), display: true, animate: false)
                }
                self.updateMinMaxWindowSize(animated: animated)
            }))


        }
        let sidebarChanged = currentSidebar != previousSidebar
        self.folders = folders
        self.previousLayout = layout
        if sidebarChanged {
            applyWindowChrome(forState: self.view.splitView.state)
        }
    }
    
    
    func updateEntertainmentSidebar(animated: Bool = false) {
        if FastSettings.sidebarEnabled && FastSettings.sidebarShown && hasSelectedChatPeer {
            if animated {
                self.view.layoutSubtreeIfNeeded()
                let additionalWidth = self.view.splitView.additionalWidthForTrailing(width: EntertainmentSidebarController.paneWidth, minimumLeadingWidth: 380)
                if additionalWidth > 0, !self.window.isFullScreen, let visibleFrame = self.window.screen?.visibleFrame {
                    var frame = self.window.frame
                    frame.size.width = min(visibleFrame.width, frame.width + additionalWidth)
                    frame.origin.x = max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - frame.width))
                    self.window.setFrame(frame, display: true, animate: true)
                    self.view.layoutSubtreeIfNeeded()
                }
            }
            let controller: EntertainmentSidebarController
            if let current = self.entertainmentSidebar {
                controller = current
            } else {
                controller = EntertainmentSidebarController(context: context, entertainment: context.bindings.entertainmentViewController, isChat: { $0 is ChatController })
                controller.availabilityUpdated = { [weak self] in
                    self?.updateEntertainmentSidebar()
                }
                self.entertainmentSidebar = controller
            }
            if controller.canShow {
                self.view.splitView.setTrailing(controller: controller, width: EntertainmentSidebarController.paneWidth, minimumLeadingWidth: 380, animated: animated)
            } else {
                self.view.splitView.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0, animated: animated)
            }
        } else {
            self.view.splitView.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0, animated: animated)
        }
    }

    func isEntertainmentSidebarAvailable(in window: NSWindow?) -> Bool {
        guard window === self.window else {
            return false
        }
        self.view.layoutSubtreeIfNeeded()
        let additionalWidth = self.view.splitView.additionalWidthForTrailing(width: EntertainmentSidebarController.paneWidth, minimumLeadingWidth: 380)
        return additionalWidth == 0 || (!self.window.isFullScreen && self.window.frame.width + additionalWidth <= (self.window.screen?.visibleFrame.width ?? 0))
    }

    func isEntertainmentSidebarVisible(in window: NSWindow?) -> Bool {
        guard window === self.window, let controller = self.entertainmentSidebar, controller.isLoaded() else {
            return false
        }
        return controller.view.window === window && !controller.view.visibleRect.isEmpty
    }

    private func updateMinMaxWindowSize(animated: Bool) {
        var width: CGFloat = 380
        if leftSidebarController != nil {
            width += leftSidebarWidth
        }
        if context.layout == .minimisize {
            width += 70
        }
        window.minSize = NSMakeSize(width, 550)
        
        if window.frame.width < window.minSize.width {
            window.setFrame(NSMakeRect(max(0, window.frame.minX - (window.minSize.width - window.frame.width)), window.frame.minY, window.minSize.width, window.frame.height), display: true, animate: false)
        }
    }
    

    
    func runLaunchAction() {
        if let launchAction = launchAction {
            switch launchAction {
            case let .navigate(controller):
                leftController.tabController.select(index: leftController.chatIndex)
                context.bindings.rootNavigation().push(controller, context.layout == .single)
            case .preferences:
                leftController.tabController.select(index: leftController.settingsIndex)
            case let .story(peerId):
                leftController.tabController.select(index: leftController.chatIndex)
                StoryModalController.ShowStories(context: context, isHidden: false, initialId: StoryInitialIndex(peerId: peerId, id: nil, messageId: nil, takeControl: nil), singlePeer: true)
            }
            self.launchAction = nil
        } else {
            leftController.tabController.select(index: leftController.chatIndex)
        }
        Queue.mainQueue().justDispatch { [weak self] in
            self?.leftController.prepareControllers()
        }
    }
    
    private func openChat(_ index: Int, _ force: Bool = false) {
        leftController.openChat(index, force: force)
    }
    
    private func switchAccount(_ index: Int, _ force: Bool = false) {
        
        let accounts = context.sharedContext.activeAccounts |> take(1) |> deliverOnMainQueue
        let context = self.context
        _ = accounts.start(next: { accounts in
            let account = accounts.accounts[min(index - 1, accounts.accounts.count - 1)]
            context.sharedContext.switchToAccount(id: account.0, action: nil)
        })
    }
    
    func splitResizeCursor(at point: NSPoint) -> NSCursor? {
        if FastSettings.isMinimisize {
            return NSCursor.resizeRight
        } else {
            if window.frame.width - point.x <= 380 {
                return NSCursor.resizeLeft
            }
            return NSCursor.resizeLeftRight
        }
    }

    func splitViewShouldResize(at point: NSPoint) {
        if !FastSettings.isMinimisize {
            let fixedLeading = self.view.splitView.fixedLeadingWidth
            let max_w = window.frame.width - 380 - fixedLeading
            let adjustedX = point.x - fixedLeading
            let result = round(min(max(adjustedX, 300), max_w))
            FastSettings.updateLeftColumnWidth(result)
            self.view.splitView.updateStartSize(size: NSMakeSize(result, result), controller: leftController)
        }

    }
    

    
    func splitViewDidNeedSwapToLayout(state: SplitViewState) {
        let previousState = self.view.splitView.state
        let w: CGFloat = FastSettings.leftColumnWidth
        let rightProp = SplitProportion(min: 380, max: CGFloat.greatestFiniteMagnitude)

        if self.view.splitView.contains(controller: leftController) {
            self.view.splitView.removeController(controller: leftController)
        }
        if self.view.splitView.contains(controller: rightController) {
            self.view.splitView.removeController(controller: rightController)
        }

        FastSettings.isMinimisize = false
        self.view.splitView.mustMinimisize = false

        switch state {
        case .single:
            let hasLeftSidebar = !(folders?.isEmpty ?? true) && (folders?.sidebar ?? false)
            leftController.insets = hasLeftSidebar
                ? NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
                : NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

            if rightController.stackCount == 1, previousState != .none {
                leftController.viewWillAppear(false)
            }
            let fixedCount = self.view.splitView.fixedControllerCount
            self.view.splitView.insertController(controller: rightController, proportion: rightProp, at: fixedCount)
            rightController.empty = leftController
            if rightController.stackCount == 1, previousState != .none {
                leftController.viewDidAppear(false)
            }
        case .dual:
            rightController.empty = emptyController
            leftController.insets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 0)
            let fixedCount = self.view.splitView.fixedControllerCount
            self.view.splitView.insertController(controller: leftController, proportion: SplitProportion(min: w, max: w), at: fixedCount)
            self.view.splitView.insertController(controller: rightController, proportion: rightProp, at: fixedCount + 1)
        case .minimisize:
            if !self.view.splitView.isAutoMinimisize {
                FastSettings.isMinimisize = true
                self.view.splitView.mustMinimisize = true
            }
            rightController.empty = emptyController
            leftController.insets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 0)
            let fixedCount = self.view.splitView.fixedControllerCount
            self.view.splitView.insertController(controller: leftController, proportion: SplitProportion(min: 90, max: 90), at: fixedCount)
            self.view.splitView.insertController(controller: rightController, proportion: rightProp, at: fixedCount + 1)
        default:
            break
        }

        updateMinMaxWindowSize(animated: false)
        context.layout = state
        applyWindowChrome(forState: state)
    }
    

    
    func splitViewDidNeedMinimisize(controller: ViewController) {
        
    }

    @available(macOS 10.15, *)
    private func handleTonConnectState(_ state: WalletContext.TonConnectState, walletContext: WalletContext) {
        let isWalletAvailable = WalletConfiguration.with(appConfiguration: self.context.appConfiguration).isAvailable
        self.tonConnectHolder.latestState = state
        if isWalletAvailable, state.presentationEnabled, let diagnostic = state.diagnostic, self.tonConnectDiagnosticId != diagnostic.id {
            self.tonConnectDiagnosticId = diagnostic.id
            if let requestId = diagnostic.requestId {
                let data = ModalAlertData(title: nil, info: diagnostic.failure.message, ok: strings().walletTonConnectRetry, mode: .confirm(text: strings().alertCancel, isThird: false))
                showModalAlert(for: self.window, data: data, completion: { [weak walletContext] _ in
                    walletContext?.retryTonConnectRequest(id: requestId)
                }, cancel: { [weak walletContext] in
                    walletContext?.closeTonConnectPresentation(id: requestId)
                })
            } else {
                alert(for: self.window, header: nil, info: diagnostic.failure.message)
            }
        }
        guard state.presentationEnabled, let active = state.active else {
            self.dismissTonConnectController(walletContext: walletContext)
            return
        }
        if self.tonConnectClosing {
            return
        }
        if let previousId = self.tonConnectRequestId, previousId != active.id {
            self.dismissTonConnectController(walletContext: walletContext)
            return
        }
        guard isWalletAvailable || self.tonConnectRequestId == active.id else {
            return
        }
        switch active.status {
        case .ready:
            guard self.tonConnectRequestId == nil else {
                return
            }
            let subject: WalletTonConnectSubject
            switch active.content {
            case let .connect(request): subject = .connection(request)
            case let .operation(request): subject = .operation(request)
            case let .signData(request):
                subject = .operation(WalletContext.TonConnectOperationRequest(
                    id: request.id,
                    applicationName: request.applicationName,
                    domain: request.domain,
                    icon: request.icon,
                    method: .signData,
                    messages: [],
                    feeNanograms: nil,
                    validUntil: nil,
                    relayerWillSubmit: false,
                    needsWalletStateInit: false,
                    warnings: [],
                    actions: [],
                    signData: request
                ))
            }
            self.tonConnectRequestId = active.id
            self.tonConnectCancelled = false
            let result = WalletTonConnectController(context: self.context, walletContext: walletContext, subject: subject, approve: { [weak self, weak walletContext] completion in
                guard let self, let walletContext, self.tonConnectRequestId == active.id else {
                    completion(.failure(.unavailable))
                    return
                }
                self.tonConnectHolder.completion = completion
                let signal = walletContext.decideTonConnectRequest(id: active.id, approve: true)
                self.tonConnectOperationDisposable.set((signal |> deliverOnMainQueue).start(error: { [weak self] error in
                    guard let self, self.tonConnectRequestId == active.id else {
                        return
                    }
                    let completion = self.tonConnectHolder.completion
                    self.tonConnectHolder.completion = nil
                    completion?(.failure(error))
                }))
            }, cancelled: { [weak self] in
                guard let self, self.tonConnectRequestId == active.id else {
                    return
                }
                self.tonConnectCancelled = true
            }, closed: { [weak self, weak walletContext] in
                guard let self, let walletContext else {
                    return
                }
                self.tonConnectControllerClosed(id: active.id, walletContext: walletContext)
            })
            self.tonConnectDismiss = result.1
            showModal(with: result.0, for: self.window)
        case .processing:
            break
        case let .completed(decision):
            guard self.tonConnectRequestId == active.id else {
                walletContext.closeTonConnectPresentation(id: active.id)
                return
            }
            if decision.approved, let completion = self.tonConnectHolder.completion {
                self.tonConnectHolder.completion = nil
                self.tonConnectClosing = true
                self.tonConnectHolder.returnTarget = decision.returnTarget
                completion(.success(Void()))
            } else {
                self.dismissTonConnectController(walletContext: walletContext)
            }
        case .invalidated:
            if self.tonConnectRequestId == active.id {
                self.dismissTonConnectController(walletContext: walletContext)
            } else {
                walletContext.closeTonConnectPresentation(id: active.id)
            }
        }
    }

    @available(macOS 10.15, *)
    private func dismissTonConnectController(walletContext: WalletContext) {
        guard !self.tonConnectClosing, let id = self.tonConnectRequestId else {
            return
        }
        self.tonConnectClosing = true
        self.tonConnectHolder.completion = nil
        self.tonConnectOperationDisposable.set(nil)
        if let dismiss = self.tonConnectDismiss {
            dismiss()
        } else {
            self.tonConnectControllerClosed(id: id, walletContext: walletContext)
        }
    }

    @available(macOS 10.15, *)
    private func tonConnectControllerClosed(id: String, walletContext: WalletContext) {
        guard self.tonConnectRequestId == id else {
            return
        }
        let rejected = self.tonConnectCancelled
        let target = self.tonConnectHolder.returnTarget
        self.tonConnectRequestId = nil
        self.tonConnectDismiss = nil
        self.tonConnectHolder.completion = nil
        self.tonConnectClosing = false
        self.tonConnectCancelled = false
        self.tonConnectHolder.returnTarget = nil
        self.tonConnectOperationDisposable.set(nil)
        if rejected {
            walletContext.rejectTonConnectRequest(id: id)
        }
        walletContext.closeTonConnectPresentation(id: id)
        if let latest = self.tonConnectHolder.latestState, let active = latest.active, active.id != id {
            self.handleTonConnectState(latest, walletContext: walletContext)
        }
        guard self.tonConnectRequestId == nil, let target else {
            return
        }
        switch target {
        case let .url(url):
            execute(inapp: .external(link: url, false), window: self.window)
        case .back, .none:
            break
        }
    }

    func splitViewDidNeedFullsize(controller: ViewController) {
        
    }
    
    func splitViewIsCanMinimisize() -> Bool {
        return self.leftController.isCanMinimisize();
    }
    
    func splitViewDrawBorder() -> Bool {
        return false
    }
    
    deinit {
        self.loggedOutDisposable.dispose()
        window.removeAllHandlers(for: self)
        altTabPreloadDisposable.dispose()
        settingsDisposable.dispose()
        suggestedLocalizationDisposable.dispose()
        audioDisposable.dispose()
        alertsDisposable.dispose()
        termDisposable.dispose()
        viewer?.close()
        someActionsDisposable.dispose()
        clearReadNotifiesDisposable.dispose()
        appUpdateDisposable.dispose()
        updateFoldersDisposable.dispose()
        foldersReadyDisposable.dispose()
        globalPeerDisposable.dispose()
        tonConnectPresentationDisposable.dispose()
        tonConnectDismiss?()
        context.cleanup()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleFullScreenWillChange(_ notification: Notification) {
        isInFullScreenTransition = true
    }

    @objc private func handleFullScreenDidChange(_ notification: Notification) {
        isInFullScreenTransition = false
        if pendingApplyWindowChrome {
            pendingApplyWindowChrome = false
            applyWindowChrome(forState: self.view.splitView.state)
        }
    }

    private func applyWindowChrome(forState state: SplitViewState) {
        if isInFullScreenTransition {
            pendingApplyWindowChrome = true
            return
        }
        let hasLeftSidebar = !(folders?.isEmpty ?? true) && (folders?.sidebar ?? false)
        let mode: Window.ChromeMode = (state == .single && !hasLeftSidebar) ? .compact : .standard
        if appliedChromeMode == mode {
            return
        }
        appliedChromeMode = mode
        leftController.genericView.compactCorners = (mode == .compact)
        window.applyChrome(mode)
        window.applyCornerRadius(for: mode)
        window.clampToScreen()
    }

}

extension Window {
    func applyCornerRadius(for mode: Window.ChromeMode) {
        if #available(macOS 27.0, *) {
            let selector = Selector(("_setCornerRadius:"))
            if self.responds(to: selector) {
                typealias SetCornerRadius = @convention(c) (AnyObject, Selector, Double) -> Void
                let radius: Double = mode == .standard ? 28 : 0
                unsafeBitCast(self.method(for: selector), to: SetCornerRadius.self)(self, selector, radius)
            }
        }
    }
}
