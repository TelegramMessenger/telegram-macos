import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
postbox_candidates = [
    root / 'submodules/telegram-ios/submodules/Postbox/Sources/ChatListView.swift',
    root.parent / 'telegram-ios-focus-source/submodules/Postbox/Sources/ChatListView.swift',
]
parser = argparse.ArgumentParser()
parser.add_argument('--postbox-source', type=Path, default=next((path for path in postbox_candidates if path.is_file()), postbox_candidates[0]))
args = parser.parse_args()

def without_imports(source):
    return '\n'.join(line for line in source.splitlines() if not line.startswith('import '))

def declaration(source, name):
    start = source.index(name)
    opening = source.index('{', start)
    depth = 1
    for position in range(opening + 1, len(source)):
        if source[position] == '{':
            depth += 1
        elif source[position] == '}':
            depth -= 1
            if depth == 0:
                return source[start:position + 1]
    raise ValueError(f'Unclosed Swift declaration: {name}')

postbox = args.postbox_source.read_text()
peer_group = without_imports(args.postbox_source.with_name('PeerGroup.swift').read_text())
predicate = declaration(postbox, 'public struct ChatListFilterPredicate {')
composition = without_imports((root / 'packages/ChatListUI/Sources/ChatListUI/ChatListFocusPredicate.swift').read_text())
fixture = Path(__file__).with_name('FocusChatListTests.swift').read_text().replace('__POSTBOX_PREDICATE__', predicate).replace('__FOCUS_COMPOSITION__', composition).replace('__POSTBOX_PEER_GROUP_ID__', peer_group)
core = sorted((root / 'packages/FocusFilterCore/Sources/FocusFilterCore').glob('*.swift'))
with tempfile.TemporaryDirectory(prefix='telegram-focus-chat-list-') as directory:
    directory = Path(directory)
    source = directory / 'Tests.swift'
    source.write_text(fixture)
    executable = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(directory / 'ModuleCache'), *(str(path) for path in core), str(source), '-o', str(executable)], check=True)
    raise SystemExit(subprocess.run([str(executable)]).returncode)
