import Cocoa
import AppAnalytics
import Foundation
import WebKit
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils
import KeyboardKey
import TelegramIconsTheme
import TelegramMedia
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import FilePanels
import TelegramLinks
import PremiumStatusUI
import SystemPermissions
import Svg
import LocalAuthentication
private final class Webapp : Window {
    fileprivate let controller: ViewController
    public init(controller: ViewController) {
        self.controller = controller
        let screen = NSScreen.main!
        
        
        self.controller.viewWillAppear(true)
        self.controller.measure(size: screen.frame.size)
        
        let rect = screen.frame.focus(controller.view.frame.insetBy(dx: -10, dy: -10).size)
        
        super.init(contentRect: rect, styleMask: [.fullSizeContentView, .titled, .borderless], backing: .buffered, defer: true)
        
        self.minSize = rect.size
        
        self.contentView?.wantsLayer = true
        self.contentView?.autoresizesSubviews = false
        
        self.modalInset = 10

        
        controller.view.layer?.cornerRadius = 10
        
       
        self.contentView?.addSubview(controller.view)
        
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = NSColor.clear
       // self.contentView?.layer?.cornerRadius = 10
        self.isMovableByWindowBackground = true
        
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden

    }
    
    public func show() {

        let shadow = SimpleShapeLayer()
        shadow.cornerRadius = 10
        shadow.masksToBounds = false
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4).cgColor
        shadow.shadowOffset = CGSize(width: 0.0, height: 1)
        shadow.shadowRadius = 5
        shadow.shadowOpacity = 0.7
        shadow.fillColor = controller.view.background.cgColor
        shadow.path = CGPath(roundedRect: controller.view.bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        shadow.frame = self.controller.frame
        
        self.contentView?.layer?.addSublayer(shadow)
        
        self.makeKeyAndOrderFront(nil)
        
        self.contentView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2, removeOnCompletion: false)
        self.contentView?.layer?.animateScaleSpring(from: 0.8, to: 1.0, duration: 0.2)
        
        
        self.controller.viewDidAppear(true)
        
    }
    
    public override func close() {
        super.close()
    }
    
    deinit {
        var bp = 0
        bp += 1
    }
}


public class WebappRecentlyUsed : Equatable {
    public static func == (lhs: WebappRecentlyUsed, rhs: WebappRecentlyUsed) -> Bool {
        return lhs.tabdata.unique != rhs.tabdata.unique
    }
    public var tabdata: BrowserTabData
    
    public init(tabdata: BrowserTabData) {
        self.tabdata = tabdata
    }
}

public struct WebappsState : Equatable {
    public var recentlyUsed: [WebappRecentlyUsed] = []
    
    
    public var isEmpty: Bool {
        return recentlyUsed.isEmpty
    }
    public init(recentlyUsed: [WebappRecentlyUsed] = []) {
        self.recentlyUsed = recentlyUsed
    }
}

private let accountHolder: Atomic<[AccountRecordId : BrowserStateContext]> = .init(value: [:])



public final class BrowserStateContext {
    
    private init(context: (any AccountContextProtocol)) {
        self.context = context
    }
    
    public static func get(_ context: (any AccountContextProtocol)) -> BrowserStateContext {
        let holder = accountHolder.with { $0[context.account.id] }
        if let holder, holder.context === context {
            return holder
        } else {
            if holder != nil {
                cleanup(context.account.id)
            }
            return accountHolder.modify { value in
                var value = value
                value[context.account.id] = .init(context: context)
                return value
            }[context.account.id]!
        }
    }
    
    public static func focusedWindow(for context: any AccountContextProtocol) -> Window? {
        let holder = accountHolder.with { $0[context.account.id] }
        guard let holder, holder.context === context, let window = holder.browser?.window,
              window.isKeyWindow, window.isVisible else {
            return nil
        }
        return window
    }

    public static func cleanup(_ accountId: AccountRecordId) {
        let holder = accountHolder.with { $0[accountId] }
        holder?.hide(close: true)
        
        _ = accountHolder.modify { value in
            var value = value
            value.removeValue(forKey: accountId)
            return value
        }
    }
    
    public static func hide(_ accountId: AccountRecordId) {
        accountHolder.with { $0[accountId] }?.hide(close: false)
    }
    
