func bindFullEditorPaste(_ coordinator: RichEntryCoordinator, analyticsContext: AnalyticsContext) {
__FULL_PASTE_BINDING__
}

final class InlinePasteHost {
    let editor = RichEntryEditor()
    var chatInteraction: RichDraftHost?
    func bind() {
        let editor = self.editor
__INLINE_PASTE_BINDING__
    }
}

final class RichPasteContextTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        RichDraftHost.store.set(nil, for: RichDraftHost(context).richTextDraftKey)
        Probe.check = nil
    }
    override func tearDown() { Probe.check = nil }
    func origin(_ peer: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: peer) }

    func testFullEditorPasteExcludesOriginalBeforeMutationAndAfterGuardEnds() {
        let source = origin(), coordinator = RichEntryCoordinator()
        bindFullEditorPaste(coordinator, analyticsContext: source)
        var calls = 0
        coordinator.editor.withPasteContext? {
            calls += 1
            XCTAssertTrue(source.isExcluded)
            XCTAssertTrue(self.hub.policy.hasExclusions)
            coordinator.editor.replaceSelection(with: [1, 2])
        }
        XCTAssertEqual(calls, 1); XCTAssertEqual(coordinator.editor.blocks, [1, 2])
        XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertTrue(origin().scope?.isValid == true)
        XCTAssertTrue(source.isExcluded)
    }

    func testInlinePasteExcludesStoredOriginWithoutReplacingContent() {
        let source = origin(), draft = RichDraftHost(context), host = InlinePasteHost()
        RichDraftHost.store.set(42, for: draft.richTextDraftKey, origin: source)
        let revision = RichDraftHost.store.captureRevision(for: draft.richTextDraftKey)
        host.chatInteraction = draft; host.bind()
        host.editor.withPasteContext? {
            XCTAssertTrue(self.hub.policy.hasExclusions)
            XCTAssertTrue(source.isExcluded)
            XCTAssertFalse(revision.isValid)
            XCTAssertEqual(RichDraftHost.store.value(for: draft.richTextDraftKey), 42)
            host.editor.replaceSelection(with: [4, 5])
        }
        XCTAssertEqual(host.editor.blocks, [4, 5])
        XCTAssertEqual(draft.invalidations, 1); XCTAssertEqual(draft.revocations, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
        let reopened = RichDraftHost(context)
        XCTAssertTrue(reopened.restrictRichTextDraftAnalyticsContext(origin()).isExcluded)
    }

    func testInlineExclusionDoesNotChangeOtherAccountOrThreadDrafts() {
        let draft = RichDraftHost(context), other = RichDraftHost(context, accountId: 2, threadId: 9)
        let source = origin(), otherSource = origin()
        RichDraftHost.store.set(42, for: draft.richTextDraftKey, origin: source)
        RichDraftHost.store.set(99, for: other.richTextDraftKey, origin: otherSource)
        let revision = RichDraftHost.store.captureRevision(for: other.richTextDraftKey)
        draft.excludeRichTextDraftAnalytics()
        XCTAssertEqual(RichDraftHost.store.value(for: other.richTextDraftKey), 99)
        XCTAssertTrue(RichDraftHost.store.entry(for: other.richTextDraftKey)?.origin === otherSource)
        XCTAssertTrue(revision.isValid)
        XCTAssertFalse(otherSource.isExcluded)
        RichDraftHost.store.set(nil, for: other.richTextDraftKey)
    }

    func testMissingDraftDoesNotInventContentOrInvalidation() {
        let draft = RichDraftHost(context)
        draft.excludeRichTextDraftAnalytics()
        XCTAssertNil(RichDraftHost.store.entry(for: draft.richTextDraftKey))
        XCTAssertEqual(draft.invalidations, 0); XCTAssertEqual(draft.revocations, 0)
    }

    func testReleasedInlineHostStillRunsPasteUnderExclusion() {
        var host: InlinePasteHost? = InlinePasteHost()
        weak var observed = host
        host?.bind()
        let editor = host!.editor
        host = nil
        XCTAssertNil(observed)
        var calls = 0
        editor.withPasteContext? { calls += 1; XCTAssertTrue(self.hub.policy.hasExclusions) }
        XCTAssertEqual(calls, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testDisabledAndAlreadyPrivateOriginsKeepPasteFunctional() {
        for source in [origin(-1), hub.unresolvedContext()] {
            let coordinator = RichEntryCoordinator()
            bindFullEditorPaste(coordinator, analyticsContext: source)
            hub.policy.isEnabled = false
            var calls = 0
            coordinator.editor.withPasteContext? {
                calls += 1
                XCTAssertTrue(self.hub.policy.hasExclusions)
                coordinator.editor.replaceSelection(with: [9])
            }
            XCTAssertEqual(calls, 1); XCTAssertEqual(coordinator.editor.blocks, [9])
            XCTAssertFalse(hub.policy.hasExclusions)
        }
    }
}
