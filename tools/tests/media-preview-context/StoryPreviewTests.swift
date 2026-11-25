enum StoryBatchResult: Equatable { case accepted, partiallyAccepted, rejected }
extension String { var nsstring: NSString { self as NSString } }
struct StoryBatchArguments {
    let medias: [Media]
    let caption: ChatTextInputState
    let additional: ChatTextInputState?
    let peer: PeerId
    let story: StoryReplyId?
    let collage: Bool
    let silent: Bool
    let date: Date?
    let spoiler: Bool
    let leading: Bool
    let stars: Int64?
}
enum StoryPreviews {
    static var onCreate: ((AnalyticsContext) -> Void)?
    static var onShow: ((Preview) -> Void)?
    static var factoryAvailable = true
    static var preview: Preview?
    static var urls: [URL] = []
    static var batch: StoryBatchArguments?
    static var expected = 1
    static var ids: [Int?] = [1]
    static var completionOnly = false
    static var deferred: (() -> Void)?
    static var hold = false
    static var disposedUnderContext = false
    static func reset() {
        onCreate = nil; onShow = nil; factoryAvailable = true; preview = nil; urls = []
        batch = nil; expected = 1; ids = [1]; completionOnly = false; deferred = nil
        hold = false; disposedUnderContext = false
    }
}
extension FeatureNavigationHooks {
    func makePreviewSenderWithContext(_ urls: [URL], _ chat: ChatInteraction, _ asMedia: Bool, _ text: NSAttributedString?, _ appearance: Int, _ context: AnalyticsContext) -> Preview? {
        StoryPreviews.onCreate?(context)
        StoryPreviews.urls = urls
        guard StoryPreviews.factoryAvailable else { return nil }
        let preview = Preview()
        preview.analyticsContext = context
        StoryPreviews.preview = preview
        return preview
    }
}
typealias PreviewSenderController = Preview
final class ChatUIHooks {
    var bindPreviewSendValidation: (AnyObject, @escaping () -> Bool) -> Bool = { _, _ in false }
    init() {
__BIND_PREVIEW__
    }
    static let shared = ChatUIHooks()
    func attachPreviewJourney(_ preview: Preview, _ journey: AnalyticsMediaJourney) { preview.analyticsMediaJourney = journey }
}
func showModal(with preview: Preview, for window: Window) { StoryPreviews.onShow?(preview) }
extension Sender {
    static func enqueue(media: [Media], caption: ChatTextInputState, context: Account, peerId: PeerId, replyId: Int?, threadId: Int64?, replyStoryId: StoryReplyId?, isCollage: Bool, additionText: ChatTextInputState?, silent: Bool, atDate: Date?, isSpoiler: Bool, messageEffect: AvailableMessageEffects.MessageEffect?, leadingText: Bool, sendPaidMessageStars: StoryStars?, observedResult: @escaping (Int, [Int?]) -> Void) -> Signal<[Int?], NoError> {
        onBuild?()
        StoryPreviews.batch = StoryBatchArguments(medias: media, caption: caption, additional: additionText, peer: peerId, story: replyStoryId, collage: isCollage, silent: silent, date: atDate, spoiler: isSpoiler, leading: leadingText, stars: sendPaidMessageStars?.value)
        return Signal { subscriber in
            let deliver = {
                if !StoryPreviews.completionOnly {
                    observedResult(StoryPreviews.expected, StoryPreviews.ids)
                    subscriber.putNext(StoryPreviews.ids)
                }
                subscriber.putCompletion()
            }
            if StoryPreviews.hold { StoryPreviews.deferred = deliver } else { deliver() }
            return ActionDisposable {
                StoryPreviews.disposedUnderContext = !Analytics.activeContexts.isEmpty
            }
        }
    }
}
extension StoryHost {
    func installPreview() {
        let chatInteraction = self.chatInteraction
        let context = chatInteraction.interactionContext
        let darkAppearance = 0
        let beforeCompletion: () -> Void = { [weak self] in self?.before += 1 }
        let afterCompletion: () -> Void = { [weak self] in self?.after += 1 }
        let canAvoidGroupRestrictions = { false }
__STORY_PREVIEW__
__STORY_ATTACHMENTS__
    }
}

