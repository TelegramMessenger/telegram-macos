import XCTest
@testable import HTMLBubbles

final class UserActionGateTests: XCTestCase {
    override func setUp() {
        HTMLBubbleUserAction.reset()
    }

    func testRequiresRecentRealInput() {
        XCTAssertFalse(HTMLBubbleUserAction.allow(now: 100, sinceInput: 30))
        XCTAssertFalse(HTMLBubbleUserAction.allow(now: 100, sinceInput: -1))
        XCTAssertTrue(HTMLBubbleUserAction.allow(now: 100, sinceInput: 0.1))
    }

    func testRateLimitsPrompts() {
        XCTAssertTrue(HTMLBubbleUserAction.allow(now: 100, sinceInput: 0.1))
        XCTAssertFalse(HTMLBubbleUserAction.allow(now: 100.2, sinceInput: 0.1))
        XCTAssertTrue(HTMLBubbleUserAction.allow(now: 101, sinceInput: 0.1))
    }
}

final class ContentLinkTests: XCTestCase {
    func testOnlyAllowedSchemesReachTheLinkHandler() {
        XCTAssertNil(HTMLBubbleState.contentLink("file:///etc/passwd"))
        XCTAssertNil(HTMLBubbleState.contentLink("data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg=="))
        XCTAssertNil(HTMLBubbleState.contentLink("javascript:alert(1)"))
        XCTAssertNil(HTMLBubbleState.contentLink(" JaVaScRiPt:alert(1)"))
        XCTAssertNil(HTMLBubbleState.contentLink("vnc://host"))
        XCTAssertNil(HTMLBubbleState.contentLink("x-apple.systempreferences:com.apple.preference.security"))
        XCTAssertNil(HTMLBubbleState.contentLink("/relative/path"))
        XCTAssertNil(HTMLBubbleState.contentLink("htt\u{0}p://evil"))
        XCTAssertNil(HTMLBubbleState.contentLink("https://a.com/\u{7}x"))
        XCTAssertEqual(HTMLBubbleState.contentLink("  HTTPS://example.com/x "), "HTTPS://example.com/x")
        XCTAssertNil(HTMLBubbleState.contentLink("tg://resolve?domain=telegram"))
        XCTAssertNil(HTMLBubbleState.contentLink("mailto:a@b.c"))
        XCTAssertNil(HTMLBubbleState.contentLink("http://example.com/x"))
        XCTAssertNil(HTMLBubbleState.contentLink(" HTTP://example.com/x"))
    }

    func testLinksCannotSendMessages() {
        XCTAssertNil(HTMLBubbleState.contentLink("chat:send?html=%3Cdiv%20class%3D%22widget%22%3Eworm%3C%2Fdiv%3E"))
        XCTAssertNil(HTMLBubbleState.contentLink("chat:send?text=&html=%3Cb%3Ex%3C%2Fb%3E"))
        XCTAssertNil(HTMLBubbleState.contentLink("chat:send?text=hi&html=%3Cb%3Ex%3C%2Fb%3E"))
        XCTAssertNil(HTMLBubbleState.contentLink("chat:send?text=/help"))
        XCTAssertNil(HTMLBubbleState.contentLink(" CHAT:send?text=hi"))
        XCTAssertNil(HTMLBubbleState.contentLink("chat:run?id=1"))
        XCTAssertNil(HTMLBubbleState.contentLink("tg://msg?text=hi&to=+10000000000"))
        XCTAssertEqual(HTMLBubbleState.contentLink("https://example.com/?html=1"), "https://example.com/?html=1")
    }
}
