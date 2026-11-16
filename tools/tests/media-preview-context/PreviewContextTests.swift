import Foundation
import XCTest
import SwiftSignalKit

struct PeerId: Hashable { var secret = false; var value = 1 }
struct Peer { var id = PeerId(); var displayTitle: String { "peer" }; func _asPeer() -> Peer { self } }
struct MessageId: Hashable { var peerId = PeerId() }
struct Message { var id = MessageId(); var containsSecretMedia = false }
struct EditState { var message = Message() }
struct ReplySubject { let messageId: MessageId }
struct InterfaceState {
    var replyMessageId: ReplySubject?
    var replyMessage: Message?
    var forwardMessageIds: [MessageId] = []
    var forwardMessages: [Message] = []
    var editState: EditState?
    var suggestPost: Int?
}
struct Presentation {
    var effectiveInput = ChatTextInputState()
    var interfaceState = InterfaceState()
    var currentSendAsPeerId: Int?
    var peer: Peer?
    var slowMode: StorySlowMode?
    var sendPaidMessageStars: StoryStars?
    var starsState: StoryBalance?
    var alwaysPaidMessage = false
    func withUpdatedAlwaysPaidMessage(_ value: Bool) -> Self { var copy = self; copy.alwaysPaidMessage = value; return copy }
}
enum ChatMode { case history, thread, scheduled, customChatContents, pinned, customLink, preview }
final class Engine {}
final class Window {}
struct Account { var engine = Engine(); let window = Window() }
typealias AnalyticsScope = Scope
final class Scope {
    func exclude() { isValid = false }
    let owner: Engine
    var isValid = true
    init(owner: Engine) { self.owner = owner }
}
final class Lease {
    let context: AnalyticsContext
    private var ended = false
    init(_ context: AnalyticsContext) { self.context = context; context.depth += 1; Analytics.activeContexts.append(context) }
    func end() {
        if !ended {
            ended = true
            context.depth -= 1
            if let index = Analytics.activeContexts.lastIndex(where: { $0 === context }) { Analytics.activeContexts.remove(at: index) }
        }
    }
    deinit { end() }
}
final class AnalyticsContext {
    let isExcluded: Bool
    let scope: Scope?
    var depth = 0
    init(excluded: Bool = false, scope: Scope? = nil) {
        self.isExcluded = excluded
        self.scope = excluded ? nil : scope
    }
    func restricting(peerId: PeerId) -> AnalyticsContext {
        peerId.secret ? AnalyticsContext(excluded: true) : self
    }
    func beginPresentation() -> Lease { Lease(self) }
__PRESERVING__
}
final class Analytics {
    static let shared = Analytics()
    static var activeContexts: [AnalyticsContext] = []
    var enabled = true
    func privacyContext(peerId: PeerId) -> AnalyticsContext { AnalyticsContext(excluded: peerId.secret) }
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(excluded: true) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext?) -> AnalyticsContext {
        guard enabled, !peerId.secret else { return unresolvedContext() }
        if let inherited {
            guard !inherited.isExcluded, let scope = inherited.scope, scope.isValid, scope.owner === engine else { return unresolvedContext() }
            return inherited
        }
        return AnalyticsContext(scope: Scope(owner: engine))
    }
}
enum AnalyticsValues { enum Via { case click } }
enum AnalyticsScreen { case chat, storiesViewer }
final class AnalyticsMediaJourney {
    static var onCreate: ((AnalyticsMediaJourney) -> Void)?
    let entry: Spec.EntryPoint
    let initialMode: Spec.MediaMode
    let source: AnalyticsScreen?
    var cancelled = false
    enum Spec {
        enum EntryPoint { case clipboard, attachFile, attachPhotoVideo }
        enum MediaMode { case media, file }
        enum Step { case openSchedule, cancelSchedule, openConfirmation, cancelConfirmation }
        enum LastBlocker { case emptySelection, missingFiles, sizeLimit, fileUnavailable }
        enum SubmitVia { case direct }
    }
    let scope: Scope?
    let context: AnalyticsContext
    var discarded = false
    var steps: [Spec.Step] = []
    var failures: [Spec.LastBlocker] = []
    var commits: [Bool] = []
    var results: [Bool] = []
    var selections: [(Int, Spec.MediaMode)] = []
    var blockers: [Spec.LastBlocker] = []
    init(context: AnalyticsContext, entry: Spec.EntryPoint = .clipboard, mode: Spec.MediaMode = .media, via: AnalyticsValues.Via? = nil, source: AnalyticsScreen? = nil) { self.context = context; scope = context.scope; self.entry = entry; initialMode = mode; self.source = source; Self.onCreate?(self) }
    func restrict(to context: AnalyticsContext) {
        if context.isExcluded || context.scope !== scope { discard() }
    }
    func discard() { discarded = true }
    func step(_ step: Spec.Step) { if !discarded { steps.append(step) } }
    func fail(_ reason: Spec.LastBlocker) { if !discarded { failures.append(reason); discarded = true } }
    func blocked(_ reason: Spec.LastBlocker) { if !discarded { blockers.append(reason) } }
    func selected(count: Int, mode: Spec.MediaMode) { if !discarded { selections.append((count, mode)) } }
    func cancel() { if !discarded { cancelled = true }; discard() }
    func beginSubmission(parts: Int, via: Spec.SubmitVia, scheduled: Bool, silent: Bool) -> MediaSubmission? {
        guard !discarded else { return nil }
        commits.append(scheduled)
        return MediaSubmission(journey: self)
    }
}
final class ChatInteraction {
    var richDraftEntry: (value: Int, origin: AnalyticsContext?)?
__RICH_RESTRICTION__
    enum AttachMediaType { case photo, video }
    var sendAppFile: (TelegramMediaFile, Bool, String?, Bool, Int?, ChatTextInputState?, Schedule?) -> Void = { _, _, _, _, _, _, _ in }
    var sendAppFileWithContext: ((TelegramMediaFile, Bool, String?, Bool, Int?, ChatTextInputState?, Schedule?, AnalyticsContext) -> Void)?
    var sendCreatedStickerWithAnalytics: ((TelegramMediaFile, AnalyticsContext, AnalyticsStickerSendRequest?) -> Void)?
    var attachFile: (Bool) -> Void = { _ in }
    var attachPhotoOrVideo: (AttachMediaType?) -> Void = { _ in }
    struct Schedule { let date: Date; let repeatPeriod: Int32? }
    var interactionContext = Account()
    var peerId = PeerId()
    var peer: Peer?
    var inheritedAnalyticsContext: AnalyticsContext?
    private let composerAnalyticsScopes = Atomic(value: ComposerAnalyticsScopeState())
    var presentation = Presentation()
    var mode = ChatMode.history
    var voiceSendFlight: VoiceFlight? = VoiceFlight()
    var sendIsCurrent = true
    func captureDeferredSendAction() -> DeferredAction { DeferredAction { [weak self] in self?.sendIsCurrent == true } }
    func update(_ f: (Presentation) -> Presentation) { presentation = f(presentation); revokePrivateComposerAnalytics() }
__CAPTURE__
__PRESENT__
__DIRECT_API__
__MULTIPART_API__
}
final class Preview {
    let pendingActions = PreviewSenderPendingActions()
    var sent = false
    func capturePendingAction() -> () -> Bool { pendingActions.capture() }
__SEND_SOURCE__
    var analyticsContext: AnalyticsContext?
__JOURNEY__
    static func fromURLs(chatInteraction: ChatInteraction, analyticsContext: AnalyticsContext?, during: (AnalyticsContext) -> Void) -> AnalyticsContext {
__URL_INIT__
        during(analyticsContext)
        return analyticsContext
    }
    static func fromAppFile(chatInteraction: ChatInteraction, analyticsContext: AnalyticsContext?, during: (AnalyticsContext) -> Void) -> AnalyticsContext {
__APP_FILE_INIT__
        during(analyticsContext)
        return analyticsContext
    }
}
final class PreviewHost {
    let chatInteraction: ChatInteraction
    var onOpen: (AnalyticsContext, AnalyticsMediaJourney?) -> Void = { _, _ in }
    init(chatInteraction: ChatInteraction) { self.chatInteraction = chatInteraction }
    func install() {
__CONTROLLER_HANDOFF__
    }
}