final class StoryPreviewTests: XCTestCase {
    var directory: URL!
    var file: URL { directory.appendingPathComponent("input") }
    override func setUpWithError() throws {
        StoryAttachmentPanels.reset(); AnalyticsMediaJourney.onCreate = nil
        StoryPreviews.reset(); StoryPayments.reset(); Analytics.shared.enabled = true; Sender.onBuild = nil
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1]).write(to: file)
    }
    override func tearDownWithError() throws {
        StoryAttachmentPanels.reset(); AnalyticsMediaJourney.onCreate = nil
        StoryPreviews.deferred?()
        StoryPreviews.reset(); Sender.onBuild = nil
        XCTAssertTrue(Analytics.activeContexts.isEmpty)
        try FileManager.default.removeItem(at: directory)
    }
    func present(_ host: StoryHost, origin: AnalyticsContext? = nil, urls: [URL]? = nil) -> AnalyticsMediaJourney {
        host.installPreview()
        let context = origin ?? host.chatInteraction.captureAnalyticsContext()
        let journey = AnalyticsMediaJourney(context: context)
        host.chatInteraction.showPreviewSender(urls ?? [file], true, nil, analyticsContext: context, journey: journey)
        return journey
    }
    func submit(_ host: StoryHost, _ submission: MediaSubmission?, part: Int = 1, media: [Media] = [Media(index: 1)]) {
        host.chatInteraction.sendMediasObserved(media, ChatTextInputState(text: "caption"), true, ChatTextInputState(text: "extra"), true, .init(date: Date(timeIntervalSince1970: 100), repeatPeriod: nil), true, nil, true, submission: submission, part: part)
    }
    func testPreviewCarriesOriginalJourneyThroughFactoryAndPresentation() {
        let host = StoryHost()
        let origin = host.chatInteraction.captureAnalyticsContext()
        StoryPreviews.onCreate = { context in
            XCTAssertTrue(context.scope === origin.scope)
            XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope })
        }
        StoryPreviews.onShow = { preview in XCTAssertNotNil(preview.analyticsMediaJourney) }
        let journey = present(host, origin: origin)
        XCTAssertTrue(StoryPreviews.preview?.analyticsMediaJourney === journey)
        XCTAssertEqual(journey.selections.count, 1)
        XCTAssertEqual(journey.selections.first?.0, 1)
        XCTAssertFalse(journey.discarded)
    }
    func testPreviewRejectsPrivateForeignAndRevokedOriginBeforeFactory() {
        for scenario in 0..<4 {
            StoryPreviews.reset()
            let host = StoryHost()
            let origin = host.chatInteraction.captureAnalyticsContext()
            switch scenario {
            case 0: host.interactions.update { state in var state = state; state.entryId = PeerId(secret: true); return state }
            case 1: host.chatInteraction.peerId.secret = true
            case 2: host.chatInteraction.interactionContext.engine = Engine()
            default: origin.scope?.isValid = false
            }
            StoryPreviews.onCreate = { context in
                XCTAssertTrue(context.isExcluded)
                XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded })
            }
            let journey = present(host, origin: origin)
            XCTAssertTrue(journey.discarded)
            XCTAssertNotNil(StoryPreviews.preview)
        }
    }
    func testFilteringFactoryFailureAndUnsupportedPreviewEndObservation() {
        let host = StoryHost()
        let partial = present(host, urls: [file, directory.appendingPathComponent("missing")])
        XCTAssertEqual(partial.blockers, [.missingFiles])
        XCTAssertEqual(partial.selections.first?.0, 1)
        let missing = present(host, urls: [directory.appendingPathComponent("missing")])
        XCTAssertEqual(missing.failures, [.missingFiles])
        let empty = present(host, urls: [])
        XCTAssertEqual(empty.failures, [.emptySelection])
        StoryPreviews.factoryAvailable = false
        XCTAssertTrue(present(host).discarded)
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(); return state }
        XCTAssertTrue(present(host).discarded)
    }
    func testPreviewBatchSkipsAbsentComposerAndPreservesAllFunctionalArguments() {
        let host = StoryHost()
        let journey = present(host)
        let submission = MediaSubmission(journey: journey)
        host.chatInteraction.sendMessageObserved(false, nil, nil, submission: submission, part: 0)
        XCTAssertEqual(submission.skippedParts, [0])
        submit(host, submission)
        XCTAssertFalse(journey.discarded)
        XCTAssertEqual(submission.batchResults, [.accepted])
        XCTAssertTrue(submission.ended)
        XCTAssertEqual(host.before, 1); XCTAssertEqual(host.after, 1)
        let batch = StoryPreviews.batch!
        XCTAssertEqual(batch.story, StoryReplyId(peerId: PeerId(), id: 7))
        XCTAssertEqual(batch.caption.text, "caption"); XCTAssertEqual(batch.additional?.text, "extra")
        XCTAssertTrue(batch.collage); XCTAssertTrue(batch.silent); XCTAssertTrue(batch.spoiler); XCTAssertTrue(batch.leading)
        XCTAssertEqual(batch.date, Date(timeIntervalSince1970: 100)); XCTAssertEqual(batch.stars, 2)
        XCTAssertTrue(StoryPreviews.disposedUnderContext)
    }
    func testBatchClassifiesExpectedMessageCountIncludingAdditionalText() {
        let cases: [(Int, [Int?], StoryBatchResult?)] = [(2, [1, 2], .accepted), (2, [1, nil], .partiallyAccepted), (2, [nil, nil], .rejected), (2, [1], nil), (0, [], nil)]
        for (expected, ids, result) in cases {
            StoryPreviews.reset()
            let host = StoryHost()
            let submission = MediaSubmission(journey: present(host))
            StoryPreviews.expected = expected; StoryPreviews.ids = ids
            submit(host, submission)
            XCTAssertEqual(submission.batchResults.count, 1)
            XCTAssertEqual(submission.batchResults[0], result)
        }
    }
    func testBatchCompletionWithoutResultRemainsUnknown() {
        let host = StoryHost()
        let submission = MediaSubmission(journey: present(host))
        StoryPreviews.completionOnly = true
        submit(host, submission)
        XCTAssertTrue(submission.batchResults.isEmpty)
        XCTAssertTrue(submission.ended)
    }
    func testBatchPrivateDestinationDiscardsJourneyButStillSendsPrivately() {
        let host = StoryHost()
        let submission = MediaSubmission(journey: present(host))
        let peer = PeerId(secret: true)
        host.interactions.update { state in var state = state; state.entryId = peer; return state }
        host.genericView.storyContext?.stateValue?.slice?.peer.id = peer
        Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
        submit(host, submission)
        XCTAssertTrue(submission.journey.discarded)
        XCTAssertTrue(submission.batchResults.isEmpty)
        XCTAssertEqual(StoryPreviews.batch?.peer, peer)
    }
    func testBatchBlockersAndClosedOwnerDiscardWithoutEnqueue() {
        for reason in 0..<5 {
            StoryPreviews.reset(); StoryPayments.reset()
            let host = StoryHost()
            let submission = MediaSubmission(journey: present(host))
            if reason == 0 { host.closed = true }
            if reason == 1 { host.chatInteraction.presentation.slowMode = StorySlowMode(timeout: 5) }
            if reason == 2 { StoryPayments.restricted = true }
            if reason == 3 { host.genericView.storyContext?.stateValue?.slice?.peer.id = PeerId(value: 9) }
            submit(host, submission, media: reason == 4 ? [] : [Media(index: 1)])
            XCTAssertTrue(submission.journey.discarded)
            XCTAssertNil(StoryPreviews.batch)
        }
    }
    func testLegacyBatchDoesNotInventProvenance() {
        let host = StoryHost()
        host.installPreview()
        Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
        host.chatInteraction.sendMedias([Media(index: 1)], ChatTextInputState(), false, nil, false, nil, false, nil, false)
        XCTAssertNotNil(StoryPreviews.batch)
    }
    func testPendingBatchRetainsContextAndSubmissionAfterControllerRelease() {
        var host: StoryHost? = StoryHost()
        let journey = present(host!)
        let submission = MediaSubmission(journey: journey)
        StoryPreviews.hold = true
        submit(host!, submission)
        weak var released = host
        host = nil
        XCTAssertNil(released)
        XCTAssertTrue(submission.batchResults.isEmpty)
        XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === journey.scope })
        StoryPreviews.deferred?(); StoryPreviews.deferred = nil
        XCTAssertEqual(submission.batchResults, [.accepted])
        XCTAssertTrue(StoryPreviews.disposedUnderContext)
    }
}

