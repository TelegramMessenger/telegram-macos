import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
sources = args.root / 'packages/SidebarUI/Sources/SidebarUI'


def read(name):
    text = (sources / name).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines() if not line.startswith('import '))


def inside(text, start, end):
    begin = text.index(start) + len(start)
    return text[begin:text.index(end, begin)]


def block(text, start):
    begin = text.index(start)
    depth = 0
    for index in range(text.index('{', begin), len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index + 1]
    raise ValueError(start)


behavior = read('SidebarFolderBehavior.swift')
controller = read('ChatListFilterController.swift')
first_row = controller.index('excludePeers.insert(arguments.environment.categoryPeer(')
rows_begin = controller.rindex('if data.', 0, first_row)
rows = controller[rows_begin:controller.index('var sectionId:Int32 = 0', rows_begin)]

fixture = (Path(__file__).with_name('FolderExcludeUncheckTests.swift.in').read_text()
           .replace('__CATEGORIES__', read('FolderCategory.swift'))
           .replace('__EXCLUDING__', block(behavior, 'func sidebarFilterExcluding('))
           .replace('__SELECTION__', block(controller, 'private struct FolderSelection'))
           .replace('__ADD_EXCLUDE__', inside(controller, '}, addExclude: {', '}, removeIncluded:'))
           .replace('__REMOVE_EXCLUDED__', inside(controller, '}, removeExcluded: { peerId in', '}, openInfo:'))
           .replace('__ROWS__', rows))

with tempfile.TemporaryDirectory(prefix='folder-exclude-uncheck-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
