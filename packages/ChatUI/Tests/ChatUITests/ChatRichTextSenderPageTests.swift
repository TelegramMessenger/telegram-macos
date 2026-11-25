import XCTest
import TelegramCore
@testable import ChatUI

final class ChatRichTextSenderPageTests: XCTestCase {
    private func page(_ title: String = "link") -> InstantPage {
        return InstantPage(blocks: [.paragraph(.url(text: .plain(title), url: "https://example.com", webpageId: nil))], media: [:], isComplete: true, rtl: false, url: "", views: nil)
    }

    func testOnlyIncomingUnacceptedPagesAreSanitized() {
        let resolver = ChatRichTextSenderPage()
        let page = page()
        XCTAssertTrue(resolver.resolve(page, isIncoming: false, allowsLinks: false) === page)
        XCTAssertTrue(resolver.resolve(page, isIncoming: true, allowsLinks: true) === page)
        XCTAssertEqual(resolver.resolve(page, isIncoming: true, allowsLinks: false).blocks, [.paragraph(.plain("link"))])
        XCTAssertEqual(page.blocks, [.paragraph(.url(text: .plain("link"), url: "https://example.com", webpageId: nil))])
    }

    func testRepeatedLayoutsReuseTheSanitizedPageIdentity() {
        let resolver = ChatRichTextSenderPage()
        let page = page()
        let shown = resolver.resolve(page, isIncoming: true, allowsLinks: false)
        XCTAssertTrue(shown === resolver.resolve(page, isIncoming: true, allowsLinks: false))
        XCTAssertTrue(page === resolver.resolve(page, isIncoming: true, allowsLinks: true))
        XCTAssertTrue(shown === resolver.resolve(page, isIncoming: true, allowsLinks: false))
        let updated = self.page("updated")
        let updatedShown = resolver.resolve(updated, isIncoming: true, allowsLinks: false)
        XCTAssertFalse(updatedShown === shown)
        XCTAssertEqual(updatedShown.blocks, [.paragraph(.plain("updated"))])
    }

    func testSafePhoneActionRemainsAvailableWithoutReenablingLinksOrMentions() {
        XCTAssertTrue(ChatRichTextSenderPage.allowsOpenURL("tel:+123456789", isIncoming: true, allowsLinks: false))
        for url in ["https://example.com", "tg://user?id=42", "mailto:a@example.com", "ton://transfer/address"] {
            XCTAssertFalse(ChatRichTextSenderPage.allowsOpenURL(url, isIncoming: true, allowsLinks: false))
            XCTAssertTrue(ChatRichTextSenderPage.allowsOpenURL(url, isIncoming: false, allowsLinks: false))
            XCTAssertTrue(ChatRichTextSenderPage.allowsOpenURL(url, isIncoming: true, allowsLinks: true))
        }
    }
}