extension Int { var appearance: Int { self } }
let photoExts = ["jpg"]
let videoExts = ["mp4"]
let mediaExts = photoExts + videoExts
enum StoryAttachmentPanels {
    static var completion: (([String]?) -> Void)?
    static var cancelled: (() -> Void)?
    static var origin: AnalyticsContext?
    static var extensions: [String]?
    static var sizes: [String: Int64] = [:]
    static var limits: [Int64?] = []
    static func reset() { completion = nil; cancelled = nil; origin = nil; extensions = nil; sizes = [:]; limits = [] }
}
func filePanel(with exts: [String]?, canChooseDirectories: Bool, for window: Window, appearance: Int, analyticsContext: AnalyticsContext?, cancelled: @escaping () -> Void, completion: @escaping ([String]?) -> Void) {
    StoryAttachmentPanels.extensions = exts
    StoryAttachmentPanels.origin = analyticsContext
    StoryAttachmentPanels.completion = completion
    StoryAttachmentPanels.cancelled = cancelled
}
func fileSize(_ path: String) -> Int64? { StoryAttachmentPanels.sizes[path] }
extension FeatureNavigationHooks {
    func fileSizeLimitExceed(_ context: Account, _ size: Int64) -> Bool { size <= 100 }
    func showFileLimit(_ context: Account, _ size: Int64?) { StoryAttachmentPanels.limits.append(size) }
}
extension StoryPreviewTests {
    func testAttachmentButtonsCreateDistinctRoutesAndCompletePreviewHandoffOnce() {
        for asMedia in [false, true] {
            StoryPreviews.reset(); StoryAttachmentPanels.reset()
            let host = StoryHost()
            host.installPreview()
            var journey: AnalyticsMediaJourney?
            AnalyticsMediaJourney.onCreate = { journey = $0 }
            if asMedia { host.chatInteraction.attachPhotoOrVideo(nil) } else { host.chatInteraction.attachFile(false) }
            XCTAssertEqual(journey?.entry, asMedia ? .attachPhotoVideo : .attachFile)
            XCTAssertEqual(journey?.initialMode, asMedia ? .media : .file)
            XCTAssertEqual(journey?.source, .storiesViewer)
            XCTAssertEqual(StoryAttachmentPanels.extensions, asMedia ? mediaExts : nil)
            StoryAttachmentPanels.sizes[file.path] = 10
            StoryAttachmentPanels.completion?([file.path])
            StoryAttachmentPanels.completion?([file.path])
            StoryAttachmentPanels.cancelled?()
            StoryAttachmentPanels.completion?(nil)
            XCTAssertTrue(StoryPreviews.preview?.analyticsMediaJourney === journey)
            XCTAssertEqual(journey?.selections.count, 1)
            XCTAssertEqual(journey?.discarded, false)
        }
    }
    func testAttachmentPhotoAndVideoFiltersRemainDistinct() {
        let host = StoryHost(); host.installPreview()
        host.chatInteraction.attachPhotoOrVideo(.photo)
        XCTAssertEqual(StoryAttachmentPanels.extensions, photoExts)
        StoryAttachmentPanels.completion?(nil)
        host.chatInteraction.attachPhotoOrVideo(.video)
        XCTAssertEqual(StoryAttachmentPanels.extensions, videoExts)
        StoryAttachmentPanels.completion?(nil)
    }
    func testAttachmentCancellationDiffersFromUnknownCompletion() {
        for cancel in [false, true] {
            StoryAttachmentPanels.reset()
            let host = StoryHost(); host.installPreview()
            var journey: AnalyticsMediaJourney?
            AnalyticsMediaJourney.onCreate = { journey = $0 }
            host.chatInteraction.attachFile(false)
            if cancel { StoryAttachmentPanels.cancelled?() }
            StoryAttachmentPanels.completion?(nil)
            XCTAssertEqual(journey?.cancelled, cancel)
            XCTAssertEqual(journey?.discarded, true)
            XCTAssertNil(StoryPreviews.preview)
        }
    }
    func testAttachmentFilteringRecordsOnlyObservedCategoricalBlockers() {
        for scenario in 0..<4 {
            StoryAttachmentPanels.reset(); StoryPreviews.reset()
            let host = StoryHost(); host.installPreview()
            var journey: AnalyticsMediaJourney?
            AnalyticsMediaJourney.onCreate = { journey = $0 }
            host.chatInteraction.attachFile(false)
            let extra = directory.appendingPathComponent("extra").path
            if scenario == 1 { StoryAttachmentPanels.sizes[file.path] = 200 }
            if scenario == 3 { StoryAttachmentPanels.sizes[file.path] = 10; StoryAttachmentPanels.sizes[extra] = 200 }
            StoryAttachmentPanels.completion?(scenario == 0 ? [] : scenario == 3 ? [file.path, extra] : [file.path])
            if scenario == 3 {
                XCTAssertEqual(journey?.blockers, [.sizeLimit])
                XCTAssertEqual(journey?.selections.first?.0, 1)
                XCTAssertEqual(journey?.discarded, false)
            } else {
                XCTAssertEqual(journey?.failures, [scenario == 0 ? .emptySelection : scenario == 1 ? .sizeLimit : .fileUnavailable])
                XCTAssertNil(StoryPreviews.preview)
                if scenario == 1 { XCTAssertEqual(StoryAttachmentPanels.limits[0], 200) }
            }
        }
    }
    func testAttachmentNavigationAwayAndBackOrComposerChangeCannotOpenPreview() {
        for changeStory in [false, true] {
            StoryAttachmentPanels.reset(); StoryPreviews.reset()
            let host = StoryHost(); host.installPreview()
            var journey: AnalyticsMediaJourney?
            AnalyticsMediaJourney.onCreate = { journey = $0 }
            host.chatInteraction.attachFile(false)
            let original = host.interactions.presentation
            if changeStory {
                host.interactions.update { state in var state = state; state.storyId = 8; return state }
                host.interactions.update { _ in original }
            } else { host.chatInteraction.sendIsCurrent = false }
            StoryAttachmentPanels.sizes[file.path] = 10
            StoryAttachmentPanels.completion?([file.path])
            XCTAssertEqual(journey?.discarded, true)
            XCTAssertNil(StoryPreviews.preview)
        }
    }
    func testPrivateAttachmentOriginNeverCreatesAnEligibleJourney() {
        let host = StoryHost(); host.installPreview()
        host.interactions.update { state in var state = state; state.entryId = PeerId(secret: true); return state }
        var count = 0
        AnalyticsMediaJourney.onCreate = { _ in count += 1 }
        host.chatInteraction.attachFile(false)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(StoryAttachmentPanels.origin?.isExcluded, true)
        StoryAttachmentPanels.sizes[file.path] = 10
        StoryAttachmentPanels.completion?([file.path])
        XCTAssertEqual(StoryPreviews.preview?.analyticsContext?.isExcluded, true)
    }
    func testReleasedAttachmentOwnerDiscardsPendingSelection() {
        var host: StoryHost? = StoryHost(); host?.installPreview()
        var journey: AnalyticsMediaJourney?
        AnalyticsMediaJourney.onCreate = { journey = $0 }
        host?.chatInteraction.attachFile(false)
        weak var released = host
        host = nil
        XCTAssertNil(released)
        StoryAttachmentPanels.sizes[file.path] = 10
        StoryAttachmentPanels.completion?([file.path])
        XCTAssertEqual(journey?.discarded, true)
        XCTAssertNil(StoryPreviews.preview)
    }
}

