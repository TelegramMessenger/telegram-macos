import Foundation
@testable import HTMLBubbles

enum DemoFixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func install() {
        HTMLDemoCatalog.fixturesRoot = root
    }
}
