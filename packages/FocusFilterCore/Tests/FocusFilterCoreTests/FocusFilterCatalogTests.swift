import Foundation
import XCTest
import FocusFilterCore

final class FocusFilterCatalogTests: XCTestCase {
    func testLegacyCatalogDecodesWithoutTelegramUserId() throws {
        let data = Data(#"{"accounts":[{"id":-8000000000000000001,"title":"Account"}],"chats":[],"folders":[]}"#.utf8)
        let catalog = try JSONDecoder().decode(FocusFilterCatalog.self, from: data)

        XCTAssertEqual(catalog.accounts.first?.id, -8_000_000_000_000_000_001)
        XCTAssertNil(catalog.accounts.first?.telegramUserId)
    }

    func testCatalogRoundTripPreservesSeparateLocalAndTelegramIdentifiers() throws {
        let catalog = FocusFilterCatalog(accounts: [
            .init(id: -8_000_000_000_000_000_001, title: "Account", telegramUserId: 6_123_456_789)
        ], chats: [
            .init(id: .init(accountId: -8_000_000_000_000_000_001, peerId: 8_589_934_634), title: "Channel", telegramChatId: -1_000_000_000_042)
        ])
        let data = try JSONEncoder().encode(catalog)

        XCTAssertEqual(try JSONDecoder().decode(FocusFilterCatalog.self, from: data), catalog)
    }

    func testLegacyChatDecodesWithoutTelegramChatId() throws {
        let data = Data(#"{"accounts":[],"chats":[{"id":{"accountId":-71,"peerId":8589934634},"title":"Channel","isArchived":false}],"folders":[]}"#.utf8)
        let catalog = try JSONDecoder().decode(FocusFilterCatalog.self, from: data)

        XCTAssertEqual(catalog.chats.first?.id, .init(accountId: -71, peerId: 8_589_934_634))
        XCTAssertNil(catalog.chats.first?.telegramChatId)
    }
}
