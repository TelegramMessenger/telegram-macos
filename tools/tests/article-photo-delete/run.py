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
    if not (root / path).is_file():
        raise SystemExit(2)
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def block(text, anchor, start=None):
    if anchor not in text:
        raise SystemExit(2)
    begin = text.index(anchor)
    if start is not None:
        if start not in text[:begin]:
            raise SystemExit(2)
        begin = text.rindex(start, 0, begin)
    depth = 0
    for index in range(text.index('{', text.index(anchor)), len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index + 1]
    raise SystemExit(2)


def function(text, signature):
    if signature not in text:
        return ''
    return block(text, signature).replace('public func', 'func', 1)


expansion_source = code('packages/MessageUtils/Sources/MessageUtils/SharedMediaExpansion.swift')
base = re.search(r'private let richSharedMediaNamespaceBase: Int32 = [^\n]+', expansion_source)
if base is None:
    raise SystemExit(2)
expansion = '\n\n'.join([base.group(0).replace('private let', 'let', 1),
                         function(expansion_source, 'public func isExpandedSharedMediaMessageId('),
                         function(expansion_source, 'public func expandSharedMediaMessages(')])

viewer = block(code('packages/GalleryUI/Sources/GalleryUI/GalleryViewer.swift'),
               'if canDeleteMessage(message, account: context.account, chatLocation: chatLocation, mode: chatMode)')
grid = block(code('packages/PeerMediaUI/Sources/PeerMediaUI/PeerPhotosMonthItem.swift'),
             'if canDeleteMessage(message, account: context.account, chatLocation: self.chatInteraction.chatLocation, mode: .history)')
row = block(code('packages/PeerMediaUI/Sources/PeerMediaUI/PeerMediaRowContent.swift'),
            'canDeleteMessage(message, account: interface.interactionContext.account, chatLocation: interface.chatLocation, mode: .history)', start='if ')
controller = code('packages/PeerInfoUI/Sources/PeerInfoUI/PeerMediaController.swift')
selection = block(controller, 'if let interactions = self?.interactions {', start='var canDelete:Bool =')
handler = block(controller, 'interactions.deleteMessages = { [weak self] messageIds, _ in')
handler_init = re.search(r'var canDelete:Bool = ([^\n]+)', handler)
handler_condition = re.search(r'if (!canDeleteMessage\(message, account: context\.account, chatLocation: strongSelf\.interactions\.chatLocation, mode: \.history\)[^\n]*) \{', handler)
if handler_init is None or handler_condition is None:
    raise SystemExit(2)

fixture = (Path(__file__).with_name('ArticlePhotoDeleteTests.swift.in').read_text()
           .replace('__EXPANSION__', expansion)
           .replace('__VIEWER_DELETE__', viewer)
           .replace('__GRID_DELETE__', grid)
           .replace('__ROW_DELETE__', row)
           .replace('__SELECTION__', selection)
           .replace('__HANDLER_INIT__', handler_init.group(1).strip())
           .replace('__HANDLER_CONDITION__', handler_condition.group(1)))

with tempfile.TemporaryDirectory(prefix='article-photo-delete-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
