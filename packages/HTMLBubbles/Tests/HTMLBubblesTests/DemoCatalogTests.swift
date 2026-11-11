import XCTest
@testable import HTMLBubbles

final class DemoCatalogTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        DemoFixtures.install()
    }

    func testAppBundleShipsNoDemoFixtures() {
        for name in ["chats", "ported", "widget-sandbox", "multiplayer"] {
            XCTAssertNil(Bundle.module.url(forResource: name, withExtension: nil), name)
        }
        XCTAssertNotNil(Bundle.module.url(forResource: "three", withExtension: "js", subdirectory: "lib"))
    }

    func testEveryCommandHasATwidgetPort() {
        for command in HTMLDemoCatalog.commands {
            for index in command.messageIndices {
                XCTAssertNotNil(HTMLDemoCatalog.portedHTML(conversationId: command.conversationId, index: index), "/\(command.command) message \(index + 1) of \(command.conversationId)")
            }
        }
    }
}
