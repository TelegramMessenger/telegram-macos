import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
def read(relative):
    path = Path('/tmp/calendar-before-' + Path(relative).name) if args.baseline else root / relative
    return path.read_text()
def block(s, marker):
    a = s.index(marker)
    b = s.index('{', a) + 1
    depth = 1
    while depth:
        depth += (s[b] == '{') - (s[b] == '}')
        b += 1
    return s[a:b]
s = read('packages/CalendarUI/Sources/CalendarUI/CalendarMonthController.swift')
controller = read('packages/CalendarUI/Sources/CalendarUI/CalendarController.swift')
extras = read('packages/TelegramUtils/Sources/TelegramUtils/CoreTypeExtras.swift')
fixture = Path(__file__).with_name('CalendarDatesTests.swift').read_text()
fixture = fixture.replace('__MONTH__', block(s, 'public final class CalendarMonthStruct').replace('public ', ''))
fixture = fixture.replace('__HIDE__', block(controller, '    open func hideYear()').replace('open ', '').replace('Calendar.current', 'systemCalendar'))
fixture = fixture.replace('__SELECT_YEAR__', block(controller, '    private func selectYear(').replace('private ', '') if '    private func selectYear(' in controller else '')
fixture = fixture.replace('__BIRTHDAY__', block(extras, 'public extension Date {').replace('public ', '').replace('Calendar.current', 'systemCalendar'))
birthday = read('packages/TelegramUtils/Sources/TelegramUtils/TelegramBirthday.swift')
formatter = read('packages/TelegramUtils/Sources/TelegramUtils/PresenceStrings.swift')
chat = read('packages/ChatUI/Sources/ChatUI/ChatServiceItem.swift')
fixture = fixture.replace('__BIRTHDAY_HELPERS__', block(birthday, 'public extension TelegramBirthday {').replace('public ', '').replace('Calendar.current', 'systemCalendar').replace('Date()', 'testNow'))
fixture = fixture.replace('__FORMAT__', block(formatter, 'public func formatBirthdayToString(').replace('public ', '').replace('Calendar.current', 'systemCalendar').replace('Locale.current', 'testLocale'))
a = chat.index('    public func openSuggestBirthday(')
a = chat.index('        let context = self.context', a) + len('        let context = self.context')
b = chat.index('            guard let controller', a)
fixture = fixture.replace('__SUGGESTED__', chat[a:b].replace('Calendar.current', 'systemCalendar') + '\nreturn date\n}\nreturn nil')

for key, marker in [('__NEXT__', '    open var isNextEnabled:'), ('__PREV__', '    open var isPrevEnabled:')]:
    fixture = fixture.replace(key, block(s, marker).replace('open ', '').replace('Date()', 'now'))
a = s.index('        let formatter:DateFormatter');b = s.index('        let barView = ', a)
fixture = fixture.replace('__LABEL__', s[a:b] + '\nreturn (monthString, yearString)')
handler = block(s, 'items.append(.init("—", handler:')
fixture = fixture.replace('__NO_YEAR__', handler.split('handler: ', 1)[1])
if 'public func isDayEnabled(' in s:
    enabled = 'return month.isDayEnabled(day, now: now)'
else:
    a = s.index('                var skipDay: Bool = false');b = s.index('                let dayTimeinterval', a)
    first = s[a:b]
    a = s.index('                if let limitedBy = month.limitedBy', b);b = s.index('                if !skipDay', a)
    enabled = ('let current = day\n' + first + s[a:b] + '\nreturn !skipDay').replace('Date()', 'now')
fixture = fixture.replace('__ENABLED__', enabled)
with tempfile.TemporaryDirectory(prefix='calendar-dates-') as directory:
    directory = Path(directory)
    (directory / 'CalendarUtils').mkdir()
    for name in ['CalendarUtils.h', 'CalendarUtils.m']:
        (directory / 'CalendarUtils' / name).write_text(read('packages/CalendarUtils/Sources/CalendarUtils/' + name))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "CalendarDates", platforms: [.macOS(.v10_13)], targets: [.target(name: "CalendarUtils", path: "CalendarUtils", publicHeadersPath: "."), .testTarget(name: "CalendarDatesTests", dependencies: ["CalendarUtils"], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/CalendarDatesTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
