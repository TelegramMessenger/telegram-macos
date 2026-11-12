import Foundation
import XCTest
import SwiftSignalKit

final class Scope { var isValid = true }
final class AnalyticsContext {
    let isExcluded: Bool
    let owner: Int
    let scope: Scope?
    var depth = 0
    init(_ owner: Int, excluded: Bool = false, scope: Scope? = Scope()) { self.owner = owner; isExcluded = excluded; self.scope = excluded ? nil : scope }
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(self) }
    func restricting(peerId: Int) -> AnalyticsContext { AnalyticsContext(owner, excluded: isExcluded || peerId < 0, scope: scope) }
__SIGNAL__
}
final class AnalyticsPresentation {
    let context: AnalyticsContext
    let excluded: Bool
    var active = true
    init(_ context: AnalyticsContext) {
        self.context = context
        excluded = context.isExcluded || context.scope?.isValid != true
        context.depth += 1
        if excluded { UI.exclusions += 1 }
    }
    func end() { guard active else { return }; active = false; context.depth -= 1; if excluded { UI.exclusions -= 1 } }
    deinit { end() }
}
final class Screens {
    var shown: [AnalyticsContext?] = []
    func show(_ id: ObjectIdentifier, screen: String, peerType: Int?, context: AnalyticsContext?) { shown.append(context) }
}
final class Analytics {
    static let shared = Analytics()
    let screens = Screens()
    var owners: [Int] = []
    func captureContext(engine: Engine, peerId: Int, inherited: AnalyticsContext) -> AnalyticsContext {
        owners.append(engine.owner)
        return AnalyticsContext(engine.owner, excluded: inherited.isExcluded || peerId < 0, scope: engine.owner == inherited.owner ? inherited.scope : nil)
    }
    func privacyContext(peerId: Int) -> AnalyticsContext { AnalyticsContext(0, excluded: peerId < 0, scope: nil) }
}
enum ChatLocation: Equatable { case peer(Int); var peerId: Int { switch self { case let .peer(value): return value } } }
enum ChatMode { case history, scheduled }
struct ChatFocusTarget {}
struct ChatInitialAction { let value: Int }
struct ChatLocationContextHolder {}
struct ViewControllerStyle {}
class ViewController {
    var analyticsContext: AnalyticsContext?
    var analyticsPeer: Int?
    var analyticsScreen: String?
    var onDeinit: (() -> Void)?
    deinit { onDeinit?() }
}
final class InputDataModalController: ViewController { let current = ViewController() }
final class ChatInteraction {
    let peerId: Int
    var inheritedAnalyticsContext: AnalyticsContext?
    var initialActions: [Int] = []
    var onAction: (() -> Void)?
    init(_ peerId: Int) { self.peerId = peerId }
    func invokeInitialAction(action: ChatInitialAction?) { onAction?(); if let action { initialActions.append(action.value) } }
}
class ChatController: ViewController {
    let context: AccountContext
    var chatLocation: ChatLocation
    let chatInteraction: ChatInteraction
    let mode: ChatMode
    var scrolled = 0
    var isAnalyticsVisible = true
    var analyticsPeerValue: Int? { nil }
    init(context: AccountContext, chatLocation: ChatLocation, mode: ChatMode = .history, focusTarget: ChatFocusTarget? = nil, initialAction: ChatInitialAction? = nil, chatLocationContextHolder: Atomic<ChatLocationContextHolder?>? = nil) {
        self.context = context; self.chatLocation = chatLocation; self.mode = mode; chatInteraction = ChatInteraction(chatLocation.peerId)
        super.init()
        UI.onConstruction?()
    }
    func scrollup(force: Bool) { scrolled += 1 }
    static func resolveAnalyticsScreen(mode: ChatMode, chatLocation: ChatLocation, accountPeerId: Int) -> String? { "chat" }
__INHERIT__
__UPDATE__
}
final class ChatAdditionController: ChatController {}
final class ChatScheduleController: ChatController {}
final class NavigationViewController {
    var controllers: [ViewController] = []
    var controller: ViewController? { controllers.last }
    var onPush: ((ViewController) -> Void)?
    var backs = 0
    func push(_ controller: ViewController, _ animated: Bool = true, style: ViewControllerStyle? = nil) { onPush?(controller); controllers.append(controller) }
    func first(_ predicate: (ViewController) -> Bool) -> ViewController? { controllers.first(where: predicate) }
    func back() { backs += 1 }
}
final class Window { var shown = 0; func makeKeyAndOrderFront(_ sender: Any?) { shown += 1 } }
final class Account { let id: Int; let postbox = Postbox(); let network = NSObject(); init(_ id: Int) { self.id = id } }
final class Postbox { var updates = 0 }
struct Peer { let id: Int; var isCommunity = false; var sensitive = false; func hasSensitiveContent(platform: String) -> Bool { sensitive } }
struct EnginePeer { let peer: Peer; func _asPeer() -> Peer { peer } }
enum TelegramEngine { enum EngineData { enum Item { enum Peer { struct Peer { let id: Int } } } } }
final class DataEngine {
    var signal: Signal<EnginePeer?, NoError> = .complete()
    var reads = 0
    func get(_ request: TelegramEngine.EngineData.Item.Peer.Peer) -> Signal<EnginePeer?, NoError> { reads += 1; return signal }
}
final class Engine { let owner: Int; let data = DataEngine(); init(_ owner: Int) { self.owner = owner } }
final class ChatList { var navigationController: NavigationViewController? }
final class MainView { let chatList = ChatList() }
final class Bindings { let navigation = NavigationViewController(); let mainViewController = MainView(); func rootNavigation() -> NavigationViewController { navigation } }
final class ContentConfig { var sensitiveContentEnabled = false; var canAdjustSensitiveContent = true }
final class AppConfiguration { var verification = false; func getBoolValue(_ name: String, orElse: Bool) -> Bool { verification } }
final class AccountContext {
    let account: Account
    let engine: Engine
    let window = Window()
    let bindings = Bindings()
    let contentConfig = ContentConfig()
    let appConfiguration = AppConfiguration()
    var isExternal = false
    var peerId: Int { account.id }
    init(_ id: Int) { account = Account(id); engine = Engine(id); bindings.mainViewController.chatList.navigationController = bindings.navigation; UI.contexts.append(self) }
}
final class Support { var external: AccountContext?; func getExternalContext(peerId: Int, accountId: Int) -> AccountContext? { external } }
final class AppDelegate { var supportAccountContextValue: Support? }
var appDelegate: AppDelegate?
final class CommunityListController: ViewController { init(_ context: AccountContext, communityId: Int) { super.init(); UI.onConstruction?() } }
func VerifyAgeAlertController(context: AccountContext) -> InputDataModalController { UI.onConstruction?(); return InputDataModalController() }
func showModal(with controller: InputDataModalController, for window: Window) { UI.modals.append(controller) }
enum ConfirmResult { case basic, thrid }
struct AlertCallbacks { let success: (ConfirmResult) -> Void; let cancel: () -> Void; let deinitAction: () -> Void }
enum UI {
    static var contexts: [AccountContext] = []
    static var exclusions = 0
    static var onConstruction: (() -> Void)?
    static var modals: [InputDataModalController] = []
    static var alerts: [AlertCallbacks] = []
}
struct Strings { let chatSensitiveContent = "sensitive"; let chatSensitiveContentConfirm = "confirm"; let chatSensitiveContentConfirmOk = "ok"; let chatSensitiveContentConfirmThird = "enable" }
func strings() -> Strings { Strings() }
func verifyAlert(for window: Window, header: String, information: String?, ok: String, option: String?, optionIsSelected: Bool?, successHandler: @escaping (ConfirmResult) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    UI.onConstruction?()
    UI.alerts.append(AlertCallbacks(success: successHandler, cancel: cancelHandler, deinitAction: onDeinit))
}
func updateRemoteContentSettingsConfiguration(postbox: Postbox, network: NSObject, sensitiveContentEnabled: Bool) -> Signal<Never, NoError> { Signal { subscriber in postbox.updates += 1; subscriber.putCompletion(); return EmptyDisposable } }
struct Hooks { var openChatWithContext: ((Any, Int, ChatInitialAction?, AnalyticsContext) -> Void)? }
func premiumOpenChat(_ context: AccountContext, peerId: Int, action: ChatInitialAction?, origin: AnalyticsContext) {
    var hooks = Hooks()
__PREMIUM__
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    hooks.openChatWithContext?(context, peerId, action, origin)
}
__NAVIGATE__

