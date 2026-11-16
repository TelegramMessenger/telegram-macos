final class TextViewLayout {}
__COMPOSER_DATE_MODE__
__COMPOSER_DATE_HELPER__
enum ConfirmResult { case basic, thrid }
enum ComposerPaymentUI {
    static var onConstruct: (() -> Void)?
    static var success: ((ConfirmResult) -> Void)?
    static var cancel: (() -> Void)?
    static var destroyed: (() -> Void)?
    static func clear() {
        onConstruct = nil
        success = nil
        cancel = nil
        destroyed = nil
    }
}
func verifyAlert(for window: Window, header: String, information: String, ok: String, option: String, optionIsSelected: Bool, successHandler: @escaping (ConfirmResult) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    ComposerPaymentUI.onConstruct?()
    ComposerPaymentUI.success = successHandler
    ComposerPaymentUI.cancel = cancelHandler
    ComposerPaymentUI.destroyed = onDeinit
}
__COMPOSER_PAYMENT_HELPER__

extension ForwardObjectTests {
    func testComposerCacheExclusionReachesDateConstructionAndDelayedSelection() {
        for unresolved in [false, true] {
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            var message = Message(id: sourceId)
            message.containsSecretMedia = true
            interaction.state.interface.ids = [sourceId]
            interaction.state.interface.forwardMessages = unresolved ? [] : [message]
            let captured = interaction.captureAnalyticsContext()
            var select: ((Date, Int32?) -> Void)?
            ChatNavigationHooks.shared.makeDateSelector = { _, _, _, _, callback, _ in
                self.assertPrivate()
                select = callback
                return ModalViewController()
            }
            defer { ChatNavigationHooks.shared.makeDateSelector = { _, _, _, _, _, _ in ModalViewController() } }
            var calls = 0
            let selector = chatDateSelector(context: account, mode: .schedule(3), analyticsContext: captured, selectedAt: { date, period in
                self.assertPrivate()
                XCTAssertEqual(date.timeIntervalSince1970, 42)
                XCTAssertEqual(period, 7)
                calls += 1
            })
            XCTAssertTrue(selector.analyticsContext === captured)
            interaction.state.interface.forwardMessages = [Message(id: sourceId)]
            selector.analyticsContext = origin()
            select?(Date(timeIntervalSince1970: 42), 7)
            XCTAssertEqual(calls, 1)
            select = nil
            XCTAssertFalse(hub.policy.hasExclusions)
        }
    }
    func testComposerCacheExclusionSurvivesPaymentConfirmationAndUnknownDismissal() {
        for confirmation in [false, true] {
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            interaction.state.interface.ids = [sourceId]
            let captured = interaction.captureAnalyticsContext()
            var confirmations = 0, dismissals = 0
            ComposerPaymentUI.onConstruct = { self.assertPrivate() }
            verifyChatSendPayment(for: account.window, header: "Pay", information: "Messages", ok: "Send", option: "Remember", analyticsContext: captured, successHandler: { _ in
                self.assertPrivate()
                confirmations += 1
            }, dismissed: {
                self.assertPrivate()
                dismissals += 1
            })
            assertPrivate()
            interaction.state.interface.forwardMessages = [Message(id: sourceId)]
            if confirmation { ComposerPaymentUI.success?(.basic) }
            ComposerPaymentUI.destroyed?()
            let drained = expectation(description: "payment destruction")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertEqual(confirmations, confirmation ? 1 : 0)
            XCTAssertEqual(dismissals, confirmation ? 0 : 1)
            XCTAssertFalse(hub.policy.hasExclusions)
            ComposerPaymentUI.clear()
        }
    }
    func testComposerResolvedOrdinaryForwardKeepsPaymentAnalyticsEligible() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        interaction.state.interface.ids = [sourceId]
        interaction.state.interface.forwardMessages = [Message(id: sourceId)]
        let captured = interaction.captureAnalyticsContext()
        ComposerPaymentUI.onConstruct = { XCTAssertFalse(self.hub.policy.hasExclusions); XCTAssertTrue(self.hub.policy.accepts(captured.scope)) }
        var cancelled = 0
        verifyChatSendPayment(for: account.window, header: "Pay", information: "Messages", ok: "Send", option: "Remember", analyticsContext: captured, successHandler: { _ in XCTFail("unexpected confirmation") }, cancelHandler: {
            XCTAssertFalse(self.hub.policy.hasExclusions)
            cancelled += 1
        })
        ComposerPaymentUI.cancel?()
        ComposerPaymentUI.destroyed?()
        let drained = expectation(description: "ordinary payment destruction")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(cancelled, 1)
        ComposerPaymentUI.clear()
    }
}

extension ForwardObjectTests {
    func testComposerReplyExclusionReachesDateAndPaymentCallbacksAfterReplyClears() {
        for pending in [false, true] {
            let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
            var message = Message(id: sourceId)
            message.containsSecretMedia = true
            interaction.state.interface.replyMessageId = ComposerReplySubject(messageId: sourceId)
            interaction.state.interface.replyMessage = pending ? nil : message
            let captured = interaction.captureAnalyticsContext()
            var selected: ((Date, Int32?) -> Void)?
            ChatNavigationHooks.shared.makeDateSelector = { _, _, _, _, callback, _ in
                self.assertPrivate()
                selected = callback
                return ModalViewController()
            }
            defer { ChatNavigationHooks.shared.makeDateSelector = { _, _, _, _, _, _ in ModalViewController() } }
            var dates = 0, confirmations = 0
            _ = chatDateSelector(context: account, mode: .schedule(3), analyticsContext: captured, selectedAt: { _, _ in self.assertPrivate(); dates += 1 })
            ComposerPaymentUI.onConstruct = { self.assertPrivate() }
            verifyChatSendPayment(for: account.window, header: "Pay", information: "Reply", ok: "Send", option: "Remember", analyticsContext: captured, successHandler: { _ in self.assertPrivate(); confirmations += 1 })
            interaction.state.interface.replyMessageId = nil
            selected?(Date(), nil)
            ComposerPaymentUI.success?(.basic)
            ComposerPaymentUI.destroyed?()
            let drained = expectation(description: "reply payment cleanup")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertEqual(dates, 1)
            XCTAssertEqual(confirmations, 1)
            XCTAssertFalse(hub.policy.hasExclusions)
            ComposerPaymentUI.clear()
            selected = nil
        }
    }
}
