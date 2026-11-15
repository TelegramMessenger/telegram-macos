import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--signalkit', type=Path)
args = parser.parse_args()
root = args.root
signalkit = args.signalkit or root / 'submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit/Source'

path = root / 'packages/ChannelSettingsUI/Sources/ChannelSettingsUI/ChannelVisibilityController.swift'
if not path.is_file() or not signalkit.is_dir():
    raise SystemExit(2)
source = '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in path.read_text().splitlines())


def block_end(text, start, opening, closing):
    depth = 0
    for index in range(text.index(opening, start), len(text)):
        if text[index] == opening:
            depth += 1
        elif text[index] == closing:
            depth -= 1
            if depth == 0:
                return index
    raise SystemExit(2)


def find(text, marker, start=0):
    index = text.find(marker, start)
    if index < 0:
        raise SystemExit(2)
    return index


def closure_body(text, label):
    start = text.find(label + ': {')
    if start < 0:
        return None
    return text[start + len(label) + 3:block_end(text, start, '{', '}')]


row_start = find(source, 'case let .allowForward(', find(source, 'func item(_ arguments: Arguments'))
row_case = source[row_start:find(source, ':', row_start) + 1]
row = source[row_start:find(source, 'case let .forwardInfo(', row_start)]
value_start = find(row, 'type: .switchable(') + len('type: .switchable')
row_value = row[value_start + 1:block_end(row, value_start, '(', ')')]
row_action = closure_body(row, 'action')
switch_action = closure_body(row, 'switchAction')
if row_action is None:
    raise SystemExit(2)

toggle_start = find(source, '}, toggleForwarding: ') + len('}, toggleForwarding: ')
toggle = source[toggle_start:block_end(source, toggle_start, '{', '}') + 1]

entries_start = find(source, 'let allowed: Bool')
entries_marker = 'entries.append(.forwardInfo('
entries_end = block_end(source, find(source, entries_marker, entries_start), '(', ')') + 1
forward_entries = source[entries_start:entries_end]

done_start = find(source, 'if let updatedCopyProtection = ')
done = source[done_start:block_end(source, done_start, '{', '}') + 1]

address_start = find(source, 'if let updatedAddressNameValue = updatedAddressNameValue {')
with_link_start = find(source, 'let others = combineLatest(', address_start)
set_marker = 'self?.updateAddressNameDisposable.set('
set_start = find(source, set_marker, with_link_start)
with_link_end = block_end(source, set_start + len(set_marker) - 1, '(', ')') + 1
with_link = source[with_link_start:with_link_end]
else_start = find(source, '} else {', with_link_end)
without_link = source[else_start + len('} else {'):block_end(source, else_start + 1, '{', '}')]

fixture = (Path(__file__).with_name('RestrictSavingSwitchTests.swift.in').read_text()
           .replace('__ROW_CASE__', row_case)
           .replace('__ROW_VALUE__', row_value)
           .replace('__ROW_ACTION__', row_action)
           .replace('__SWITCH_ACTION__', 'nil' if switch_action is None else '{' + switch_action + '}')
           .replace('__TOGGLE__', toggle)
           .replace('__ENTRIES__', forward_entries)
           .replace('__DONE__', done)
           .replace('__WITH_LINK__', with_link)
           .replace('__WITHOUT_LINK__', without_link))

with tempfile.TemporaryDirectory(prefix='restrict-saving-switch-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    sources = sorted(str(file) for file in signalkit.glob('*.swift'))
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), *sources, str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