final class NavigationTests: XCTestCase {
    private func drain() { let done = expectation(description: "main"); DispatchQueue.main.async { done.fulfill() }; wait(for: [done], timeout: 2) }
    override func setUp() { appDelegate = nil; UI.modals = []; UI.alerts = []; UI.onConstruction = nil; Analytics.shared.owners = []; Analytics.shared.screens.shown = [] }
    override func tearDown() { appDelegate = nil; UI.contexts.forEach { $0.bindings.navigation.controllers = [] }; UI.contexts = []; UI.modals = []; UI.alerts.forEach { $0.deinitAction() }; UI.alerts = []; UI.onConstruction = nil; drain(); XCTAssertEqual(UI.exclusions, 0) }
    func testDeferredPeerResultBindsEveryChatKindBeforePushAndConsumesOnce() {
        for kind in 0..<3 {
            let context = AccountContext(1)
            let origin = AnalyticsContext(1, excluded: true)
            let parent = origin.beginPresentation()
            var emit: (() -> Void)?
            context.engine.data.signal = Signal { subscriber in emit = { subscriber.putNext(EnginePeer(peer: Peer(id: 2))) }; return EmptyDisposable }
            UI.onConstruction = { XCTAssertGreaterThan(UI.exclusions, 0) }
            context.bindings.navigation.onPush = { child in
                XCTAssertTrue(child.analyticsContext!.isExcluded)
                XCTAssertTrue((child as? ChatController)?.chatInteraction.inheritedAnalyticsContext?.isExcluded == true)
            }
            var callbacks = 0
            navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(2), mode: kind == 1 ? .scheduled : .history, additional: kind == 2, callback: { _ in callbacks += 1 }, analyticsContext: origin)
            parent.end()
            emit?(); emit?()
            XCTAssertEqual(callbacks, 1)
            XCTAssertEqual(context.bindings.navigation.controllers.count, 1)
            if kind == 1 { XCTAssertTrue(context.bindings.navigation.controller is ChatScheduleController) }
            if kind == 2 { XCTAssertTrue(context.bindings.navigation.controller is ChatAdditionController) }
            context.bindings.navigation.controllers = []
        }
    }
    func testReusedChatIsRestrictedBeforeActionAndScreenUpdatesCannotRelaxOrigin() {
        let context = AccountContext(1)
        let chat = ChatController(context: context, chatLocation: .peer(2))
        context.bindings.navigation.controllers = [chat]
        chat.chatInteraction.onAction = { [weak chat] in XCTAssertTrue(chat?.analyticsContext?.isExcluded == true) }
        premiumOpenChat(context, peerId: 2, action: ChatInitialAction(value: 1), origin: AnalyticsContext(1, excluded: true))
        XCTAssertEqual(context.bindings.navigation.backs, 1)
        XCTAssertEqual(chat.chatInteraction.initialActions, [1])
        chat.inheritAnalyticsContext(AnalyticsContext(1))
        chat.updateAnalyticsScreen(chatLocation: .peer(3))
        XCTAssertTrue(chat.analyticsContext!.isExcluded)
        XCTAssertTrue(chat.chatInteraction.inheritedAnalyticsContext!.isExcluded)
    }
    func testAdditionalReuseAlsoBindsBeforeScrollAndActionWithoutCreatingChat() {
        let context = AccountContext(1)
        let chat = ChatController(context: context, chatLocation: .peer(2))
        context.bindings.navigation.controllers = [chat]
        context.engine.data.signal = .single(EnginePeer(peer: Peer(id: 2)))
        chat.chatInteraction.onAction = { [weak chat] in XCTAssertTrue(chat?.analyticsContext?.isExcluded == true) }
        navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(2), initialAction: ChatInitialAction(value: 2), additional: true, analyticsContext: AnalyticsContext(1, excluded: true))
        XCTAssertEqual(context.bindings.navigation.controllers.count, 1)
        XCTAssertEqual(chat.scrolled, 1)
        XCTAssertEqual(chat.chatInteraction.initialActions, [2])
    }
    func testSensitivityConsentRetainsOriginAfterCloseBeforeCallbackAndConsumesOnce() {
        let context = AccountContext(1)
        context.engine.data.signal = .single(EnginePeer(peer: Peer(id: 2, sensitive: true)))
        UI.onConstruction = { XCTAssertGreaterThan(UI.exclusions, 0) }
        navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(2), analyticsContext: AnalyticsContext(1, excluded: true))
        let alert = UI.alerts[0]
        alert.deinitAction()
        alert.success(.thrid); alert.success(.thrid); alert.cancel()
        drain()
        XCTAssertEqual(context.account.postbox.updates, 1)
        XCTAssertEqual(context.bindings.navigation.controllers.count, 1)
        XCTAssertTrue(context.bindings.navigation.controller!.analyticsContext!.isExcluded)
    }
    func testCancelledAndUnknownConsentCannotOpenChatOrChangeSettings() {
        for unknown in [false, true] {
            let context = AccountContext(1)
            context.engine.data.signal = .single(EnginePeer(peer: Peer(id: 2, sensitive: true)))
            navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(2), analyticsContext: AnalyticsContext(1, excluded: true))
            let alert = UI.alerts.last!
            if unknown { alert.deinitAction(); drain() } else { alert.cancel() }
            alert.success(.thrid)
            XCTAssertTrue(context.bindings.navigation.controllers.isEmpty)
            XCTAssertEqual(context.account.postbox.updates, 0)
            alert.deinitAction(); drain()
        }
    }
    func testAgeAndCommunityRootsKeepContextAfterLookupEnds() {
        for community in [false, true] {
            let context = AccountContext(1)
            context.appConfiguration.verification = true
            context.engine.data.signal = .single(EnginePeer(peer: Peer(id: 2, isCommunity: community, sensitive: true)))
            UI.onConstruction = { XCTAssertGreaterThan(UI.exclusions, 0) }
            navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(2), analyticsContext: AnalyticsContext(1, excluded: true))
            let child: ViewController = community ? context.bindings.navigation.controller! : UI.modals.last!
            XCTAssertTrue(child.analyticsContext!.isExcluded)
            if let modal = child as? InputDataModalController { XCTAssertTrue(modal.current.analyticsContext!.isExcluded) }
            UI.modals = []
        }
    }
    func testExternalAccountRevalidatesOriginAndInvalidScopeCannotAdmitConstructor() {
        let original = AccountContext(1)
        let external = AccountContext(2)
        external.isExternal = true
        external.engine.data.signal = .single(EnginePeer(peer: Peer(id: 3)))
        let delegate = AppDelegate(); let support = Support(); support.external = external; delegate.supportAccountContextValue = support; appDelegate = delegate
        UI.onConstruction = { XCTAssertGreaterThan(UI.exclusions, 0) }
        navigateToChat(navigation: original.bindings.navigation, context: original, chatLocation: .peer(3), analyticsContext: AnalyticsContext(1))
        XCTAssertTrue(original.bindings.navigation.controllers.isEmpty)
        XCTAssertEqual(external.bindings.navigation.controllers.count, 1)
        XCTAssertNil(external.bindings.navigation.controller!.analyticsContext!.scope)
        XCTAssertEqual(Analytics.shared.owners, [2, 2])
        external.bindings.navigation.controllers = []
        appDelegate = nil
    }
    func testSecretDestinationTightensOrdinaryOriginAndLegacyOverloadStillNavigates() {
        let context = AccountContext(1)
        context.engine.data.signal = .single(EnginePeer(peer: Peer(id: -2)))
        navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(-2), analyticsContext: AnalyticsContext(1))
        XCTAssertTrue(context.bindings.navigation.controller!.analyticsContext!.isExcluded)
        context.bindings.navigation.controllers = []
        context.engine.data.signal = .single(EnginePeer(peer: Peer(id: 2)))
        navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(2))
        XCTAssertEqual(context.bindings.navigation.controllers.count, 1)
    }
    func testFirstOrdinaryGrantSurvivesUpdatesAndCannotBeReplacedByAnotherGrant() {
        let context = AccountContext(1)
        let first = AnalyticsContext(1)
        let second = AnalyticsContext(1)
        let chat = ChatController(context: context, chatLocation: .peer(2))
        chat.inheritAnalyticsContext(first)
        chat.inheritAnalyticsContext(second)
        chat.updateAnalyticsScreen(chatLocation: .peer(3))
        XCTAssertTrue(chat.chatInteraction.inheritedAnalyticsContext?.scope === first.scope)
        XCTAssertTrue(chat.analyticsContext?.scope === first.scope)
        XCTAssertFalse(chat.analyticsContext!.isExcluded)
    }
    func testOriginRevokedDuringLookupRemainsDeniedDuringConstructionAndChildLifetime() {
        let context = AccountContext(1)
        let origin = AnalyticsContext(1)
        var emit: (() -> Void)?
        context.engine.data.signal = Signal { subscriber in emit = { subscriber.putNext(EnginePeer(peer: Peer(id: 2))) }; return EmptyDisposable }
        navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(2), analyticsContext: origin)
        XCTAssertEqual(UI.exclusions, 0)
        origin.scope?.isValid = false
        UI.onConstruction = { XCTAssertGreaterThan(UI.exclusions, 0) }
        emit?()
        XCTAssertEqual(context.bindings.navigation.controllers.count, 1)
        XCTAssertFalse(context.bindings.navigation.controller!.analyticsContext!.scope?.isValid ?? false)
        XCTAssertGreaterThan(UI.exclusions, 0)
        context.bindings.navigation.controllers = []
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testMissingPeerDoesNotCreateChildAndRevokedOriginRemainsDenied() {
        let context = AccountContext(1)
        let origin = AnalyticsContext(1)
        context.engine.data.signal = .single(nil)
        navigateToChat(navigation: context.bindings.navigation, context: context, chatLocation: .peer(2), analyticsContext: origin)
        XCTAssertTrue(context.bindings.navigation.controllers.isEmpty)
        origin.scope?.isValid = false
        context.engine.data.signal = .single(EnginePeer(peer: Peer(id: 2)))
        UI.onConstruction = { XCTAssertGreaterThan(UI.exclusions, 0) }
        premiumOpenChat(context, peerId: 2, action: nil, origin: origin)
        XCTAssertFalse(context.bindings.navigation.controller!.analyticsContext!.scope?.isValid ?? false)
    }
}
