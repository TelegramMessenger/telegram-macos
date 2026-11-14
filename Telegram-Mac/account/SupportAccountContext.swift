import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import AppKit

final class SupportAccountContext {
    
    private class ExternalChat {
        
        struct Key: Hashable {
            let peerId: PeerId
            let accountId: AccountRecordId
        }
        
        let context: AccountContext
        let parentContext: AccountContext
        let navigation: MajorNavigationController
        let splitView: SplitView
        weak var forumSidebarOwner: ViewController?
        var entertainment: EntertainmentViewController?
        init(context: AccountContext, parentContext: AccountContext, navigation: MajorNavigationController, splitView: SplitView, entertainment: EntertainmentViewController? = nil) {
            self.context = context
            self.parentContext = parentContext
            self.navigation = navigation
            self.splitView = splitView
            self.entertainment = entertainment
        }
    }
    
    var didUpdate:([AccountRecordId])->Void = { _ in }
    
    private let applicationContext: SharedApplicationContext
    
    var accountIds: [AccountRecordId] {
        return contexts.map { $0.context.account.id }
    }
    
    private var contexts:[AuthorizedApplicationContext] = [] {
        didSet {
            self.didUpdate(contexts.map { $0.context.account.id })
        }
    }
    private var windows: [Window] = []
    init(applicationContext: SharedApplicationContext) {
        self.applicationContext = applicationContext
    }
    
    func find(_ id: AccountRecordId) -> AccountContext? {
        if let value = self.contexts.first(where: { $0.context.account.id == id }) {
            return value.context
        }
        return nil
    }
    
    private let disposable: DisposableDict<AccountRecordId> = DisposableDict()
    private let chatDisposable: DisposableDict<ExternalChat.Key> = DisposableDict()
    private let chatReadyDisposable: DisposableDict<ExternalChat.Key> = DisposableDict()

    
    private var externalChats: [ExternalChat.Key : ExternalChat] = [:]
    
    func getExternalContext(peerId: PeerId, accountId: AccountRecordId) -> AccountContext? {
        return self.externalChats[.init(peerId: peerId, accountId: accountId)]?.context
    }
    
