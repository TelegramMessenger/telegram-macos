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

text = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
source = '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def block(text, start):
    begin = text.index('{', start)
    depth = 0
    for index in range(begin, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError('unbalanced braces')


pinned = source.index('let getPinned:')
history = '.HistoryView(view, _, _, _):'
case = source.index(history, pinned) + len(history)
loop = source.index('for i in 0 ..< view.entries.count', case)
selection = source[case:loop] + block(source, loop)
rule = block(selection, selection.index('let isInLocation'))
old_selection = selection.replace(rule, 'let isInLocation: (Message) -> Bool = { message in\n    return oldRule(chatLocation, message)\n}')

fixture = (Path(__file__).with_name('PinnedRepliesBarTests.swift.in').read_text()
           .replace('__SELECTION__', selection)
           .replace('__OLD_SELECTION__', old_selection))

with tempfile.TemporaryDirectory(prefix='pinned-replies-bar-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
