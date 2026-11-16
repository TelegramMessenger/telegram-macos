import Foundation
import ObjectiveC
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
struct MessageId: Hashable { let peerId: PeerId; var id: Int32 = 1 }
final class Scope { var valid = true }
final class AnalyticsContext {
    let isExcluded: Bool
    let owner: Int
    let scope: Scope?
    init(_ owner: Int = 1, excluded: Bool = false, scope: Scope? = Scope()) { self.owner = owner; isExcluded = excluded; self.scope = excluded ? nil : scope }
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(self) }
    func restricting(peerId: PeerId) -> AnalyticsContext { AnalyticsContext(owner, excluded: isExcluded || peerId < 0, scope: scope) }
__SIGNAL__
}
final class AnalyticsPresentation {
    let excluded: Bool
    var active = true
    init(_ context: AnalyticsContext) { excluded = context.isExcluded || context.scope?.valid != true; if excluded { UI.exclusions += 1 } }
    func end() { guard active else { return }; active = false; if excluded { UI.exclusions -= 1 } }
    deinit { end() }
}
final class Analytics {
    static let shared = Analytics()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(excluded: true) }
    func privacyContext(peerId: PeerId) -> AnalyticsContext { AnalyticsContext(excluded: peerId < 0, scope: nil) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext) -> AnalyticsContext {
        AnalyticsContext(engine.owner, excluded: inherited.isExcluded || peerId < 0, scope: engine.owner == inherited.owner ? inherited.scope : nil)
    }
}
protocol AccountContextProtocol: AnyObject { var engine: Engine { get }; var window: Window { get }; var peerId: PeerId { get }; var appConfiguration: Configuration { get } }
final class Context: AccountContextProtocol {
    let engine: Engine
    let window = Window()
    let peerId: PeerId = 1
    let appConfiguration = Configuration()
    init(_ owner: Int = 1) { engine = Engine(owner) }
}
final class Configuration { var ageBot = ""; func getStringValue(_ key: String, orElse: String) -> String { ageBot } }
final class Layer {
    func animateAlpha(from: Double, to: Double, duration: Double, removeOnCompletion: Bool, completion: @escaping (Bool) -> Void) {
        UI.hides += 1
        if UI.deferHide { UI.hideCompletions.append { completion(true) } } else { completion(true) }
    }
}
final class View {
    var layer: Layer? = Layer()
    func addSubview(_ view: View) {}
}
class Window {
    var contentView: View? = View()
    var orderOutCount = 0
    var shown = 0
    var front = 0
    func makeKeyAndOrderFront(_ sender: Any?) { front += 1 }
    var handlerRemovals = 0
    func orderOut(_ sender: Any?) { orderOutCount += 1 }
    func show() { shown += 1 }
    func removeAllHandlers(for object: NSObject) { handlerRemovals += 1 }
    var isFullScreen = false; var toggles = 0; func toggleFullScreen(_ sender: Any?) { toggles += 1; isFullScreen.toggle() } }
