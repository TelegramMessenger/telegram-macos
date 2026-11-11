from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile


def declaration(source, marker):
    if source.count(marker) != 1:
        raise ValueError(f'Expected one declaration: {marker}')
    start = source.index(marker)
    masked = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', lambda match: ' ' * len(match.group()), source, flags=re.S)
    opening = masked.index('{', start)
    depth = 1
    for index in range(opening + 1, len(masked)):
        depth += (masked[index] == '{') - (masked[index] == '}')
        if depth == 0:
            return source[start:index + 1]
    raise ValueError(marker)


parser = argparse.ArgumentParser(description='Test extracted header status/update/layout code with real TGUIKit TextView and AppKit.')
parser.add_argument('--source-revision', help='Read header and status sources at this revision for a behavioral negative control.')
parser.add_argument('--signal-kit', type=Path, help='Existing SSignalKit checkout for the native TGUIKit dependency.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
signal_kit = args.signal_kit or root / 'submodules/telegram-ios/submodules/SSignalKit'
if not (signal_kit / 'Package.swift').is_file():
    parser.error('SSignalKit missing; use --signal-kit /path/to/SSignalKit')


def source(path):
    if args.source_revision:
        return subprocess.check_output(['git', '-C', str(root), 'show', f'{args.source_revision}:{path}'], text=True)
    return (root / path).read_text()


header = source('packages/ChatUI/Sources/ChatUI/ChatHeaderBubblesView.swift')
header = header[header.index('final class ChatHeaderBubblesView:'):]
status = source('packages/TelegramUtils/Sources/TelegramUtils/PeerStatusText.swift')
layout = declaration(header, '    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition)')
layout = layout[layout.index('        let titleWidthAvailable ='):layout.rfind('\n    }')]
result = declaration(status, 'public struct PeerStatusStringResult') + '\n' + declaration(status, 'public func ==(lhs: PeerStatusStringResult')
parts = {
    '__STATUS_RESULT__': result.replace('public ', ''),
    '__CONNECTION_PROPERTY__': declaration(header, '    var connectionStatus:'),
    '__COMPUTE_STATUS__': declaration(header, '    private func computeTitleStatus('),
    '__UPDATE_STATUS__': declaration(header, '    private func updateStatusText('),
    '__TOPIC_MODE__': declaration(header, '    private func isTopicMode('),
    '__TEXT_LAYOUT__': layout,
}
images = {}
for name in ['Icon_SearchField', 'Icon_SearchClear', 'Icon_Quote', 'Icon_Quote_Collapse', 'Icon_Quote_Expand']:
    directory = root / 'Telegram-Mac/Assets.xcassets' / (name + '.imageset')
    entries = json.loads((directory / 'Contents.json').read_text())['images']
    image = next(item for item in entries if item.get('filename') and item.get('scale') == '1x')
    images[name] = str(directory / image['filename'])
parts['__IMAGE_PATHS__'] = '[' + ', '.join(json.dumps(name) + ': ' + json.dumps(path) for name, path in images.items()) + ']'
fixture = Path(__file__).with_name('NetworkStatusTests.swift.in').read_text()
for placeholder, body in parts.items():
    assert fixture.count(placeholder) == 1, placeholder
    fixture = fixture.replace(placeholder, body)
    if placeholder != '__IMAGE_PATHS__':
        print(f'{placeholder}: sha256 {hashlib.sha256(body.encode()).hexdigest()}', flush=True)
assert not re.search(r'__[A-Z_]+__', fixture)
with tempfile.TemporaryDirectory(prefix='header-network-status-') as temporary:
    directory = Path(temporary)
    for package in ['TGUIKit', 'ColorPalette', 'Colors', 'Strings', 'KeyboardKey', 'ObjcUtils']:
        shutil.copytree(root / 'packages' / package, directory / 'packages' / package, ignore=shutil.ignore_patterns('.build', '.swiftpm', '__pycache__'))
    shutil.copytree(signal_kit, directory / 'submodules/telegram-ios/submodules/SSignalKit', ignore=shutil.ignore_patterns('.build', '.swiftpm', '.git'))
    tests = directory / 'Tests'
    tests.mkdir()
    (tests / 'NetworkStatusTests.swift').write_text(fixture)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "HeaderNetworkStatus", platforms: [.macOS(.v12)], dependencies: [.package(path: "packages/TGUIKit"), .package(path: "packages/ColorPalette")], targets: [.testTarget(name: "HeaderNetworkStatusTests", dependencies: [.product(name: "TGUIKit", package: "TGUIKit"), .product(name: "ColorPalette", package: "ColorPalette")], path: "Tests")])
''')
    print(f'Production sources: {args.source_revision or "working tree"}; native TGUIKit/TextView from isolated branch', flush=True)
    result = subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4'])
    print('Scope: exact status computation, connection observer, text update and text-position layout with native TGUIKit text controls; Telegram peer/state, activity and glass-container boundaries are adapters.', flush=True)
    raise SystemExit(result.returncode)
