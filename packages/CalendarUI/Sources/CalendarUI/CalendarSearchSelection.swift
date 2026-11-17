import Foundation

struct CalendarSearchSelection {
    let calendar: Calendar
    let minDay: Date
    let maxDay: Date
    private(set) var month: Date
    private(set) var selected: Date
    private(set) var focused: Date

    init(current: Date, minDay: Date, maxDay: Date, calendar: Calendar) {
        self.calendar = calendar
        self.minDay = calendar.startOfDay(for: minDay)
        self.maxDay = calendar.startOfDay(for: maxDay)
        let day = min(max(calendar.startOfDay(for: current), self.minDay), self.maxDay)
        self.month = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
        self.selected = day
        self.focused = day
    }

    func isEnabled(_ date: Date) -> Bool {
        return date >= minDay && date <= maxDay
    }

    mutating func focus(_ date: Date) {
        guard calendar.isDate(date, equalTo: month, toGranularity: .month) else {
            return
        }
        focused = calendar.startOfDay(for: date)
    }

    @discardableResult
    mutating func select(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard isEnabled(day) else {
            return false
        }
        selected = day
        focused = day
        month = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
        return true
    }

    @discardableResult
    mutating func browse(_ date: Date) -> Bool {
        guard let target = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let days = calendar.range(of: .day, in: .month, for: target),
              let lastDay = calendar.date(byAdding: .day, value: days.count - 1, to: target),
              target <= maxDay, lastDay >= minDay else {
            return false
        }
        let day = min(calendar.component(.day, from: focused), days.count)
        guard let focused = calendar.date(byAdding: .day, value: day - 1, to: target) else {
            return false
        }
        month = target
        self.focused = min(max(focused, minDay), maxDay)
        return true
    }

    @discardableResult
    mutating func move(days: Int) -> Bool {
        guard let target = calendar.date(byAdding: .day, value: days, to: focused) else {
            return false
        }
        return select(min(max(target, minDay), maxDay))
    }

    @discardableResult
    mutating func moveMonth(_ direction: Int) -> Bool {
        guard let target = calendar.date(byAdding: .month, value: direction, to: month), browse(target) else {
            return false
        }
        return select(focused)
    }
}
