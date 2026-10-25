let now: Int32 = 1_780_000_000
let baselineOnly = CommandLine.arguments.contains("--baseline")
var rows: [[String: Any]] = []
var failures: [String] = []

for (name, dates, duration) in [
    ("fresh-past-one-hour", [now - 1], 3600),
    ("week-old-one-day", [now - 7 * 86400], 86400),
    ("future-two-hours", [now + 7200], 7200),
    ("mixed-recent-then-old", [now - 10, now - 7200], 3600),
    ("mixed-old-then-recent", [now - 7200, now - 10], 3600)
] {
    let period = Int32(originalPeriod(dates, now)!)
    var originalShown = dates.map { originalLabel($0, now) }
    var currentShown = dates.map { currentLabel($0, Int64(now)) }
    var next = nextRelativeDateTimeEntityUpdate(timestamps: dates, now: Double(now))!
    var originalCallbacks = 0
    var currentCallbacks = 0
    var originalStaleSeconds = 0
    var currentStaleSeconds = 0
    var sampleBefore: [String] = []
    var sampleAfter: [String] = []
    for offset in 1...duration {
        let time = now + Int32(offset)
        let expected = dates.map { originalLabel($0, time) }
        if offset % Int(period) == 0 {
            originalCallbacks += 1
            originalShown = expected
        }
        if Double(time) >= next {
            currentCallbacks += 1
            currentShown = dates.map { currentLabel($0, Int64(time)) }
            next = nextRelativeDateTimeEntityUpdate(timestamps: dates, now: Double(time))!
        }
        if originalShown != expected { originalStaleSeconds += 1 }
        if currentShown != expected { currentStaleSeconds += 1 }
        if name == "future-two-hours", offset == 7170 {
            sampleBefore = originalShown
            sampleAfter = currentShown
        }
    }
    if currentStaleSeconds != 0 { failures.append("\(name): stale new labels") }
    if baselineOnly {
        if originalStaleSeconds != 0 { failures.append("\(name): baseline stale labels") }
        if name != "future-two-hours", originalCallbacks > currentCallbacks { failures.append("\(name): baseline redundant callbacks") }
    }
    rows.append(["scenario": name, "duration_seconds": duration, "before_callbacks": originalCallbacks, "after_callbacks": currentCallbacks, "before_stale_seconds": originalStaleSeconds, "after_stale_seconds": currentStaleSeconds, "before_at_30_seconds_to_event": sampleBefore, "after_at_30_seconds_to_event": sampleAfter])
}

var seed: UInt64 = 0x20261024
var formattingChecks = 0
for _ in 0..<20000 {
    seed = seed &* 6364136223846793005 &+ 1
    let delta = Int32(Int64(seed % 200_000_001) - 100_000_000)
    let date = now - delta
    if originalLabel(date, now) != currentLabel(date, Int64(now)) {
        failures.append("formatter changed at delta \(delta)")
    }
    formattingChecks += 1
}

let result: [String: Any] = ["rows": rows, "formatting_checks": formattingChecks, "row_wiring_probes": 2, "failures": failures, "baseline_expected_to_fail": baselineOnly, "scope": "Deterministic one-second clock replay; real old selector/formatter and new planner/formatter; row initializer slices use recording adapters; no full AppKit rows, Dispatch wakeups, CPU or energy measurement"]
print(String(data: try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
exit(failures.isEmpty ? 0 : 1)
