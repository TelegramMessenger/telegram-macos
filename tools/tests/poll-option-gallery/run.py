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


def function(text, signature):
    if text.count(signature) != 1:
        raise SystemExit(2)
    start = text.index(signature)
    depth = 0
    for index in range(text.index('{', start), len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise SystemExit(2)


def section(text, start, end):
    if text.count(start) != 1:
        raise SystemExit(2)
    begin = text.index(start)
    if end not in text[begin:]:
        raise SystemExit(2)
    return text[begin:text.index(end, begin)]


def require(text, *parts):
    for part in parts:
        if part not in text:
            raise SystemExit(2)


poll = code('packages/ChatUI/Sources/ChatUI/ChatPollItem.swift')
viewer = code('packages/GalleryUI/Sources/GalleryUI/GalleryViewer.swift')
pager = code('packages/GalleryUI/Sources/GalleryUI/GalleryPageController.swift')
photo = code('packages/GalleryUI/Sources/GalleryUI/MGalleryPhotoItem.swift')
utils = code('packages/TelegramMediaUtils/Sources/TelegramMediaUtils/CoreMediaResourceExtensions.swift')

eligible = function(poll, 'private func isPollGalleryMedia(_ media: Media) -> Bool').replace('private func', 'func', 1)
info = function(poll, 'public struct GalleryMediaInfo').replace('public ', '')
medias = function(poll, 'public func allGalleryMedias() -> GalleryMediaInfo').replace('public func', 'func', 1)
option = function(poll, 'private func openGalleryForOption(').replace('private func', 'func', 1)
opener = function(poll, 'private func openOptionMedia(')
require(opener,
        '} else if file.isGraphicFile || file.isVideoFile {\n                openGalleryForOption(',
        '} else if media is TelegramMediaImage {\n            openGalleryForOption(')
require(function(poll, 'public func openGallery(firstIndex: Int)'), 'medias: info.medias', 'firstIndex: firstIndex')

init = function(viewer, 'fileprivate convenience init(context: any AccountContextProtocol, media:[Media], firstIndex: Int')
factory = section(init, 'var inserted: [(Int, MGalleryItem)] = []', '_ = self.pager.merge(with: UpdateTransition(deleted: [], inserted: inserted, updated: []))')
require(init, 'self.pager.set(index: firstIndex, animated: false)')
require(function(viewer, 'public func showGalleryMedia('), 'GalleryViewer(context: context, media: medias, firstIndex: firstIndex')

insert = section(pager, 'let searchItem:(AnyHashable, [MGalleryItem])->MGalleryItem? = { stableId, items in', 'for (idx,item) in transition.updated {')
clamps = [line.strip() for line in function(pager, 'public func set(index:Int, animated:Bool)').splitlines() if line.strip().startswith('let index = ')]
if len(clamps) != 1:
    raise SystemExit(2)

case = section(photo, 'case .media(let media, _, _):', 'default:\n            fatalError("photo item not supported entry type")')
case = case.replace('media as! TelegramMediaImage', 'forceImage(media)')

graphic = function(utils, 'var isGraphicFile:Bool {')
video = function(utils, 'var isVideoFile:Bool {')

fixture = Path(__file__).with_name('PollOptionGalleryTests.swift.in').read_text()
for marker, text in [
    ('__IS_POLL_GALLERY_MEDIA__', eligible),
    ('__GALLERY_MEDIA_INFO__', info),
    ('__ALL_GALLERY_MEDIAS__', medias),
    ('__OPEN_GALLERY_FOR_OPTION__', option),
    ('__GALLERY_FACTORY__', factory),
    ('__PAGER_INSERT__', insert),
    ('__PAGER_CLAMP__', clamps[0]),
    ('__PHOTO_MEDIA_CASE__', case),
    ('__IS_GRAPHIC_FILE__', graphic),
    ('__IS_VIDEO_FILE__', video),
]:
    if fixture.count(marker) != 1:
        raise SystemExit(2)
    fixture = fixture.replace(marker, text)

with tempfile.TemporaryDirectory(prefix='poll-option-gallery-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