extension StoryPreviewTests {
    func testPreviewSourceRemainsValidForMultipleBatchesWithoutConsumingStoryAction() {
        let host = StoryHost()
        let journey = present(host)
        let preview = StoryPreviews.preview!
        for _ in 0..<4 { XCTAssertTrue(preview.validateSendSource()) }
        XCTAssertFalse(journey.discarded)
        let action = host.interactions.captureReplyAction()
        XCTAssertTrue(action())
        XCTAssertFalse(action())
        XCTAssertTrue(preview.validateSendSource())
    }
    func testPresentedPreviewCannotFollowStoryNavigationOrReturnToOriginalStory() {
        for changePeer in [false, true] {
            StoryPreviews.reset()
            let host = StoryHost()
            let journey = present(host)
            let preview = StoryPreviews.preview!
            let original = host.interactions.presentation
            host.interactions.update { state in
                var state = state
                if changePeer { state.entryId = PeerId(value: 8) } else { state.storyId = 8 }
                return state
            }
            XCTAssertFalse(preview.validateSendSource())
            host.interactions.update { _ in original }
            XCTAssertFalse(preview.validateSendSource())
            XCTAssertTrue(journey.discarded)
        }
    }
    func testPreviewBindingRejectsClosedOrReleasedStoryOwner() {
        for release in [false, true] {
            StoryPreviews.reset()
            var host: StoryHost? = StoryHost()
            let journey = present(host!)
            let preview = StoryPreviews.preview!
            weak var released = host
            if release { host = nil; XCTAssertNil(released) } else { host?.closed = true }
            XCTAssertFalse(preview.validateSendSource())
            XCTAssertTrue(journey.discarded)
        }
    }
    func testNavigationDuringPreviewFactoryCannotBindAReplacementSource() {
        let host = StoryHost()
        StoryPreviews.onCreate = { _ in host.interactions.update { state in var state = state; state.storyId = 9; return state } }
        let journey = present(host)
        XCTAssertFalse(StoryPreviews.preview!.validateSendSource())
        XCTAssertTrue(journey.discarded)
    }
    func testSourceBindingWorksWithoutAnAnalyticsJourneyAndRejectsUnknownProvider() {
        let host = StoryHost()
        host.installPreview()
        let origin = host.chatInteraction.captureAnalyticsContext()
        host.chatInteraction.showPreviewSender([file], true, nil, analyticsContext: origin)
        let preview = StoryPreviews.preview!
        XCTAssertTrue(preview.validateSendSource())
        host.interactions.update { state in var state = state; state.closed = true; return state }
        XCTAssertFalse(preview.validateSendSource())
        XCTAssertFalse(ChatUIHooks.shared.bindPreviewSendValidation(NSObject(), { true }))
    }
}
