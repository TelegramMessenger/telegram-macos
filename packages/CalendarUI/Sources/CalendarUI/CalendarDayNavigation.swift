import Foundation

struct CalendarDayNavigation {
    let calendar: Calendar
    let bounds: ClosedRange<Date>?

    init(current: Date, now: Date, onlyFuture: Bool, limitedBy: Date?, lowYear: Int, yearHidden: Bool, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        let minimum: Date?
        var maximum: Date?
        if yearHidden && !onlyFuture {
            let year = calendar.component(.year, from: current)
            minimum = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            maximum = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
        } else {
            minimum = onlyFuture ? today : calendar.date(from: DateComponents(year: lowYear, month: 1, day: 1))
            maximum = onlyFuture ? calendar.date(byAdding: .year, value: 1, to: today) : today
        }
        if let limitedBy, let value = maximum {
            maximum = min(value, calendar.startOfDay(for: limitedBy))
        }
        if let minimum, let maximum, minimum <= maximum {
            bounds = minimum ... maximum
        } else {
            bounds = nil
        }
    }

    func isEnabled(_ date: Date) -> Bool {
        return bounds?.contains(calendar.startOfDay(for: date)) == true
    }

    func day(in month: Date, preferred: Int) -> Date? {
        guard let bounds,
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let days = calendar.range(of: .day, in: .month, for: first),
              let last = calendar.date(byAdding: .day, value: days.count - 1, to: first),
              first <= bounds.upperBound, last >= bounds.lowerBound,
              let date = calendar.date(byAdding: .day, value: min(max(preferred, 1), days.count) - 1, to: first) else {
            return nil
        }
        return min(max(date, bounds.lowerBound), bounds.upperBound)
    }

    func moving(_ date: Date, days: Int) -> Date? {
        guard let bounds, let result = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) else {
            return nil
        }
        return min(max(result, bounds.lowerBound), bounds.upperBound)
    }

    func movingMonth(_ date: Date, direction: Int) -> Date? {
        guard let month = calendar.date(byAdding: .month, value: direction, to: date) else {
            return nil
        }
        return day(in: month, preferred: calendar.component(.day, from: date))
    }
}
