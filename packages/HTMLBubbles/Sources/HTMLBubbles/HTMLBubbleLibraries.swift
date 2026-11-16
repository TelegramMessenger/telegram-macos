import Foundation

enum HTMLBubbleLibraries {
    private static let three: String? = {
        guard let url = Bundle.module.url(forResource: "three", withExtension: "js", subdirectory: "lib") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    static func source(named name: String) -> String? {
        switch name {
        case "three":
            return three
        default:
            return nil
        }
    }
}
