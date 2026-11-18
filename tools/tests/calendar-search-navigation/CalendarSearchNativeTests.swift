import Cocoa

private var assertions = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() {
        fatalError(message)
    }
}

private func calendar(_ zone: String = "UTC", locale: String = "en_US") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.locale = Locale(identifier: locale)
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar, hour: Int = 0) -> Date {
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func selection(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> CalendarSearchSelection {
    return CalendarSearchSelection(current: date(year, month, day, in: calendar), minDay: date(2013, 1, 1, in: calendar), maxDay: date(2026, 11, 17, in: calendar), calendar: calendar)
}

private func testDayNavigation() {
    let calendar = calendar()
    var state = selection(2024, 2, 28, in: calendar)
    expect(state.move(days: 1), "right arrow selects next day")
    expect(state.selected == date(2024, 2, 29, in: calendar), "leap day is selectable")
    expect(state.focused == state.selected, "keyboard focus follows selection")
    expect(state.move(days: 1), "right arrow crosses month")
    expect(state.selected == date(2024, 3, 1, in: calendar), "leap day transitions to March")
    expect(state.month == date(2024, 3, 1, in: calendar), "visible month follows selected day")
    expect(state.move(days: -1), "left arrow crosses month")
    expect(state.selected == date(2024, 2, 29, in: calendar), "left arrow restores leap day")
    state = selection(2023, 2, 28, in: calendar)
    state.move(days: 1)
    expect(state.selected == date(2023, 3, 1, in: calendar), "non-leap February has no day29")
    state = selection(2023, 12, 31, in: calendar)
    state.move(days: 1)
    expect(state.selected == date(2024, 1, 1, in: calendar), "right arrow crosses year")
    state.move(days: -1)
    expect(state.selected == date(2023, 12, 31, in: calendar), "left arrow crosses year")
    state = selection(2024, 3, 4, in: calendar)
    state.move(days: -1)
    expect(state.selected == date(2024, 3, 3, in: calendar), "left arrow wraps Monday to Sunday")
    state.move(days: 1)
    expect(state.selected == date(2024, 3, 4, in: calendar), "right arrow wraps Sunday to Monday")
    state.move(days: -7)
    expect(state.selected == date(2024, 2, 26, in: calendar), "up arrow crosses month by one week")
    state.move(days: 7)
    expect(state.selected == date(2024, 3, 4, in: calendar), "down arrow restores same weekday")
    state = selection(2023, 12, 29, in: calendar)
    state.move(days: 7)
    expect(state.selected == date(2024, 1, 5, in: calendar), "week movement crosses year")
    print("PASS day/month/year/leap/week navigation")
}

private func testLimitsAndBrowsing() {
    let calendar = calendar()
    var state = selection(2012, 1, 1, in: calendar)
    expect(state.selected == state.minDay, "initial lower date clamps")
    state.move(days: -1)
    expect(state.selected == state.minDay, "left cannot pass earliest day")
    state.move(days: -7)
    expect(state.selected == state.minDay, "up cannot pass earliest day")
    expect(!state.moveMonth(-1), "month shortcut cannot pass earliest month")
    expect(!state.browse(date(2012, 12, 1, in: calendar)), "pointer month cannot pass earliest month")
    state = selection(2030, 1, 1, in: calendar)
    expect(state.selected == state.maxDay, "initial upper date clamps")
    state.move(days: 1)
    state.move(days: 7)
    expect(state.selected == state.maxDay, "right/down cannot pass latest day")
    expect(!state.moveMonth(1), "month shortcut cannot pass latest month")
    let previous = state.selected
    expect(!state.select(date(2026, 11, 18, in: calendar)), "disabled future day rejects activation")
    expect(state.selected == previous, "rejected activation does not change selection")
    state = selection(2024, 1, 31, in: calendar)
    expect(state.browse(date(2024, 2, 1, in: calendar)), "pointer browse can change month")
    expect(state.selected == date(2024, 1, 31, in: calendar), "pointer browsing preserves existing selection")
    expect(state.focused == date(2024, 2, 29, in: calendar), "browsing clamps focus to short month")
    expect(state.select(state.focused), "Return selects focused day in browsed month")
    expect(state.selected == date(2024, 2, 29, in: calendar), "Return no longer accepts stale selection")
    state = selection(2023, 1, 31, in: calendar)
    state.moveMonth(1)
    expect(state.selected == date(2023, 2, 28, in: calendar), "month shortcut clamps non-leap February")
    state = selection(2024, 12, 31, in: calendar)
    state.moveMonth(1)
    expect(state.selected == date(2025, 1, 31, in: calendar), "month shortcut crosses year")
    state = selection(2026, 10, 31, in: calendar)
    state.moveMonth(1)
    expect(state.selected == date(2026, 11, 17, in: calendar), "month shortcut clamps to current day")
    state.focus(date(2026, 11, 30, in: calendar))
    expect(state.focused == date(2026, 11, 30, in: calendar), "AX can inspect disabled date")
    expect(!state.select(state.focused), "Return rejects disabled AX focus")
    expect(state.selected == date(2026, 11, 17, in: calendar), "disabled focus does not alter confirmed day")
    state.focus(date(2026, 10, 1, in: calendar))
    expect(state.focused == date(2026, 11, 30, in: calendar), "stale off-month AX focus is ignored")
    state.move(days: -7)
    expect(state.selected == state.maxDay, "keyboard navigation recovers from disabled focused date")
    var partial = CalendarSearchSelection(current: date(2024, 1, 1, in: calendar), minDay: date(2024, 1, 15, in: calendar), maxDay: date(2024, 2, 10, in: calendar), calendar: calendar)
    expect(partial.selected == date(2024, 1, 15, in: calendar), "partial min month clamps current")
    partial.move(days: -7)
    expect(partial.selected == partial.minDay, "partial min month clamps week")
    partial.moveMonth(1)
    expect(partial.selected == partial.maxDay, "partial max month clamps month shortcut")
    print("PASS disabled limits, pointer browsing, focused Return, month shortcuts")
}

private func testTimeZonesAndLocales() {
    for zone in ["UTC", "America/Los_Angeles", "Europe/Berlin", "Pacific/Auckland", "Asia/Kathmandu"] {
        let calendar = calendar(zone)
        for (year, month, day) in [(2024, 3, 9), (2024, 3, 10), (2024, 11, 2), (2024, 11, 3), (2024, 3, 30), (2024, 10, 26)] {
            var state = selection(year, month, day, in: calendar)
            let previous = state.selected
            state.move(days: 1)
            expect(calendar.component(.hour, from: state.selected) == 0, "day movement stays at local midnight in \(zone)")
            expect(calendar.dateComponents([.day], from: previous, to: state.selected).day == 1, "day movement uses calendar rather than86400 seconds in \(zone)")
            state.move(days: -1)
            expect(state.selected == previous, "DST transition reverses in \(zone)")
            state.move(days: 7)
            expect(calendar.component(.weekday, from: state.selected) == calendar.component(.weekday, from: previous), "week keeps weekday in \(zone)")
        }
        let state = CalendarSearchSelection(current: date(2024, 5, 12, in: calendar, hour: 17), minDay: date(2013, 1, 1, in: calendar), maxDay: date(2026, 11, 17, in: calendar), calendar: calendar)
        expect(state.selected == date(2024, 5, 12, in: calendar), "initial date normalizes to local midnight")
    }
    for locale in ["en_US", "en_GB", "ru_RU", "ar", "he", "fa", "ja_JP"] {
        let calendar = calendar(locale: locale)
        var state = selection(2024, 2, 29, in: calendar)
        state.move(days: 1)
        expect(state.selected == date(2024, 3, 1, in: calendar), "existing Gregorian grid movement is locale-independent: \(locale)")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = ""
        formatter.dateStyle = .full
        let label = formatter.string(from: state.selected)
        expect(!label.isEmpty, "localized full AX date exists for \(locale)")
        print("AX date \(locale): \(label)")
    }
    print("PASS timezone/DST and localized LTR/RTL Gregorian dates")
}

private func testNativeAccessibility() {
    let calendar = calendar()
    let date = date(2024, 2, 29, in: calendar)
    var view: NSView? = NSView(frame: NSRect(x: 0, y: 0, width: 266, height: 228))
    weak var weakView = view
    let element = CalendarSearchDayAccessibilityElement(date: date, label: "Thursday, February 29, 2024", view: view!)
    let protocolElement: NSAccessibilityProtocol = element
    expect(protocolElement.isAccessibilityElement(), "native AX element is exposed")
    expect(protocolElement.accessibilityRole() == .radioButton, "native AX role communicates exclusive day selection")
    expect(protocolElement.accessibilityLabel() == "Thursday, February 29, 2024", "full date label is exposed via AppKit protocol")
    expect(element.date == date, "AX stable date identity")
    expect((protocolElement.accessibilityParent() as? NSView) === view, "AX parent is correct native view")
    expect(protocolElement.accessibilityFrame() == .zero, "detached AX element has no stale screen frame")
    expect(element.responds(to: #selector(NSAccessibilityProtocol.accessibilityPerformPress)), "actual Objective-C AX press selector exists")
    expect(element.responds(to: #selector(NSAccessibilityProtocol.setAccessibilityFocused(_:))), "actual Objective-C AX focus setter exists")
    var presses = 0
    element.press = { presses += 1; return true }
    element.setAccessibilityEnabled(true)
    element.setAccessibilitySelected(false)
    expect(protocolElement.isAccessibilityEnabled(), "enabled date semantic")
    expect(!protocolElement.isAccessibilitySelected(), "unselected date semantic")
    expect((protocolElement.accessibilityValue() as? NSNumber)?.boolValue == false, "radio value tracks unselected semantic")
    expect(protocolElement.accessibilityPerformPress(), "AX press invokes date activation")
    expect(presses == 1, "AX press invokes one callback independent of mouse")
    element.setAccessibilitySelected(true)
    expect(protocolElement.isAccessibilitySelected(), "selected date semantic")
    expect((protocolElement.accessibilityValue() as? NSNumber)?.boolValue == true, "radio value tracks selected semantic")
    element.setAccessibilityEnabled(false)
    expect(!protocolElement.isAccessibilityEnabled(), "disabled date semantic")
    expect(!protocolElement.accessibilityPerformPress(), "disabled AX press rejected")
    expect(presses == 1, "disabled AX press never invokes callback")
    var focused = false
    var focusCount = 0
    element.focus = { focused = true; focusCount += 1 }
    element.isFocused = { focused }
    protocolElement.setAccessibilityFocused(true)
    expect(protocolElement.isAccessibilityFocused(), "native AX focus is observable")
    expect(focusCount == 1, "native AX focus updates keyboard date once")
    protocolElement.setAccessibilityFocused(false)
    expect(focusCount == 1, "losing AX focus does not select a date")
    focused = false
    expect(!protocolElement.isAccessibilityFocused(), "native AX focus follows responder state")
    element.setAccessibilityEnabled(true)
    element.press = nil
    expect(!protocolElement.accessibilityPerformPress(), "missing activation reports false")
    element.press = { presses += 1; return true }
    view = nil
    expect(weakView == nil, "AX element does not retain view")
    expect(protocolElement.accessibilityParent() == nil, "detached parent is nil")
    expect(!protocolElement.accessibilityPerformPress(), "stale detached AX activation rejected")
    expect(presses == 1, "stale AX activation does not call selection")
    print("PASS actual AppKit AX role/date/value/selected/enabled/focus/press/lifetime contracts")
}

@main
private struct CalendarSearchNativeTests {
    static func main() {
        testDayNavigation()
        testLimitsAndBrowsing()
        testTimeZonesAndLocales()
        testNativeAccessibility()
        print("PASS \(assertions) native assertions; no NSApplication, NSWindow, Telegram launch, GUI events, or account access")
    }
}
