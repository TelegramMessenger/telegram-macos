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


def code(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def body(text, label):
    start = text.index(label) + len(label)
    depth = 1
    for index in range(start, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[start:index]
    raise SystemExit(f'no end for {label}')


rows = code('packages/ChatListUI/Sources/ChatListUI/ForumSidebarRowsView.swift')
delete_case = rows[rows.index('case .delete:', rows.index('private func applySelection(')):]
sidebar = body(delete_case, 'successHandler: { [weak self] _ in')

leave = code('packages/ChatUI/Sources/ChatUI/LeaveChatActions.swift')
dialog_function = leave[leave.index('private func showStandardLeaveDialog('):]
dialog = body(dialog_function, '|> map { result, location -> Bool in')

fixture = (Path(__file__).with_name('SidebarDeleteOpenTopicTests.swift.in').read_text()
           .replace('__SIDEBAR__', sidebar)
           .replace('__DIALOG__', dialog))

with tempfile.TemporaryDirectory(prefix='sidebar-delete-open-topic-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
