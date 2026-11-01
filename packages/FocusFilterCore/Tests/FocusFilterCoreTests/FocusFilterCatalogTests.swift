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
        ])
        let data = try JSONEncoder().encode(catalog)

        XCTAssertEqual(try JSONDecoder().decode(FocusFilterCatalog.self, from: data), catalog)
    }
}
