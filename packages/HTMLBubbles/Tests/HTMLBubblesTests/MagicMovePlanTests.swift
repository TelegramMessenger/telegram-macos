import XCTest
import AppKit
import LiteHTML
import TwidgetRenderer
@testable import HTMLBubbles

final class MagicMovePlanTests: XCTestCase {
    private func page(_ order: [Int], step: Int) -> String {
        let colors = ["#ff3b30", "#ff9500", "#34c759", "#007aff", "#af52de"]
        let cards = order.map { "<div class=\"c\" data-key=\"k\($0)\" style=\"background-color: \(colors[$0])\">Item \($0)<br>\(step)</div>" }.joined()
        return "<!doctype html><style>body { margin: 0; font: 13px -apple-system; } .c { display: inline-block; width: 70px; height: 34px; margin: 4px; padding: 6px; border-radius: 8px; color: #fff; }</style><div>\(cards)</div>"
    }

    private func tiles(_ document: LHDocument, width: CGFloat) -> [HTMLBubbleTile] {
        let size = document.layout(withMaxWidth: width)
        return [HTMLBubbleTile(rect: CGRect(x: 0, y: 0, width: width, height: size.height), image: document.copyImage(maxWidth: width, rect: CGRect(x: 0, y: 0, width: width, height: size.height), scale: 2)!)]
    }

    func testPlanMovesEntersAndLeaves() throws {
        let width: CGFloat = 360
        let old = LHDocument(html: page([0, 1, 2, 3], step: 0), css: nil)
        _ = old.layout(withMaxWidth: width)
        let capture = try XCTUnwrap(HTMLBubbleMagicMove.capture(old, presented: [:], scale: 2))
        XCTAssertEqual(Set(capture.rects.keys), ["k0", "k1", "k2", "k3"])
        let new = LHDocument(html: page([4, 3, 1, 0], step: 1), css: nil, previous: old)
        let plan = try XCTUnwrap(HTMLBubbleMagicMove.plan(capture, document: new, width: width, scale: 2, tiles: tiles(new, width: width)))
        var moves: [String] = [], enters: [String] = [], leaves = 0, crossfades = 0
        for item in plan.items {
            switch item {
            case let .move(key, _, _, previous):
                moves.append(key)
                crossfades += previous == nil ? 0 : 1
            case let .enter(key, _):
                enters.append(key)
            case .leave:
                leaves += 1
            }
        }
        XCTAssertEqual(Set(moves), ["k0", "k1", "k3"])
        XCTAssertEqual(enters, ["k4"])
        XCTAssertEqual(leaves, 1)
        XCTAssertEqual(crossfades, 3)
        XCTAssertEqual(plan.baseTiles.count, 1)
    }
}
