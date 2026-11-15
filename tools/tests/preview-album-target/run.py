import argparse
from contextlib import nullcontext
from pathlib import Path
import os
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description='Test preview album targets using exact production Swift snippets.')
parser.add_argument('--source-revision', help='Read production sources at a git revision, e.g. c64a3ea7 for the negative control.')
parser.add_argument('--output-dir', type=Path)
parser.add_argument('--extract-only', action='store_true')
parser.add_argument('--scenario', choices=['original', 'stale', 'missing', 'boundary-forward', 'boundary-backward'])
args = parser.parse_args()
environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
if args.extract_only and args.output_dir is None:
    parser.error('--extract-only requires --output-dir')


def read(path):
    if args.source_revision:
        return subprocess.check_output(['git', '-C', str(root), 'show', args.source_revision + ':' + path], text=True, env=environment)
    source = root / path
    if source.is_file():
        return source.read_text()
    return subprocess.check_output(['git', '-C', str(root), 'show', 'HEAD:' + path], text=True, env=environment)


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


controller = read('packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift')
row = read('packages/PreviewSenderUI/Sources/PreviewSenderUI/MediaGroupPreviewRowItem.swift')
layout = read('packages/ChatUI/Sources/ChatUI/GroupedLayout.swift')
extensions = read('packages/TGUIKit/Sources/Extensions.swift')
fixture = Path(__file__).with_name('AlbumTargetTests.swift.in').read_text()
individual_spoilers = 'spoilerOverrides' in controller
parts = {
    '__SPOILER_ARGUMENTS__': ', toggleSpoiler: { _ in }, canSpoiler: true' if individual_spoilers else '',
    '__ARGUMENTS__': block(controller, 'private final class SenderPreviewArguments'),
    '__ENTRY_CASES__': section(controller, '    case section(Int)\n    case media(index:', '    var stableId: PreviewEntryId'),
    '__ENTRIES__': block(controller, 'private func previewMediaEntries('),
    '__GROUP_ITEM__': section(controller, '        case let .mediaGroup(_, _, urls, messages, ' + ('spoilers' if individual_spoilers else 'isSpoiler') + ', payAmount, renderingPreviews):', '\n        }\n    }'),
    '__ROW_ITEM__': section(row, 'class MediaGroupPreviewRowItem:', '    override func makeSize(') + '}\n',
    '__CONTROL__': section(row, '                let url = item.urls[i]\n                self.editControl.set(edit:' if '                let url = item.urls[i]\n                self.editControl.set(edit:' in row else '                self.editControl.set(edit:', '                self.editControl.setFrameOrigin('),
    '__DROP__': section(row, '        if let index = draggingIndex, let newIndex = item.layout.moveItemIfNeeded(', '            set(item: item, animated: true)') + '        }',
    '__RENDERING__': section(row, 'updateMediaPreviewRendering(', ', in: contents[i], animated: animated)').removeprefix('updateMediaPreviewRendering('),
    '__LAYOUT_MOVE__': block(layout, '    public func moveItemIfNeeded('),
    '__ARRAY_MOVE__': block(extensions, '    mutating func move(at oldIndex:'),
    '__CHUNKS__': block(extensions, '    func chunks('),
    '__DELETE__': section(controller, '            self.urls.removeAll(where:', '\n'),
    '__GLOBAL_MOVE__': block(controller, 'reorder: { [weak self] from, to in').removeprefix('reorder: '),
    '__TABLE_REORDER__': section(controller, 'self.genericView.tableView.resortController = TableResortController(', '\n            } else {'),
}
for marker, source in parts.items():
    assert fixture.count(marker) == 1, marker
    fixture = fixture.replace(marker, source)
assert not re.search(r'__[A-Z_]+__', fixture)

if args.output_dir:
    try:
        args.output_dir.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        parser.error('--output-dir must not already exist')
    directory_context = nullcontext(args.output_dir.resolve())
else:
    directory_context = tempfile.TemporaryDirectory(prefix='preview-album-target-')
with directory_context as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    print('Production sources: ' + (args.source_revision or 'working tree'), flush=True)
    print('Extracted fixture: ' + str(main), flush=True)
    if not args.extract_only:
        binary = directory / 'tests'
        compile_result = subprocess.run(['xcrun', 'swiftc', '-j1', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], capture_output=True, text=True, env=environment)
        compile_log = compile_result.stdout + compile_result.stderr
        (directory / 'compile.log').write_text(compile_log)
        print(compile_log, end='', flush=True)
        if compile_result.returncode != 0:
            raise SystemExit(compile_result.returncode)
        scenarios = [args.scenario] if args.scenario else ['original', 'stale', 'missing', 'boundary-forward', 'boundary-backward']
        failed = False
        for scenario in scenarios:
            result = subprocess.run([str(binary), scenario], capture_output=True, text=True, env=environment)
            output = result.stdout + result.stderr
            (directory / (scenario + '.log')).write_text(output)
            print(scenario + ' exit: ' + str(result.returncode), flush=True)
            print(output, end='', flush=True)
            failed |= result.returncode != 0
        raise SystemExit(1 if failed else 0)