func hasModals(_ window: Window) -> Bool { false }
final class WebappBrowser: Window { init(parent: Window) {} }
struct Bar { let height: Int }
class ViewController: NSObject {
    var analyticsContext: AnalyticsContext?
    let view = View()
    var bar = Bar(height: 0)
    var _window: Window?
    var window: Window? { _window }
}
struct EnginePeer { let id: PeerId; var addressName: String? = "synthetic" }
struct WebPage { let id: Int64 }
struct RequestWebViewResult {}
enum Source { case generic, settings }
struct BrowserTabData {
    typealias Unique = Int64
    enum Data {
        case mainapp(bot: EnginePeer, source: Source)
        case webapp(bot: EnginePeer, peerId: PeerId, buttonText: String, url: String?, payload: String?, threadId: Int64?, replyTo: MessageId?, fromMenu: Bool)
        case simple(bot: EnginePeer, url: String?, buttonText: String, source: Source)
        case straight(bot: EnginePeer, peerId: PeerId, title: String, result: RequestWebViewResult)
        case tonsite(url: String)
        case instantView(url: String, webPage: WebPage, anchor: String?)
        case game(url: String, peerId: PeerId, messageId: MessageId)
        var peer: EnginePeer? {
            switch self { case let .mainapp(bot, _), let .webapp(bot, _, _, _, _, _, _, _), let .simple(bot, _, _, _), let .straight(bot, _, _, _): return bot; default: return nil }
        }
        var newUniqueId: Unique {
            switch self { case let .mainapp(bot, _), let .simple(bot, _, _, _): return bot.id
            default: UI.serial += 1; return UI.serial }
        }
    }
    let unique: Unique
    let data: Data
    var selected = false
    var external: WebpageModalState? = WebpageModalState(needConfirmation: true)
}
struct State {
    var tabs: [BrowserTabData] = []
    var selected: BrowserTabData? { tabs.first(where: { $0.selected }) }
    func select(_ unique: Int64) -> State { var copy = self; copy.tabs = tabs.map { var tab = $0; tab.selected = tab.unique == unique; return tab }; return copy }
    func closeTab(_ unique: Int64) -> State { var copy = self; copy.tabs.removeAll { $0.unique == unique }; return copy.select(copy.tabs.first?.unique ?? 0) }
    func newTab(_ data: BrowserTabData.Data, unique: Int64, external: WebpageModalState?) -> (State, BrowserTabData?) {
        if tabs.contains(where: { $0.unique == unique }) { return (self, nil) }
        var copy = self; let tab = BrowserTabData(unique: unique, data: data, selected: true); copy.tabs.append(tab); return (copy.select(unique), tab)
    }
}
struct WebpageModalState { var needConfirmation: Bool = true }
struct Recently { let tabdata: BrowserTabData }
final class Arguments {
    var insertTab: (BrowserTabData.Data, BrowserAnalyticsOrigin?, BrowserTabData.Unique?) -> Void = { _, _, _ in }
    var select: (Int64) -> Void = { _ in }
    var shake: (Int64) -> Void = { _ in }
    var closeTab: (Int64?, Bool) -> Void = { _, _ in }
    var removeTab: (Int64) -> Void = { _ in }
    var getExternalState: (Int64) -> WebpageModalState? = { _ in nil }
}
final class BrowserPageController: ViewController { var cancelledInvoices = 0; func cancelPendingPageActions() { cancelledInvoices += 1 }; func add(_ data: BrowserTabData.Data) -> Bool { UI.onPageAdd?(); return false } }
final class WebpageContainerController: ViewController {
    let data: BrowserTabData
    let context: any AccountContextProtocol
    let arguments: Arguments
    fileprivate let analyticsOrigin: BrowserAnalyticsOrigin
    var controller: BrowserPageController?
__CONTAINER_INIT__
__CONTAINER_ADD__
    func createPage() { analyticsOrigin.perform { let page = BrowserPageController(); analyticsOrigin.bind(page); controller = page } }
}
__LINK_MANAGER__
final class WebappBrowserController: ViewController {
    let context: any AccountContextProtocol
    var initialTab: BrowserTabData.Data?
    var initialUniqueId: BrowserTabData.Unique?
    var initialAnalyticsOrigin: BrowserAnalyticsOrigin?
    var webpages: [Int64: WebpageContainerController] = [:]
    var current: WebpageContainerController?
    var arguments: Arguments?
__LIFECYCLE_FIELDS__
    var front = 0
    var browser: WebappBrowser { _window as! WebappBrowser }
__BROWSER_INIT_ADD__
__BROWSER_CLOSE__
__BROWSER_HIDE__
__BROWSER_FRONT__
    var publicState: Signal<[BrowserTabData], NoError> { .single([]) }
    func loadViewIfNeeded() { if arguments == nil { configure() } }
__BROWSER_SHOW_START__
        UI.onShow?(self)
    }
    func configure() {
        let context = self.context
        let stateValue = Atomic(value: State())
        let updateState: ((State) -> State) -> Void = { [weak self] f in
            let state = stateValue.modify(f)
            self?.current = state.selected.flatMap { self?.webpages[$0.unique] }
            if let current = self?.current { self?.analyticsContext = current.analyticsOrigin.context }
        }
        var getArguments: (() -> Arguments?)?
__INSERT__
        let arguments = Arguments()
        arguments.insertTab = insertTab
        arguments.select = { id in updateState { $0.select(id) } }
        self.arguments = arguments
__CLOSE_TAB__
__REMOVE_TAB__
        getArguments = { [weak arguments] in arguments }
__INITIAL_INSERT__
    }
    func removeForTest(_ id: Int64) {
        if current?.data.unique == id { current = nil }
        webpages.removeValue(forKey: id)
        analyticsContext = current?.analyticsOrigin.context ?? Analytics.shared.privacyContext(peerId: context.peerId)
    }
}
enum TelegramEngine { enum EngineData { enum Item { enum Peer { struct BotPrivacyPolicyUrl { let id: PeerId } } } } }
final class Engine { let owner: Int; let data = DataEngine(); init(_ owner: Int) { self.owner = owner } }
final class DataEngine { var signal: Signal<String?, NoError> = .single(nil); var requests: [PeerId] = []; func get(_ item: TelegramEngine.EngineData.Item.Peer.BotPrivacyPolicyUrl) -> Signal<String?, NoError> { requests.append(item.id); return signal } }
enum FastSettings {
    static var needsConfirmation = false
    static var confirmed: [PeerId] = []
    static func shouldConfirmWebApp(_ id: PeerId) -> Bool { needsConfirmation }
    static func markWebAppAsConfirmed(_ id: PeerId) { UI.onConfirmed?(); confirmed.append(id) }
}
struct Strings {
    let webpageConfirmClose = "close", webpageConfirmOk = "ok"
    let botInfoLaunchInfoPrivacyUrl = "policy", botLaunchApp = "open", modalCancel = "cancel", botMoreAbout = "about"
    func webAppFirstOpenTerms(_ url: String) -> String { "terms" }
}
func strings() -> Strings { Strings() }
struct ModalAlertData {
    struct Header { let id: String; let value: (Int, Int, Int) -> AlertHeaderItem }
    enum Mode { case confirm(text: String, isThird: Bool) }
    let title: String?
    let info: String
    let description: String?
    let ok: String
    let options: [String]
    let mode: Mode
    let header: Header
}
final class AlertHeaderItem {
    let callback: (Int) -> Void
    init(_ size: Int, stableId: Int, presentation: Int, context: any AccountContextProtocol, peer: EnginePeer, info: String, callback: @escaping (Int) -> Void) { self.callback = callback }
}
func showModalAlert(for window: Window, data: ModalAlertData, completion: @escaping (Bool) -> Void, cancel: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    UI.onConfirmation?(); UI.alerts += 1; UI.accept = completion; UI.cancel = cancel; UI.dismiss = onDeinit; UI.header = data.header.value(0, 0, 0)
}
func verifyAlert_button(for window: Window, information: String, ok: String, successHandler: @escaping (Bool) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    UI.onConfirmation?(); UI.closeAccept = successHandler; UI.closeCancel = cancelHandler; UI.closeDismiss = onDeinit
}
func closeAllModals(window: Window) { UI.closedModals += 1 }
struct BrowserHooks {
    static var shared = BrowserHooks()
    var openChat: (any AccountContextProtocol, PeerId) -> Void = { _, _ in }
__BROWSER_CHAT__
}
final class BrowserStateContext {
    let context: any AccountContextProtocol
    var browser: WebappBrowserController?
    init(_ context: any AccountContextProtocol) { self.context = context }
    static func get(_ context: any AccountContextProtocol) -> BrowserStateContext {
        let key = ObjectIdentifier(context)
        if let value = UI.states[key] { return value }
        let value = BrowserStateContext(context); UI.states[key] = value; return value
    }
__STATE_SHOW__
    func cancelJoinChatOperation(uniqueId: Int64) { UI.cancelledJoinIds.append(uniqueId) }
    func cancelJoinChatOperations() { UI.cancelledJoinAccounts += 1 }
    let browserState = Promise<[BrowserTabData]>([])
__STATE_HIDE__
__STATE_CLOSE__
    func add(_ recently: Recently) { UI.recent += 1 }
    func getExternal(_ id: Int64) -> WebpageModalState? { nil }
__STATE_OPEN__
}
enum ChatBrowserTab {
    case webapp(bot: EnginePeer, peerId: PeerId, buttonText: String, url: String?, payload: String?, threadId: Int64?, replyTo: MessageId?, fromMenu: Bool)
    case simple(bot: EnginePeer, url: String?, buttonText: String, source: Source)
    case straight(bot: EnginePeer, peerId: PeerId, title: String, result: RequestWebViewResult)
    case instantView(url: String, webPage: WebPage, anchor: String?)
    case game(url: String, peerId: PeerId, messageId: MessageId)
}
struct ChatHooks {
    var openBrowserTab: (any AccountContextProtocol, ChatBrowserTab) -> Void = { _, _ in }
    var openBrowserTabWithContext: ((any AccountContextProtocol, ChatBrowserTab, AnalyticsContext) -> Void)?
}
func installedChatHooks() -> ChatHooks {
    var hooks = ChatHooks()
__INSTALL__
    return hooks
}
__ORIGIN__
enum UI {
    static var cancelledJoinIds: [Int64] = []
    static var cancelledJoinAccounts = 0
    static var exclusions = 0
    static var states: [ObjectIdentifier: BrowserStateContext] = [:]
    static var serial: Int64 = 100
    static var recent = 0
    static var alerts = 0
    static var hides = 0
    static var deferHide = false
    static var hideCompletions: [() -> Void] = []
    static var closeAccept: ((Bool) -> Void)?
    static var closeCancel: (() -> Void)?
    static var closeDismiss: (() -> Void)?
    static var closedModals = 0
    static var accept: ((Bool) -> Void)?
    static var cancel: (() -> Void)?
    static var dismiss: (() -> Void)?
    static var header: AlertHeaderItem?
    static var onShow: ((WebappBrowserController) -> Void)?
    static var onConfirmation: (() -> Void)?
    static var onConfirmed: (() -> Void)?
    static var onPageAdd: (() -> Void)?
    static func reset() {
        cancelledJoinIds = []; cancelledJoinAccounts = 0
        deferHide = false; hideCompletions = []
        closeAccept = nil; closeCancel = nil; closeDismiss = nil; hides = 0
        states = [:]; accept = nil; cancel = nil; dismiss = nil; header = nil
        onShow = nil; onConfirmation = nil; onConfirmed = nil; onPageAdd = nil
        serial = 100; recent = 0; alerts = 0; closedModals = 0; FastSettings.needsConfirmation = false; FastSettings.confirmed = []; BrowserHooks.shared = BrowserHooks()
    }
}
final class BrowserTests: XCTestCase {
    override func setUp() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    override func tearDown() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    func tab(_ id: PeerId = 2) -> BrowserTabData.Data { .simple(bot: EnginePeer(id: id), url: nil, buttonText: "", source: .settings) }
    func testPrivateTabOutlivesOpenRequestAndReleasesWhenContainerAndPageAreGone() {
        let context = Context(); let state = BrowserStateContext.get(context)
        UI.onShow = { browser in XCTAssertTrue(browser.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(UI.exclusions, 0) }
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        XCTAssertNil(state.browser?.initialAnalyticsOrigin); XCTAssertNil(state.browser?.initialTab)
        var container = state.browser!.webpages[2]
        container?.createPage()
        var page = container?.controller
        XCTAssertTrue(page?.analyticsContext?.isExcluded == true)
        state.browser?.removeForTest(2)
        XCTAssertGreaterThan(UI.exclusions, 0)
        container?.controller = nil; container = nil
        XCTAssertGreaterThan(UI.exclusions, 0)
        page = nil
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testAssociatedOriginSurvivesTemporaryOwnerAndEndsAtControllerRelease() {
        let context = Context(); var controller: ViewController? = ViewController()
        do { let origin = BrowserAnalyticsOrigin(account: context, data: tab(), inherited: AnalyticsContext(excluded: true)); origin.bind(controller!) }
        XCTAssertGreaterThan(UI.exclusions, 0); controller = nil; XCTAssertEqual(UI.exclusions, 0)
    }
    func testDelayedPolicyAndCloseBeforeAcceptRetainOriginAndConfirmOnce() {
        let context = Context(); let state = BrowserStateContext.get(context); FastSettings.needsConfirmation = true
        var result: Subscriber<String?, NoError>?
        context.engine.data.signal = Signal { result = $0; return EmptyDisposable }
        UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onConfirmed = { XCTAssertGreaterThan(UI.exclusions, 0) }
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertEqual(UI.alerts, 0)
        result?.putNext("synthetic"); result?.putNext("duplicate"); result = nil
        XCTAssertEqual(UI.alerts, 1)
        UI.dismiss?(); UI.accept?(true); UI.accept?(true); drainMain()
        XCTAssertEqual(FastSettings.confirmed, [2]); XCTAssertEqual(state.browser?.webpages.count, 1); XCTAssertGreaterThan(UI.exclusions, 0)
    }
    func testCancelAndUnknownConfirmationDoNotMarkOrCreateBrowser() {
        for cancel in [true, false] {
            let context = Context(); let state = BrowserStateContext.get(context); FastSettings.needsConfirmation = true
            state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
            if cancel { UI.cancel?() }; UI.dismiss?(); drainMain(); UI.accept?(true)
            XCTAssertTrue(FastSettings.confirmed.isEmpty); XCTAssertNil(state.browser); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testHeaderChatConsumesRequestUnderOriginWithoutConfirmingBot() {
        let context = Context(); let state = BrowserStateContext.get(context); FastSettings.needsConfirmation = true
        var navigations = 0
        BrowserHooks.shared.openChatWithContext = { _, id, origin in navigations += 1; XCTAssertEqual(id, 2); XCTAssertTrue(origin.isExcluded); XCTAssertGreaterThan(UI.exclusions, 0) }
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        UI.header?.callback(0); UI.accept?(true); UI.header?.callback(0)
        XCTAssertEqual(navigations, 1); XCTAssertNil(state.browser); XCTAssertTrue(FastSettings.confirmed.isEmpty); XCTAssertEqual(UI.closedModals, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testNaturalDedupAndExplicitReuseTightenBeforePageAddAndCannotRelax() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab(), analyticsContext: AnalyticsContext())
        let container = state.browser!.webpages[2]!; container.createPage()
        UI.onPageAdd = { XCTAssertTrue(container.analyticsContext?.isExcluded == true); XCTAssertTrue(container.controller?.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(UI.exclusions, 0) }
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        state.open(tab: tab(), uniqueId: 2, analyticsContext: AnalyticsContext())
        XCTAssertEqual(state.browser?.webpages.count, 1); XCTAssertTrue(container.analyticsOrigin.context.isExcluded)
    }
    func testOrdinaryReuseKeepsOriginalGrantAndRefreshesAfterRevocation() {
        let context = Context(); let state = BrowserStateContext.get(context); let first = AnalyticsContext()
        state.open(tab: tab(), analyticsContext: first)
        XCTAssertEqual(UI.exclusions, 0)
        first.scope?.valid = false
        state.open(tab: tab(), uniqueId: 2, analyticsContext: AnalyticsContext())
        XCTAssertTrue(state.browser?.webpages[2]?.analyticsOrigin.context.scope === first.scope)
        XCTAssertGreaterThan(UI.exclusions, 0)
    }
    func testAllDestinationKindsAndForeignAccountRemainExcluded() {
        let context = Context()
        let values: [BrowserTabData.Data] = [
            .mainapp(bot: EnginePeer(id: -2), source: .generic),
            .webapp(bot: EnginePeer(id: 2), peerId: -3, buttonText: "", url: nil, payload: nil, threadId: nil, replyTo: nil, fromMenu: false),
            .webapp(bot: EnginePeer(id: 2), peerId: 3, buttonText: "", url: nil, payload: nil, threadId: nil, replyTo: MessageId(peerId: -3), fromMenu: false),
            .straight(bot: EnginePeer(id: 2), peerId: -3, title: "", result: RequestWebViewResult()),
            .game(url: "", peerId: 3, messageId: MessageId(peerId: -3))]
        for value in values { let origin = BrowserAnalyticsOrigin(account: context, data: value, inherited: AnalyticsContext()); XCTAssertTrue(origin.context.isExcluded); XCTAssertGreaterThan(UI.exclusions, 0) }
        let foreign = BrowserAnalyticsOrigin(account: Context(2), data: tab(), inherited: AnalyticsContext())
        XCTAssertNil(foreign.context.scope); XCTAssertGreaterThan(UI.exclusions, 0)
    }
    func testNilLegacyOriginFailsClosedAndDoesNotCreateAnOrdinaryGrant() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab())
        XCTAssertTrue(state.browser?.webpages[2]?.analyticsOrigin.context.isExcluded == true)
        XCTAssertNil(state.browser?.webpages[2]?.analyticsOrigin.context.scope)
    }
    func testBrowserLinkManagerCarriesParentOriginIntoNewChildTab() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        let browser = state.browser!; let parent = browser.webpages[2]!
        let manager = BrowserLinkManager(context: context, window: browser.window, unique: 2, arguments: browser.arguments, analyticsOrigin: parent.analyticsOrigin)
        manager.open(tab(3))
        XCTAssertEqual(browser.webpages.count, 2); XCTAssertTrue(browser.webpages[3]?.analyticsOrigin.context.isExcluded == true)
        XCTAssertFalse(browser.webpages[3]!.analyticsOrigin === parent.analyticsOrigin)
    }
    func testInstalledChatBridgePreservesOriginIntoBrowserState() {
        let context = Context(); let origin = AnalyticsContext(excluded: true)
        installedChatHooks().openBrowserTabWithContext?(context, .simple(bot: EnginePeer(id: 2), url: nil, buttonText: "", source: .settings), origin)
        XCTAssertTrue(BrowserStateContext.get(context).browser?.webpages[2]?.analyticsOrigin.context.isExcluded == true)
    }
    func testRevocationBeforePolicyDeliveryCannotCreateFreshOrdinaryTab() {
        let context = Context(); let state = BrowserStateContext.get(context); let origin = AnalyticsContext(); FastSettings.needsConfirmation = true
        var result: Subscriber<String?, NoError>?
        context.engine.data.signal = Signal { result = $0; return EmptyDisposable }
        state.open(tab: tab(), analyticsContext: origin)
        origin.scope?.valid = false
        UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }
        result?.putNext(nil); result = nil; UI.accept?(true)
        XCTAssertFalse(state.browser?.webpages[2]?.analyticsOrigin.context.scope?.valid ?? true)
        XCTAssertGreaterThan(UI.exclusions, 0)
    }
    func testNoConfirmationRoutesSkipLookupAndDoNotMarkConsent() {
        let context = Context(); let state = BrowserStateContext.get(context); context.appConfiguration.ageBot = "synthetic"; FastSettings.needsConfirmation = true
        state.open(tab: tab(), analyticsContext: AnalyticsContext())
        state.open(tab: .tonsite(url: "synthetic"), analyticsContext: AnalyticsContext())
        XCTAssertTrue(context.engine.data.requests.isEmpty); XCTAssertEqual(UI.alerts, 0); XCTAssertTrue(FastSettings.confirmed.isEmpty)
    }
    func testCloseConfirmationRechecksCountAfterAnotherTabOpens() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        let browser = state.browser!
        browser.arguments?.closeTab(2, true)
        state.open(tab: tab(3), analyticsContext: AnalyticsContext())
        UI.closeDismiss?(); UI.closeAccept?(true); UI.closeAccept?(true); drainMain()
        XCTAssertNil(browser.webpages[2]); XCTAssertNotNil(browser.webpages[3])
        XCTAssertTrue(state.browser === browser); XCTAssertEqual(UI.hides, 0)
    }
    func testCloseConfirmationRejectsReplacedContainerWithSameId() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        state.open(tab: tab(3), analyticsContext: AnalyticsContext())
        let browser = state.browser!
        let original = browser.webpages[2]!
        browser.arguments?.closeTab(2, true)
        browser.arguments?.closeTab(2, false)
        state.open(tab: tab(), analyticsContext: AnalyticsContext())
        let replacement = browser.webpages[2]
        XCTAssertNotNil(replacement)
        withExtendedLifetime(original) { UI.closeAccept?(true) }
        XCTAssertTrue(browser.webpages[2] === replacement); XCTAssertEqual(UI.hides, 0)
    }
    func testCloseCancelAndUnknownDismissalConsumeDecisionWithoutClosing() {
        for cancel in [true, false] {
            let context = Context(); let state = BrowserStateContext.get(context)
            state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
            let browser = state.browser!
            UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }
            browser.arguments?.closeTab(2, true)
            if cancel { UI.closeCancel?() }
            UI.closeDismiss?(); drainMain(); UI.closeAccept?(true)
            XCTAssertNotNil(browser.webpages[2]); XCTAssertEqual(UI.hides, 0)
            UI.reset()
        }
    }
    func testOldBrowserDecisionCannotHideReplacementBrowser() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        let old = state.browser!
        old.arguments?.closeTab(2, true)
        state.browser = nil
        state.open(tab: tab(3), analyticsContext: AnalyticsContext())
        let replacement = state.browser
        UI.closeAccept?(true)
        XCTAssertTrue(state.browser === replacement); XCTAssertEqual(UI.hides, 0)
    }
    func testLateCloseFromHiddenBrowserWithoutWindowIsIgnored() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        let browser = state.browser!
        browser.hide({})
        UI.hides = 0
        browser.arguments?.closeTab(2, true)
        XCTAssertNil(UI.closeAccept); XCTAssertEqual(UI.hides, 0)
    }
    func testCloseDecisionEndsItsOwnLeaseWithoutEndingRetainedTabOrigin() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        let retainedPage = state.browser!.webpages[2]!
        state.browser?.arguments?.closeTab(2, true)
        UI.closeAccept?(true); UI.closeAccept?(true)
        XCTAssertEqual(UI.hides, 1); XCTAssertNil(state.browser)
        XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(retainedPage.analyticsOrigin.context.isExcluded)
    }
    func testEmptyPolicyLookupReleasesRequestWithoutDialogOrConsent() {
        let context = Context(); let state = BrowserStateContext.get(context)
        FastSettings.needsConfirmation = true
        context.engine.data.signal = .complete()
        state.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        XCTAssertEqual(UI.exclusions, 0); XCTAssertEqual(UI.alerts, 0)
        XCTAssertNil(state.browser); XCTAssertTrue(FastSettings.confirmed.isEmpty)
    }
    func testPolicyDeliveryAfterStateReleaseDoesNotOpenOrRetainExclusion() {
        let context = Context(); var state: BrowserStateContext? = BrowserStateContext(context)
        FastSettings.needsConfirmation = true
        var result: Subscriber<String?, NoError>?
        context.engine.data.signal = Signal { result = $0; return EmptyDisposable }
        state?.open(tab: tab(), analyticsContext: AnalyticsContext(excluded: true))
        XCTAssertGreaterThan(UI.exclusions, 0)
        weak var weakState = state
        state = nil
        XCTAssertNil(weakState)
        result?.putNext(nil); result = nil
        XCTAssertEqual(UI.exclusions, 0); XCTAssertEqual(UI.alerts, 0); XCTAssertTrue(FastSettings.confirmed.isEmpty)
    }
    private func drainMain() {
        let done = expectation(description: "main delivery")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}
