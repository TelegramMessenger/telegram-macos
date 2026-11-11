struct ChatTextInputState { let text: String }
struct FileSlowMode { let hasLocked: Bool }
struct FileStars { let value: Int64 }
struct FileStarsState { let balance: FileStars }
struct FileInterfaceState { var forwardMessageIds: [MessageId] = [] }
struct FilePresentation {
    var interfaceState = FileInterfaceState()
    var threadInfo: Int? = nil
    var cachedData: Int? = nil
    var messageEffect: Int? = nil
    var peer: Peer? = Peer(42)
    var sendPaidMessageStars: FileStars?
    var starsState: FileStarsState?
    var alwaysPaidMessage = false
    func withUpdatedAlwaysPaidMessage(_ value: Bool) -> Self { var copy = self; copy.alwaysPaidMessage = value; return copy }
}
protocol ChatInteractionProtocol: AnyObject {
    var interactionContext: AccountContext { get }
    var peerId: PeerId { get }
    var peer: Peer? { get }
    @discardableResult func appendText(_ text: NSAttributedString, selectedRange: Range<Int>?) -> Range<Int>
    func sendFile(_ file: TelegramMediaFile, silent: Bool, query: String?, scheduled: Bool, collectionId: ItemCollectionId?)
}
class FileChatInteraction: ChatInteractionProtocol {
    struct Schedule { let date: Date; let repeatPeriod: Int32? }
    let interactionContext: AccountContext
    var peerId: PeerId = 42
    var peer: Peer? = Peer(42)
    var presentation = FilePresentation()
    var presentationSlowMode: FileSlowMode?
    var privateComposer = false
    var inheritedAnalyticsContext: AnalyticsContext?
    var sendAppFile: (TelegramMediaFile, Bool, String?, Bool, ItemCollectionId?, ChatTextInputState?, Schedule?) -> Void = { _, _, _, _, _, _, _ in FileProbe.check?(); FileProbe.legacy += 1 }
    var sendCreatedStickerWithAnalytics: ((TelegramMediaFile, AnalyticsContext, AnalyticsStickerSendRequest?) -> Void)?
    init(_ context: AccountContext = AccountContext()) { interactionContext = context }
    func captureAnalyticsContext() -> AnalyticsContext {
        let origin = Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: inheritedAnalyticsContext)
        return privateComposer ? Analytics.shared.unresolvedContext() : origin.restricting(peerId: peer?.id ?? peerId)
    }
    func captureAnalyticsContext(inherited: AnalyticsContext) -> AnalyticsContext {
        let current = captureAnalyticsContext()
        guard !current.isExcluded, current.scope?.isValid == true else { return current }
        return Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: inherited)
    }
    func update(_ f: (FilePresentation) -> FilePresentation) { FileProbe.check?(); presentation = f(presentation) }
    func sendMessage(_ silent: Bool, _ schedule: Schedule?, _ effect: Int?) { FileProbe.check?(); FileProbe.forwarded += 1 }
    @discardableResult func appendText(_ text: NSAttributedString, selectedRange: Range<Int>?) -> Range<Int> { 0..<text.length }
__APPEND_OBSERVED__
    func sendFile(_ file: TelegramMediaFile, silent: Bool, query: String?, scheduled: Bool, collectionId: ItemCollectionId?) { sendAppFile(file, silent, query, scheduled, collectionId, nil, nil) }
