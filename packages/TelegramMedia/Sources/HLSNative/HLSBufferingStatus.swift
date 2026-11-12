import Foundation
import RangeSet
import HLSPlayback

func hlsBufferingStatus(parts: [HLSBufferedPart], duration: Double?) -> (RangeSet<Int64>, Int64)? {
    guard let duration, duration.isFinite, duration >= 0.0, duration * 1000.0 < Double(Int64.max) else {
        return nil
    }
    var ranges = RangeSet<Int64>()
    for part in parts {
        let lower = max(0.0, part.start - 0.2)
        let upper = min(duration, part.end + 0.2)
        if lower < upper {
            ranges.formUnion(RangeSet<Int64>(Int64(lower * 1000.0) ..< Int64(upper * 1000.0)))
        }
    }
    return (ranges, Int64(duration * 1000.0))
}