    public static func focus(_ active: [AccountRecordId]) -> Void {
        for accountId in active {
            let holder = accountHolder.with { $0[accountId] }
            if let browser = holder?.browser {
                holder?.show(browser)
            }
        }
        
        let holders = accountHolder.with { $0 }
        for (key, holder) in holders {
            if !active.contains(key) {
                holder.hide(close: false)
                if holder.browser == nil {
                    _ = accountHolder.modify { value in
                        var value = value
                        if value[key] === holder {
                            value.removeValue(forKey: key)
                        }
                        return value
                    }
                }
            }
        }
    }
    
    public static func checkActive(_ active: [AccountRecordId]) {
        let holders = accountHolder.with { $0 }
        for (key, _) in holders {
            if !active.contains(key) {
                cleanup(key)
            }
        }
    }
    
    public static func checkKey(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) {
            let list = accountHolder.with { $0.values }
            var invoked: Bool = false
            for value in list {
                if value.browser?.window == event.window {
                    if event.keyCode == KeyboardKey.W.rawValue {
                        value.browser?.closeTab()
                        invoked = true
                    } else {
                        let keyCodes: [KeyboardKey] = [.Escape, .Zero, .One, .Two, .Three, .Four, .Five, .Six, .Seven, .Eight, .Nine]
                        if keyCodes.contains(where: { $0.rawValue == event.keyCode }) {
                            event.window?.sendEvent(event)
                            invoked = true
                        }
                    }
                               
                }
            }
            if invoked {
                return nil
            }
        }
        return event
    }
    
    public private(set) var browser: WebappBrowserController? = nil
    private let context: (any AccountContextProtocol)
    
    private let browserState: Promise<[BrowserTabData]> = Promise([])
    private var joinChatOperations: [BrowserTabData.Unique: JoinChatWebViewOperation] = [:]
    
    public func show(_ browser: WebappBrowserController) {
        guard !browser.markAsDeinit else { return }
        self.browser = browser
        browser.show()
        
        browserState.set(browser.publicState)
    }
    
    public func hide(close: Bool = true) {
        hide(close: close, cancelJoinOperations: true)
    }

    func hide(close: Bool, cancelJoinOperations: Bool) {
        if close, cancelJoinOperations { cancelJoinChatOperations() }
        let browser = self.browser
        browser?.hide({ [weak self, weak browser] in
            guard close, let self, let browser, self.browser === browser else { return }
            self.browser = nil
        }, close: close)
        if close, self.browser == nil || self.browser === browser {
            browserState.set(.single([]))
        }
    }
    
    
    
    private let statePromise = ValuePromise<WebappsState>(.init(), ignoreRepeated: true)
    private let stateValue = Atomic<WebappsState>(value: .init())
    
    public var state: Signal<WebappsState, NoError> {
        return statePromise.get()
    }
    
    public struct FullState : Equatable {
        
        public struct ResolvedRecently : Equatable {
            public let tab: BrowserTabData
            public init(tab: BrowserTabData) {
                self.tab = tab
            }
        }
        
        public let opened: [BrowserTabData]
        
        public let state: WebappsState
        public let recentlyMenu: [ResolvedRecently]
        
        public struct Recommended : Equatable {
            public let peer: EnginePeer
            public init(peer: EnginePeer) {
                self.peer = peer
            }
        }
        
        public var isEmpty: Bool {
            return recentlyMenu.isEmpty && opened.isEmpty
        }
        
        public let recommended:[Recommended]
        public let recentUsedApps: [Recommended]
        public init(opened: [BrowserTabData], state: WebappsState, recentlyMenu: [ResolvedRecently], recommended: [Recommended], recentUsedApps: [Recommended]) {
            self.opened = opened
            self.state = state
            self.recentlyMenu = recentlyMenu
            self.recommended = recommended
            self.recentUsedApps = recentUsedApps
        }
    }
    
    public func fullState() -> Signal<FullState, NoError> {
        let context = self.context
        return combineLatest(statePromise.get(), browserState.get()) |> mapToSignal { value, browserState in
            let recommendedList:(Signal<[EnginePeer.Id]?, NoError>) -> Signal<[FullState.Recommended], NoError> = { signal in
                return signal |> mapToSignal { appIds in
                    if let appIds {
                        return context.engine.data.subscribe(
                            EngineDataMap(
                                appIds.map { peerId -> TelegramEngine.EngineData.Item.Peer.Peer in
                                    return TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)
                                }
                            )) |> map  { peers in
                                var result: [FullState.Recommended] = []
                                for id in appIds {
                                    if let peer = peers[id] as? EnginePeer  {
                                        result.append(FullState.Recommended(peer: peer))
                                    }
                                }
                                return Array(result)
                            }
                    } else {
                        return .single(Array<FullState.Recommended>())
                    }
                }
            }
            
            let recommendedApps: Signal<[FullState.Recommended], NoError> = recommendedList(context.engine.peers.recommendedAppPeerIds())
            let recentUsedApps: Signal<[FullState.Recommended], NoError> = recommendedList(context.engine.peers.recentApps() |> map(Optional.init)) |> map { Array($0.filter { $0.peer._asPeer().botInfo?.flags.contains(.hasWebApp) == true }.prefix(10)) }
            
            
            let combinedRecentApps: [FullState.ResolvedRecently] = value.recentlyUsed.compactMap { recent in
                if !browserState.contains(where: { $0.unique == recent.tabdata.unique }) {
                    return .init(tab: recent.tabdata)
                }
                return nil
            }
            
                        
            return combineLatest(recommendedApps, recentUsedApps) |> map { (recommendedApps, recentUsedApps) in
                let recommended = recommendedApps.filter { value in
                    return !recentUsedApps.contains(where: { $0.peer.id == value.peer.id })
                }
                return FullState(opened: browserState, state: value, recentlyMenu: combinedRecentApps, recommended: recommended, recentUsedApps: recentUsedApps)
            }
        }
    }
    
    private func updateState(_ f:(WebappsState) -> WebappsState) {
        self.statePromise.set(stateValue.modify(f))
    }

    
    public func add(_ recently: WebappRecentlyUsed) {
        if recently.tabdata.peer?.addressName != context.appConfiguration.getStringValue("verify_age_bot_username", orElse: "") {
            if recently.tabdata.data.canBeRecent {
                updateState { current in
                    var current = current
                    if let index = current.recentlyUsed.firstIndex(where: { $0.tabdata.unique == recently.tabdata.unique }) {
                        current.recentlyUsed.move(at: index, to: 0)
                        current.recentlyUsed[0] = recently
                    } else {
                        current.recentlyUsed.insert(recently, at: 0)
                    }
                    return current
                }
            }
        }
    }
    public func setExternalState(_ unique: BrowserTabData.Unique, external: WebpageModalState) {
        updateState { current in
            let current = current
            if let index = current.recentlyUsed.firstIndex(where: { $0.tabdata.unique == unique }) {
                current.recentlyUsed[index].tabdata.external = external
            }
            return current
        }
    }
    
    public func getExternal(_ unique: BrowserTabData.Unique) -> WebpageModalState? {
        return self.stateValue.with {
            $0.recentlyUsed.first(where: { $0.tabdata.unique == unique })?.tabdata.external
        }
    }
    
    public func closeAll() {
        hide()
    }

    public func closeTab(uniqueId: BrowserTabData.Unique) {
        self.browser?.closeTab(uniqueId)
    }
    
    public func clearRecent() {
        updateState { current in
            var current = current
            current.recentlyUsed.removeAll()
            return current
        }
    }
    
    func openJoinChatWebView(botId: PeerId, url: String?, queryId: Int64, peerId: PeerId?, analyticsContext: AnalyticsContext?) {
        let uniqueId: BrowserTabData.Unique = .webapp(queryId)
        joinChatOperations.removeValue(forKey: uniqueId)?.cancel(closeTab: true)
        let operation = JoinChatWebViewOperation(context: context, owner: self, botId: botId, url: url, queryId: queryId, peerId: peerId, analyticsContext: analyticsContext, finished: { [weak self] operation in
            guard self?.joinChatOperations[uniqueId] === operation else { return }
            self?.joinChatOperations.removeValue(forKey: uniqueId)
        })
        joinChatOperations[uniqueId] = operation
        operation.start()
    }

    func cancelJoinChatOperation(uniqueId: BrowserTabData.Unique) {
        joinChatOperations.removeValue(forKey: uniqueId)?.cancel(closeTab: false)
    }

    private func cancelJoinChatOperations() {
        let operations = Array(joinChatOperations.values)
        joinChatOperations.removeAll()
        for operation in operations { operation.cancel(closeTab: false) }
    }

    func closeJoinChatTab(uniqueId: BrowserTabData.Unique) {
        browser?.removeTab(uniqueId)
    }

    public func open(tab: BrowserTabData.Data, uniqueId: BrowserTabData.Unique? = nil) {
        open(tab: tab, uniqueId: uniqueId, analyticsContext: nil)
    }

    public func open(tab: BrowserTabData.Data, uniqueId: BrowserTabData.Unique? = nil, analyticsContext: AnalyticsContext?) {
        _ = openCancellable(tab: tab, uniqueId: uniqueId, analyticsContext: analyticsContext)
    }

    func openCancellable(tab: BrowserTabData.Data, uniqueId: BrowserTabData.Unique? = nil, analyticsContext: AnalyticsContext?, completion: ((Bool) -> Void)? = nil) -> Disposable {
        let cancelled = Atomic(value: false)
        let policyDisposable = MetaDisposable()
        var presented = false
        var completed = false
        let complete: (Bool) -> Void = { opened in
            guard !completed else { return }
            completed = true
            completion?(opened)
        }
        let context = self.context
        let origin = BrowserAnalyticsOrigin(account: context, data: tab, inherited: analyticsContext)
        let request = BrowserDecision(origin: origin)
        let invoke: (Bool) -> Void = { [weak self] confirmed in
            request.resolve {
                guard !cancelled.with({ $0 }), let self else { complete(false); return }
                if confirmed, let peer = tab.peer { FastSettings.markWebAppAsConfirmed(peer.id) }
                if let browser = self.browser, !browser.markAsDeinit {
                    browser.add(tab, uniqueId: uniqueId, analyticsContext: origin.context)
                    browser.makeKeyAndOrderFront()
                } else {
                    let controller = WebappBrowserController(context: context, initialTab: tab, initialUniqueId: uniqueId, analyticsContext: origin.context)
                    self.show(controller)
                }
                complete(true)
            }
        }
        let verifyAgeBot = context.appConfiguration.getStringValue("verify_age_bot_username", orElse: "")
        if let peer = tab.peer, FastSettings.shouldConfirmWebApp(peer.id), peer.addressName != verifyAgeBot {
            let signal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.BotPrivacyPolicyUrl(id: peer.id)) |> take(1) |> deliverOnMainQueue
            policyDisposable.set(origin.preserving(signal).start(next: { [weak self] privacyUrl in
                guard !cancelled.with({ $0 }), let self else { return }
                let window = self.browser?.markAsDeinit == false ? self.browser?.window : context.window
                guard let window else { return }
                let data = ModalAlertData(title: nil, info: strings().webAppFirstOpenTerms(privacyUrl ?? strings().botInfoLaunchInfoPrivacyUrl), description: nil, ok: strings().botLaunchApp, options: [], mode: .confirm(text: strings().modalCancel, isThird: false), header: .init(id: "header", value: { initialSize, stableId, presentation in
                    return AlertHeaderItem(initialSize, stableId: stableId, presentation: presentation, context: context, peer: peer, info: strings().botMoreAbout, callback: { _ in
                        guard !cancelled.with({ $0 }) else { return }
                        request.resolve {
                            BrowserHooks.shared.openChatObserved(context, peer.id, analyticsContext: origin.context)
                            closeAllModals(window: window)
                            complete(false)
                        }
                    })
                }))
                presented = true
                showModalAlert(for: window, data: data, completion: { _ in
                    invoke(true)
                }, cancel: {
                    request.resolve { complete(false) }
                }, onDeinit: {
                    request.dismissed()
                    DispatchQueue.main.async { complete(false) }
                })
            }, completed: {
                if !presented { request.resolve { complete(false) } }
            }))
        } else {
            invoke(false)
        }
        return ActionDisposable {
            _ = cancelled.swap(true)
            let cleanup: () -> Void = {
                policyDisposable.dispose()
                if !presented { request.resolve {} }
                complete(false)
            }
            if Queue.mainQueue().isCurrent() {
                cleanup()
            } else {
                Queue.mainQueue().async(cleanup)
            }
        }
    }

}


/*

 */
