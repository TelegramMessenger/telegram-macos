import Cocoa
import XCTest
import WidgetSandbox
import Postbox
@testable import HTMLBubbles

final class WidgetWalletHostTests: XCTestCase {
    private final class Space: WidgetFeedSpace {
        var slots: [WidgetFeedSlot] = []
        var feedViewport: CGRect { CGRect(x: 0, y: 0, width: 240, height: 100) }
        var feedOnScreen: Bool { true }
        func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { slots }
    }

    private func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !condition() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func withHost(preview: Bool = false, _ check: (HTMLBubbleState, WidgetHost) throws -> Void) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = HTMLBubbleState(html: "<button>Pay</button><script>console.log(TelegramWidget.wallet===null?'no-wallet':'wallet-ready');</script>", outgoing: false, selfContained: true)
        state.isWidgetMessage = true
        state.widgetPreview = preview
        let peer = PeerId(100)
        state.attachWidget(HTMLWidgetContext(accountPeerId: peer, basePath: directory.path, messageId: MessageId(peerId: peer, namespace: 0, id: 1), locale: "en", runtime: WidgetContext(canQuery: true, chatType: .group, wallet: true)))
        let appearance = HTMLBubbleAppearance(key: "wallet-host", css: "", dark: false, incoming: true)
        let space = Space()
        let slot = try XCTUnwrap(state.twidgetSlot(appearance: appearance, width: 240, locate: { space.feedViewport }))
        slot.space = space
        space.slots = [slot]
        let feed = HTMLTwidgetTableSpace.feed(for: .twidget)
        feed.attach(space)
        defer { feed.detach(space) }
        feed.update()
        pump { state.twidgetHost?.diagnostics.loaded == true }
        let host = try XCTUnwrap(state.twidgetHost)
        defer { host.destroy() }
        XCTAssertNil(host.diagnostics.dead)
        try check(state, host)
    }

    func testMessageRequestRetainsWalletFlagAndBotReply() throws {
        try withHost { state, host in
            XCTAssertTrue(host.diagnostics.logs.contains { $0.text == "wallet-ready" })
            var received: WidgetRequest?
            state.widgetRequestHandler = { request, respond in
                received = request
                respond(.success(WidgetRequestAnswer(result: "bot-answer")))
            }
            let send = try XCTUnwrap(host.onRequest)
            var answer: WidgetRequestAnswer?
            send(WidgetRequest(data: "order:42", wallet: true)) { result in answer = try? result.get() }
            XCTAssertEqual(received, WidgetRequest(data: "order:42", wallet: true))
            XCTAssertEqual(answer, WidgetRequestAnswer(result: "bot-answer"))
        }
    }

    func testWalletCallAndUserRejectionReachTheMessageHandler() throws {
        try withHost { state, host in
            let call = WalletCall.signData(SignDataPayload(type: .text, text: "Sign order"), data: "signed:42")
            var received: WalletCall?
            state.widgetWalletHandler = { value, respond in
                received = value
                respond(.failure(.rejected))
            }
            let send = try XCTUnwrap(host.onWallet)
            var failure: WidgetRequestFailure?
            send(call) { result in if case let .failure(value) = result { failure = value } }
            XCTAssertEqual(received, call)
            XCTAssertEqual(failure, .rejected)
            state.widgetWalletHandler = nil
            failure = nil
            send(call) { result in if case let .failure(value) = result { failure = value } }
            XCTAssertEqual(failure, .notAllowed)
        }
    }

    func testInlinePreviewNeverAdvertisesWalletSupport() throws {
        try withHost(preview: true) { _, host in
            XCTAssertTrue(host.diagnostics.logs.contains { $0.text == "no-wallet" })
            XCTAssertFalse(host.diagnostics.logs.contains { $0.text == "wallet-ready" })
        }
    }
}
