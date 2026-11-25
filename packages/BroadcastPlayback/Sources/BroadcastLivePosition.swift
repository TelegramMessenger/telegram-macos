// Ported from hls.js v1.7.3 (src/controller/latency-controller.ts), Copyright (c) Dailymotion and hls.js contributors, Apache License 2.0.

import Foundation

// Where live playback sits, with hls.js's formulas and a 1 s target duration (the part length). `edgeStalled` is 0: our
// edge is the server's time or its newest part, never a late playlist.
public enum BroadcastLivePosition {
    public static let partDurationMs: Int64 = 1000

    // hls.js's live edge, the end of the newest segment: the server's time for a listener, the newest part's end for a
    // stream (`last_timestamp_ms` is that part's start).
    public static func edgeMs(format: BroadcastFormat, reportedMs: Int64) -> Int64 {
        switch format {
        case .listener:
            return reportedMs
        case .unified:
            return reportedMs + BroadcastLivePosition.partDurationMs
        }
    }

    // `liveSyncDurationCount × targetduration + min(stallCount × liveSyncOnStallIncrease, targetduration)`.
    public static func targetLatencyMs(liveSyncDurationCount: Double, stallCount: Int, liveSyncOnStallIncrease: Double) -> Int64 {
        let targetDuration = Double(BroadcastLivePosition.partDurationMs)
        let base = liveSyncDurationCount * targetDuration
        let increase = min(Double(max(0, stallCount)) * liveSyncOnStallIncrease * 1000.0, targetDuration)
        return Int64((base + increase).rounded())
    }

    // `min(max(edge − totalduration, edge − targetLatency), edge − targetduration)`; the window is what the server
    // keeps.
    public static func liveSyncPositionMs(edgeMs: Int64, targetLatencyMs: Int64, windowMs: Int64) -> Int64 {
        let syncPosition = edgeMs - targetLatencyMs
        let minimum = edgeMs - windowMs
        let maximum = edgeMs - BroadcastLivePosition.partDurationMs
        return min(max(minimum, syncPosition), maximum)
    }

    // The start of the part that holds `positionMs`.
    public static func partTimestamp(containing positionMs: Int64) -> Int64 {
        let duration = BroadcastLivePosition.partDurationMs
        let quotient = positionMs / duration
        let floored = (positionMs % duration != 0 && positionMs < 0) ? quotient - 1 : quotient
        return floored * duration
    }
}
