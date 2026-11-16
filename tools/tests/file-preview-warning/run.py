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


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def code(text):
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def read(path):
    return code((root / path).read_text())


preview = read('packages/GalleryUI/Sources/GalleryUI/QuickLookPreview.swift')
chat = read('packages/ChatUI/Sources/ChatUI/ChatFileContentView.swift')
hooks = [section(read(f'Telegram-Mac/packages-integration/hooks/{name}'), 'showQuickLookPreview: {', '\n    }') for name in ('ChatMediaUIHooksInstall.swift', 'PeerMediaUIHooksInstall.swift', 'DataUsageHooksInstall.swift')]
callers = {
    'packages/PeerMediaUI/Sources/PeerMediaUI/PeerMediaFileRowContent.swift': 'PeerMediaUIHooks.shared.showQuickLookPreview(',
    'packages/ChatUI/Sources/ChatUI/ChatPollItem.swift': 'ChatMediaUIHooks.shared.showQuickLookPreview(',
    'packages/DataUsageUI/Sources/DataUsageUI/StorageUsage_Block_MediaList.swift': 'DataUsageHooks.shared.showQuickLookPreview(',
}
routed = all(call in read(path) for path, call in callers.items()) and all('QuickLookPreview.current.show(' in hook and 'NSWorkspace' not in hook for hook in hooks)
mime_types = {}
for line in (root / 'Resources/data/mime-types.txt').read_text(errors='replace').splitlines():
    parts = line.split(':')
    if len(parts) == 2:
        mime_types[parts[1]] = parts[0]

show_start = '    public func show(context: any AccountContextProtocol'
if 'private func present(' in preview:
    show = section(preview, show_start, '    private func present(')
    warning = section(preview, 'private let previewWarningExtensions', 'private class QuickLookPreviewItem')
    present = section(preview, '    private func present(', '    @objc func openPanelInRunLoop')
    keeps_preview = present.split('{', 1)[1].strip().startswith('self.context = context') and all(line in present for line in ('self.context = context', 'self.media = media', 'self.delegate = delegate', 'self.stableId = stableId', 'panel = QLPreviewPanel.shared()', 'copyToDownloads(', 'NSWorkspace.shared.openFile('))
else:
    show = show_start + ', with media:Media, stableId:ChatHistoryEntryId?,  _ delegate:InteractionContentViewProtocol? = nil) {\n        self.present(context: context, with: media, stableId: stableId, delegate)\n    }\n'
    warning = ''
    keeps_preview = False

fixture = (Path(__file__).with_name('FilePreviewWarningTests.swift.in').read_text()
           .replace('__WARNING__', warning)
           .replace('__SHOW__', show)
           .replace('__OPEN__', section(chat, '    public override func open() {', '    public override func cancelFetching').replace('public override func', 'func'))
           .replace('__MIME_TYPES__', ', '.join(f'"{key}": "{value}"' for key, value in sorted(mime_types.items())))
           .replace('__ROUTED__', 'true' if routed else 'false')
           .replace('__KEEPS_PREVIEW__', 'true' if keeps_preview else 'false'))

with tempfile.TemporaryDirectory(prefix='file-preview-warning-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
