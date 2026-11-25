final class RichDraftHost {
    static let store = ChatRichTextDraftStore<Int, AnalyticsContext>()
    var invalidations = 0
    var revocations = 0
    func invalidateDeferredSendActions() { invalidations += 1 }
    func revokePrivateComposerAnalytics() { revocations += 1 }
    let interactionContext: Context
    let peerId: PeerId
    let richTextDraftKey: ChatRichTextDraftKey

    init(_ context: Context, accountId: Int64 = 1, peerId: PeerId = 1, threadId: Int64? = nil, welcome: Bool = false) {
        interactionContext = context
        self.peerId = peerId
        richTextDraftKey = ChatRichTextDraftKey(accountId: accountId, peerId: peerId, threadId: threadId, isWelcome: welcome)
    }

__RICH_RESTRICTION__
__RICH_EXCLUSION__
}

final class RichDraftContextTests: XCTestCase {
    var context: Context!
    var host: RichDraftHost!
    var hub: Analytics { Analytics.shared }

    override func setUp() {
        Analytics.shared = Analytics()
        context = Context()
        host = RichDraftHost(context)
        RichDraftHost.store.set(nil, for: host.richTextDraftKey)
        hub.policy.setOwner(context.engine.account)
        hub.policy.isEnabled = true
    }

    func ordinary() -> AnalyticsContext {
        hub.captureContext(engine: context.engine, peerId: 1)
    }

    func testMissingDraftPreservesComposerOrigin() {
        let current = ordinary()
        XCTAssertTrue(host.restrictRichTextDraftAnalyticsContext(current) === current)
    }

    func testUnclassifiedDraftIsExcludedWithoutChangingItsContent() {
        RichDraftHost.store.set(42, for: host.richTextDraftKey)
        XCTAssertTrue(host.restrictRichTextDraftAnalyticsContext(ordinary()).isExcluded)
        XCTAssertEqual(RichDraftHost.store.value(for: host.richTextDraftKey), 42)
    }

    func testReopenedDraftRetainsOriginalScope() {
        let source = ordinary()
        RichDraftHost.store.set(42, for: host.richTextDraftKey, origin: source)
        let reopened = RichDraftHost(context)
        let result = reopened.restrictRichTextDraftAnalyticsContext(ordinary())
        XCTAssertTrue(result.scope === source.scope)
        XCTAssertTrue(result.scope?.isValid == true)
        source.scope?.exclude()
        XCTAssertFalse(result.scope?.isValid == true)
        XCTAssertTrue(reopened.restrictRichTextDraftAnalyticsContext(ordinary()).isExcluded)
    }

    func testPrivateDraftAndPrivateReceiverStayExcluded() {
        let privateOrigin = hub.captureContext(engine: context.engine, peerId: -1)
        RichDraftHost.store.set(42, for: host.richTextDraftKey, origin: privateOrigin)
        XCTAssertTrue(host.restrictRichTextDraftAnalyticsContext(ordinary()).isExcluded)
        RichDraftHost.store.set(42, for: host.richTextDraftKey, origin: ordinary())
        XCTAssertTrue(host.restrictRichTextDraftAnalyticsContext(privateOrigin).isExcluded)
    }

    func testDisabledCollectionNeverBlocksDraftStorage() {
        hub.policy.isEnabled = false
        RichDraftHost.store.set(42, for: host.richTextDraftKey, origin: ordinary())
        XCTAssertEqual(RichDraftHost.store.value(for: host.richTextDraftKey), 42)
        XCTAssertTrue(host.restrictRichTextDraftAnalyticsContext(ordinary()).isExcluded)
        hub.policy.isEnabled = true
        XCTAssertTrue(host.restrictRichTextDraftAnalyticsContext(ordinary()).isExcluded)
    }

    func testAccountSwitchCannotAdoptStoredGrant() {
        RichDraftHost.store.set(42, for: host.richTextDraftKey, origin: ordinary())
        let replacement = Context()
        hub.policy.setOwner(replacement.engine.account)
        let current = hub.captureContext(engine: replacement.engine, peerId: 1)
        XCTAssertTrue(RichDraftHost(replacement).restrictRichTextDraftAnalyticsContext(current).isExcluded)
    }

    func testUnrelatedAccountChatThreadAndWelcomeKeysStayIndependent() {
        RichDraftHost.store.set(42, for: host.richTextDraftKey)
        for other in [RichDraftHost(context, accountId: 2), RichDraftHost(context, peerId: 2), RichDraftHost(context, threadId: 0), RichDraftHost(context, welcome: true)] {
            let current = ordinary()
            XCTAssertTrue(other.restrictRichTextDraftAnalyticsContext(current) === current)
        }
    }

    func testProvenanceOnlyChangeInvalidatesPendingRevision() {
        let source = ordinary()
        RichDraftHost.store.set(42, for: host.richTextDraftKey, origin: source)
        let revision = RichDraftHost.store.captureRevision(for: host.richTextDraftKey)
        XCTAssertFalse(RichDraftHost.store.set(42, for: host.richTextDraftKey, origin: source))
        XCTAssertTrue(revision.isValid)
        XCTAssertTrue(RichDraftHost.store.set(42, for: host.richTextDraftKey))
        XCTAssertFalse(revision.isValid)
        XCTAssertTrue(host.restrictRichTextDraftAnalyticsContext(ordinary()).isExcluded)
    }

    func testClearingDraftReleasesOriginAndCannotReviveOldRevision() {
        var source: AnalyticsContext? = ordinary()
        weak var observed = source
        RichDraftHost.store.set(42, for: host.richTextDraftKey, origin: source)
        let revision = RichDraftHost.store.captureRevision(for: host.richTextDraftKey)
        source = nil
        XCTAssertNotNil(observed)
        RichDraftHost.store.set(nil, for: host.richTextDraftKey)
        XCTAssertNil(observed)
        XCTAssertFalse(revision.isValid)
        XCTAssertNil(RichDraftHost.store.entry(for: host.richTextDraftKey))
        XCTAssertTrue(host.restrictRichTextDraftAnalyticsContext(ordinary()).scope?.isValid == true)
    }
}