extension BrowserTests {
    func straight(_ peerId: PeerId = 3) -> BrowserTabData.Data { .straight(bot: EnginePeer(id: 2), peerId: peerId, title: "synthetic", result: RequestWebViewResult()) }
    func testExplicitQueryIdSurvivesInitialBrowserCreationAndTemporaryFieldsClear() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        XCTAssertEqual(Set(state.browser!.webpages.keys), [901]); XCTAssertEqual(UI.serial, 100)
        XCTAssertNil(state.browser?.initialUniqueId); XCTAssertNil(state.browser?.initialTab); XCTAssertNil(state.browser?.initialAnalyticsOrigin)
        XCTAssertTrue(state.browser?.webpages[901]?.analyticsOrigin.context.isExcluded == true)
        state.closeTab(uniqueId: 901)
        XCTAssertNil(state.browser); XCTAssertEqual(UI.hides, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testExplicitQueryIdsStayIndependentInExistingBrowserAndCloseOnlyTheirTab() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: tab(), analyticsContext: AnalyticsContext())
        let browser = state.browser!
        state.open(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        state.open(tab: straight(), uniqueId: 902, analyticsContext: AnalyticsContext())
        XCTAssertEqual(Set(browser.webpages.keys), [2, 901, 902]); XCTAssertEqual(UI.serial, 100)
        state.closeTab(uniqueId: 901)
        XCTAssertTrue(state.browser === browser); XCTAssertEqual(Set(browser.webpages.keys), [2, 902]); XCTAssertEqual(UI.hides, 0)
        state.closeTab(uniqueId: 999)
        XCTAssertEqual(Set(browser.webpages.keys), [2, 902]); XCTAssertEqual(UI.hides, 0)
    }
    func testExplicitQueryReuseKeepsContainerAndTightensBeforePageAdd() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(), uniqueId: 901, analyticsContext: AnalyticsContext())
        guard let container = state.browser?.webpages[901] else { return XCTFail("Missing explicit query tab") }
        container.createPage()
        var adds = 0
        UI.onPageAdd = {
            adds += 1; XCTAssertTrue(container.analyticsContext?.isExcluded == true)
            XCTAssertTrue(container.controller?.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(UI.exclusions, 0)
        }
        state.open(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        XCTAssertTrue(state.browser?.webpages[901] === container); XCTAssertEqual(state.browser?.webpages.count, 1); XCTAssertEqual(adds, 1)
    }
    func testImplicitStraightIdsStillCreateDistinctTabsAndChildTabsDoNotInheritQueryId() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(), analyticsContext: AnalyticsContext())
        state.open(tab: straight(), analyticsContext: AnalyticsContext())
        XCTAssertEqual(Set(state.browser!.webpages.keys), [101, 102])
        state.open(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        let browser = state.browser!
        guard let parent = browser.webpages[901] else { return XCTFail("Missing explicit query parent") }
        let manager = BrowserLinkManager(context: context, window: browser.window, unique: 901, arguments: browser.arguments, analyticsOrigin: parent.analyticsOrigin)
        manager.open(straight())
        XCTAssertEqual(Set(browser.webpages.keys), [101, 102, 901, 103])
        XCTAssertTrue(browser.webpages[103]?.analyticsOrigin.context.isExcluded == true)
    }
    func testDelayedConsentRetainsQueryIdWhenAnotherBrowserOpensFirst() {
        let context = Context(); let state = BrowserStateContext.get(context)
        FastSettings.needsConfirmation = true
        var policy: Subscriber<String?, NoError>?
        context.engine.data.signal = Signal { policy = $0; return EmptyDisposable }
        state.open(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        state.open(tab: .tonsite(url: "synthetic"), analyticsContext: AnalyticsContext())
        let browser = state.browser!
        policy?.putNext(nil); policy = nil
        UI.accept?(true); UI.accept?(true)
        XCTAssertTrue(state.browser === browser); XCTAssertEqual(Set(browser.webpages.keys), [101, 901])
        XCTAssertEqual(FastSettings.confirmed, [2]); XCTAssertTrue(browser.webpages[901]?.analyticsOrigin.context.isExcluded == true)
    }
    func testOldHideCompletionCannotClearReplacementBrowserOrItsQueryTab() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(), uniqueId: 901, analyticsContext: AnalyticsContext())
        let old = state.browser!
        UI.deferHide = true
        state.closeTab(uniqueId: 901)
        XCTAssertTrue(old.markAsDeinit); XCTAssertEqual(UI.hideCompletions.count, 1)
        state.open(tab: straight(-3), uniqueId: 902, analyticsContext: AnalyticsContext())
        let replacement = state.browser!
        XCTAssertFalse(replacement === old); XCTAssertEqual(Set(replacement.webpages.keys), [902])
        guard let completion = UI.hideCompletions.first else { return XCTFail("Missing old browser close") }
        completion(); completion(); UI.hideCompletions = []
        XCTAssertTrue(state.browser === replacement); XCTAssertEqual(Set(replacement.webpages.keys), [902])
        XCTAssertGreaterThan(UI.exclusions, 0)
    }
    func testHideWithoutCloseRetainsBrowserAndOldConstructorsKeepDefaultIdentity() {
        let context = Context(); let state = BrowserStateContext.get(context)
        let legacy = WebappBrowserController(context: context, initialTab: tab())
        state.show(legacy)
        XCTAssertEqual(Set(legacy.webpages.keys), [2])
        state.hide(close: false)
        XCTAssertTrue(state.browser === legacy)
        let observed = WebappBrowserController(context: context, initialTab: tab(3), analyticsContext: AnalyticsContext())
        state.show(observed)
        XCTAssertEqual(Set(observed.webpages.keys), [3]); XCTAssertNil(observed.initialUniqueId)
    }
}
extension BrowserTests {
    func testCancelledPolicyRequestDisposesUnderOriginAndCannotPresentLateResult() {
        let context = Context(); let state = BrowserStateContext.get(context)
        FastSettings.needsConfirmation = true
        var result: Subscriber<String?, NoError>?
        var disposals = 0
        context.engine.data.signal = Signal { subscriber in
            result = subscriber
            return ActionDisposable { disposals += 1; XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(Thread.isMainThread) }
        }
        let request = state.openCancellable(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        XCTAssertGreaterThan(UI.exclusions, 0)
        request.dispose(); request.dispose()
        result?.putNext(nil); result = nil
        XCTAssertEqual(disposals, 1); XCTAssertEqual(UI.alerts, 0); XCTAssertNil(state.browser); XCTAssertEqual(UI.exclusions, 0)
    }
    func testCancelledVisibleConsentKeepsExclusionUntilDismissalAndRejectsHeader() {
        let context = Context(); let state = BrowserStateContext.get(context)
        FastSettings.needsConfirmation = true
        var chats = 0
        BrowserHooks.shared.openChatWithContext = { _, _, _ in chats += 1 }
        let request = state.openCancellable(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        XCTAssertEqual(UI.alerts, 1)
        request.dispose()
        XCTAssertGreaterThan(UI.exclusions, 0)
        UI.header?.callback(0)
        XCTAssertEqual(chats, 0); XCTAssertEqual(UI.closedModals, 0); XCTAssertGreaterThan(UI.exclusions, 0)
        UI.dismiss?(); drainCancellationMain()
        XCTAssertEqual(UI.exclusions, 0); XCTAssertNil(state.browser); XCTAssertTrue(FastSettings.confirmed.isEmpty)
    }
    func testCancelledConsentCannotConfirmOrOpenEvenWithLateDuplicateAcceptance() {
        let context = Context(); let state = BrowserStateContext.get(context)
        FastSettings.needsConfirmation = true
        let request = state.openCancellable(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        request.dispose(); UI.accept?(true); UI.accept?(true)
        XCTAssertNil(state.browser); XCTAssertTrue(FastSettings.confirmed.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testOffMainCancellationInvalidatesBeforeQueuedMainCleanup() {
        let context = Context(); let state = BrowserStateContext.get(context)
        FastSettings.needsConfirmation = true
        var result: Subscriber<String?, NoError>?
        context.engine.data.signal = Signal { result = $0; return EmptyDisposable }
        let request = state.openCancellable(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        DispatchQueue.global().sync { request.dispose() }
        result?.putNext(nil); result = nil
        XCTAssertEqual(UI.alerts, 0); XCTAssertNil(state.browser)
        drainCancellationMain(); XCTAssertEqual(UI.exclusions, 0)
    }
    func testCancellingCompletedOpenDoesNotCloseItsTabOrReleaseTabExclusion() {
        let context = Context(); let state = BrowserStateContext.get(context)
        let request = state.openCancellable(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        request.dispose()
        XCTAssertNotNil(state.browser?.webpages[901]); XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertEqual(UI.hides, 0)
        state.closeTab(uniqueId: 901)
        XCTAssertNil(state.browser); XCTAssertEqual(UI.exclusions, 0)
    }
    func testOpenCompletionReportsSuccessOnceDespiteDisposalAndDismissal() {
        let context = Context(); let state = BrowserStateContext.get(context)
        FastSettings.needsConfirmation = true
        var results: [Bool] = []
        let request = state.openCancellable(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext(), completion: { results.append($0) })
        UI.dismiss?(); UI.accept?(true); UI.accept?(true)
        request.dispose(); drainCancellationMain()
        XCTAssertEqual(results, [true]); XCTAssertNotNil(state.browser?.webpages[901])
    }
    func testOpenCompletionReportsCancellationOnceForEveryExitWithoutOpening() {
        for exit in 0..<4 {
            let context = Context(); let state = BrowserStateContext.get(context)
            FastSettings.needsConfirmation = true
            if exit == 3 { context.engine.data.signal = .complete() }
            var results: [Bool] = []
            let request = state.openCancellable(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext(), completion: { results.append($0) })
            switch exit {
            case 0: UI.cancel?()
            case 1: UI.dismiss?(); drainCancellationMain()
            case 2: request.dispose()
            default: break
            }
            request.dispose(); UI.accept?(true); UI.dismiss?(); drainCancellationMain()
            XCTAssertEqual(results, [false]); XCTAssertNil(state.browser)
            UI.reset()
        }
    }
    func testForcedJoinRemovalBypassesFullscreenAndConfirmationWithoutCancellingOtherOperations() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(3), uniqueId: 901, analyticsContext: AnalyticsContext())
        state.open(tab: straight(4), uniqueId: 902, analyticsContext: AnalyticsContext())
        let browser = state.browser!
        browser.browser.isFullScreen = true
        browser.removeTab(901)
        XCTAssertNil(browser.webpages[901]); XCTAssertNotNil(browser.webpages[902]); XCTAssertTrue(state.browser === browser)
        XCTAssertNil(UI.closeAccept); XCTAssertTrue(UI.cancelledJoinIds.isEmpty); XCTAssertEqual(UI.cancelledJoinAccounts, 0)
        browser.removeTab(902)
        XCTAssertNil(state.browser); XCTAssertEqual(UI.hides, 1); XCTAssertEqual(UI.cancelledJoinAccounts, 0)
    }
    func testUserTabClosureCancelsOnlyItsJoinAndLastClosureCancelsAccountOperations() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(3), uniqueId: 901, analyticsContext: AnalyticsContext())
        state.open(tab: straight(4), uniqueId: 902, analyticsContext: AnalyticsContext())
        state.browser?.closeTab(901)
        XCTAssertEqual(UI.cancelledJoinIds, [901]); XCTAssertEqual(UI.cancelledJoinAccounts, 0)
        state.browser?.closeTab(902)
        XCTAssertNil(state.browser); XCTAssertEqual(UI.cancelledJoinAccounts, 1)
    }
    func testHiddenBrowserReusesOriginalTabsAndInvalidatesOldHideWhenOpenedAgain() {
        let context = Context(); let state = BrowserStateContext.get(context)
        let origin = AnalyticsContext(excluded: true)
        state.open(tab: straight(-3), uniqueId: 901, analyticsContext: origin)
        let browser = state.browser!; let window = browser.browser
        let container = browser.webpages[901]
        UI.deferHide = true
        state.hide(close: false)
        XCTAssertFalse(browser.markAsDeinit); XCTAssertTrue(state.browser === browser)
        XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertEqual(UI.cancelledJoinAccounts, 0)
        state.open(tab: straight(4), uniqueId: 902, analyticsContext: AnalyticsContext())
        XCTAssertTrue(state.browser === browser); XCTAssertTrue(browser.webpages[901] === container)
        XCTAssertEqual(window.shown, 2); XCTAssertEqual(window.handlerRemovals, 3)
        UI.hideCompletions[0](); UI.hideCompletions[0]()
        XCTAssertEqual(window.orderOutCount, 0); XCTAssertTrue(browser.window === window)
        XCTAssertTrue(browser.webpages[901]?.analyticsOrigin.context.isExcluded == true)
        XCTAssertGreaterThan(UI.exclusions, 0)
    }
    func testRepeatedHiddenAnimationsOnlyApplyLatestCompletion() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(), uniqueId: 901, analyticsContext: AnalyticsContext())
        let browser = state.browser!; let window = browser.browser
        UI.deferHide = true
        var completions = 0
        browser.hide({ completions += 1 }, close: false)
        browser.hide({ completions += 1 }, close: false)
        UI.hideCompletions[1](); UI.hideCompletions[0](); UI.hideCompletions[1]()
        XCTAssertEqual(window.orderOutCount, 1); XCTAssertEqual(completions, 2)
        XCTAssertFalse(browser.markAsDeinit); XCTAssertTrue(browser.window === window)
        state.show(browser)
        XCTAssertEqual(window.shown, 2); XCTAssertTrue(state.browser === browser)
    }
    func testTerminalCloseCannotBeRevivedByAccountFocusOrOlderHideCallback() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        let browser = state.browser!; let window = browser.browser
        UI.deferHide = true
        state.hide(close: false)
        state.hide(close: true)
        XCTAssertTrue(browser.markAsDeinit)
        state.show(browser); browser.makeKeyAndOrderFront()
        XCTAssertEqual(window.shown, 1)
        UI.hideCompletions[0]()
        XCTAssertEqual(window.orderOutCount, 0); XCTAssertTrue(browser.window === window)
        UI.hideCompletions[1](); UI.hideCompletions[1]()
        XCTAssertEqual(window.orderOutCount, 1); XCTAssertNil(browser.window); XCTAssertNil(state.browser)
        state.show(browser)
        XCTAssertNil(state.browser); XCTAssertEqual(UI.cancelledJoinAccounts, 1)
    }
    func testHideWithoutAnimationLayerStillCompletesAndClearsWindowOnClose() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(), uniqueId: 901, analyticsContext: AnalyticsContext())
        let browser = state.browser!; let window = browser.browser
        window.contentView?.layer = nil
        state.hide(close: false)
        XCTAssertEqual(window.orderOutCount, 1); XCTAssertTrue(browser.window === window)
        state.show(browser); state.hide(close: true)
        XCTAssertEqual(window.orderOutCount, 2); XCTAssertNil(browser.window); XCTAssertNil(state.browser)
        var completed = 0
        browser.hide({ completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertEqual(window.orderOutCount, 2)
    }
    func testClosingAnimationStillHidesCapturedWindowAfterControllerRelease() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(), uniqueId: 901, analyticsContext: AnalyticsContext())
        var browser: WebappBrowserController? = state.browser
        weak var weakBrowser = browser
        let window = browser!.browser
        UI.deferHide = true
        var completed = 0
        browser?.hide({ completed += 1 })
        state.browser = nil; browser = nil
        XCTAssertNil(weakBrowser)
        UI.hideCompletions[0](); UI.hideCompletions[0]()
        XCTAssertEqual(window.orderOutCount, 1); XCTAssertEqual(completed, 1)
    }
    func testHiddenQueryCanBeRemovedWithoutRestoringOrCancellingOtherOperations() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(-3), uniqueId: 901, analyticsContext: AnalyticsContext())
        let browser = state.browser!; let window = browser.browser
        UI.deferHide = true
        state.hide(close: false)
        browser.removeTab(901)
        XCTAssertTrue(browser.webpages.isEmpty); XCTAssertTrue(browser.markAsDeinit)
        XCTAssertEqual(UI.cancelledJoinAccounts, 0); XCTAssertEqual(window.shown, 1)
        UI.hideCompletions[1](); UI.hideCompletions[0]()
        XCTAssertNil(state.browser); XCTAssertEqual(window.orderOutCount, 1)
    }
    func testVisibleTabOpenRaisesWindowWithoutReplayingShowAnimation() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(), uniqueId: 901, analyticsContext: AnalyticsContext())
        let window = state.browser!.browser
        state.open(tab: straight(4), uniqueId: 902, analyticsContext: AnalyticsContext())
        XCTAssertEqual(window.shown, 1); XCTAssertEqual(window.front, 1)
        XCTAssertEqual(window.handlerRemovals, 1)
    }
    private func drainCancellationMain() {
        let done = expectation(description: "cancellable open cleanup")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}

