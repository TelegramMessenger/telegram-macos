__PREVIEW_INFO__
struct TelegramAIComposeToneExample: Equatable { let number: Int32 }
typealias StyleExample = TelegramAIComposeToneExample
struct PreviewState: Equatable {
    var info: StylePreviewInfo?
    var isLoading = true
    var example: StyleExample?
    var exampleNum: Int32 = 0
    var hasMoreExamples = true
    var isInstalled = false
}
struct PreviewArguments {
    let context: Context
    let requestAnother: () -> Void
    let openAuthor: (String, String) -> Void
}
func entries(_ state: PreviewState, arguments: PreviewArguments) -> [State] { Probe.check?(); PreviewProbe.state = state; PreviewProbe.arguments = arguments; return [] }
extension Context { var account: Account { engine.account } }
extension CloudStyle.Custom { var slug: String { "sample" } }
struct PreviewContent {
    struct StyleAttribute { let emojiFileId: Int64? }
    enum Attribute { case aiTextStyle(StyleAttribute), other }
    let title: String?
    let text: String?
    let author: String?
    let attributes: [Attribute]
}
struct PreviewWebpage {
    enum Content { case Loaded(PreviewContent), pending }
    let content: Content
}
struct ResolvedPreview { let webpage: PreviewWebpage }
enum PreviewResult { case progress, result(ResolvedPreview?) }
func webpagePreview(account: Account, urls: [String]) -> Signal<PreviewResult, NoError> {
    Probe.check?(); PreviewProbe.urls = urls
    return Signal { sink in Probe.check?(); PreviewProbe.webSinks.append(sink); return ActionDisposable { Probe.check?(); PreviewProbe.webDisposals += 1 } }
}
struct PreviewStickers {
    func resolveInlineStickers(fileIds: [Int64]) -> Signal<[Int64: TelegramMediaFile], NoError> {
        Probe.check?(); PreviewProbe.fileIds = fileIds
        return Signal { sink in Probe.check?(); PreviewProbe.fileSinks.append(sink); return ActionDisposable { Probe.check?(); PreviewProbe.fileDisposals += 1 } }
    }
}
extension Engine { var stickers: PreviewStickers { PreviewStickers() } }
extension Messages {
    func getAIComposeToneExample(slug: String, num: Int32) -> Signal<TelegramAIComposeToneExample?, NoError> {
        Probe.check?(); PreviewProbe.exampleRequests.append((slug, num))
        return Signal { sink in Probe.check?(); PreviewProbe.exampleSinks.append(sink); return ActionDisposable { Probe.check?(); PreviewProbe.exampleDisposals += 1 } }
    }
}
final class PreviewController: Controller {
    enum Screen { case chatAiEditorStylePreview }
    var analyticsScreen: Screen?
    var afterTransaction: ((PreviewController) -> Void)?
    var leftModalHeader: ModalHeaderData?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) { super.init(dataSignal) }
}
struct PreviewButton {
    enum Kind { case Normal }
    func set(text: String, for kind: Kind) { Probe.check?(); PreviewProbe.button = text }
}
extension ModalInteractions { func updateDone(_ action: (PreviewButton) -> Void) { Probe.check?(); action(PreviewButton()) } }
final class PreviewModal {
    let controller: PreviewController
    let interactions: ModalInteractions
    var analyticsContext: AnalyticsContext?
    var modal: PreviewModal? { self }
    init(_ controller: PreviewController, modalInteractions: ModalInteractions, size: NSSize) { Probe.check?(); self.controller = controller; interactions = modalInteractions }
    func close() { Probe.check?(); PreviewProbe.closes += 1 }
}
func showModal(with modal: PreviewModal, for window: Int) { Probe.check?(); PreviewProbe.presented = modal }
extension Strings {
    var aiStylePreviewAddStyle: String { "Add Style" }
    var aiStylePreviewOpenLinkOnTelegram: String { "Open in Telegram" }
    var inAppLinksStyleNotFound: String { "Not found" }
}
extension ParsedAboutLink {
    static func followResolvedName(link: String, username: String, postId: Int32?, forceProfile: Bool, context: Context, action: ChatInitialAction?, callback: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> ParsedAboutLink {
        Probe.check?(); PreviewProbe.author = (link, username); XCTAssertTrue(forceProfile); XCTAssertNil(postId); XCTAssertNil(action)
        return ParsedAboutLink(chatHistoryInAppLink: .internalLink)
    }
}
enum PreviewProbe {
    static var urls: [String] = []
    static var webSinks: [Subscriber<PreviewResult, NoError>] = []
    static var webDisposals = 0
    static var fileIds: [Int64] = []
    static var fileSinks: [Subscriber<[Int64: TelegramMediaFile], NoError>] = []
    static var fileDisposals = 0
    static var exampleRequests: [(String, Int32)] = []
    static var exampleSinks: [Subscriber<TelegramAIComposeToneExample?, NoError>] = []
    static var exampleDisposals = 0
    static var arguments: PreviewArguments?
    static var state = PreviewState()
    static var presented: PreviewModal?
    static var author: (String, String)?
    static var button = ""
    static var closes = 0
    static func reset() { urls = []; webSinks = []; webDisposals = 0; fileIds = []; fileSinks = []; fileDisposals = 0; exampleRequests = []; exampleSinks = []; exampleDisposals = 0; arguments = nil; state = PreviewState(); presented = nil; author = nil; button = ""; closes = 0 }
}
__PREVIEW_FETCH__
__PREVIEW_FACTORY__
func installPreviewAuthorBridge() {
    var hooks = styleShareHooks()
__PREVIEW_AUTHOR_BRIDGE__
    TranslateUIHooks.install(hooks)
}
func openStylePreviewLink(_ context: Context, slug: String = "sample", analyticsContext: AnalyticsContext?, afterComplete: (Bool) -> Void) {
    let getWindow: (Context) -> Int = { $0.window }
__PREVIEW_LINK__
}
final class StylePreviewTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.check = nil; PreviewProbe.reset(); AboutProbe.reset(); Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true; installPreviewAuthorBridge()
    }
    override func tearDown() {
        Probe.check = nil; PreviewProbe.presented = nil
        PreviewProbe.webSinks.forEach { $0.putCompletion() }; PreviewProbe.exampleSinks.forEach { $0.putCompletion() }; PreviewProbe.fileSinks.forEach { $0.putCompletion() }
        PreviewProbe.reset(); AboutProbe.reset(); TranslateUIHooks.install(.placeholder); super.tearDown()
    }
    func origin(_ id: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: id) }
    func info() -> StylePreviewInfo { .init(title: "title", description: "body", emojiFileId: 9, emojiFile: nil, authorUsername: "author") }
    func resolved(title: String? = "title") -> ResolvedPreview { .init(webpage: .init(content: .Loaded(.init(title: title, text: "body", author: "author", attributes: [.other, .aiTextStyle(.init(emojiFileId: 9))])))) }
    func excluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testOrdinaryLinkPassesScopeAndParsesMetadataAfterProgress() {
        let source = origin(); Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        var handled = false
        openStylePreviewLink(context, analyticsContext: source, afterComplete: { handled = $0 })
        XCTAssertTrue(handled); XCTAssertNil(PreviewProbe.presented)
        XCTAssertEqual(PreviewProbe.urls, ["https://example.invalid/addstyle/sample"])
        PreviewProbe.webSinks[0].putNext(.progress); XCTAssertNil(PreviewProbe.presented)
        PreviewProbe.webSinks[0].putNext(.result(resolved()))
        XCTAssertTrue(PreviewProbe.presented?.analyticsContext?.scope === source.scope)
        XCTAssertTrue(PreviewProbe.presented?.controller.analyticsContext?.scope === source.scope)
        XCTAssertEqual(PreviewProbe.state.info, info()); XCTAssertEqual(PreviewProbe.webDisposals, 1)
    }
    func testPrivateLinkProtectsLookupPreviewLoadingAndCleanup() {
        excluded(); var parent: Modal? = makeTranslation(context, analyticsContext: origin(-1))
        let inherited = parent!.getOrigin(); parent = nil
        openStylePreviewLink(context, analyticsContext: inherited, afterComplete: { _ in Probe.check?() })
        XCTAssertTrue(hub.policy.hasExclusions)
        PreviewProbe.webSinks[0].putNext(.result(resolved()))
        XCTAssertTrue(PreviewProbe.presented!.analyticsContext!.isExcluded)
        PreviewProbe.fileSinks[0].putNext([9: 9]); PreviewProbe.exampleSinks[0].putNext(.init(number: 0))
        context.engine.messages.styleSinks.last!.putNext([.init(id: 1, authorId: 1)])
        XCTAssertTrue(PreviewProbe.state.isInstalled)
        XCTAssertEqual(PreviewProbe.state.info?.emojiFile, 9)
        PreviewProbe.presented = nil; PreviewProbe.arguments = nil
        XCTAssertEqual(PreviewProbe.exampleDisposals, 1); XCTAssertEqual(PreviewProbe.fileDisposals, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testExamplePaginationStopsAtConfiguredLimitAndNilResponse() {
        let modal = AiStylePreviewModalController(context: context, slug: "sample", info: info(), analyticsContext: origin())
        PreviewProbe.exampleSinks[0].putNext(.init(number: 0)); PreviewProbe.arguments!.requestAnother()
        PreviewProbe.exampleSinks[1].putNext(.init(number: 1)); PreviewProbe.arguments!.requestAnother()
        PreviewProbe.exampleSinks[2].putNext(.init(number: 2)); PreviewProbe.arguments!.requestAnother()
        XCTAssertEqual(PreviewProbe.exampleRequests.map { $0.1 }, [0, 1, 2]); XCTAssertFalse(PreviewProbe.state.hasMoreExamples)
        PreviewProbe.exampleSinks[2].putNext(nil); XCTAssertFalse(PreviewProbe.state.hasMoreExamples)
        withExtendedLifetime(modal) {}
    }
    func testInstalledAndUninstalledButtonsPreserveExistingFeedbackWithoutSaving() {
        let modal = AiStylePreviewModalController(context: context, slug: "sample", info: info(), analyticsContext: origin())
        let toasts = ActionProbe.toasts
        context.engine.messages.styleSinks[0].putNext([]); modal.controller.afterTransaction?(modal.controller)
        XCTAssertEqual(PreviewProbe.button, "Add Style"); modal.interactions.accept()
        XCTAssertEqual(ActionProbe.toasts, toasts + 1); XCTAssertEqual(PreviewProbe.closes, 1)
        let installed = AiStylePreviewModalController(context: context, slug: "sample", info: info(), analyticsContext: origin())
        context.engine.messages.styleSinks.last!.putNext([.init(id: 1, authorId: 1)]); installed.controller.afterTransaction?(installed.controller)
        XCTAssertEqual(PreviewProbe.button, "OK"); installed.interactions.accept()
        XCTAssertEqual(ActionProbe.toasts, toasts + 1); XCTAssertEqual(PreviewProbe.closes, 2)
    }
    func testAuthorCallbackRetainsContextAfterModalRelease() {
        excluded()
        var modal: PreviewModal? = AiStylePreviewModalController(context: context, slug: "sample", info: info(), analyticsContext: origin(-1))
        let author = PreviewProbe.arguments!.openAuthor
        modal = nil; PreviewProbe.arguments = nil; XCTAssertFalse(hub.policy.hasExclusions)
        author("@author", "author")
        XCTAssertEqual(PreviewProbe.author?.0, "@author"); XCTAssertEqual(PreviewProbe.author?.1, "author")
        XCTAssertTrue(AboutProbe.executed!.isExcluded); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testAccountChangesBeforeLookupCompletesOrAuthorResolves() {
        openStylePreviewLink(context, analyticsContext: origin(), afterComplete: { _ in })
        hub.policy.setOwner(Account()); excluded()
        PreviewProbe.webSinks[0].putNext(.result(resolved()))
        XCTAssertTrue(PreviewProbe.presented!.analyticsContext!.scope?.isValid != true)
        PreviewProbe.arguments!.openAuthor("@author", "author")
        XCTAssertTrue(AboutProbe.executed!.scope?.isValid != true)
    }
    func testMissingOrPendingMetadataShowsFeedbackWithoutPreview() {
        for resolved in [ResolvedPreview?.none, .init(webpage: .init(content: .pending))] {
            excluded(); let toasts = ActionProbe.toasts
            openStylePreviewLink(context, analyticsContext: origin(-1), afterComplete: { _ in })
            PreviewProbe.webSinks.last!.putNext(.result(resolved))
            XCTAssertNil(PreviewProbe.presented); XCTAssertEqual(ActionProbe.toasts, toasts + 1)
            XCTAssertFalse(hub.policy.hasExclusions)
        }
    }
    func testMissingTitleFallsBackToSlugAndCancelledLookupReleasesGuard() {
        excluded(); var result: StylePreviewInfo?
        let disposable = fetchAiStylePreviewInfo(context: context, slug: "sample", analyticsContext: origin(-1)).start(next: { result = $0 })
        PreviewProbe.webSinks[0].putNext(.result(resolved(title: nil)))
        XCTAssertEqual(result?.title, "sample"); disposable.dispose(); XCTAssertFalse(hub.policy.hasExclusions)
        let cancelled = fetchAiStylePreviewInfo(context: context, slug: "sample", analyticsContext: origin(-1)).start()
        XCTAssertTrue(hub.policy.hasExclusions); cancelled.dispose(); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testLegacyAuthorFallbackAndDisabledPreviewRemainFunctional() {
        var calls = 0
        TranslateUIHooks.install(TranslateUIHooks(showAboutCocoonModal: { _ in }, shareLink: { _, _ in }, followResolvedName: { _, _, _ in Probe.check?(); calls += 1 }, showStyleEmojiPicker: { _, _, _ in }))
        hub.policy.isEnabled = false; excluded()
        var modal: PreviewModal? = AiStylePreviewModalController(context: context, slug: "sample", info: info())
        XCTAssertTrue(modal!.analyticsContext!.isExcluded)
        PreviewProbe.arguments!.openAuthor("@author", "author"); modal!.interactions.accept()
        XCTAssertEqual(calls, 1); modal = nil; PreviewProbe.arguments = nil; XCTAssertFalse(hub.policy.hasExclusions)
    }
}
