import Foundation

// Where a stream's unified part plays in ChunkMediaPlayerV2 (the part's `offsetTime`, in seconds on the server's clock).
// Each slice's own timeline starts at zero, and AAC frames do not end on the second, so a part directly after the last
// one placed starts where that part's audio ended; any other part (the first, one after a gap or a jump, one after a
// part without audio) starts at its own timestamp.
public struct BroadcastStreamTimeline {
    private var last: (timestampMs: Int64, offset: Double, audioDurationSeconds: Double?)?

    public init() {
    }

    // Places the part at `timestampMs`, whose audio lasts `audioDurationSeconds`, and returns its offset.
    public mutating func offset(timestampMs: Int64, audioDurationSeconds: Double?) -> Double {
        var offset = Double(timestampMs) / 1000.0
        if let last = self.last, last.timestampMs + BroadcastLivePosition.partDurationMs == timestampMs, let duration = last.audioDurationSeconds {
            offset = last.offset + duration
        }
        self.last = (timestampMs, offset, audioDurationSeconds)
        return offset
    }
}
