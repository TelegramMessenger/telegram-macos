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

text = (root / 'packages/ChannelSettingsUI/Sources/ChannelSettingsUI/ChannelReactionsController.swift').read_text()
source = '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def matching(text, start, opening, closing):
    depth = 1
    for index in range(start, len(text)):
        if text[index] == opening:
            depth += 1
        elif text[index] == closing:
            depth -= 1
            if depth == 0:
                return text[start:index]
    raise SystemExit(f'no closing {closing}')


def after(text, label, opening, closing):
    start = text.index(label) + len(label)
    return matching(text, start, opening, closing)


state = 'struct State : Equatable {' + after(source, 'private struct State : Equatable {', '{', '}') + '}'
opening = 'let textInteractions = TextView_Interactions()'
initial_end = source.index('\n', source.index('let initialState = State('))
initial = source[source.index(opening):initial_end]
toggle = after(source, 'toggleEnabled: {', '{', '}')
saved = after(source[source.index('controller.validateData'):], 'reactionSettings: .init(', '(', ')')

fixture = (Path(__file__).with_name('ChannelReactionsOffTests.swift.in').read_text()
           .replace('__STATE__', state)
           .replace('__INITIAL__', initial)
           .replace('__TOGGLE__', toggle)
           .replace('__SAVED__', saved))

with tempfile.TemporaryDirectory(prefix='channel-reactions-off-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
