import Foundation
import RangeSet
import HLSPlayback

func part(_ index: Int, _ start: Double, _ end: Double) -> HLSBufferedPart {
    return HLSBufferedPart(key: HLSSegmentKey(level: 0, index: index), start: start, end: end)
}

let test = CommandLine.arguments[1]
var parts: [HLSBufferedPart] = []
var duration: Double? = 10.0
var expected: [Range<Int64>] = []
var expectedDuration: Int64? = 10000
switch test {
case "normal":
    parts = [part(0, 1.0, 3.0)]
    expected = [800 ..< 3200]
case "merged":
    parts = [part(1, 5.1, 8.0), part(0, 0.0, 5.0)]
    expected = [0 ..< 8200]
case "separate":
    parts = [part(0, 0.0, 2.0), part(3, 6.0, 8.0)]
    expected = [0 ..< 2200, 5800 ..< 8200]
case "past-end":
    duration = 5.0
    parts = [part(0, 6.0, 8.0)]
    expectedDuration = 5000
case "straddles-end":
    duration = 5.0
    parts = [part(0, 4.5, 6.0)]
    expected = [4300 ..< 5000]
    expectedDuration = 5000
case "before-start":
    parts = [part(0, -4.0, -1.0)]
case "nan-part":
    parts = [part(0, .nan, .nan)]
    expected = [0 ..< 10000]
case "empty":
    parts = []
case "zero-duration":
    duration = 0.0
    parts = [part(0, 1.0, 2.0)]
    expectedDuration = 0
case "infinite-duration":
    duration = .infinity
    parts = [part(0, 1.0, 3.0)]
    expectedDuration = nil
case "nan-duration":
    duration = .nan
    parts = [part(0, 1.0, 3.0)]
    expectedDuration = nil
case "negative-duration":
    duration = -1.0
    parts = [part(0, 1.0, 3.0)]
    expectedDuration = nil
case "overflow-duration":
    duration = Double(Int64.max) / 1000.0
    parts = [part(0, 1.0, 3.0)]
    expectedDuration = nil
case "unknown-duration":
    duration = nil
    parts = [part(0, 1.0, 3.0)]
    expectedDuration = nil
case "submillisecond":
    duration = 0.0009
    parts = [part(0, 0.0, 0.01)]
    expectedDuration = 0
default:
    preconditionFailure("Unknown case")
}
let result = hlsBufferingStatus(parts: parts, duration: duration)
if let expectedDuration {
    guard let (ranges, value) = result else {
        preconditionFailure("Expected buffer state")
    }
    precondition(value == expectedDuration, "duration \(value) != \(expectedDuration)")
    precondition(Array(ranges.ranges) == expected, "ranges \(Array(ranges.ranges)) != \(expected)")
    print("buffer=\(Array(ranges.ranges)) duration=\(value)")
} else {
    precondition(result == nil)
    print("buffer state unavailable")
}