    func openChat(peerId: PeerId, parent: AccountContext) {
        
        if let external = externalChats[.init(peerId: peerId, accountId: parent.account.id)] {
            external.navigation.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        
        let window: Window
        
        let frame = NSScreen.main?.frame ?? NSMakeRect(0, 0, 1920, 1080)
        
        window = Window(contentRect: frame.focus(NSMakeSize(500, 600)), styleMask: [.closable, .miniaturizable, .resizable, .titled], backing: .buffered, defer: true)
        window.minSize = NSMakeSize(400, 550)
        window.isReleasedWhenClosed = false
        

        let context = AccountContext(sharedContext: parent.sharedContext, window: window, account: parent.account, isSupport: false, isExternal: true)
        let accountId = context.account.id
        
        
        let out = context.account.loggedOut
        |> filter { $0 }
        |> take(1)
        |> deliverOnMainQueue
        
        self.chatDisposable.set(out.start(next: { [weak self] value in
            self?.close(peerId: peerId, accountId: accountId)
        }), forKey: .init(peerId: peerId, accountId: accountId))
        
        let chatController = ChatController(context: context, chatLocation: .peer(peerId))
        
        let navigation = MajorNavigationController(EmptyChatViewController.self, chatController, window)
        navigation.alwaysAnimate = true
        navigation._frameRect = window.contentView?.bounds ?? window.bounds
        
        context.bindings = AccountContextBindings(rootNavigation: { [weak navigation] () -> MajorNavigationController in
            guard let navigation else {
                fatalError()
            }
            return navigation
        }, mainController: { () -> MainViewController in
            return parent.bindings.mainViewController
        }, globalSearch: { search, peerId, cached in
            
        }, entertainment: { [weak self, weak context] () -> EntertainmentViewController in
            guard let context = context else {
                fatalError("Cannot use bindings. Account context is not exists")
            }
            guard let external = self?.externalChats[.init(peerId: peerId, accountId: parent.account.id)] else {
                return EntertainmentViewController.init(size: NSZeroSize, context: context)
            }
            if external.entertainment == nil {
                external.entertainment = EntertainmentViewController(size: NSMakeSize(350, 350), context: context)
            }
            return external.entertainment!
        }, switchSplitLayout: { _ in
           
        }, needFullsize: {
           
        }, displayUpgradeProgress: { _ in
                
        })
        
        telegramUpdateTheme(theme, window: window, animated: false)
        window.applyChrome(.compact)

        let splitView = SplitView(frame: window.contentView?.bounds ?? window.bounds)
        splitView.canChangeState = false
        splitView.autoresizingMask = [.width, .height]
        self.externalChats[.init(peerId: peerId, accountId: context.account.id)] = ExternalChat(context: context, parentContext: parent, navigation: navigation, splitView: splitView)
        window.contentView?.addSubview(splitView)
        splitView.addController(controller: navigation, proportion: SplitProportion(min: splitView.bounds.width, max: .greatestFiniteMagnitude))
        splitView.needsLayout = true
        splitView.layoutSubtreeIfNeeded()
        self.chatReadyDisposable.set(chatController.ready.get().start(next: { [weak window] _ in
            window?.makeKeyAndOrderFront(self)
        }), forKey: .init(peerId: peerId, accountId: accountId))
        
        window.closeInterceptor = { [weak self] in
            self?.close(peerId: peerId, accountId: accountId)
            return true
        }
        
        window.set(handler: { _ -> KeyHandlerResult in
            appDelegate?.sharedApplicationContextValue?.notificationManager.updatePasslock(parent.sharedContext.accountManager.transaction { transaction -> Bool in
                return transaction.getAccessChallengeData() != .none
            })
            return .invoked
        }, with: navigation, for: .L, priority: .supreme, modifierFlags: [.command])

        
        var toRemove:[ViewController] = []
        parent.bindings.rootNavigation().enumerateControllers({ controller, index in
            if let controller = controller as? ChatController {
                if controller.chatLocation.peerId == peerId {
                    toRemove.append(controller)
                }
            }
            return true
        })
        for remove in toRemove {
            parent.bindings.rootNavigation().removeImmediately(remove)
        }
        


    }
    
    func setForumSidebar(context: AccountContext, owner: ViewController, controller: ViewController?, open: Bool) {
        guard let external = externalChats.values.first(where: { $0.context === context }),
              external.navigation.controller === owner || external.forumSidebarOwner === owner else { return }
        external.forumSidebarOwner = controller == nil ? nil : owner
        let selected = external.navigation.controller === owner && open ? controller : nil
        external.splitView.setTrailing(controller: selected, width: selected == nil ? 0 : EntertainmentSidebarController.paneWidth, minimumLeadingWidth: selected == nil ? 0 : 380, animated: true, overlayWhenNarrow: true, navigationOwner: owner)
    }

    func open(account: Account) {
        let showTags = TelegramEngine(account: account).data.get(TelegramEngine.EngineData.Item.ChatList.FiltersDisplayTags())

        let data = combineLatest(TelegramEngine(account: account).peers.updatedChatListFilters(), chatListFolderSettings(account.postbox), showTags) |> map {
            return ChatListFolders(list: $0, sidebar: $1.sidebar, showTags: $2)
        }
        |> deliverOnMainQueue
        |> take(1)
        
        _ = data.start(next: { [self] folders in
            if let value = self.contexts.first(where: { $0.context.account.id == account.id }) {
                value.context.window.makeKeyAndOrderFront(nil)
                value.context.window.deminiaturize(nil)
                return
            }
            
            let sharedContext = self.applicationContext.sharedContext
            
            let window: Window
            if self.windows.isEmpty {
                window = Window(contentRect: NSMakeRect(0, 0, 400, 400), styleMask: [.closable, .miniaturizable, .resizable, .titled], backing: .buffered, defer: true)
                window.styleMask.insert(.fullSizeContentView)
                if System.liquidGlass, #available(macOS 26, *) {
                    let toolbar = NSToolbar(identifier: "window")
                    toolbar.allowsUserCustomization = false
                    toolbar.allowsDisplayModeCustomization = false
                    window.toolbar = toolbar
                }
                window.toolbar?.showsBaselineSeparator = false
                window.titlebarAppearsTransparent = true
                
                window.titleVisibility = .hidden

                window.isReleasedWhenClosed = false
                
                if !System.liquidGlass {
                    window.setTrafficLightsInset(NSPoint(x: 10, y: 6))
                }
            } else {
                window = self.windows.removeFirst()
            }
            
            let context = AccountContext(sharedContext: sharedContext, window: window, account: account, isSupport: true)
            let applicationContext = AuthorizedApplicationContext(window: window, context: context, launchSettings: LaunchSettings.defaultSettings, callSession: sharedContext.getCrossAccountCallSession(), groupCallContext: sharedContext.getCrossAccountGroupCall(), inlinePlayerContext: sharedContext.getCrossInlinePlayer(), folders: folders)

            let out = account.loggedOut
            |> filter { $0 }
            |> take(1)
            |> deliverOnMainQueue
            
            self.disposable.set(out.start(next: { [weak self] value in
                self?.close(account: account)
            }), forKey: account.id)
            
            window.contentView?.addSubview(applicationContext.rootView, positioned: .below, relativeTo: window.contentView?.subviews.first)
            _ = applicationContext.ready.start(next: { [weak window] _ in
                window?.makeKeyAndOrderFront(self)
            })
            
            window.closeInterceptor = { [weak self] in
                self?.close(account: account)
                return true
            }

            telegramUpdateTheme(theme, window: window, animated: false)
            applicationContext.applyNewTheme()
            self.contexts.append(applicationContext)
        })
        
    }
    
    func close(peerId: PeerId, accountId: AccountRecordId) {
        let key = ExternalChat.Key(peerId: peerId, accountId: accountId)
        self.chatDisposable.set(nil, forKey: key)
        self.chatReadyDisposable.set(nil, forKey: key)
        let external = self.externalChats.removeValue(forKey: key)
        if let external, let window = external.navigation.window {
            window.closeInterceptor = nil
            window.removeAllHandlers(for: external.navigation)
        }
        external?.navigation.window?.orderOut(nil)
        external?.navigation.window?.contentView?.removeAllSubviews()
    }
    
    func close(account: Account) {
        guard let index = self.contexts.firstIndex(where: { $0.context.account.id == account.id }) else {
            return
        }
        let value = self.contexts.remove(at: index)
        value.context.window.closeInterceptor = nil
        self.windows.append(value.context.window)
        value.context.window.orderOut(nil)
        value.context.window.contentView?.removeAllSubviews()
    }
    
    func enumerateAccountContext(_ f:(AccountContext)->Void) {
        for context in contexts {
            f(context.context)
        }
    }
    
    func enumerateExternalChatContext(_ f:(AccountContext)->Void) {
        for (_, value) in externalChats {
            f(value.context)
        }
    }
    func enumerateApplicationContext(_ f:(AuthorizedApplicationContext)->Void) {
        for context in contexts {
            f(context)
        }
    }
    
    deinit {
        disposable.dispose()
    }
}
