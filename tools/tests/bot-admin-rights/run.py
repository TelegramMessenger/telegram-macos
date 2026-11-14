import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root

text = (root / 'packages/ChannelAdminUI/Sources/ChannelAdminUI/ChannelBotAdminController.swift').read_text()
source = '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def inside(text, start, end):
    begin = text.index(start) + len(start)
    return text[begin:text.index(end, begin)]


def closure(text, label):
    start = text.find(label + ': {')
    if start < 0:
        return None
    begin = start + len(label) + 3
    depth = 1
    for index in range(begin, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index]
    return None


orders = inside(source, 'let rightsOrder: [RightsItem]', 'for (i, rights) in rightsOrder.enumerated()')
names = sorted(set(re.findall(r'\.direct\(\.(\w+)\)', orders)))
loop = source[source.index('for (i, rights) in rightsOrder.enumerated()'):]
direct_row = inside(loop, 'case let .direct(right):', 'case let .sub(type, subRights):')
action = closure(direct_row, 'action') or ''
switch_action = closure(direct_row, 'switchAction')
toggle = inside(source, '}, toggleRight: ', ', toggleIsOptionExpanded:')
defaults = inside(source, '?.chatAdminRights ?? [', ']')
add = inside(source, 'controller.validateData', 'close = {')
add_sends_state = 'let rights = stateValue.with { $0.rights }' in add and 'adminRights: .init(rights: rights)' in add

fixture = (Path(__file__).with_name('BotAdminRightsTests.swift.in').read_text()
           .replace('__DEFAULTS__', defaults)
           .replace('__TOGGLE__', toggle)
           .replace('__ACTION__', action)
           .replace('__SWITCH_ACTION__', action if switch_action is None else switch_action)
           .replace('__ROWS__', ', '.join(f'("{name}", .{name})' for name in names))
           .replace('__ROW_CLICK_AT_ONCE__', 'false' if switch_action is None else 'true')
           .replace('__ADD_SENDS_STATE__', 'true' if add_sends_state else 'false'))

with tempfile.TemporaryDirectory(prefix='bot-admin-rights-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
