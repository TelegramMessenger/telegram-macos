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


def source(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def block(text, start):
    begin = text.find(start)
    if begin < 0:
        print(f'not found: {start}')
        raise SystemExit(2)
    depth = 0
    for index in range(text.index('{', begin), len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index + 1], text[begin + len(start):index]
    print(f'no end: {start}')
    raise SystemExit(2)


complete_header = 'private func completeRights(_ flags: TelegramChatBannedRightsFlags) -> TelegramChatBannedRightsFlags {'

modal = source('packages/PeerModerationUI/Sources/PeerModerationUI/RestictedModalViewController.swift')
page = source('packages/PeerModerationUI/Sources/PeerModerationUI/ChannelPermissionsController.swift')
utils = source('packages/TelegramUtils/Sources/TelegramUtils/GroupPermissions.swift')

complete, _ = block(modal, complete_header)
page_complete, _ = block(page, complete_header)
state, _ = block(modal, 'private struct RestrictedControllerState: Equatable {')
_, toggle = block(modal, 'toggleRight: { rights, value in')
_, ok = block(modal, 'okClicked = {')
dependencies, _ = block(page, 'public func groupPermissionDependencies(_ right: TelegramChatBannedRightsFlags) -> TelegramChatBannedRightsFlags {')
media, _ = block(utils, 'public func banSendMediaSubList() -> [(TelegramChatBannedRightsFlags, TelegramChannelPermission)] {')
lists, _ = block(utils, 'public func allGroupPermissionList(peer: Peer) -> [(TelegramChatBannedRightsFlags, TelegramChannelPermission)] {')

names = []
for name in re.findall(r'\(\.(\w+), \.\w+\)', lists + media):
    if name not in names:
        names.append(name)

fixture = (Path(__file__).with_name('ExceptionsInlineBotsTests.swift.in').read_text()
           .replace('__STATE__', state.replace('private ', '', 1))
           .replace('__COMPLETE__', complete.replace('private ', '', 1))
           .replace('__PAGE_COMPLETE__', page_complete.replace('private func completeRights(', 'func pageCompleteRights(', 1))
           .replace('__MEDIA_LIST__', media.replace('public ', '', 1))
           .replace('__DEPENDENCIES__', dependencies.replace('public ', '', 1))
           .replace('__ROWS__', ', '.join(f'("{name}", .{name})' for name in names))
           .replace('__TOGGLE__', toggle)
           .replace('__OK__', ok))

with tempfile.TemporaryDirectory(prefix='exceptions-inline-bots-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
