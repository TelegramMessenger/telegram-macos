typealias NSColor = Int
typealias LocalAnimatedSticker = Int
typealias ChatInitialAction = Int
extension Int {
    static var clear: Int { 0 }
    func makeKeyAndOrderFront(_ sender: Any?) { Probe.check?(); AboutProbe.focuses += 1 }
}
extension String { var nsstring: NSString { self as NSString } }
extension Theme {
    struct Colors { var accent: Int { 9 } }
    var colors: Colors { Colors() }
}
extension Theme.Icons { var modalClose: Int { 1 } }
struct TelegramThemeHooks {
    static var shared = TelegramThemeHooks()
    enum Icon { case cocoon120, iconOptionLock, iconOptionStatistics, iconOptionGift }
    struct Image { func precomposed(_ color: Int = 0) -> Int { Probe.check?(); return color } }
    func image(_ icon: Icon) -> Image { Probe.check?(); return Image() }
}
extension Strings {
    var aboutCocoonTitle: String { "Cocoon" }
    var aboutCocoonDescription: String { "description" }
    var aboutCocoonFeaturePrivateTitle: String { "private" }
    var aboutCocoonFeaturePrivateDescription: String { "private-description" }
    var aboutCocoonFeatureEfficientTitle: String { "efficient" }
    var aboutCocoonFeatureEfficientDescription: String { "efficient-description" }
    var aboutCocoonFeatureForEveryoneTitle: String { "everyone" }
    var aboutCocoonFeatureForEveryoneDescription: String { "everyone-description" }
    var aboutCocoonFooter: String { "footer" }
    var monetizationIntroUnderstood: String { "Understood" }
}
__ABOUT_CONFIG__
struct AboutState: Equatable {}
struct AboutArguments {
    let context: Context
    let dismiss: () -> Void
    let configuration: AboutFeatureConfiguration
}
func entries(_ state: AboutState, arguments: AboutArguments) -> [State] {
    Probe.check?(); AboutProbe.configuration = arguments.configuration
    return []
}
struct ModalHeaderData { let image: Int; let handler: () -> Void }
final class AboutController: Controller {
    enum Screen { case appFeatureInfo }
    enum Validation { case none }
    var analyticsScreen: Screen?
    var validateData: ((Int) -> Validation)?
    var leftModalHeader: ModalHeaderData?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) { super.init(dataSignal) }
    func returnKeyAction() -> Bool { Probe.check?(); _ = validateData?(0); return true }
}
final class AboutModal {
    let controller: AboutController
    let interactions: ModalInteractions
    var analyticsContext: AnalyticsContext?
    var _hasBorder = true
    var modal: AboutModal? { self }
    init(_ controller: AboutController, modalInteractions: ModalInteractions) { Probe.check?(); self.controller = controller; interactions = modalInteractions }
    func close() { Probe.check?(); AboutProbe.closes += 1 }
}
func showModal(with modal: AboutModal, for window: Int) { Probe.check?(); AboutProbe.presented = modal }
enum ChatLocation { case peer(PeerId) }
struct FocusTarget { let messageId: MessageId? }
final class ChatAdditionController {
    let peerId: PeerId
    var analyticsContext: AnalyticsContext?
    init(context: Context, chatLocation: ChatLocation, focusTarget: FocusTarget, initialAction: ChatInitialAction?) {
        Probe.check?(); switch chatLocation { case let .peer(id): peerId = id }
    }
    func inheritAnalyticsContext(_ origin: AnalyticsContext) { Probe.check?(); analyticsContext = origin }
}
final class AboutNavigation {
    var chats: [ChatAdditionController] = []
    func push(_ controller: ChatAdditionController) { Probe.check?(); chats.append(controller) }
}
struct AboutBindings { func rootNavigation() -> AboutNavigation { Probe.check?(); return AboutProbe.navigation } }
extension Context { var bindings: AboutBindings { AboutBindings() } }
enum PeerInfoController<C> {
    static func push(navigation: AboutNavigation, context: C, peerId: PeerId, analyticsContext: AnalyticsContext) {
        Probe.check?(); AboutProbe.profiles.append((peerId, analyticsContext))
    }
}
struct ParsedAboutLink {
    enum Kind { case external, internalLink }
    let chatHistoryInAppLink: Kind
}
typealias inAppLink = ParsedAboutLink
enum ChatHistoryLink {
    static func inApp(for url: NSString, context: Context, openInfo: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, confirm: Bool) -> ParsedAboutLink {
        Probe.check?(); XCTAssertFalse(confirm)
        AboutProbe.resolver = openInfo
        return ParsedAboutLink(chatHistoryInAppLink: AboutProbe.external ? .external : .internalLink)
    }
__ABOUT_EXECUTE__
}
func execute(inapp: inAppLink, analyticsContext: AnalyticsContext) { Probe.check?(); AboutProbe.executed = analyticsContext }
enum AboutProbe {
    static var configuration: AboutFeatureConfiguration?
    static var presented: AboutModal?
    static var navigation = AboutNavigation()
    static var resolver: ((PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)?
    static var profiles: [(PeerId, AnalyticsContext)] = []
    static var executed: AnalyticsContext?
    static var external = false
    static var closes = 0
    static var focuses = 0
    static func reset() { configuration = nil; presented = nil; navigation = AboutNavigation(); resolver = nil; profiles = []; executed = nil; external = false; closes = 0; focuses = 0 }
}
__ABOUT_FACTORY__
__COCOON_FACTORY__
func installAboutBridges() {
    var hooks = styleShareHooks()
__ABOUT_BRIDGE__
    TranslateUIHooks.install(hooks)
    var historyHooks = makeMessageHooks()
__ABOUT_EXECUTE_BRIDGE__
    ChatHistoryUIHooks.shared = historyHooks
}
func aboutHeaderAction(_ context: Context, getAnalyticsContext: @escaping () -> AnalyticsContext) -> () -> Void {
    return {
__ABOUT_HEADER__
    }
}
final class AboutContextTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.check = nil; AboutProbe.reset(); Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true; installAboutBridges()
    }
    override func tearDown() {
        Probe.check = nil; AboutProbe.reset(); TranslateUIHooks.install(.placeholder); ChatHistoryUIHooks.shared = makeMessageHooks()
        super.tearDown()
    }
    func origin(_ id: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: id) }
    func excluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testOrdinaryHeaderPassesScopeAndExistingContent() {
        let source = origin(); Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        aboutHeaderAction(context, getAnalyticsContext: { source })()
        XCTAssertTrue(AboutProbe.presented?.analyticsContext?.scope === source.scope)
        XCTAssertTrue(AboutProbe.presented?.controller.analyticsContext?.scope === source.scope)
        XCTAssertEqual(AboutProbe.configuration?.title, "Cocoon")
        XCTAssertEqual(AboutProbe.configuration?.features.map(\.title), ["private", "efficient", "everyone"])
        XCTAssertEqual(AboutProbe.configuration?.buttonTitle, "Understood")
        XCTAssertFalse(AboutProbe.presented!._hasBorder)
    }
    func testPrivateEntryAndFeatureFooterLinksRetainOriginAfterModalRelease() {
        excluded()
        var parent: Modal? = makeTranslation(context, analyticsContext: origin(-1))
        let header = aboutHeaderAction(context, getAnalyticsContext: parent!.getOrigin)
        parent = nil; XCTAssertFalse(hub.policy.hasExclusions); header()
        let config = AboutProbe.configuration!
        AboutProbe.presented = nil; AboutProbe.configuration = nil; XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertEqual(config.features.last!.linkCallback?("link"), true)
        XCTAssertTrue(AboutProbe.executed!.isExcluded)
        let resolve = AboutProbe.resolver!
        resolve(3, true, nil, nil)
        XCTAssertTrue(AboutProbe.navigation.chats.last!.analyticsContext!.isExcluded)
        XCTAssertEqual(config.footerLinkCallback?("link"), true)
        AboutProbe.resolver?(4, false, nil, nil)
        XCTAssertTrue(AboutProbe.profiles.last!.1.isExcluded)
        XCTAssertEqual(AboutProbe.focuses, 2); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testOrdinaryLinkResolutionKeepsScopeAndRestrictsPrivateDestination() {
        let source = origin(); showAboutCocoonModal(context: context, analyticsContext: source)
        let callback = AboutProbe.configuration!.footerLinkCallback!
        AboutProbe.presented = nil; AboutProbe.configuration = nil
        XCTAssertTrue(callback("link")); XCTAssertTrue(AboutProbe.executed!.scope === source.scope)
        let resolve = AboutProbe.resolver!
        resolve(2, false, nil, nil)
        XCTAssertTrue(AboutProbe.profiles.last!.1.scope === source.scope)
        excluded(); resolve(-2, true, nil, nil)
        XCTAssertTrue(AboutProbe.navigation.chats.last!.analyticsContext!.isExcluded)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testAccountChangesBeforeDelayedLinkResolution() {
        showAboutCocoonModal(context: context, analyticsContext: origin())
        _ = AboutProbe.configuration!.footerLinkCallback?("link")
        let resolve = AboutProbe.resolver!
        AboutProbe.presented = nil; AboutProbe.configuration = nil
        hub.policy.setOwner(Account()); excluded(); resolve(2, false, nil, nil)
        XCTAssertTrue(AboutProbe.profiles.last!.1.scope?.isValid != true)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRevokedAboutOriginCannotBecomeOrdinaryOnClick() {
        let source = origin(); showAboutCocoonModal(context: context, analyticsContext: source)
        let callback = AboutProbe.configuration!.footerLinkCallback!
        AboutProbe.presented = nil; AboutProbe.configuration = nil
        source.scope?.exclude(); excluded(); XCTAssertTrue(callback("link"))
        XCTAssertTrue(AboutProbe.executed!.isExcluded)
    }
    func testExternalLinkKeepsExistingDismissalDecision() {
        showAboutCocoonModal(context: context, analyticsContext: origin())
        AboutProbe.external = true
        XCTAssertEqual(AboutProbe.configuration!.footerLinkCallback?("https://example.invalid"), false)
        XCTAssertNotNil(AboutProbe.executed)
    }
    func testAllConfigurationCallbacksRemainGuardedAfterControllerRelease() {
        var called: [String] = []
        let configuration = AboutFeatureConfiguration(headerImage: 4, headerSticker: 5, headerBackgroundColor: 6, title: "title", description: "description", features: [.init(icon: 7, title: "feature", description: "body", linkCallback: { value in Probe.check?(); called.append(value); return false })], footerText: "footer", buttonTitle: "button", descriptionLinkCallback: { value in Probe.check?(); called.append(value) }, footerLinkCallback: { value in Probe.check?(); called.append(value); return true }, buttonCallback: { Probe.check?(); called.append("button") })
        excluded()
        var modal: AboutModal? = AboutFeatureModalController(context: context, configuration: configuration, analyticsContext: origin(-1))
        let guarded = AboutProbe.configuration!
        let accept = modal!.interactions.accept
        modal = nil; AboutProbe.configuration = nil; XCTAssertFalse(hub.policy.hasExclusions)
        guarded.descriptionLinkCallback?("description")
        XCTAssertEqual(guarded.features[0].linkCallback?("feature"), false)
        XCTAssertEqual(guarded.footerLinkCallback?("footer"), true)
        accept()
        XCTAssertEqual(called, ["description", "feature", "footer", "button"])
        XCTAssertEqual(guarded.headerImage, 4); XCTAssertEqual(guarded.headerSticker, 5); XCTAssertEqual(guarded.headerBackgroundColor, 6)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testLegacyAboutDefaultsToExcludedAndDisabledCollectionStillWorks() {
        for disabled in [false, true] {
            hub.policy.isEnabled = !disabled; excluded()
            showAboutCocoonModal(context: context)
            XCTAssertTrue(AboutProbe.presented!.analyticsContext!.isExcluded)
            AboutProbe.presented!.interactions.accept()
            XCTAssertEqual(AboutProbe.configuration!.features.count, 3)
            AboutProbe.presented = nil; AboutProbe.configuration = nil; XCTAssertFalse(hub.policy.hasExclusions)
        }
        XCTAssertEqual(AboutProbe.closes, 2)
    }
    func testLegacyHookAndLinkFallbacksKeepInvocationGuards() {
        var calls = 0
        TranslateUIHooks.install(TranslateUIHooks(showAboutCocoonModal: { _ in Probe.check?(); calls += 1 }, shareLink: { _, _ in }, followResolvedName: { _, _, _ in }, showStyleEmojiPicker: { _, _, _ in }))
        var hooks = makeMessageHooks(); hooks.executeLink = { _ in Probe.check?(); calls += 1 }; ChatHistoryUIHooks.shared = hooks
        excluded()
        TranslateUIHooks.shared.showAboutCocoonModalObserved(context, analyticsContext: origin(-1))
        ChatHistoryLink.execute(inapp: 1, analyticsContext: origin(-1))
        XCTAssertEqual(calls, 2); XCTAssertFalse(hub.policy.hasExclusions)
    }
}
