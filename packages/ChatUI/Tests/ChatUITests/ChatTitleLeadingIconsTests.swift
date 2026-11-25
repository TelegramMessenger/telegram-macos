import AppKit
import XCTest
import Postbox
import TelegramCore
import PremiumStatusUI
import TGUIKit
@testable import ChatUI

private final class VerificationHeaderFixture: TitledBarView {
    var badgeWidth: CGFloat?
    override var inset: CGFloat { 86 + ChatTitleLeadingIcons.badgeInset(badgeWidth) }
}

final class ChatTitleLeadingIconsTests: XCTestCase {
    override func setUp() { super.setUp(); UITestBootstrap.install() }

    private func user(icon: Int64?) -> TelegramUser {
        TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(5_000_000_000)), accessHash: nil, firstName: "Verified person", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: icon)
    }

    func testVerificationBelongsToAssociatedUserAndRespectsReportMode() {
        let person = user(icon: 42)
        XCTAssertEqual(ChatTitleLeadingIcons.badgePeer(person, allowed: true)?.id, person.id)
        XCTAssertNil(ChatTitleLeadingIcons.badgePeer(person, allowed: false))
        XCTAssertNil(ChatTitleLeadingIcons.badgePeer(user(icon: nil), allowed: true))
        XCTAssertNil(ChatTitleLeadingIcons.badgePeer(nil, allowed: true))
    }

    func testAbsentVerificationDoesNotShiftEitherTitle() {
        for secret in [false, true] {
            let insets = ChatTitleLeadingIcons.insets(base: 46, badgeWidth: nil, hasLock: secret)
            XCTAssertEqual(insets.text, 46)
            XCTAssertEqual(insets.title, 0)
        }
        XCTAssertEqual(ChatTitleLeadingIcons.badgeInset(nil), 0)
    }

    func testActualNativeTitleLayoutLeavesBadgeThenLockThenNameAtBothWidths() throws {
        let size = try XCTUnwrap(PremiumStatusControl.controlSize(user(icon: 42), false, left: true))
        let lock = NSImage(size: NSSize(width: 10, height: 14), flipped: true) { rect in
            NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill(); return true
        }
        let lockImage = try XCTUnwrap(lock.cgImage(forProposedRect: nil, context: nil, hints: nil))
        for width: CGFloat in [260, 600] {
            for secret in [false, true] {
                let header = VerificationHeaderFixture(controller: ViewController(), NSAttributedString(string: String(repeating: "Long verified contact ", count: 5), attributes: [.font: NSFont.systemFont(ofSize: 14)]), nil)
                header.badgeWidth = size.width
                header.setFrameSize(NSSize(width: width, height: 50))
                let insets = ChatTitleLeadingIcons.insets(base: 46, badgeWidth: size.width, hasLock: secret)
                header.textInset = insets.text
                header.titleInset = insets.title
                header.titleImage = secret ? (lockImage, .left(topInset: 0)) : nil
                header.layoutSubtreeIfNeeded()
                let title = try XCTUnwrap(header.titleRect)
                let badge = ChatTitleLeadingIcons.verificationFrame(title: title, lockWidth: secret ? lockImage.backingSize.width : nil, badgeSize: size)
                XCTAssertEqual(badge.minX, 46, accuracy: 0.01)
                if secret {
                    let lockX = try XCTUnwrap(header.textInset)
                    XCTAssertEqual(lockX - badge.maxX, 2, accuracy: 0.01)
                    XCTAssertEqual(title.minX - lockX - lockImage.backingSize.width, 4, accuracy: 0.01)
                } else {
                    XCTAssertEqual(title.minX - badge.maxX, 2, accuracy: 0.01)
                }
                XCTAssertFalse(badge.intersects(title))
                XCTAssertLessThanOrEqual(title.maxX, width - 24)
                XCTAssertGreaterThan(title.width, 20)
            }
        }
    }
}
