from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
reference = HERE / 'Reference'
provenance = json.loads((reference / 'provenance.json').read_text())
for file, expected in provenance['fragments_sha256'].items():
    assert hashlib.sha256((reference / file).read_bytes()).hexdigest() == expected, file
catalog = json.loads((reference / 'EnglishRelativeStrings.json').read_text())
labels = 'struct Labels {\n'
for name in ['SecondsAgo', 'MinutesAgo', 'HoursAgo', 'DaysAgo', 'InSeconds', 'InMinutes', 'InHours', 'InDays']:
    value = json.dumps(catalog[f'FormattedDate.{name}_other'])
    labels += f'func formattedDate{name}Other(_ count: Int) -> String {{ String(format: {value}, count) }}\n'
labels += '}\nfunc strings() -> Labels { Labels() }\n'
source = '''import Foundation
enum Format { case relative, full }
enum EntityType { case FormattedDate(Format, Int32) }
struct Entity { let type: EntityType }
final class TextEntitiesMessageAttribute { let entities: [Entity]; init(_ dates: [Int32]) { entities = dates.map { Entity(type: .FormattedDate(.relative, $0)) } } }
struct Message { let attributes: [Any] }
struct Context { let timestamp: Int32 }
func originalPeriod(_ dates: [Int32], _ now: Int32) -> Double? {
    let context = Context(timestamp: now)
    let message = Message(attributes: [TextEntitiesMessageAttribute(dates)])
'''
source += (reference / 'OriginalInterval.swift.txt').read_text() + '\nreturn relativeDateUpdatePeriod\n}\n'
source += labels
source += 'func originalLabel(_ date: Int32, _ currentTimestamp: Int32) -> String {\n' + (reference / 'OriginalRelativeFormat.swift.txt').read_text() + '\n}\n'
current = (ROOT / 'packages/TelegramUtils/Sources/TelegramUtils/DateTimeEntityFormat.swift').read_text()
relative = current.split('case .relative:', 1)[1].split('case let .full(', 1)[0]
source += 'func currentLabel(_ date: Int32, _ currentTimestamp: Int64) -> String {\n' + relative + '\n}\n'
def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    level, cursor = 1, opening + 1
    while level:
        level += (text[cursor] == '{') - (text[cursor] == '}')
        cursor += 1
    return text[start:cursor]

listing = (ROOT / 'packages/ChatListUI/Sources/ChatListUI/ChatListRowItem.swift').read_text()
chat = (ROOT / 'packages/ChatUI/Sources/ChatUI/ChatMessageItem.swift').read_text()
listing_setup = block(listing, 'private func setupRelativeDateTimer(')
start = chat.index('var relativeDateTimestamps: [Int32] = []')
chat_setup = chat[start:chat.index('\n            return', start)]
source += '''final class RelativeDateUpdateTimer {
    let timestamps: [Int32]
    let update: () -> Void
    init?(timestamps: [Int32], relativeTo timestamp: TimeInterval, update: @escaping () -> Void) {
        guard !timestamps.isEmpty else { return nil }
        self.timestamps = timestamps
        self.update = update
    }
    func invalidate() {}
}
'''
for name, setup in [('List', listing_setup), ('Chat', 'private func setupRelativeDateTimer(relativeTo timestamp: TimeInterval) { let message = messages.first!\nlet relativeDateReferenceTimestamp = timestamp\n' + chat_setup + '\n}')]:
    source += f'''final class {name}RowProbe {{
        let messages: [Message]
        var relativeDateTimer: RelativeDateUpdateTimer?
        var updateCount = 0
        init(_ dates: [Int32]) {{ messages = [Message(attributes: [TextEntitiesMessageAttribute(dates)])] }}
        init(attributes: [Any]) {{ messages = [Message(attributes: attributes)] }}
        func prepare() {{ setupRelativeDateTimer(relativeTo: 1_780_000_000) }}
        func updateRelativeDates() {{ updateCount += 1 }}
        {setup}
    }}
    func check{name}RowWiring() {{
        let dates: [Int32] = [1_779_999_990, 1_779_992_800]
        var row: {name}RowProbe? = {name}RowProbe(dates)
        weak var weakRow = row
        row!.prepare()
        let recorded = row!.relativeDateTimer!
        precondition(recorded.timestamps == dates)
        recorded.update()
        precondition(row!.updateCount == 1)
        row = nil
        precondition(weakRow == nil)
        recorded.update()
        let empty = {name}RowProbe([])
        empty.prepare()
        precondition(empty.relativeDateTimer == nil)
    }}
    check{name}RowWiring()
'''
source += (HERE / 'Comparison.swift').read_text()
with tempfile.TemporaryDirectory(prefix='telegram-relative-date-comparison-') as directory:
    work = Path(directory)
    main = work / 'main.swift'
    main.write_text(source)
    binary = work / 'compare'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-O', str(ROOT / 'packages/TelegramUtils/Sources/TelegramUtils/RelativeDateTimeEntity.swift'), str(main), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)] + (['--baseline'] if args.baseline else []), text=True, stdout=subprocess.PIPE)
    print(result.stdout)
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        name = 'baseline.json' if args.baseline else 'comparison.json'
        (args.output / name).write_text(result.stdout)
    raise SystemExit(result.returncode)
