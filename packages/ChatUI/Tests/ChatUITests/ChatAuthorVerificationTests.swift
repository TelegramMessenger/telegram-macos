import AppKit
import XCTest
import Postbox
import TelegramCore
import PremiumStatusUI
import TGUIKit
import TelegramTheme
import ThemeSettings
import ColorPalette
@testable import ChatUI

final class ChatAuthorVerificationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func user(id: Int64 = 2, icon: Int64? = 42) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Verified sender", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: icon)
    }

    private func channel(id: Int64 = 3) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(id)), accessHash: nil, title: "Verified channel", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: 43, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    func testUsersAndPostingChannelsUseTheirOwnVerification() {
        let chat = channel(id: 4)
        XCTAssertEqual(ChatAuthorVerification.peer(author: user(), chatId: chat.id, displaysAuthor: true)?.verificationIconFileId, 42)
        XCTAssertEqual(ChatAuthorVerification.peer(author: channel(), chatId: chat.id, displaysAuthor: true)?.verificationIconFileId, 43)
    }

    func testChatItselfAndAnonymousAdminNeverRepeatHeaderVerification() {
        let chat = channel()
        XCTAssertNil(ChatAuthorVerification.peer(author: chat, chatId: chat.id, displaysAuthor: true))
    }

    func testMissingAuthorNameOrIconReservesNoSpace() {
        XCTAssertNil(ChatAuthorVerification.peer(author: user(icon: nil), chatId: channel().id, displaysAuthor: true))
        XCTAssertNil(ChatAuthorVerification.peer(author: user(), chatId: channel().id, displaysAuthor: false))
        XCTAssertNil(ChatAuthorVerification.peer(author: nil, chatId: channel().id, displaysAuthor: true))
        XCTAssertEqual(ChatAuthorVerification.inset(for: nil), 0)
    }

    func testIconPrecedesNameWithFourPointSpacingAndSharesVerticalCenter() throws {
        let author = user()
        let size = try XCTUnwrap(PremiumStatusControl.controlSize(author, false, left: true))
        let inset = ChatAuthorVerification.inset(for: author)
        let nameOrigin = NSPoint(x: 24 + inset, y: 20)
        let frame = ChatAuthorVerification.frame(nameOrigin: nameOrigin, nameHeight: 16, size: size)
        XCTAssertEqual(frame.minX, 24)
        XCTAssertEqual(nameOrigin.x - frame.maxX, 4)
        XCTAssertEqual(frame.midY, nameOrigin.y + 8)
        XCTAssertEqual(inset, size.width + 4)
    }

    func testIncomingOutgoingAndListBadgesUseTheirOwnAccent() {
        for palette in [dayClassicPalette, nightAccentPalette] {
            let presentation = generateTheme(palette: palette, cloudTheme: nil, bubbled: true, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false)
            XCTAssertEqual(ChatAuthorVerification.color(incoming: true, bubbled: true, presentation: presentation), palette.linkBubble_incoming)
            XCTAssertEqual(ChatAuthorVerification.color(incoming: false, bubbled: true, presentation: presentation), palette.linkBubble_outgoing)
            XCTAssertEqual(ChatAuthorVerification.color(incoming: true, bubbled: false, presentation: presentation), palette.accent)
            XCTAssertEqual(ChatAuthorVerification.color(incoming: false, bubbled: false, presentation: presentation), palette.accent)
        }
    }

    func testBadgeGeometryMockRendersBesideTruncatedSender() throws {
        let author = user()
        let size = try XCTUnwrap(PremiumStatusControl.controlSize(author, false, left: true))
        let image = NSImage(size: NSSize(width: 340, height: 150), flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            let presentation = generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: true, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false)
            let variants = [("Incoming", true, true, true), ("Outgoing", false, true, true), ("List", true, false, true), ("No bubble", true, true, false)]
            for (index, variant) in variants.enumerated() {
                let (_, incoming, bubbled, displaysAuthor) = variant
                let verifiedPeer = ChatAuthorVerification.peer(author: author, chatId: self.channel().id, displaysAuthor: displaysAuthor)
                let inset = ChatAuthorVerification.inset(for: verifiedPeer)
                let nameOrigin = NSPoint(x: 24 + inset, y: CGFloat(index * 32 + 10))
                let frame = ChatAuthorVerification.frame(nameOrigin: nameOrigin, nameHeight: 16, size: size)
                if verifiedPeer != nil {
                    ChatAuthorVerification.color(incoming: incoming, bubbled: bubbled, presentation: presentation).setFill()
                    NSBezierPath(ovalIn: frame).fill()
                    XCTAssertEqual(nameOrigin.x - frame.maxX, 4)
                } else {
                    XCTAssertEqual(inset, 0)
                }
                let label = variant.0 + (displaysAuthor ? ": Verified sender with a long author name" : ": no author verification")
                let text = TextViewLayout(NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.black]), maximumNumberOfLines: 1, truncationType: .end)
                text.measure(width: 280 - inset)
                text.attributedString.draw(in: NSRect(origin: nameOrigin, size: text.layoutSize))
                XCTAssertLessThanOrEqual(text.layoutSize.width + inset, 280)
            }
            return true
        }
        let imageData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: imageData))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "Author verification geometry mock"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["CHATUI_SYNC_PROOF_DIR"] {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("author-verification-geometry-mock.png"))
        }
    }
}