final class PreviewContextTests: XCTestCase {
    override func setUp() { Analytics.shared.enabled = true }
    func testMarkedComposerRejectsCaptureAndRevokesHandedOffScopes() {
        let interaction = ChatInteraction()
        let captured = interaction.captureAnalyticsContext()
        XCTAssertTrue(captured.scope?.isValid == true)
        interaction.update { value in var value = value; value.effectiveInput.hasExcludedAnalytics = true; return value }
        XCTAssertFalse(captured.scope?.isValid == true)
        XCTAssertTrue(interaction.captureAnalyticsContext().isExcluded)
        XCTAssertTrue(interaction.captureAnalyticsContext(inherited: captured).isExcluded)
    }
    func testClearingMarkerAllowsFreshActionButCannotReviveCapturedGrant() {
        let interaction = ChatInteraction()
        let original = interaction.captureAnalyticsContext()
        interaction.update { value in var value = value; value.effectiveInput.hasExcludedAnalytics = true; return value }
        let excluded = interaction.captureAnalyticsContext()
        interaction.update { value in var value = value; value.effectiveInput.hasExcludedAnalytics = false; return value }
        XCTAssertTrue(interaction.captureAnalyticsContext().scope?.isValid == true)
        XCTAssertTrue(interaction.captureAnalyticsContext(inherited: original).isExcluded)
        XCTAssertTrue(interaction.captureAnalyticsContext(inherited: excluded).isExcluded)
    }
    func testUndoRestoredMarkerRevokesInterveningOrdinaryCapture() {
        let interaction = ChatInteraction()
        interaction.update { value in var value = value; value.effectiveInput.hasExcludedAnalytics = true; return value }
        interaction.update { value in var value = value; value.effectiveInput.hasExcludedAnalytics = false; return value }
        let intermediate = interaction.captureAnalyticsContext()
        interaction.update { value in var value = value; value.effectiveInput.hasExcludedAnalytics = true; return value }
        XCTAssertFalse(intermediate.scope?.isValid == true)
        XCTAssertTrue(interaction.captureAnalyticsContext().isExcluded)
    }
    func testEligibleHandoffPreservesOriginalScopeAndJourney() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let journey = AnalyticsMediaJourney(context: origin)
        var received = 0
        chat.presentPreviewSenderWithJourney = { urls, asMedia, text, context, task in
            received += 1
            XCTAssertTrue(context.scope === origin.scope)
            XCTAssertGreaterThan(context.depth, 0)
            XCTAssertTrue(task === journey)
            XCTAssertFalse(journey.discarded)
            XCTAssertEqual(urls.count, 1)
            XCTAssertTrue(asMedia)
            XCTAssertEqual(text?.string, "caption")
        }
        chat.showPreviewSender([URL(fileURLWithPath: "/file")], true, NSAttributedString(string: "caption"), analyticsContext: origin, journey: journey)
        XCTAssertEqual(received, 1)
        XCTAssertEqual(origin.depth, 0)
    }
    func testReceivingPrivateChatOrSourceRejectsSuppliedOrdinaryJourney() {
        for scenario in 0..<6 {
            let chat = ChatInteraction()
            let origin = chat.captureAnalyticsContext()
            let journey = AnalyticsMediaJourney(context: origin)
            switch scenario {
            case 0: chat.peerId.secret = true
            case 1: chat.peer = Peer(id: PeerId(secret: true))
            case 2: chat.presentation.interfaceState.forwardMessageIds = [MessageId(peerId: PeerId(secret: true))]
            case 3: chat.presentation.interfaceState.editState = EditState(message: Message(id: MessageId(peerId: PeerId(secret: true))))
            case 4: chat.inheritedAnalyticsContext = Analytics.shared.unresolvedContext()
            default: chat.interactionContext.engine = Engine()
            }
            var calls = 0
            chat.presentPreviewSenderWithJourney = { _, _, _, context, task in
                calls += 1
                XCTAssertTrue(context.isExcluded || context.scope == nil)
                XCTAssertGreaterThan(context.depth, 0)
                XCTAssertTrue(task === journey)
                XCTAssertTrue(journey.discarded)
            }
            chat.showPreviewSender([], false, nil, analyticsContext: origin, journey: journey)
            XCTAssertEqual(calls, 1)
        }
    }
    func testPrivateMissingAndRevokedOriginCannotBecomeOrdinaryAtHandoff() {
        for scenario in 0..<3 {
            let chat = ChatInteraction()
            let origin: AnalyticsContext
            switch scenario {
            case 0: origin = Analytics.shared.unresolvedContext()
            case 1: origin = AnalyticsContext()
            default:
                origin = chat.captureAnalyticsContext()
                origin.scope?.isValid = false
            }
            let journey = AnalyticsMediaJourney(context: origin)
            var calls = 0
            chat.presentPreviewSenderWithJourney = { _, _, _, context, _ in
                calls += 1
                XCTAssertTrue(context.isExcluded || context.scope == nil)
                XCTAssertTrue(journey.discarded)
            }
            chat.showPreviewSender([], true, nil, analyticsContext: origin, journey: journey)
            XCTAssertEqual(calls, 1)
        }
    }
    func testLegacyCallbackKeepsPrivacyLifetimeAndDiscardsUnsupportedJourney() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let journey = AnalyticsMediaJourney(context: origin)
        chat.peerId.secret = true
        var calls = 0
        chat.presentPreviewSender = { _, _, _, context in
            calls += 1
            XCTAssertTrue(context.isExcluded)
            XCTAssertGreaterThan(context.depth, 0)
        }
        chat.showPreviewSender([], true, nil, analyticsContext: origin, journey: journey)
        chat.showPreviewSender([], true, nil, analyticsContext: origin)
        XCTAssertTrue(journey.discarded)
        XCTAssertEqual(calls, 2)
    }
    func testJourneyFactoryValidatesDestinationAndAccountBeforeStarting() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        XCTAssertNotNil(chat.makeMediaAnalyticsJourney(context: origin, entry: .clipboard, mode: .media))
        chat.peerId.secret = true
        XCTAssertNil(chat.makeMediaAnalyticsJourney(context: origin, entry: .clipboard, mode: .media))
        chat.peerId.secret = false
        chat.interactionContext.engine = Engine()
        XCTAssertNil(chat.makeMediaAnalyticsJourney(context: origin, entry: .clipboard, mode: .media))
    }
    func testBothConstructorPrefixesValidateBeforeCreatingChildren() {
        for constructor in [Preview.fromURLs, Preview.fromAppFile] {
            let chat = ChatInteraction()
            let origin = chat.captureAnalyticsContext()
            let eligible = constructor(chat, origin) { context in
                XCTAssertTrue(context.scope === origin.scope)
                XCTAssertGreaterThan(context.depth, 0)
            }
            XCTAssertEqual(eligible.depth, 0)
            chat.peerId.secret = true
            let excluded = constructor(chat, origin) { context in
                XCTAssertTrue(context.isExcluded)
                XCTAssertGreaterThan(context.depth, 0)
            }
            XCTAssertEqual(excluded.depth, 0)
        }
    }
    func testInstalledControllerCallbackValidatesBeforeHandlingPreviewOutcome() {
        for secret in [false, true] {
            let chat = ChatInteraction()
            let origin = chat.captureAnalyticsContext()
            let journey = AnalyticsMediaJourney(context: origin)
            let host = PreviewHost(chatInteraction: chat)
            var calls = 0
            host.onOpen = { context, task in
                calls += 1
                XCTAssertEqual(context.isExcluded, secret)
                XCTAssertGreaterThan(context.depth, 0)
                XCTAssertTrue(task === journey)
                XCTAssertEqual(journey.discarded, secret)
            }
            host.install()
            chat.peerId.secret = secret
            chat.presentPreviewSenderWithJourney?([], true, nil, origin, journey)
            XCTAssertEqual(calls, 1)
        }
    }
    func testReleasedControllerDiscardsJourneyWithoutPresenting() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let journey = AnalyticsMediaJourney(context: origin)
        var host: PreviewHost? = PreviewHost(chatInteraction: chat)
        host?.onOpen = { _, _ in XCTFail("Presented after owner release") }
        host?.install()
        weak var released = host
        host = nil
        XCTAssertNil(released)
        chat.presentPreviewSenderWithJourney?([], true, nil, origin, journey)
        XCTAssertTrue(journey.discarded)
    }
    func testAttachmentToHiddenPrivateOrMismatchedPreviewDiscardsJourney() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        for context in [Analytics.shared.unresolvedContext(), chat.captureAnalyticsContext(), AnalyticsContext()] {
            let preview = Preview()
            preview.analyticsContext = context
            let journey = AnalyticsMediaJourney(context: origin)
            preview.analyticsMediaJourney = journey
            XCTAssertTrue(journey.discarded)
        }
    }
    func testReplacementDiscardsOldJourneyAndReadingTightenedContextDiscardsCurrent() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let first = AnalyticsMediaJourney(context: origin)
        let next = AnalyticsMediaJourney(context: origin)
        let preview = Preview()
        preview.analyticsContext = origin
        preview.analyticsMediaJourney = first
        preview.analyticsMediaJourney = first
        XCTAssertFalse(first.discarded)
        preview.analyticsMediaJourney = next
        XCTAssertTrue(first.discarded)
        XCTAssertFalse(next.discarded)
        preview.analyticsContext = Analytics.shared.unresolvedContext()
        XCTAssertTrue(preview.analyticsMediaJourney === next)
        XCTAssertTrue(next.discarded)
        preview.analyticsContext = origin
        XCTAssertTrue(preview.analyticsMediaJourney?.discarded == true)
    }
}

extension PreviewContextTests {
    func testReplySourceRestrictsPreviewFactoryAndInstalledHandoffBeforeChildren() {
        for pending in [false, true] {
            let chat = ChatInteraction()
            let origin = chat.captureAnalyticsContext()
            let journey = AnalyticsMediaJourney(context: origin)
            var message = Message()
            message.containsSecretMedia = true
            chat.presentation.interfaceState.replyMessageId = ReplySubject(messageId: message.id)
            chat.presentation.interfaceState.replyMessage = pending ? nil : message
            XCTAssertNil(chat.makeMediaAnalyticsJourney(context: origin, entry: .clipboard, mode: .media))
            let host = PreviewHost(chatInteraction: chat)
            var calls = 0
            host.onOpen = { context, _ in
                XCTAssertTrue(context.isExcluded)
                XCTAssertTrue(journey.discarded)
                XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded })
                calls += 1
            }
            host.install()
            chat.presentPreviewSenderWithJourney?([], true, nil, origin, journey)
            XCTAssertEqual(calls, 1)
        }
    }
}
