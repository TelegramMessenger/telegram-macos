import Foundation
import XCTest

public final class WKWebView {}
public enum WKNavigationActionPolicy: Equatable { case allow, cancel }
public struct WKNavigationAction {
    let request: URLRequest
}
public struct WKScriptMessage {
    let body: Any
    let frameInfo: FrameInfo
    struct FrameInfo { let isMainFrame: Bool }
}
struct BotCheckoutPaymentWebToken {
    let title: String
    let data: String
    let saveOnServer: Bool
}
enum PaymentWebInteractionIntent {
    case addPaymentMethod((BotCheckoutPaymentWebToken) -> Void)
    case externalVerification((Bool) -> Void)
}
final class AnalyticsContext {
    var depth = 0
    func beginPresentation() -> Presentation { Presentation(self) }
}
final class Presentation {
    let context: AnalyticsContext
    var active = true
    init(_ context: AnalyticsContext) { self.context = context; context.depth += 1 }
    func end() { if active { active = false; context.depth -= 1 } }
    deinit { end() }
}
final class Analytics {
    static let shared = Analytics()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext() }
}
struct PaymentsHooks {
    static let shared = PaymentsHooks()
    func meUrlHost() -> String { "t.me" }
}
public class ModalViewController {
    var analyticsContext: AnalyticsContext?
    var closeCount = 0
    private var closed = false
    public func viewWillDisappear(_ animated: Bool) {}
    func close() {
        guard !closed else { return }
        closed = true
        closeCount += 1
        viewWillDisappear(false)
    }
}
final class WebController: ModalViewController {
    private let intent: PaymentWebInteractionIntent
    private var completed = false
    init(intent: PaymentWebInteractionIntent, context: AnalyticsContext) {
        self.intent = intent
        super.init()
        analyticsContext = context
    }
    func receive(_ message: WKScriptMessage) { handleScriptMessage(message) }
__DISAPPEAR__
__CALLBACKS__
}

final class WebContextTests: XCTestCase {
    private func validMessage(mainFrame: Bool = true) throws -> WKScriptMessage {
        let data = try JSONSerialization.data(withJSONObject: ["title": "fixture", "credentials": ["token": "fixture"]])
        return WKScriptMessage(body: ["eventName": "payment_form_submit", "eventData": String(data: data, encoding: .utf8)!], frameInfo: .init(isMainFrame: mainFrame))
    }
    private func navigation(_ url: String) -> WKNavigationAction {
        WKNavigationAction(request: URLRequest(url: URL(string: url)!))
    }

    func testScriptResultIsOnceUnderContextEvenWithReentrantCloseAndMessage() throws {
        let origin = AnalyticsContext()
        let message = try validMessage()
        var values = 0
        var controller: WebController!
        controller = WebController(intent: .addPaymentMethod { _ in
            XCTAssertEqual(origin.depth, 1)
            values += 1
            controller.close()
            controller.receive(message)
            XCTAssertEqual(origin.depth, 1)
        }, context: origin)
        controller.receive(message)
        controller.receive(message)
        XCTAssertEqual(values, 1)
        XCTAssertEqual(controller.closeCount, 1)
        XCTAssertEqual(origin.depth, 0)
    }

    func testClosedWebFormRejectsLateScriptResult() throws {
        let origin = AnalyticsContext()
        var values = 0
        let controller = WebController(intent: .addPaymentMethod { _ in values += 1 }, context: origin)
        controller.viewWillDisappear(false)
        controller.receive(try validMessage())
        XCTAssertEqual(values, 0)
        XCTAssertEqual(origin.depth, 0)
    }

    func testMalformedAndSubframeMessagesDoNotConsumeValidResult() throws {
        let origin = AnalyticsContext()
        var values = 0
        let controller = WebController(intent: .addPaymentMethod { _ in values += 1 }, context: origin)
        controller.receive(WKScriptMessage(body: ["eventName": "payment_form_submit", "eventData": "invalid"], frameInfo: .init(isMainFrame: true)))
        controller.receive(try validMessage(mainFrame: false))
        XCTAssertEqual(values, 0)
        controller.receive(try validMessage())
        XCTAssertEqual(values, 1)
    }

    func testVerificationMarksCompletionBeforeReentrantPolicyCallback() {
        let origin = AnalyticsContext()
        var values = 0
        var policies: [WKNavigationActionPolicy] = []
        let controller = WebController(intent: .externalVerification { value in
            XCTAssertTrue(value)
            XCTAssertEqual(origin.depth, 1)
            values += 1
        }, context: origin)
        let action = navigation("https://t.me/fixture")
        controller.webView(WKWebView(), decidePolicyFor: action, decisionHandler: { policy in
            policies.append(policy)
            controller.webView(WKWebView(), decidePolicyFor: action, decisionHandler: { policies.append($0) })
        })
        XCTAssertEqual(values, 1)
        XCTAssertEqual(policies, [.cancel, .cancel])
        XCTAssertEqual(controller.closeCount, 1)
        XCTAssertEqual(origin.depth, 0)
    }

    func testOtherNavigationIsAllowedWithoutConsumingVerification() {
        let origin = AnalyticsContext()
        var values = 0
        var policies: [WKNavigationActionPolicy] = []
        let controller = WebController(intent: .externalVerification { _ in values += 1 }, context: origin)
        controller.webView(WKWebView(), decidePolicyFor: navigation("https://example.test/fixture"), decisionHandler: {
            XCTAssertEqual(origin.depth, 1)
            policies.append($0)
        })
        XCTAssertEqual(values, 0)
        controller.webView(WKWebView(), decidePolicyFor: navigation("https://telegram.me/fixture"), decisionHandler: { policies.append($0) })
        XCTAssertEqual(values, 1)
        XCTAssertEqual(policies, [.allow, .cancel])
    }

    func testClosedVerificationStillAnswersEveryPolicyCallback() {
        let origin = AnalyticsContext()
        var values = 0
        var policies: [WKNavigationActionPolicy] = []
        let controller = WebController(intent: .externalVerification { _ in values += 1 }, context: origin)
        controller.viewWillDisappear(false)
        for _ in 0..<3 {
            controller.webView(WKWebView(), decidePolicyFor: navigation("https://t.me/fixture"), decisionHandler: {
                XCTAssertEqual(origin.depth, 1)
                policies.append($0)
            })
        }
        XCTAssertEqual(values, 0)
        XCTAssertEqual(policies, [.cancel, .cancel, .cancel])
    }
}
