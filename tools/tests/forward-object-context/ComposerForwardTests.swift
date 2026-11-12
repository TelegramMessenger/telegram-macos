final class ComposerTransaction {
    var handler: (() -> Void)?
    var armed = 0
    func set(handler: @escaping () -> Void) { self.handler = handler; armed += 1 }
    func execute() { let current = handler; handler = nil; current?() }
}
enum ComposerBannedRight { case banSendInline }
final class InlineBotMessageAttribute {}
enum ComposerPermissions {
    static var onCheck: (() -> Void)?
    static var mediaBlocked = false
}
func permissionText(from peer: Peer, for right: ComposerBannedRight, cachedData: Int?) -> String {
    ComposerPermissions.onCheck?()
    return "inline blocked"
}
func checkMediaPermission(_ media: GalleryMedia, for peer: Peer) -> String? {
    ComposerPermissions.onCheck?()
    return ComposerPermissions.mediaBlocked ? "media blocked" : nil
}
final class ComposerSubmission {
    let scope: AnalyticsScope?
    var discarded = false
    init(_ context: AnalyticsContext) { scope = context.scope }
    func discard() { discarded = true }
    func restrict(to context: AnalyticsContext) {
        if context.isExcluded || context.scope !== scope { discarded = true }
    }
}
final class ComposerGroup {
    enum Result { case rejected, accepted }
    let submission: ComposerSubmission
    var onComplete: (() -> Void)?
    var recorded = 0
    var endings = 0
    func end() { endings += 1 }
    init(_ submission: ComposerSubmission) { self.submission = submission }
    func complete(index: Int, buildResult: () -> Result?) {
        guard !submission.discarded, submission.scope?.isValid == true else { return }
        complete(index: index, result: buildResult())
    }
    func complete(index: Int, result: Result?) {
        onComplete?()
        guard !submission.discarded, submission.scope?.isValid == true else { return }
        if result == nil { submission.discarded = true } else { recorded += 1 }
    }
}
func chatAnalyticsEnqueueResult(_ ids: [MessageId?]) -> ComposerGroup.Result {
    ids.isEmpty || ids.contains(where: { $0 == nil }) ? .rejected : .accepted
}
func composerForwardResult(controller: ChatController, origin: AnalyticsContext, messages: [Message], peer: Peer, requested: [MessageId], task: ComposerSubmission?, group: ComposerGroup?, makeTextSignal: @escaping (AnalyticsContext) -> Signal<Never, NoError> = { _ in .complete() }, startSending: @escaping () -> Void = {}) -> Signal<Never, NoError> {
    let context = controller.context
    let submission = task
    let resultGroup = group
    let fwdIds = requested
    let hasText = true
    let cachedData: Int? = nil
    let destinationPeerId: PeerId = 3
    let destinationReply: Int? = nil
    let destinationThreadId: Int64? = nil
    let hideNames = false, hideCaptions = false, silent = false
    let atDate: Date? = nil
    let currentSendAsPeerId: PeerId? = nil
    let controller: ChatController? = controller
__COMPOSER_FORWARD_RESULT__
}

func composerForwardPipeline(controller: ChatController, origin: AnalyticsContext, requested: [MessageId], task: ComposerSubmission?, group: ComposerGroup?, scheduledAt: Date? = nil, afterSentTransition: @escaping () -> Void = {}, scrollAfterSend: @escaping () -> Void = {}, makeTextSignal: @escaping (AnalyticsContext) -> Signal<Never, NoError> = { _ in .complete() }) -> Signal<Never, NoError> {
    let context = controller.context
    let submission = task
    let resultGroup = group
    let fwdIds = requested
    let hasText = true
    let cachedData: Int? = nil
    let destinationPeerId: PeerId = 3
    let destinationReply: Int? = nil
    let destinationThreadId: Int64? = nil
    let hideNames = false, hideCaptions = false, silent = false
    let atDate = scheduledAt
    let currentSendAsPeerId: PeerId? = nil
    let peerId: PeerId = 3
    var setNextToTransaction = true
__COMPOSER_START__
__COMPOSER_FORWARD_PIPELINE__
    return origin.preservingPresentation(invokeSignal |> deliverOnMainQueue) |> afterCompleted {
__COMPOSER_COMPLETED__
    }
}

