import Foundation

enum RelativeDateTimeEntityUnit: Equatable {
    case seconds
    case minutes
    case hours
    case days
}

struct RelativeDateTimeEntityValue: Equatable {
    let isPast: Bool
    let unit: RelativeDateTimeEntityUnit
    let value: Int

    init(date: Int32, timestamp: Int64) {
        let difference = timestamp - Int64(date)
        self.isPast = difference > 0
        let magnitude = abs(difference)
        if magnitude < 60 {
            self.unit = .seconds
            self.value = Int(magnitude)
        } else if magnitude <= 60 * 60 {
            self.unit = .minutes
            self.value = Int(round(Float(magnitude) / 60))
        } else if magnitude <= 24 * 60 * 60 {
            self.unit = .hours
            self.value = Int(round(Float(magnitude) / (60 * 60)))
        } else {
            self.unit = .days
            self.value = Int(round(Float(magnitude) / (24 * 60 * 60)))
        }
    }
}

public func nextRelativeDateTimeEntityUpdate(timestamps: [Int32], now: TimeInterval) -> TimeInterval? {
    guard !timestamps.isEmpty, now.isFinite, abs(now) < Double(Int64.max / 4) else {
        return nil
    }
    let currentTimestamp = Int64(floor(now))
    var nextTimestamp: Int64?
    for date in timestamps {
        let currentValue = RelativeDateTimeEntityValue(date: date, timestamp: currentTimestamp)
        var lower: Int64 = 0
        var upper: Int64 = 1
        while RelativeDateTimeEntityValue(date: date, timestamp: currentTimestamp + upper) == currentValue {
            lower = upper
            upper *= 2
        }
        while upper - lower > 1 {
            let middle = lower + (upper - lower) / 2
            if RelativeDateTimeEntityValue(date: date, timestamp: currentTimestamp + middle) == currentValue {
                lower = middle
            } else {
                upper = middle
            }
        }
        let candidate = currentTimestamp + upper
        nextTimestamp = min(nextTimestamp ?? candidate, candidate)
    }
    return nextTimestamp.map(TimeInterval.init)
}
