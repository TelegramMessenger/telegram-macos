import XCTest
import AppKit
import TGUIKit
import TelegramCore
import Postbox
import Localization
import LocalAnimations
@testable import StarsUI

final class StarGiftActionsTests: XCTestCase {
    private static let themeImages: [NSImage] = {
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Telegram-Mac/Assets.xcassets")
        return [("Icon_SearchField", "search-icon@2x.png"), ("Icon_SearchClear", "ic_delete@2x.png"), ("Icon_Quote", "ic_quote_10@2x.png"), ("Icon_Quote_Collapse", "collapse_16@2x.png"), ("Icon_Quote_Expand", "expand_16@2x.png")].compactMap { name, file in
            guard let image = NSImage(contentsOf: assets.appendingPathComponent(name + ".imageset").appendingPathComponent(file)) else {
                XCTFail("Missing theme image: \(name)")
                return nil
            }
            image.size = NSSize(width: image.size.width / 2, height: image.size.height / 2)
            image.setName(name)
            return image
        }
    }()

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        XCTAssertEqual(Self.themeImages.count, 5)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let values = NSDictionary(contentsOf: root.appendingPathComponent("Telegram-Mac/en.lproj/Localizable.strings")) as? [String: String] ?? [:]
        XCTAssertFalse(values.isEmpty)
        let component = LocalizationComponent(languageCode: "en", localizedName: "English", localization: TelegramCore.Localization(version: 0, entries: values.map { LocalizationEntry.string(key: $0.key, value: $0.value) }), customPluralizationCode: nil)
        applyUILocalization(LocalizationSettings(primaryComponent: component, secondaryComponent: nil))
    }

    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))

    private func user(_ id: Int64) -> EnginePeer {
        return .user(TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Sender", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
    }

    private func gift(limited: Bool = false) -> StarGift {
        return .generic(.init(id: 1, title: nil, file: LocalAnimatedSticker.gift.file, price: 50, convertStars: 43, availability: limited ? .init(remains: 1, total: 10, resale: 0, minResaleStars: nil) : nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil, perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil, auctionStartDate: nil, upgradeVariantsCount: nil, background: nil))
    }

    func testConversionDisappearsAtConfiguredDeadline() {
        let date: Int32 = 1_700_000_000
        let period: Int32 = 7 * 24 * 60 * 60
        for (offset, expected) in [(Int32(0), true), (period - 1, true), (period, false), (period + 1, false)] {
            XCTAssertEqual(starGiftCanConvert(date: date, period: period, timestamp: date + offset, amount: 43, converted: false, upgraded: false, refunded: false), expected)
        }
    }

    func testConfiguredWindowIsNotHardcodedToSevenDays() {
        let date: Int32 = 1_700_000_000
        XCTAssertTrue(starGiftCanConvert(date: date, period: 30 * 86400, timestamp: date + 8 * 86400, amount: 43, converted: false, upgraded: false, refunded: false))
        XCTAssertFalse(starGiftCanConvert(date: date, period: 60, timestamp: date + 60, amount: 43, converted: false, upgraded: false, refunded: false))
        XCTAssertEqual(starGiftConversionDeadline(date: .max, period: .max), Int64(Int32.max) * 2)
    }

    func testIneligibleGiftCannotConvert() {
        for amount: Int64? in [nil, 0, -1] {
            XCTAssertFalse(starGiftCanConvert(date: 1000, period: 100, timestamp: 1001, amount: amount, converted: false, upgraded: false, refunded: false))
        }
        for flags in [(true, false, false), (false, true, false), (false, false, true)] {
            XCTAssertFalse(starGiftCanConvert(date: 1000, period: 100, timestamp: 1001, amount: 43, converted: flags.0, upgraded: flags.1, refunded: flags.2))
        }
        for period: Int32 in [0, -1] {
            XCTAssertFalse(starGiftCanConvert(date: 1000, period: period, timestamp: 1001, amount: 43, converted: false, upgraded: false, refunded: false))
        }
        XCTAssertFalse(starGiftCanConvert(date: 0, period: 100, timestamp: 1, amount: 43, converted: false, upgraded: false, refunded: false))
    }

    func testMenuPreservesCollectionsVisibilityAndDeleteCallbacks() {
        for saved in [false, true] {
            var calls: [String] = []
            let collection = ContextMenuItem(strings().peerMediaGiftsCollectionContextAddToCollection)
            let submenu = ContextMenu()
            submenu.items = [ContextMenuItem("Collection", handler: { calls.append("collection") })]
            collection.submenu = submenu
            let items = genericGiftMenuItems(collections: collection, savedToProfile: saved, toggleVisibility: { calls.append("visibility") }, delete: { calls.append("delete") })
            XCTAssertEqual(items.map { $0.isSeparatorItem ? "separator" : $0.title }, [collection.title, "separator", saved ? strings().giftContextHide : strings().giftContextShow, "separator", strings().giftViewContextDelete])
            XCTAssertTrue(items[0] === collection)
            XCTAssertTrue(calls.isEmpty)
            (items[0].submenu?.items[0] as? ContextMenuItem)?.handler?()
            items[2].handler?()
            items[4].handler?()
            XCTAssertEqual(calls, ["collection", "visibility", "delete"])
        }
    }

    func testIneligibleDeleteDoesNotLeaveEmptySeparators() {
        let items = genericGiftMenuItems(collections: nil, savedToProfile: true, toggleVisibility: {}, delete: nil)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, strings().giftContextHide)
        XCTAssertFalse(items[0].isSeparatorItem)
    }

    func testDeletionEligibilityMatchesExistingOwnershipAndGiftPolicy() {
        let reference = StarGiftReference.message(messageId: .init(peerId: accountId, namespace: Namespaces.Message.Cloud, id: 1))
        XCTAssertTrue(starGiftCanDelete(gift: gift(), reference: reference, owner: user(1), accountPeerId: accountId, converted: false, fromProfile: true, upgraded: false, refunded: false))
        XCTAssertFalse(starGiftCanDelete(gift: gift(), reference: reference, owner: user(2), accountPeerId: accountId, converted: false, fromProfile: true, upgraded: false, refunded: false))
        XCTAssertFalse(starGiftCanDelete(gift: gift(limited: true), reference: reference, owner: user(1), accountPeerId: accountId, converted: false, fromProfile: true, upgraded: false, refunded: false))
        XCTAssertFalse(starGiftCanDelete(gift: gift(), reference: nil, owner: user(1), accountPeerId: accountId, converted: false, fromProfile: true, upgraded: false, refunded: false))
        for flags in [(true, false, false), (false, true, false), (false, false, true)] {
            XCTAssertFalse(starGiftCanDelete(gift: gift(), reference: reference, owner: user(1), accountPeerId: accountId, converted: flags.0, fromProfile: false, upgraded: flags.1, refunded: flags.2))
        }
    }
}
