import Cocoa
import XCTest
import TGUIKit

final class ContextMenuBuildTests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment

    override func setUp() {
        TGUIKitTestBootstrap.install()
    }

    private func buildSubmenus(forums: Int, topics: Int) -> [ContextMenu] {
        (0..<forums).map { forum in
            let menu = ContextMenu()
            for topic in 0..<topics {
                menu.addItem(ContextMenuItem("Forum \(forum) topic \(topic)"))
            }
            return menu
        }
    }

    func testTopicSubmenuInsertions() {
        let expectsBug = environment["CONTEXT_MENU_EXPECT_BUG"] == "1"
        for topics in [1, 25, 100, 400] {
            let menu = ContextMenu()
            var insertions = 0
            let observer = NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: menu, queue: nil) { _ in
                insertions += 1
            }
            let items = (0..<topics).map { ContextMenuItem("Topic \($0)") }
            items.forEach(menu.addItem)
            NotificationCenter.default.removeObserver(observer)

            print("CONTEXT_MENU_INSERTIONS {\"topics\": \(topics), \"insertions\": \(insertions)}")
            XCTAssertEqual(insertions, expectsBug ? topics * (topics + 1) / 2 : topics)
            XCTAssertEqual(menu.numberOfItems, topics)
            XCTAssertTrue(items.indices.allSatisfy { menu.item(at: $0) === items[$0] && menu.items[$0] === items[$0] })
        }
    }

    func testForwardMenuBuildTime() throws {
        guard environment["CONTEXT_MENU_BENCHMARK"] == "1" else {
            throw XCTSkip("Set CONTEXT_MENU_BENCHMARK=1 to measure build time")
        }
        let scenarios: [(name: String, forums: Int, topics: Int)] = [
            ("one forum, 100 topics", 1, 100),
            ("15 forums, 100 topics each", 15, 100),
            ("one forum, 1000 topics", 1, 1000),
            ("100 forums, 1000 topics each", 100, 1000),
        ]
        for scenario in scenarios {
            autoreleasepool {
                _ = buildSubmenus(forums: scenario.forums, topics: scenario.topics)
            }
            let samples: [Double] = (0..<9).map { _ in
                autoreleasepool {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let menus = buildSubmenus(forums: scenario.forums, topics: scenario.topics)
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start
                    XCTAssertEqual(menus.reduce(0) { $0 + $1.numberOfItems }, scenario.forums * scenario.topics)
                    return Double(elapsed) / 1_000_000
                }
            }
            let median = samples.sorted()[samples.count / 2]
            let rounded = samples.map { ($0 * 1000).rounded() / 1000 }
            print("CONTEXT_MENU_BENCHMARK {\"scenario\": \"\(scenario.name)\", \"median_ms\": \((median * 1000).rounded() / 1000), \"samples_ms\": \(rounded)}")
        }
    }
}
