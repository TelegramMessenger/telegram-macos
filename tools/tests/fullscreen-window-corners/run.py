import argparse
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'Telegram-Mac/app/ApplicationContext.swift')
parser.add_argument('--scratch-path', type=Path)
args = parser.parse_args()
source = args.source.read_text()


def section(start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError(f'Expected unique source boundaries: {start!r}, {end!r}')
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


state = section('    private var isInFullScreenTransition:', '    private let _ready:')
observers = section('        NotificationCenter.default.addObserver(self, selector: #selector(handleFullScreenWillChange(_:)), name: NSWindow.willEnterFullScreenNotification', '\n\n        let accountId = context.account.id')
methods = section('    @objc private func handleFullScreenWillChange(', '\n}\n\nextension Window {\n    func applyCornerRadius(')
radius_start = 'extension Window {\n    func applyCornerRadius('
if source.count(radius_start) != 1:
    raise ValueError('Expected one window corner radius extension')
radius = source[source.index(radius_start):]
fixture = Path(__file__).with_name('FullscreenWindowCornersTests.swift.in').read_text()
for marker, text in [('__STATE__', state), ('__OBSERVERS__', observers), ('__METHODS__', methods), ('__RADIUS__', radius)]:
    if fixture.count(marker) != 1:
        raise ValueError(f'Expected one fixture marker: {marker}')
    fixture = fixture.replace(marker, text)

with tempfile.TemporaryDirectory(prefix='fullscreen-window-corners-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "FullscreenWindowCorners", platforms: [.macOS(.v10_15)], targets: [.testTarget(name: "FullscreenWindowCornersTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/FullscreenWindowCornersTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--jobs', '2']
    if args.scratch_path:
        command += ['--scratch-path', str(args.scratch_path.resolve())]
    raise SystemExit(subprocess.run(command).returncode)