extension BrowserTests {
    func testInvoiceCancellationOnlyForRemovedTabAndTerminalBrowserClosure() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(3), uniqueId: 901, analyticsContext: AnalyticsContext())
        state.open(tab: straight(4), uniqueId: 902, analyticsContext: AnalyticsContext())
        let browser = state.browser!
        browser.webpages[901]?.createPage(); browser.webpages[902]?.createPage()
        let first = browser.webpages[901]!.controller!, second = browser.webpages[902]!.controller!
        state.hide(close: false)
        XCTAssertEqual(first.cancelledInvoices, 0); XCTAssertEqual(second.cancelledInvoices, 0)
        state.show(browser); browser.removeTab(901)
        XCTAssertEqual(first.cancelledInvoices, 1); XCTAssertEqual(second.cancelledInvoices, 0)
        state.hide(close: true)
        XCTAssertEqual(second.cancelledInvoices, 1)
    }
    func testUserInvoiceTabRemovalCancelsBeforeRetainedPageIsReleased() {
        let context = Context(); let state = BrowserStateContext.get(context)
        state.open(tab: straight(3), uniqueId: 901, analyticsContext: AnalyticsContext())
        state.open(tab: straight(4), uniqueId: 902, analyticsContext: AnalyticsContext())
        let browser = state.browser!
        browser.webpages[901]?.createPage()
        let page = browser.webpages[901]!.controller!
        browser.closeTab(901)
        XCTAssertEqual(page.cancelledInvoices, 1); XCTAssertNil(browser.webpages[901])
        state.hide(close: true)
    }
}
