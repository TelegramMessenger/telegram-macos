import Foundation
import SwiftSignalKit

public final class EditedPhotoVideos {
    public static let shared = EditedPhotoVideos()

    private let paths = Atomic<Set<String>>(value: [])

    public func add(path: String) {
        _ = paths.modify { $0.union([path]) }
    }

    public func contains(path: String) -> Bool {
        return paths.with { $0.contains(path) }
    }
}
