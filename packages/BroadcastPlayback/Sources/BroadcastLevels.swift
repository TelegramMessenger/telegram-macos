import Foundation
import HLSPlayback

public enum BroadcastBitrateKey: Hashable {
    case audio
    case video(BroadcastQuality)
    case unified(BroadcastQuality)

    public init(_ kind: BroadcastPartKind) {
        switch kind {
        case .audio:
            self = .audio
        case let .video(_, quality):
            self = .video(quality)
        case let .unified(quality):
            self = .unified(quality)
        }
    }
}

// Each level's bitrate, learned from the parts that arrive: no nominal bitrates exist. A part is one second, so a part's
// bytes × 8 is its bits per second; a level reads the mean of its last 10 parts, its seed until one arrives.
public struct BroadcastLevelBitrates: Equatable {
    public static let observedParts = 10
    // Full and medium: a stream's two levels as an HLS master playlist declared them; thumbnail and audio: designer's
    // calls (audio: three speakers at 32 kbit/s).
    public static let seeds: [BroadcastBitrateKey: Double] = [
        .audio: 100_000.0,
        .video(.thumbnail): 300_000.0,
        .video(.medium): 1_000_000.0,
        .video(.full): 3_300_000.0,
        .unified(.thumbnail): 300_000.0,
        .unified(.medium): 1_000_000.0,
        .unified(.full): 3_300_000.0
    ]

    private var observed: [BroadcastBitrateKey: [Int64]] = [:]

    public init() {
    }

    public func bitsPerSecond(_ key: BroadcastBitrateKey) -> Double {
        if let parts = self.observed[key], !parts.isEmpty {
            return 8.0 * Double(parts.reduce(0, +)) / Double(parts.count)
        }
        return BroadcastLevelBitrates.seeds[key] ?? 0.0
    }

    public mutating func observe(_ key: BroadcastBitrateKey, bytes: Int64) {
        var parts = self.observed[key] ?? []
        parts.append(bytes)
        if parts.count > BroadcastLevelBitrates.observedParts {
            parts.removeFirst(parts.count - BroadcastLevelBitrates.observedParts)
        }
        self.observed[key] = parts
    }

    // The three levels of a video channel (or a stream), as `HLSAbr` reads them: thumbnail, medium, full.
    public func bitsPerSecond(video: Bool) -> [Double] {
        return BroadcastQuality.allCases.map { self.bitsPerSecond(video ? .video($0) : .unified($0)) }
    }

    public func levels(video: Bool) -> [HLSLevel] {
        let sizes = [(320, 180), (640, 360), (1280, 720)]
        return HLSLevels.sorted(zip(BroadcastQuality.allCases, sizes).map { quality, size in
            let bandwidth = Int(self.bitsPerSecond(video ? .video(quality) : .unified(quality)).rounded())
            return HLSLevel(key: min(size.0, size.1), width: size.0, height: size.1, bandwidth: bandwidth)
        })
    }
}