__FILE_OBSERVED__
}
extension TelegramMediaFile { var maskData: Int? { fileId == -1 ? 1 : nil } }
extension Peer {
    var displayTitle: String { "Peer" }
    func canSendMessage(_ thread: Bool, media: TelegramMediaFile, threadData: Int?, cachedData: Int?) -> Bool { FileProbe.check?(); return FileProbe.canSend }
}
enum FileMode { case history, scheduled; var isThreadMode: Bool { false } }
enum FileStickerStep { case openSchedule, cancelSchedule, openConfirmation, cancelConfirmation }
enum FileStickerFailure { case paymentRequired, chatPermission, enqueueRejected }
enum FileStickerResult { case accepted, terminalFailure(FileStickerFailure) }
final class AnalyticsStickerSendRequest {
    let origin: AnalyticsContext
    var discarded = false
    init(_ origin: AnalyticsContext) { self.origin = origin }
    func restrict(to context: AnalyticsContext) { if context.isExcluded || context.scope?.isValid != true || context.scope !== origin.scope { discarded = true } }
    func end() { discarded = true }
    func fail(_ reason: FileStickerFailure) { discarded = true }
    func step(_ step: FileStickerStep) {}
    func cancel() { discarded = true }
    func commit(scheduled: Bool, silent: Bool) -> FileStickerSubmission? { discarded ? nil : FileStickerSubmission() }
}
final class FileStickerSubmission {
    func complete(_ build: () -> FileStickerResult?) { FileProbe.check?(); _ = build() }
    func end() { FileProbe.check?() }
}
final class FileObservation {
    func complete(expectedCount: Int, resultCount: Int, acceptedCount: Int) { FileProbe.check?(); FileProbe.results.append((expectedCount, resultCount, acceptedCount)) }
}
func chatAnalyticsMessageKind(_ file: TelegramMediaFile) -> Int { 0 }
struct FileSend {
    let id: Int64
    let silent: Bool
    let date: Date?
    let repeatPeriod: Int32?
    let caption: String?
    let query: String?
}
enum Sender {
    static func enqueue(media: TelegramMediaFile, context: AccountContext, peerId: PeerId, replyId: Int?, threadId: Int64?, silent: Bool, atDate: Date?, repeatPeriod: Int32?, query: String?, collectionId: ItemCollectionId?, customChatContents: Int?, sendPaidMessageStars: Int?, observedResult: @escaping (Int, [MessageId?]) -> Void) -> Signal<[MessageId?], NoError> {
        FileProbe.operation(.init(id: media.fileId, silent: silent, date: atDate, repeatPeriod: repeatPeriod, caption: nil, query: query), observedResult)
    }
    static func enqueue(media: [TelegramMediaFile], caption: ChatTextInputState, context: AccountContext, peerId: PeerId, replyId: Int?, threadId: Int64?, silent: Bool, atDate: Date?, repeatPeriod: Int32?, query: String?, collectionId: ItemCollectionId?, customChatContents: Int?, sendPaidMessageStars: Int?, observedResult: @escaping (Int, [MessageId?]) -> Void) -> Signal<[MessageId?], NoError> {
        FileProbe.operation(.init(id: media[0].fileId, silent: silent, date: atDate, repeatPeriod: repeatPeriod, caption: caption.text, query: query), observedResult)
    }
}
final class FileTransaction {
    var handler: (() -> Void)?
    func set(handler: @escaping () -> Void) { FileProbe.check?(); self.handler = handler }
}
enum FileConfirmResult { case basic, thrid }
func verifyAlert(for window: Int, header: String, information: String, ok: String, option: String, optionIsSelected: Bool, successHandler: @escaping (FileConfirmResult) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    FileProbe.check?(); FileProbe.confirm = successHandler; FileProbe.cancel = cancelHandler; FileProbe.dismiss = onDeinit
}
enum FastSettings { static func toggleCofirmPaid(_ peerId: PeerId, price: Int) { FileProbe.check?(); FileProbe.preferences += 1 } }
extension CommonStrings {
    var chatPayStarsConfirmTitle: String { "Confirm" }
    var chatPayStarsConfirmCheckbox: String { "Remember" }
    func starListItemCountOther(_ value: Int) -> String { String(value) }
    func chatPayStarsConfirmMessagesOther(_ value: Int) -> String { String(value) }
    func chatPayStarsConfirmPayOther(_ value: Int) -> String { String(value) }
    func chatPayStarsConfirmText(_ peer: String, _ amount: String, _ amount2: String, _ count: String) -> String { "Pay" }
}
struct FileNavigationHooks {
    static let shared = FileNavigationHooks()
    enum Source { case schedule(PeerId), stars }
    func selectDateObserved(_ context: AccountContext, _ window: Int, _ a: Int?, _ b: Int?, _ source: Source, analyticsContext: AnalyticsContext, selectedAt: @escaping (Date, Int32?) -> Void, cancelled: @escaping () -> Void, dismissed: @escaping () -> Void) {
        FileProbe.check?(); FileProbe.scheduleOrigin = analyticsContext; FileProbe.schedule = selectedAt; FileProbe.cancelSchedule = cancelled; FileProbe.dismissSchedule = dismissed
    }
    func showStarsPurchaseWithContext(_ context: AccountContext, _ window: Int, _ source: Source, _ peer: Int?, _ amount: Int64, _ origin: AnalyticsContext) { FileProbe.check?(); FileProbe.purchases.append(origin) }
}
final class AppFileHost {
    let chatInteraction: PackInteraction
    var mode = FileMode.history
    let nextTransaction = FileTransaction()
    init(_ context: AccountContext) { chatInteraction = PackInteraction(context); install() }
    func makeMessageSendObservation(_ kind: Int, analyticsContext: AnalyticsContext, scheduled: Bool, silent: Bool) -> FileObservation? {
        FileProbe.check?(); FileProbe.origins.append(analyticsContext)
        return analyticsContext.scope?.isValid == true ? FileObservation() : nil
    }
    func install() {
        let chatInteraction = self.chatInteraction
        let context = chatInteraction.interactionContext
        let makePeerId = { chatInteraction.peerId }
        let customChatContents: Int? = nil
        let takeReplyId: () -> Int? = { nil }
        let threadId64: () -> Int64? = { nil }
        let takePaidMessageStars: () -> Int? = { nil }
        let scrollAfterSend = { FileProbe.check?(); FileProbe.scrolls += 1 }
        let _afterSentTransition: (Bool) -> Void = { _ in FileProbe.check?(); FileProbe.transitions += 1 }
__APP_FILE_SEND__
    }
}
func installPackFileBridge() {
    var hooks = EntertainmentUIHooks.shared
__PACK_FILE_BRIDGE__
    EntertainmentUIHooks.shared = hooks
}
func showSlowModeTimeoutTooltip(_ mode: FileSlowMode, for view: NSView) { FileProbe.check?(); FileProbe.slowTooltips += 1 }
func makePackSend(context: AccountContext, getAnalyticsContext: @escaping () -> AnalyticsContext) -> (Any, NSView, Bool, Bool) -> Void {
    let close: (() -> Void)? = { FileProbe.check?(); FileProbe.closes += 1 }
    return __PACK_SEND_CALLBACK__
}
enum FileProbe {
    static var check: (() -> Void)?
    static var canSend = true
    static var legacy = 0, forwarded = 0, closes = 0, preferences = 0, scrolls = 0, transitions = 0, slowTooltips = 0
    static var sends: [FileSend] = []
    static var origins: [AnalyticsContext] = []
    static var purchases: [AnalyticsContext] = []
    static var results: [(Int, Int, Int)] = []
    static var sink: Subscriber<[MessageId?], NoError>?
    static var observe: ((Int, [MessageId?]) -> Void)?
    static var confirm: ((FileConfirmResult) -> Void)?
    static var cancel: (() -> Void)?
    static var dismiss: (() -> Void)?
    static var scheduleOrigin: AnalyticsContext?
    static var schedule: ((Date, Int32?) -> Void)?
    static var cancelSchedule: (() -> Void)?
    static var dismissSchedule: (() -> Void)?
    static func operation(_ send: FileSend, _ result: @escaping (Int, [MessageId?]) -> Void) -> Signal<[MessageId?], NoError> {
        check?(); sends.append(send)
        return Signal { subscriber in check?(); sink = subscriber; observe = result; return ActionDisposable { check?() } }
    }
    static func finish() { let ids: [MessageId?] = [.init(peerId: 42, id: 1)]; observe?(1, ids); sink?.putNext(ids); sink?.putCompletion(); sink = nil; observe = nil }
    static func reset() {
        check = nil; finish(); dismiss?(); dismiss = nil; confirm = nil; cancel = nil
        schedule = nil; scheduleOrigin = nil; cancelSchedule = nil; dismissSchedule = nil
        canSend = true; legacy = 0; forwarded = 0; closes = 0; preferences = 0; scrolls = 0; transitions = 0; slowTooltips = 0
        sends = []; origins = []; purchases = []; results = []
    }
}
final class PackFileSendContextTests: XCTestCase {
    var context: AccountContext!
    var host: AppFileHost!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        FileProbe.reset(); PackNavigationProbe.reset(); PackProbe.reset(); TagProbe.reset(); Analytics.shared = Analytics()
        context = AccountContext(); hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        host = AppFileHost(context); PackNavigationProbe.interaction = host.chatInteraction; installPackFileBridge()
    }
    override func tearDown() { FileProbe.reset(); drain(); PackNavigationProbe.reset(); PackProbe.reset(); TagProbe.reset(); host = nil; context = nil }
    func drain() { let ready = expectation(description: "callback"); DispatchQueue.main.async { ready.fulfill() }; wait(for: [ready], timeout: 2) }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func send(_ source: AnalyticsContext, silent: Bool = false, scheduled: Bool = false, file: Int64 = 7) {
        var preview: ReactionStickerModal? = StickerPackPreviewModalController(context, peerId: nil, references: [.stickers(42)], analyticsContext: source)
        let getter = preview!.getOrigin; preview = nil
        makePackSend(context: context, getAnalyticsContext: getter)(TelegramMediaFile(fileId: file), NSView(), silent, scheduled)
    }
    func expectExcluded() { FileProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }; PackNavigationProbe.check = FileProbe.check }
    func testOrdinaryPackSendRetainsOriginFileAndOptions() {
        let source = origin(); send(source, silent: true, scheduled: true)
        XCTAssertTrue(FileProbe.sends.isEmpty); XCTAssertTrue(FileProbe.scheduleOrigin?.scope === source.scope)
        let date = Date(timeIntervalSince1970: 100); FileProbe.schedule?(date, 60)
        XCTAssertEqual(FileProbe.sends.first?.id, 7); XCTAssertEqual(FileProbe.sends.first?.silent, true)
        XCTAssertEqual(FileProbe.sends.first?.date, date); XCTAssertEqual(FileProbe.sends.first?.repeatPeriod, 60)
        XCTAssertTrue(FileProbe.origins.first?.scope === source.scope); XCTAssertEqual(FileProbe.closes, 1)
        FileProbe.finish(); XCTAssertEqual(FileProbe.results.first?.2, 1)
    }
    func testPrivatePackGuardsProviderSubscriptionDeliveryAndTransition() {
        let source = origin(.excluded); expectExcluded(); send(source)
        FileProbe.finish(); host.nextTransaction.handler?()
        XCTAssertEqual(FileProbe.sends.count, 1); XCTAssertTrue(FileProbe.origins.first!.isExcluded)
        XCTAssertEqual(FileProbe.scrolls, 1); XCTAssertEqual(FileProbe.transitions, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testDelayedScheduleRechecksPrivateComposerAndAccount() {
        for accountChange in [false, true] {
            FileProbe.reset(); PackNavigationProbe.check = nil; let source = origin(); send(source, scheduled: true)
            if accountChange { hub.policy.setOwner(Account()) } else { host.chatInteraction.privateComposer = true }
            expectExcluded(); FileProbe.schedule?(Date(), nil); FileProbe.finish()
            XCTAssertEqual(FileProbe.sends.count, 1); XCTAssertFalse(FileProbe.origins.first!.scope?.isValid == true)
            host.chatInteraction.privateComposer = false
        }
    }
    func testPrivatePaymentConfirmationAndPurchaseRetainOrigin() {
        host.chatInteraction.presentation.sendPaidMessageStars = FileStars(value: 2)
        host.chatInteraction.presentation.starsState = FileStarsState(balance: FileStars(value: 0))
        expectExcluded(); send(origin(.excluded)); FileProbe.confirm?(.basic)
        XCTAssertEqual(FileProbe.purchases.count, 1); XCTAssertTrue(FileProbe.purchases.first!.isExcluded)
        XCTAssertTrue(FileProbe.sends.isEmpty)
    }
    func testPaymentSubmissionRechecksChangedComposerBeforePreferenceAndProvider() {
        host.chatInteraction.presentation.sendPaidMessageStars = FileStars(value: 2)
        host.chatInteraction.presentation.starsState = FileStarsState(balance: FileStars(value: 10))
        send(origin()); host.chatInteraction.privateComposer = true; expectExcluded(); FileProbe.confirm?(.thrid); FileProbe.finish()
        XCTAssertEqual(FileProbe.preferences, 1); XCTAssertEqual(FileProbe.sends.count, 1)
        XCTAssertFalse(FileProbe.origins.first!.scope?.isValid == true)
    }
    func testPrivateForwardContinuationKeepsGuardAfterEnqueueCompletes() {
        host.chatInteraction.presentation.interfaceState.forwardMessageIds = [.init(peerId: 42, id: 2)]
        expectExcluded(); send(origin(.excluded)); FileProbe.finish(); host.nextTransaction.handler?(); drain()
        XCTAssertEqual(FileProbe.forwarded, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testSlowModeMasksAndMissingChatDoNotSendOrClose() {
        let source = origin(.excluded); expectExcluded()
        host.chatInteraction.presentationSlowMode = FileSlowMode(hasLocked: true); send(source)
        XCTAssertEqual(FileProbe.slowTooltips, 1)
        host.chatInteraction.presentationSlowMode = nil; send(source, file: -1)
        PackNavigationProbe.interaction = nil; send(source)
        XCTAssertTrue(FileProbe.sends.isEmpty); XCTAssertEqual(FileProbe.closes, 0)
    }
    func testLegacyFallbackAndDisabledCollectionRemainFunctional() {
        hub.policy.isEnabled = false; expectExcluded(); send(origin()); FileProbe.finish()
        XCTAssertEqual(FileProbe.sends.count, 1); XCTAssertTrue(FileProbe.results.isEmpty)
        host.chatInteraction.sendAppFileWithContext = nil
        host.chatInteraction.sendAppFile = { _, silent, _, scheduled, _, _, _ in FileProbe.check?(); XCTAssertTrue(silent); XCTAssertTrue(scheduled); FileProbe.legacy += 1 }
        send(origin(), silent: true, scheduled: true); XCTAssertEqual(FileProbe.legacy, 1)
    }
    func testCaptionAndPreScheduleRetainOriginalArguments() {
        let source = origin(.excluded); expectExcluded()
        host.chatInteraction.sendAppFileObserved(.init(fileId: 9), true, "query", false, nil, .init(text: "caption"), .init(date: Date(timeIntervalSince1970: 123), repeatPeriod: 30), analyticsContext: source)
        XCTAssertEqual(FileProbe.sends.first?.caption, "caption"); XCTAssertEqual(FileProbe.sends.first?.query, "query")
        XCTAssertEqual(FileProbe.sends.first?.repeatPeriod, 30); FileProbe.finish()
    }
    func testScheduleCancellationAndOwnerLossDoNotSubmit() {
        send(origin(.excluded), scheduled: true); expectExcluded()
        FileProbe.cancelSchedule?(); FileProbe.dismissSchedule?()
        XCTAssertTrue(FileProbe.sends.isEmpty)
        host = nil; PackNavigationProbe.interaction = nil
        FileProbe.schedule?(Date(), nil)
        XCTAssertTrue(FileProbe.sends.isEmpty)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testExistingStickerRequestIsDiscardedForPrivateComposer() {
        let source = origin(); let request = AnalyticsStickerSendRequest(source)
        host.chatInteraction.privateComposer = true; expectExcluded()
        host.chatInteraction.sendCreatedStickerWithAnalytics?(.init(fileId: 7), source, request); FileProbe.finish()
        XCTAssertTrue(request.discarded); XCTAssertTrue(FileProbe.results.isEmpty)
    }
}
