import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ReplyModel.swift')
parser.add_argument('--scratch-path', type=Path)
args = parser.parse_args()


def section(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError(f'Expected unique source boundaries: {start!r}, {end!r}')
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


reply = section(args.source.read_text(), 'public class ReplyModel:', 'public class StoryReplyModel:')
selection = section(reply, '    public override var updatedMedia:', '    private func updateImageIfNeeded()')
geometry = section(reply, '            var imageDimensions:', '                let imageHost = view.makeAccessoryImage()')
for use in (
    'cachedMedia(media: updatedMedia, arguments: arguments, scale: System.backingScale)',
    'cacheMedia(result, media: updatedMedia, arguments: arguments, scale: System.backingScale)',
    'imageHost.setAccessoryArguments(arguments)',
):
    if reply.count(use) != 1:
        raise ValueError(f'Expected shared render/cache arguments: {use}')
arguments = (root / 'packages/TGUIKit/Sources/TransformImageArguments.swift').read_text()
extensions = (root / 'packages/TGUIKit/Sources/Extensions.swift').read_text()
aspect = section(extensions, '    func aspectFilled(_ size: CGSize)', '    func fittedToWidthOrSmaller(')
insets = section(extensions, 'extension NSEdgeInsets : @retroactive Equatable {', '\n\npublic func arc4random64()')
drawing = (root / 'packages/TGUIKit/Sources/DrawingContext.swift').read_text()
bitmap = section(drawing, 'public let deviceColorSpace:', 'private final class DisplayColorConversion')
bitmap += section(drawing, 'public enum DrawingContextBltMode {', 'private extension NSImage {')
bitmap += section(drawing, 'public func getSharedDevideGraphicsContextSettings(', 'public enum ParsingError:')
corners = (root / 'packages/TelegramMediaUtils/Sources/TelegramMediaUtils/ImageCorners.swift').read_text()
corners = '\n'.join(line for line in corners.splitlines() if line not in ('import TGUIKit', 'import TelegramMedia'))
fixture = Path(__file__).with_name('RoundVideoReplyThumbnailTests.swift.in').read_text()
for marker, text in [('__SELECTION__', selection), ('__GEOMETRY__', geometry), ('__ASPECT__', aspect)]:
    if fixture.count(marker) != 1:
        raise ValueError(f'Expected one fixture marker: {marker}')
    fixture = fixture.replace(marker, text)

with tempfile.TemporaryDirectory(prefix='round-video-reply-thumbnail-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RoundVideoReplyThumbnail", platforms: [.macOS(.v10_15)], targets: [.testTarget(name: "RoundVideoReplyThumbnailTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/TransformImageArguments.swift').write_text(arguments + '\n' + insets)
    (directory / 'Tests/DrawingContext.swift').write_text('import Cocoa\n' + bitmap)
    (directory / 'Tests/ImageCorners.swift').write_text(corners)
    (directory / 'Tests/RoundVideoReplyThumbnailTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--jobs', '2']
    if args.scratch_path:
        command += ['--scratch-path', str(args.scratch_path.resolve())]
    raise SystemExit(subprocess.run(command).returncode)
