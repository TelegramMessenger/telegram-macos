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


def function(marker):
    start = find(source, marker)
    return source[start:block_end(source, start, '{', '}') + 1].replace('private func', 'func')


def closure(label):
    start = find(source, label) + len(label)
    return source[start:block_end(source, start, '{', '}') + 1]


def shown(marker):
    start = find(source, 'let selectedType: CurrentChannelType', find(source, marker, find(source, 'private func entries(')))
    return source[start:find(source, 'entries.append(.typeHeader(', start)]


done_start = find(source, 'if let peer = state.peer?.peer {', find(source, 'strongSelf.doneButton?.set(handler:'))
enabled_start = find(source, 'var doneEnabled = true')

fixture = (Path(__file__).with_name('BasicGroupPrivateTests.swift.in').read_text()
           .replace('__EFFECTIVE__', function('private func effectiveChannelType('))
           .replace('__UPDATED__', function('private func updatedAddressName('))
           .replace('__SHOWN_CHANNEL__', shown('if let peer = state.peer?.peer as? TelegramChannel {'))
           .replace('__SHOWN_GROUP__', shown('} else if let peer = state.peer?.peer as? TelegramGroup {'))
           .replace('__DONE_ENABLED__', source[enabled_start:find(source, 'let entries = entries(', enabled_start)])
           .replace('__UPDATE_TYPE__', closure('onlyUsername: self.onlyUsername, updateCurrentType: '))
           .replace('__UPDATE_LINK__', closure('}, updatePublicLinkText: '))
           .replace('__DONE__', source[done_start:block_end(source, done_start, '{', '}') + 1]))

with tempfile.TemporaryDirectory(prefix='basic-group-private-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    sources = sorted(str(file) for file in signalkit.glob('*.swift'))
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), *sources, str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