extension ForwardObjectTests {
    func testComposerForwardOrdinaryResultPreservesMessagesAndProviderBehavior() {
        let origin = origin()
        let controller = ChatController(account, .peer(3))
        let task = ComposerSubmission(origin)
        let group = ComposerGroup(task)
        UI.sendResult = .single([sourceId])
        UI.onSendSetup = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        var completions = 0
        let disposable = composerForwardResult(controller: controller, origin: origin, messages: [Message(id: sourceId)], peer: Peer(3), requested: [sourceId], task: task, group: group).start(completed: { completions += 1 })
        XCTAssertEqual(UI.forwarded, [[sourceId]])
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(task.discarded)
        XCTAssertEqual(group.recorded, 1)
        disposable.dispose()
    }
    func testComposerForwardReturnedSecretSourceOrPeerExcludesMixedBatchBeforeChecks() {
        for kind in 0..<4 {
            UI.reset()
            let origin = origin()
            let controller = ChatController(account, .peer(3))
            var message = Message(id: kind == 0 ? MessageId(peerId: -1, id: 2) : sourceId)
            if kind == 1 { message.containsSecretMedia = true }
            if kind == 3 { controller.chatInteraction.peer = Peer(-1) }
            let task = ComposerSubmission(origin)
            let group = ComposerGroup(task)
            ComposerPermissions.onCheck = { self.assertPrivate(); XCTAssertTrue(task.discarded) }
            defer { ComposerPermissions.onCheck = nil }
            UI.onSendSetup = { self.assertPrivate(); XCTAssertTrue(task.discarded) }
            UI.sendResult = Signal { subscriber in
                self.assertPrivate()
                subscriber.putNext([self.sourceId])
                subscriber.putCompletion()
                return ActionDisposable { self.assertPrivate() }
            }
            let messages = [Message(id: sourceId), message]
            let disposable = composerForwardResult(controller: controller, origin: origin, messages: messages, peer: Peer(kind == 2 ? -1 : 3), requested: messages.map(\.id), task: task, group: group).start(next: { _ in self.assertPrivate() }, completed: { self.assertPrivate() })
            XCTAssertTrue(task.discarded)
            XCTAssertEqual(UI.forwarded, [messages.map(\.id)])
            XCTAssertEqual(group.recorded, 0)
            disposable.dispose()
        }
    }
    func testComposerForwardPrivacyPrecedesMismatchedSourceResult() {
        let origin = origin()
        let controller = ChatController(account, .peer(3))
        let task = ComposerSubmission(origin)
        let group = ComposerGroup(task)
        group.onComplete = { self.assertPrivate(); XCTAssertTrue(task.discarded) }
        let message = Message(id: MessageId(peerId: -1, id: 2))
        let disposable = composerForwardResult(controller: controller, origin: origin, messages: [message], peer: Peer(3), requested: [sourceId, sourceId], task: task, group: group).start()
        XCTAssertEqual(group.recorded, 0)
        XCTAssertTrue(task.discarded)
        disposable.dispose()
    }
    func testComposerForwardPrivatePermissionAlertKeepsExclusionUntilDismissal() {
        for inline in [false, true] {
            UI.reset()
            let origin = origin()
            let controller = ChatController(account, .peer(3))
            var message = Message(id: sourceId)
            message.containsSecretMedia = true
            if inline { message.attributes = [InlineBotMessageAttribute()] }
            let peer = Peer(3)
            peer.bansInline = inline
            ComposerPermissions.mediaBlocked = !inline
            defer { ComposerPermissions.mediaBlocked = false }
            let task = ComposerSubmission(origin)
            let group = ComposerGroup(task)
            UI.onAlert = { self.assertPrivate() }
            let disposable = composerForwardResult(controller: controller, origin: origin, messages: [message], peer: peer, requested: [sourceId], task: task, group: group).start(completed: { self.assertPrivate() })
            XCTAssertTrue(UI.forwarded.isEmpty)
            XCTAssertEqual(group.recorded, 0)
            XCTAssertEqual(UI.alerts, 1)
            disposable.dispose()
            assertPrivate()
            UI.alertClosures.forEach { $0() }
            UI.alertClosures = []
            XCTAssertFalse(hub.policy.hasExclusions)
        }
    }
    func testComposerForwardDelayedPrivateResultSurvivesOwnerReleaseAndDisposal() {
        let origin = origin()
        var controller: ChatController? = ChatController(account, .peer(3))
        let task = ComposerSubmission(origin)
        var message = Message(id: sourceId)
        message.containsSecretMedia = true
        var subscriber: Subscriber<[MessageId?], NoError>?
        var disposed = 0
        UI.sendResult = Signal { observer in subscriber = observer; self.assertPrivate(); return ActionDisposable { disposed += 1; self.assertPrivate() } }
        let signal = composerForwardResult(controller: controller!, origin: origin, messages: [message], peer: Peer(3), requested: [sourceId], task: task, group: nil)
        weak var released = controller
        controller = nil
        XCTAssertNil(released)
        let disposable = signal.start(next: { _ in self.assertPrivate() })
        assertPrivate()
        subscriber?.putNext([sourceId])
        disposable.dispose()
        XCTAssertEqual(disposed, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
        subscriber = nil
    }
    func testComposerForwardOrdinaryPermissionFailureStillReportsLocalRejection() {
        let origin = origin()
        let controller = ChatController(account, .peer(3))
        let task = ComposerSubmission(origin)
        let group = ComposerGroup(task)
        ComposerPermissions.mediaBlocked = true
        defer { ComposerPermissions.mediaBlocked = false }
        let disposable = composerForwardResult(controller: controller, origin: origin, messages: [Message(id: sourceId)], peer: Peer(3), requested: [sourceId], task: task, group: group).start()
        XCTAssertEqual(group.recorded, 1)
        XCTAssertEqual(UI.alerts, 1)
        XCTAssertTrue(UI.forwarded.isEmpty)
        XCTAssertFalse(hub.policy.hasExclusions)
        UI.alertClosures.forEach { $0() }
        UI.alertClosures = []
        disposable.dispose()
    }
    func testComposerForwardRevokedOriginCannotRefreshAtLookupDelivery() {
        let origin = origin()
        hub.policy.isEnabled = false
        hub.policy.isEnabled = true
        let controller = ChatController(account, .peer(3))
        let task = ComposerSubmission(origin)
        UI.onSendSetup = { self.assertPrivate() }
        let disposable = composerForwardResult(controller: controller, origin: origin, messages: [Message(id: sourceId)], peer: Peer(3), requested: [sourceId], task: task, group: nil).start()
        XCTAssertTrue(task.discarded)
        XCTAssertEqual(UI.forwarded, [[sourceId]])
        disposable.dispose()
    }
}

extension ForwardObjectTests {
    func testComposerForwardClassifiesPrivateSourcesBeforeConstructingText() {
        for secretPeer in [false, true] {
            UI.reset()
            let origin = origin()
            let controller = ChatController(account, .peer(3))
            let task = ComposerSubmission(origin)
            var message = Message(id: secretPeer ? MessageId(peerId: -1, id: 2) : sourceId)
            message.containsSecretMedia = !secretPeer
            var order: [String] = []
            UI.onSendSetup = { order.append("forward"); self.assertPrivate() }
            let disposable = composerForwardResult(controller: controller, origin: origin, messages: [message], peer: Peer(3), requested: [message.id], task: task, group: nil, makeTextSignal: { context in
                XCTAssertTrue(context.isExcluded)
                XCTAssertTrue(task.discarded)
                self.assertPrivate()
                order.append("text construction")
                return Signal { subscriber in
                    self.assertPrivate()
                    order.append("text subscription")
                    subscriber.putCompletion()
                    return EmptyDisposable
                }
            }).start()
            XCTAssertEqual(order, ["text construction", "text subscription", "forward"])
            disposable.dispose()
        }
    }
    func testComposerForwardWaitsForDelayedTextAndKeepsPrivateLifetime() {
        let origin = origin()
        let controller = ChatController(account, .peer(3))
        var message = Message(id: sourceId)
        message.containsSecretMedia = true
        var textSubscriber: Subscriber<Never, NoError>?
        var textDisposed = false
        UI.onSendSetup = { self.assertPrivate() }
        let disposable = composerForwardResult(controller: controller, origin: origin, messages: [message], peer: Peer(3), requested: [sourceId], task: nil, group: nil, makeTextSignal: { _ in
            Signal { observer in
                self.assertPrivate()
                textSubscriber = observer
                return ActionDisposable { self.assertPrivate(); textDisposed = true }
            }
        }).start()
        XCTAssertTrue(UI.forwarded.isEmpty)
        assertPrivate()
        textSubscriber?.putCompletion()
        XCTAssertEqual(UI.forwarded, [[sourceId]])
        disposable.dispose()
        XCTAssertTrue(textDisposed)
        XCTAssertFalse(hub.policy.hasExclusions)
        textSubscriber = nil
    }
    func testComposerForwardPermissionFailureStillSendsAccompanyingTextFirst() {
        let origin = origin()
        let controller = ChatController(account, .peer(3))
        let task = ComposerSubmission(origin)
        let group = ComposerGroup(task)
        ComposerPermissions.mediaBlocked = true
        defer { ComposerPermissions.mediaBlocked = false; ComposerPermissions.onCheck = nil }
        var order: [String] = []
        ComposerPermissions.onCheck = { order.append("permission") }
        UI.onAlert = { order.append("alert") }
        let disposable = composerForwardResult(controller: controller, origin: origin, messages: [Message(id: sourceId)], peer: Peer(3), requested: [sourceId], task: task, group: group, makeTextSignal: { context in
            XCTAssertTrue(context.scope === origin.scope)
            return Signal { subscriber in
                order.append("text")
                subscriber.putCompletion()
                return EmptyDisposable
            }
        }).start()
        XCTAssertEqual(order, ["text", "permission", "alert"])
        XCTAssertEqual(group.recorded, 1)
        XCTAssertTrue(UI.forwarded.isEmpty)
        UI.alertClosures.forEach { $0() }
        UI.alertClosures = []
        disposable.dispose()
    }
    func testComposerForwardLookupPrecedesTextAndConsumesOneSourceSnapshot() {
        let origin = origin()
        let controller = ChatController(account, .peer(3))
        var sourceSubscriber: Subscriber<[Message], NoError>?
        account.account.postbox.composerMessages = Signal { observer in sourceSubscriber = observer; return EmptyDisposable }
        var constructions = 0
        let completed = expectation(description: "mixed action completed")
        let disposable = composerForwardPipeline(controller: controller, origin: origin, requested: [sourceId], task: nil, group: nil, makeTextSignal: { context in
            constructions += 1
            XCTAssertTrue(context.isExcluded)
            self.assertPrivate()
            return .complete()
        }).start(completed: { completed.fulfill() })
        XCTAssertEqual(constructions, 0)
        XCTAssertTrue(UI.forwarded.isEmpty)
        var message = Message(id: sourceId)
        message.containsSecretMedia = true
        sourceSubscriber?.putNext([message])
        sourceSubscriber?.putNext([Message(id: sourceId)])
        wait(for: [completed], timeout: 2)
        XCTAssertEqual(constructions, 1)
        XCTAssertEqual(UI.forwarded, [[sourceId]])
        disposable.dispose()
        sourceSubscriber = nil
    }
    func testComposerForwardCancelledLookupCannotStartEitherSender() {
        let controller = ChatController(account, .peer(3))
        var sourceSubscriber: Subscriber<[Message], NoError>?
        var lookupDisposed = false
        account.account.postbox.composerMessages = Signal { observer in
            sourceSubscriber = observer
            return ActionDisposable { lookupDisposed = true }
        }
        var constructions = 0
        let disposable = composerForwardPipeline(controller: controller, origin: origin(), requested: [sourceId], task: nil, group: nil, makeTextSignal: { _ in constructions += 1; return .complete() }).start()
        disposable.dispose()
        sourceSubscriber?.putNext([Message(id: sourceId)])
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(lookupDisposed)
        XCTAssertEqual(constructions, 0)
        XCTAssertTrue(UI.forwarded.isEmpty)
        sourceSubscriber = nil
    }
    func testComposerForwardWithoutSourcesSendsTextWithOriginalContext() {
        let origin = origin()
        let controller = ChatController(account, .peer(3))
        account.account.postbox.composerMessages = Signal { _ in XCTFail("unexpected source lookup subscription"); return EmptyDisposable }
        var constructions = 0
        let disposable = composerForwardPipeline(controller: controller, origin: origin, requested: [], task: nil, group: nil, makeTextSignal: { context in
            XCTAssertTrue(context.scope === origin.scope)
            constructions += 1
            return .complete()
        }).start()
        XCTAssertEqual(constructions, 1)
        XCTAssertTrue(UI.forwarded.isEmpty)
        disposable.dispose()
    }
}


extension ForwardObjectTests {
    func testComposerCaptureRejectsSecretMediaBeforeAnyDescendant() {
        for editing in [false, true] {
            let original = origin()
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            var privateMessage = Message(id: sourceId)
            privateMessage.containsSecretMedia = true
            if editing {
                interaction.state.interface.editState = FixtureEditState(message: privateMessage)
            } else {
                interaction.state.interface.ids = [sourceId]
                interaction.state.interface.forwardMessages = [privateMessage]
            }
            for captured in [interaction.captureAnalyticsContext(), interaction.captureAnalyticsContext(inherited: original)] {
                XCTAssertTrue(captured.isExcluded)
                XCTAssertNil(captured.scope)
                let presentation = captured.beginPresentation()
                self.assertPrivate()
                presentation.end()
            }
        }
    }
    func testComposerCaptureRequiresCompleteMatchingForwardResolution() {
        let secondId = MessageId(peerId: 2, id: 2)
        let unrelatedId = MessageId(peerId: 4, id: 3)
        for cached in [[], [Message(id: sourceId)], [Message(id: sourceId), Message(id: sourceId)], [Message(id: sourceId), Message(id: unrelatedId)], [Message(id: sourceId), Message(id: secondId), Message(id: unrelatedId)]] {
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            interaction.state.interface.ids = [sourceId, secondId]
            interaction.state.interface.forwardMessages = cached
            let captured = interaction.captureAnalyticsContext()
            XCTAssertTrue(captured.isExcluded)
            XCTAssertFalse(hub.policy.accepts(captured.scope))
        }
    }
    func testComposerCaptureResolvedOrdinarySourcesKeepExactInheritedScope() {
        let secondId = MessageId(peerId: 4, id: 2)
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        let original = origin()
        interaction.state.interface.ids = [sourceId, secondId]
        interaction.state.interface.forwardMessages = [Message(id: secondId), Message(id: sourceId)]
        let captured = interaction.captureAnalyticsContext(inherited: original)
        XCTAssertTrue(captured.scope === original.scope)
        XCTAssertTrue(hub.policy.accepts(captured.scope))
        XCTAssertFalse(captured.isExcluded)
    }
    func testComposerCaptureUnresolvedActionCannotUpgradeAfterCacheArrives() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        interaction.state.interface.ids = [sourceId]
        let pendingAction = interaction.captureAnalyticsContext()
        interaction.state.interface.forwardMessages = [Message(id: sourceId)]
        XCTAssertFalse(hub.policy.accepts(interaction.captureAnalyticsContext(inherited: pendingAction).scope))
        XCTAssertTrue(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
    }
    func testComposerCaptureIgnoresInactiveCacheButNotDisplayedStaleSelection() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        var cached = Message(id: sourceId)
        cached.containsSecretMedia = true
        interaction.state.interface.forwardMessages = [cached]
        XCTAssertTrue(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
        interaction.state.interface.ids = [MessageId(peerId: 4, id: 2)]
        XCTAssertFalse(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
        interaction.state.interface.ids = []
        XCTAssertTrue(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
    }
    func testComposerCaptureOrdinaryEditRemainsEligibleAndRevocationStillWins() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        interaction.state.interface.editState = FixtureEditState(message: Message(id: sourceId))
        let original = interaction.captureAnalyticsContext()
        XCTAssertTrue(hub.policy.accepts(original.scope))
        hub.policy.isEnabled = false
        hub.policy.isEnabled = true
        XCTAssertFalse(hub.policy.accepts(interaction.captureAnalyticsContext(inherited: original).scope))
    }
}


extension ForwardObjectTests {
    func testComposerReplyPrivatePeerAndSecretMediaNeverGrantScope() {
        for secretPeer in [false, true] {
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            let original = origin()
            let id = secretPeer ? MessageId(peerId: -1, id: 1) : sourceId
            var message = Message(id: id)
            message.containsSecretMedia = !secretPeer
            interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: id)
            interaction.state.interface.replyMessage = message
            for context in [interaction.captureAnalyticsContext(), interaction.captureAnalyticsContext(inherited: original)] {
                XCTAssertTrue(context.isExcluded)
                XCTAssertNil(context.scope)
                let lifetime = context.beginPresentation()
                assertPrivate()
                lifetime.end()
            }
        }
    }
    func testComposerReplyMissingOrMismatchedCacheStaysUnresolved() {
        let cases: [Message?] = [nil, Message(id: MessageId(peerId: 2, id: 99)), Message(id: MessageId(peerId: 4, id: 1))]
        for message in cases {
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
            interaction.state.interface.replyMessage = message
            let context = interaction.captureAnalyticsContext()
            XCTAssertTrue(context.isExcluded)
            XCTAssertFalse(hub.policy.accepts(context.scope))
        }
    }
    func testComposerReplyResolvedOrdinaryMessagePreservesInheritedScope() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        let original = origin()
        interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
        interaction.state.interface.replyMessage = Message(id: sourceId)
        let context = interaction.captureAnalyticsContext(inherited: original)
        XCTAssertTrue(context.scope === original.scope)
        XCTAssertTrue(hub.policy.accepts(context.scope))
    }
    func testComposerReplyCacheArrivalCannotUpgradePendingAction() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
        let pending = interaction.captureAnalyticsContext()
        interaction.state.interface.replyMessage = Message(id: sourceId)
        XCTAssertFalse(hub.policy.accepts(interaction.captureAnalyticsContext(inherited: pending).scope))
        XCTAssertTrue(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
    }
    func testComposerReplyClearingSubjectIgnoresStaleCacheWithoutRevivingOldOrigin() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        var message = Message(id: sourceId)
        message.containsSecretMedia = true
        interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
        interaction.state.interface.replyMessage = message
        let excluded = interaction.captureAnalyticsContext()
        interaction.state.interface.replyMessageId = nil
        XCTAssertTrue(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
        XCTAssertFalse(hub.policy.accepts(interaction.captureAnalyticsContext(inherited: excluded).scope))
    }
    func testComposerReplyOrdinarySourceCannotRelaxOtherPrivateComposerSources() {
        for edit in [false, true] {
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
            interaction.state.interface.replyMessage = Message(id: sourceId)
            var message = Message(id: MessageId(peerId: 4, id: 2))
            message.containsSecretMedia = true
            if edit {
                interaction.state.interface.editState = FixtureEditState(message: message)
            } else {
                interaction.state.interface.ids = [message.id]
                interaction.state.interface.forwardMessages = [message]
            }
            XCTAssertFalse(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
        }
    }
}
