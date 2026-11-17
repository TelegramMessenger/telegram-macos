import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

assert sys.flags.isolated
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--baseline', default='861aefaaada199e0ddf93547437cd64c81181eb5')
args = parser.parse_args()
WORK = Path(__file__).resolve().parents[3]
ROOT = args.output.resolve()
assert not ROOT.is_relative_to(WORK)
ROOT.mkdir(parents=True, exist_ok=False)
PATH = 'packages/CalendarUI/Sources/CalendarUI/CalendarSearchController.swift'
BASELINE = args.baseline
base = subprocess.check_output(['git', '-C', str(WORK), 'show', f'{BASELINE}:{PATH}'], text=True)
current = (WORK / PATH).read_text()
(ROOT / 'baseline-CalendarSearchController.swift').write_text(base)


def block(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def body(source, marker):
    text = block(source, marker)
    return text[text.index('{') + 1:-1]


checks = {}
for marker in ['private var mouseIndex:', 'private func click(double:', 'private func updateHover()', 'override func mouseMoved(', 'override func mouseEntered(', 'override func mouseExited(', 'private func step(', 'public override func escapeKeyAction()']:
    checks[marker] = block(base, marker) == block(current, marker)
    assert checks[marker], marker
for key, days in [('LeftArrow', -1), ('RightArrow', 1), ('UpArrow', -7), ('DownArrow', 7)]:
    handler = f'return self?.navigate(days: {days}, modifiers: event.modifierFlags) ?? .rejected\n        }}, with: self, for: .{key}, priority: .modal)'
    checks[f'{key} wiring'] = handler in current
    assert checks[f'{key} wiring']
for expression in [
    'modifiers.intersection([.command, .control, .option, .shift])',
    'if modifiers == .option, abs(days) == 1',
    'changed = selection.moveMonth(days)',
    'changed = selection.move(days: days)',
    'return .invokeNext',
    'if selection.select(selection.focused)',
    'self.onDay?(date)',
    'self.userInteractionEnabled, self.dayEnabled(date)',
    'previous?.isAccessibilityDecorative = true',
    'previous?.userInteractionEnabled = false',
    'window?.removeAllHandlers(for: self)',
]:
    checks[expression] = expression in current
    assert checks[expression], expression
checks['baseline lacks day AX children'] = 'accessibilityChildren()' not in base and 'NSAccessibilityElement' not in base
checks['baseline has only horizontal month shortcuts'] = 'for: .UpArrow' not in base and 'for: .DownArrow' not in base
assert checks['baseline lacks day AX children']
assert checks['baseline has only horizontal month shortcuts']

keyresult_path = 'packages/TGUIKit/Sources/Window.swift'
window = subprocess.check_output(['git', '-C', str(WORK), 'show', f'{BASELINE}:{keyresult_path}'], text=True)
keyresult = block(window, 'public enum KeyHandlerResult')
helpers = '\n\n'.join(block(base, marker).replace('private ', '', 1) for marker in ['private func monthStart(', 'private func monthOffset(', 'private func monthDays(', 'private func monthRows(', 'private func dayAfter('])
base_methods = '\n\n'.join(block(base, marker).replace('public override ', '').replace('private ', '') for marker in ['private var isPrevEnabled:', 'private var isNextEnabled:', 'private func step(', 'public override func returnKeyAction()', 'public override func escapeKeyAction()', 'private func done()'])
new_methods = '\n\n'.join(block(current, marker).replace('public override ', '').replace('private ', '') for marker in ['public override func returnKeyAction()', 'public override func escapeKeyAction()', 'private func done()'])
mouse_body = body(base, 'private var mouseIndex:')
mouse_math = mouse_body[mouse_body.index('        let cell ='):]
mouse_math = mouse_math.replace('CalendarSearchMetrics.cell', 'CGFloat(38)')
frame_math = body(current, 'private func dayFrame(at index:').replace('CalendarSearchMetrics.cell', 'CGFloat(38)')
nav_body = body(current, 'private func navigate(days:')
nav_body = nav_body[:nav_body.index('        if changed {')]
nav_body = nav_body.replace('        let previousMonth = month\n', '')

output = '''import Cocoa

private let searchCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

''' + keyresult + '\n\n' + helpers + '''

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    return searchCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

private var assertions = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() { fatalError(message) }
}

private final class BaselineProjection {
    let minDay = day(2013, 1, 1)
    let maxDay = day(2026, 11, 17)
    var month = day(2024, 2, 1)
    var selected = day(2024, 2, 28)
    var closeCount = 0
    var dates: [Date] = []
    func close() { closeCount += 1 }
    func onSelect(_ date: Date) { dates.append(date) }
    func showMonth(_ target: Date, direction: Int, animated: Bool) { self.month = target }

''' + base_methods + '''
}

private final class CurrentCompletionProjection {
    var selection = CalendarSearchSelection(current: day(2024, 2, 28), minDay: day(2013, 1, 1), maxDay: day(2026, 11, 17), calendar: searchCalendar)
    var closeCount = 0
    var dates: [Date] = []
    func close() { closeCount += 1 }
    func onSelect(_ date: Date) { dates.append(date) }

''' + new_methods + '''

    func route(days: Int, modifiers: NSEvent.ModifierFlags) -> KeyHandlerResult {
''' + nav_body + '''
        return changed ? .invoked : .rejected
    }
}

private func pointerIndex(_ point: NSPoint, offset: Int, days: Int) -> Int? {
''' + mouse_math + '''
}

private func dayFrame(at index: Int, offset: Int) -> NSRect {
''' + frame_math + '''
}

@main
private struct CalendarSearchRegressionTests {
    static func main() {
        let baseline = BaselineProjection()
        baseline.step(1)
        expect(baseline.month == day(2024, 3, 1), "baseline right arrow moves whole month")
        expect(baseline.selected == day(2024, 2, 28), "baseline negative: right arrow never selects next day")
        expect(baseline.returnKeyAction() == .invoked, "baseline Return consumes event")
        expect(baseline.dates == [day(2024, 2, 28)], "baseline negative: Return emits stale date")
        expect(baseline.dates != [day(2024, 2, 29)], "baseline cannot reach expected next day")
        print("NEGATIVE CONTROL reproduced baseline right-arrow/month and stale-Return defect")

        let current = CurrentCompletionProjection()
        expect(current.route(days: 1, modifiers: []) == .invoked, "plain right routes to day movement")
        expect(current.returnKeyAction() == .invoked, "new Return consumes event")
        expect(current.dates == [day(2024, 2, 29)], "new exact Return/done methods emit focused next day")
        expect(current.closeCount == 1, "successful Return closes exactly once")
        let browsed = CurrentCompletionProjection()
        browsed.selection.browse(day(2024, 3, 1))
        _ = browsed.returnKeyAction()
        expect(browsed.dates == [day(2024, 3, 28)], "Return uses focused visible month after pointer month browse")
        let disabled = CurrentCompletionProjection()
        disabled.selection.browse(day(2026, 11, 1))
        disabled.selection.focus(day(2026, 11, 30))
        expect(disabled.returnKeyAction() == .invoked, "disabled Return remains inside modal")
        expect(disabled.closeCount == 0 && disabled.dates.isEmpty, "disabled Return neither closes nor emits old selected date")
        expect(disabled.escapeKeyAction() == .invoked, "Escape consumes modal key")
        expect(disabled.closeCount == 1 && disabled.dates.isEmpty, "Escape closes without selection")
        let oldEscape = BaselineProjection()
        _ = oldEscape.escapeKeyAction()
        expect(oldEscape.closeCount == 1 && oldEscape.dates.isEmpty, "Escape baseline parity")

        let routed = CurrentCompletionProjection()
        for flags: NSEvent.ModifierFlags in [[.control, .option], [.command], [.shift], [.option, .shift], [.command, .option]] {
            let previous = routed.selection.selected
            expect(routed.route(days: 1, modifiers: flags) == .invokeNext, "modified accessibility/system arrow falls through")
            expect(routed.selection.selected == previous, "modified accessibility/system arrow leaves date unchanged")
        }
        expect(routed.route(days: -1, modifiers: [.option]) == .invoked, "Option-left preserves month shortcut")
        expect(routed.selection.selected == day(2024, 1, 28), "Option-left selects same day previous month")
        expect(routed.route(days: 1, modifiers: [.option]) == .invoked, "Option-right preserves month shortcut")
        expect(routed.selection.selected == day(2024, 2, 28), "Option-right returns same day next month")
        expect(routed.route(days: -7, modifiers: [.option]) == .invokeNext, "Option-up is not silently consumed")
        expect(routed.route(days: 1, modifiers: [.numericPad, .function]) == .invoked, "hardware arrow flags do not block navigation")
        expect(routed.selection.selected == day(2024, 2, 29), "hardware-arrow next day is correct")
        expect(routed.route(days: -7, modifiers: []) == .invoked, "up routes to previous week")
        expect(routed.selection.selected == day(2024, 2, 22), "previous week date")
        expect(routed.route(days: 7, modifiers: []) == .invoked, "down routes to next week")
        expect(routed.selection.selected == day(2024, 2, 29), "next week date")
        print("PASS exact Return/Escape bodies and modifier-routing slice; rendering/close effects replaced only by explicit recording sinks")

        for year in 2013 ... 2026 {
            for month in 1 ... 12 {
                let start = day(year, month, 1)
                let offset = monthOffset(start)
                let days = monthDays(start)
                expect((4 ... 6).contains(monthRows(start)), "Gregorian month row count")
                for index in 0 ..< days {
                    let frame = dayFrame(at: index, offset: offset)
                    expect(pointerIndex(NSPoint(x: frame.midX, y: frame.midY), offset: offset, days: days) == index, "AX/drawing rect center matches unchanged mouse arithmetic")
                    expect(dayAfter(start, index) == day(year, month, index + 1), "AX day date matches baseline day arithmetic")
                    let baselinePreview = NSRect(x: CGFloat((offset + index) % 7) * 38 + 3, y: CGFloat((offset + index) / 7) * 38 + 3, width: 32, height: 32)
                    expect(frame.insetBy(dx: 3, dy: 3) == baselinePreview, "preview geometry unchanged")
                }
                for position in 0 ..< (monthRows(start) * 7) {
                    let point = NSPoint(x: CGFloat(position % 7) * 38 + 19, y: CGFloat(position / 7) * 38 + 19)
                    let index = pointerIndex(point, offset: offset, days: days)
                    if position < offset || position >= offset + days {
                        expect(index == nil, "leading/trailing blank dates remain unclickable")
                    }
                }
                expect(pointerIndex(NSPoint(x: -1, y: 0), offset: offset, days: days) == nil, "negative x rejected")
                expect(pointerIndex(NSPoint(x: 0, y: -1), offset: offset, days: days) == nil, "negative y rejected")
                expect(pointerIndex(NSPoint(x: 266, y: 0), offset: offset, days: days) == nil, "right edge rejected")
            }
        }
        print("PASS mouse/AX frame parity for168 months, blank cells, day-preview rectangles")
        print("PASS \\(assertions) regression assertions; no UI interaction or Telegram runtime")
    }
}
'''
(ROOT / 'CalendarSearchRegressionTests.swift').write_text(output)
(ROOT / 'regression-extraction.json').write_text(json.dumps({
    'baseline_revision': BASELINE,
    'baseline_sha256': hashlib.sha256(base.encode()).hexdigest(),
    'current_sha256': hashlib.sha256(current.encode()).hexdigest(),
    'static_checks': checks,
    'method_extraction': 'Return/Escape/done and baseline step+limits verbatim bodies; access modifiers relaxed for local projection. Exact new modifier-routing prefix, original mouse-index arithmetic, baseline date helpers and new shared dayFrame arithmetic. Actual KeyHandlerResult enum from baseline TGUIKit source, not a module stub.',
    'seams': 'Recording close/onSelect and month renderer (showMonth assignment) replace side effects only. Pointer event handlers asserted byte-identical, not dispatched against NSWindow. Full real-module source typecheck separately validates UI integration.',
    'not_exercised': ['live VoiceOver', 'Telegram window event routing', 'NSWindow screen-frame conversion', 'visual focus ring', 'AppMenu display', 'animation', 'manual acceptance']
}, indent=2) + '\n')
print('generated baseline/current regression projections; static checks:', len(checks))
