extension ForwardObjectTests {
    func testComposerLivePrivateSourcesRevokeOriginalAndDerivedPresentations() {
        for kind in 0..<3 {
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            var message = Message(id: sourceId)
            switch kind {
            case 0:
                interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
                interaction.state.interface.replyMessage = message
            case 1:
                interaction.state.interface.ids = [sourceId]
                interaction.state.interface.forwardMessages = [message]
            default:
                interaction.state.interface.editState = FixtureEditState(message: message)
            }
            let inherited = origin()
            let captured = interaction.captureAnalyticsContext(inherited: inherited)
            let child = captured.restricting(peerId: 4)
            let parentLease = captured.beginPresentation()
            let childLease = child.beginPresentation()
            message.containsSecretMedia = true
            interaction.applyComposerPrivacyUpdate { state in
                var state = state
                switch kind {
                case 0: state.interface.replyMessage = message
                case 1: state.interface.forwardMessages = [message]
                default: state.interface.editState = FixtureEditState(message: message)
                }
                return state
            }
            XCTAssertTrue(inherited.isExcluded)
            XCTAssertTrue(captured.isExcluded)
            XCTAssertTrue(child.isExcluded)
            XCTAssertFalse(hub.policy.accepts(child.scope))
            assertPrivate()
            interaction.state.interface.replyMessageId = nil
            interaction.state.interface.ids = []
            interaction.state.interface.editState = nil
            parentLease.end()
            assertPrivate()
            childLease.end()
            XCTAssertFalse(hub.policy.hasExclusions)
            XCTAssertTrue(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
            XCTAssertFalse(hub.policy.accepts(interaction.captureAnalyticsContext(inherited: inherited).scope))
        }
    }
    func testComposerLiveOrdinaryMetadataDoesNotRevokeEligibleScopes() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
        interaction.state.interface.replyMessage = Message(id: sourceId)
        let captured = interaction.captureAnalyticsContext()
        let lease = captured.beginPresentation()
        interaction.applyComposerPrivacyUpdate { state in
            var state = state
            var message = Message(id: self.sourceId)
            message.media = [1, 2]
            state.interface.replyMessage = message
            return state
        }
        XCTAssertFalse(captured.isExcluded)
        XCTAssertTrue(hub.policy.accepts(captured.scope))
        XCTAssertFalse(hub.policy.hasExclusions)
        lease.end()
    }
    func testComposerLiveMissingReplyResolutionRevokesBeforePendingCleanup() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
        interaction.state.interface.replyMessage = Message(id: sourceId)
        let captured = interaction.captureAnalyticsContext()
        var cancelled = 0
        let request = interaction.prepareForwardSend(onInvalidated: {
            XCTAssertTrue(captured.isExcluded)
            self.assertPrivate()
            cancelled += 1
        }, request: { Signal<Int, NoError> { _ in EmptyDisposable } })
        let disposable = captured.preservingPresentation(request).start()
        interaction.applyComposerPrivacyUpdate({ state in
            var state = state
            state.interface.replyMessage = nil
            return state
        }, after: {
            XCTAssertTrue(captured.isExcluded)
            interaction.invalidateDeferredSendActions()
        })
        XCTAssertEqual(cancelled, 1)
        disposable.dispose()
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testComposerLiveExclusionStillUpdatesPresentationAfterAccountGenerationChanges() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        let captured = interaction.captureAnalyticsContext()
        let lease = captured.beginPresentation()
        hub.policy.isEnabled = false
        hub.policy.isEnabled = true
        interaction.applyComposerPrivacyUpdate { state in
            var state = state
            state.interface.replyMessageId = ComposerReplySubject(messageId: self.sourceId)
            return state
        }
        XCTAssertTrue(captured.isExcluded)
        assertPrivate()
        lease.end()
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testComposerLiveScopeRegistryDoesNotKeepFinishedScopesAlive() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        var captured: AnalyticsContext? = interaction.captureAnalyticsContext()
        weak var scope = captured?.scope
        XCTAssertNotNil(scope)
        captured = nil
        XCTAssertNil(scope)
        interaction.applyComposerPrivacyUpdate { state in
            var state = state
            state.interface.ids = [self.sourceId]
            return state
        }
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testComposerLivePrivateReplyUpdatesAlreadyOpenPaymentLifetime() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
        interaction.state.interface.replyMessage = Message(id: sourceId)
        let captured = interaction.captureAnalyticsContext()
        ComposerPaymentUI.onConstruct = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        var confirmations = 0
        verifyChatSendPayment(for: account.window, header: "Pay", information: "Reply", ok: "Send", option: "Remember", analyticsContext: captured, successHandler: { _ in
            self.assertPrivate()
            XCTAssertFalse(self.hub.policy.accepts(captured.scope))
            confirmations += 1
        })
        interaction.applyComposerPrivacyUpdate { state in
            var state = state
            var message = Message(id: self.sourceId)
            message.containsSecretMedia = true
            state.interface.replyMessage = message
            return state
        }
        assertPrivate()
        ComposerPaymentUI.success?(.basic)
        ComposerPaymentUI.destroyed?()
        let drained = expectation(description: "live private payment dismissal")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(confirmations, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
        ComposerPaymentUI.clear()
    }
}


extension ForwardObjectTests {
    func testComposerLivePrivacyRevisionRejectsContextRegisteredAfterPrivateUpdate() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        let revision = interaction.composerPrivacyRevision
        let capturedBeforeUpdate = origin()
        interaction.applyComposerPrivacyUpdate { state in
            var state = state
            state.interface.replyMessageId = ComposerReplySubject(messageId: self.sourceId)
            return state
        }
        interaction.applyComposerPrivacyUpdate { state in
            var state = state
            state.interface.replyMessageId = nil
            return state
        }
        let returned = interaction.rememberComposerAnalyticsContext(capturedBeforeUpdate, revision: revision)
        XCTAssertTrue(returned.isExcluded)
        XCTAssertFalse(hub.policy.accepts(returned.scope))
        XCTAssertTrue(hub.policy.accepts(interaction.captureAnalyticsContext().scope))
    }
    func testComposerLiveMatchingPrivacyRevisionRetainsEligibleScope() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        let revision = interaction.composerPrivacyRevision
        let captured = origin()
        let returned = interaction.rememberComposerAnalyticsContext(captured, revision: revision)
        XCTAssertTrue(returned.scope === captured.scope)
        XCTAssertTrue(hub.policy.accepts(returned.scope))
    }
}
