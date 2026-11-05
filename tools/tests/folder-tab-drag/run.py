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


def read(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


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


def body(text, start):
    found = block(text, start)
    return found[found.index('{') + 1:-1]


try:
    reveal = read('packages/ChatListUI/Sources/ChatListUI/ChatListRevealItem.swift')
    segment = read('packages/TGUIKit/Sources/ScrollableSegmentView.swift')
    extensions = read('packages/TGUIKit/Sources/Extensions.swift')

    set_item = body(reveal, reveal.index('public override func set(item: TableRowItem, animated: Bool = false)'))
    range_start = set_item.index('let range: NSRange')
    install = set_item[range_start:set_item.index('segmentView.resortHandler = {', range_start)] + block(set_item, set_item.index('segmentView.resortHandler = {', range_start))

    counter = set_item.index('var index: Int = 0')
    loop = block(set_item, set_item.index('for tab in item.tabs {', counter))
    tabs_in_list_order = re.search(r'ScrollableSegmentItem\(title: \w+, index: index,', loop) is not None and loop.count('index += 1') == 1

    starting = body(segment, segment.index('private func startDraggingIfNeeded('))
    can_drag = re.search(r'if let range = self\.resortRange, let window = self\.window \{\s*if (.+?) \{', starting).group(1)
    live = body(segment, segment.index('private func applyLiveResort()'))
    clamp = re.search(r'^\s*(bestIndex = .*resortRange.*)$', live, re.M).group(1)
    resort = body(segment, segment.index('private func applyResort()'))
    apply = body(resort, resort.index('layoutItems(animated: true, completion: { [weak self] in'))

    move = block(extensions, extensions.index('mutating func move(at oldIndex: Int, to newIndex: Int)'))
    range_extension = block(extensions, extensions.index('public extension NSRange {'))
    range_max = block(range_extension, re.search(r'var max\s*:\s*Int', range_extension).start())
    index_in = block(range_extension, range_extension.index('func indexIn(_ index: Int) -> Bool'))
    peers_list = read('packages/ChatListUI/Sources/ChatListUI/PeersListController.swift')
    chat_list = read('packages/ChatListUI/Sources/ChatListUI/ChatListController.swift')
    preferences = read('packages/InAppSettings/Sources/InAppSettings/ChatListFilterPreferences.swift')
    folders_signal = body(preferences, preferences.index('public func chatListFilterPreferences('))
except (OSError, ValueError, AttributeError) as error:
    print(f'the source no longer has the code this test reads, update the test: {error!r}')
    raise SystemExit(2)

bar_gets_filter_data = re.search(r'foldersItem = \.init\([^\n]*\btabs: state\.filterData\.tabs\b', peers_list) is not None
tab_updates = re.findall(r'\.withUpdatedTabs\(([^()]*)\)', chat_list)
filter_data_is_stored_list = 'filters.list' in tab_updates and all(value in ('filters.list', '[]') for value in tab_updates)
list_is_engine_list = 'engine.peers.updatedChatListFilters()' in folders_signal and 'ChatListFolders(list: $0,' in folders_signal
tabs_are_stored_list = bar_gets_filter_data and filter_data_is_stored_list and list_is_engine_list

fixture = (Path(__file__).with_name('FolderTabDragTests.swift.in').read_text()
           .replace('__MOVE__', move)
           .replace('__RANGE_MAX__', range_max)
           .replace('__INDEX_IN__', index_in)
           .replace('__CAN_DRAG__', can_drag)
           .replace('__CLAMP__', clamp)
           .replace('__APPLY__', apply)
           .replace('__INSTALL__', install)
           .replace('__TABS_IN_LIST_ORDER__', 'true' if tabs_in_list_order else 'false')
           .replace('__TABS_ARE_STORED_LIST__', 'true' if tabs_are_stored_list else 'false'))

with tempfile.TemporaryDirectory(prefix='folder-tab-drag-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    result = subprocess.run([str(binary)])
    if result.returncode < 0:
        print(f'FAILED: the tests crashed with signal {-result.returncode}')
        raise SystemExit(1)
    raise SystemExit(result.returncode)
