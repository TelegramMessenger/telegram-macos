import XCTest
import AppKit
import Postbox
import TelegramCore
import TGUIKit
import TelegramTheme
import LocalAnimations
@testable import StarsUI
@testable import ChatUI

final class ChatGiftMessageLayoutTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func layout(_ text: String) -> TextViewLayout {
        return TextViewLayout(.initialize(string: text, color: theme.colors.text, font: .normal(.text)))
    }

    private func source(unique: Bool, refunded: Bool = false) -> ChatServiceItem.GiftData.Source {
        let gift: StarGift
        if unique {
            gift = .unique(.init(id: 1, giftId: 1, title: "Desk Calendar", number: 96344, slug: "DeskCalendar-96344", owner: .peerId(peerId), attributes: [], availability: .init(issued: 1, total: 100), giftAddress: nil, resellAmounts: nil, resellForTonOnly: false, releasedBy: nil, valueAmount: nil, valueCurrency: nil, valueUsdAmount: nil, flags: [], themePeerId: nil, peerColor: nil, hostPeerId: nil, minOfferStars: nil, craftChancePermille: nil))
        } else {
            gift = .generic(.init(id: 1, title: nil, file: LocalAnimatedSticker.gift.file, price: 50, convertStars: 43, availability: nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil, perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil, auctionStartDate: nil, upgradeVariantsCount: nil, background: nil))
        }
        let purpose = Star_TransactionPurpose.starGift(gift: gift, convertStars: nil, text: nil, entities: nil, nameHidden: false, savedToProfile: false, converted: false, fromProfile: false, upgraded: unique, prepaidUpgradeHash: nil, transferStars: nil, canExportDate: nil, reference: nil, sender: nil, saverId: nil, canTransferDate: nil, canResaleDate: nil, dropOriginalDetailsStars: nil, canUpgrade: false, number: nil, isRefunded: refunded, canCraftAt: nil, craftChancePermille: nil, upgradeStars: nil)
        return .starGift(amount: 0, date: 1, from: nil, to: nil, purpose: purpose)
    }

    private func data(source: ChatServiceItem.GiftData.Source, text: String = "Gift from Sender", info: TextViewLayout? = nil, attributes: ChatServiceItem.GiftData.UniqueAttributes? = nil, message: ChatServiceItem.GiftData.GiftMessage? = nil, author: TextViewLayout? = nil) -> ChatServiceItem.GiftData {
        return .init(from: peerId, to: peerId, text: layout(text), info: info, source: source, ribbon: nil, uniqueAttributes: attributes, giftMessage: message, authorLayout: author, author: nil, isPrepaidUpgrade: false)
    }

    func testCollectibleAndOrdinaryGiftArtworkUsesRequestedSize() {
        for unique in [false, true] {
            let gift = data(source: source(unique: unique))
            XCTAssertEqual(gift.stickerSize, NSSize(width: 120, height: 120))
            XCTAssertEqual(gift.height, 140 + gift.text.layoutSize.height + 15 + 38)
        }
    }

    func testAddMessagePreviewUsesTheSameArtworkSize() {
        XCTAssertEqual(AddGiftMessagePreviewItem.stickerSize, NSSize(width: 120, height: 120))
        for unique in [false, true] {
            let gift = data(source: source(unique: unique))
            XCTAssertEqual(gift.stickerSize, AddGiftMessagePreviewItem.stickerSize)
        }
    }

    func testPremiumStarsAndTonKeepTheirOriginalGeometry() {
        let sources: [ChatServiceItem.GiftData.Source] = [
            .premium(days: 90),
            .stars(amount: 100, date: 1, transactionId: nil, peer: nil),
            .ton(amount: 100, date: 1, transactionId: nil, peer: nil)
        ]
        for source in sources {
            let gift = data(source: source)
            XCTAssertEqual(gift.stickerSize, NSSize(width: 150, height: 150))
            XCTAssertEqual(gift.height, 170 + gift.text.layoutSize.height + 15 + 38)
        }
    }

    func testCollectibleAttributesAndLongSenderRetainTheirSpace() {
        let attributes = ChatServiceItem.GiftData.UniqueAttributes(header: layout("Desk Calendar #96344"), attributes: [
            .init(name: layout("Model"), value: layout("Cat Seasons")),
            .init(name: layout("Symbol"), value: layout("Mannaz Rune")),
            .init(name: layout("Backdrop"), value: layout("Cappuccino"))
        ])
        let gift = data(source: source(unique: true), text: "Gift from a sender with a very long display name", attributes: attributes)
        XCTAssertGreaterThan(gift.text.numberOfLines, 1)
        XCTAssertEqual(gift.height, 140 + gift.text.layoutSize.height + 15 + attributes.height + 38)
        XCTAssertEqual(gift.stickerSize.width, gift.stickerSize.height)
    }

    func testRefundedGiftWithoutAttributesStillUsesCompactArtwork() {
        for unique in [false, true] {
            let info = layout("This gift was refunded.")
            let gift = data(source: source(unique: unique, refunded: true), info: info)
            XCTAssertNil(gift.uniqueAttributes)
            XCTAssertEqual(gift.stickerSize, NSSize(width: 120, height: 120))
            XCTAssertEqual(gift.height, 140 + gift.text.layoutSize.height + 15 + 4 + info.layoutSize.height + 38)
        }
    }

    func testGiftMessageAndAuthorRetainTheirSpace() {
        let message = ChatServiceItem.GiftData.GiftMessage(peer: nil, text: layout("A longer gift message that wraps onto several lines in the card."))
        let author = layout("Sender")
        let gift = data(source: source(unique: true), message: message, author: author)
        XCTAssertGreaterThan(message.text.numberOfLines, 1)
        XCTAssertEqual(gift.height, 140 + gift.text.layoutSize.height + 15 + message.height + author.layoutSize.height + 38)
    }
}
