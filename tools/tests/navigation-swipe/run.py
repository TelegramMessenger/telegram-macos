import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--revision')
parser.add_argument('--expect-bug', action='store_true')
parser.add_argument('--scratch-path', type=Path, required=True)
parser.add_argument('--snapshots', type=Path)
args = parser.parse_args()
if args.snapshots:
    args.snapshots.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='telegram-navigation-swipe-') as directory:
    directory = Path(directory)
    kit = directory / 'TGUIKit'
    (kit / 'Sources').mkdir(parents=True)
    original = root / 'packages/TGUIKit'
    manifest = (original / 'Package.swift').read_text()
    for relative in ['../../submodules/telegram-ios/submodules/SSignalKit', '../ColorPalette', '../KeyboardKey', '../ObjcUtils']:
        manifest = manifest.replace('"' + relative + '"', json.dumps(str((original / relative).resolve())))
    (kit / 'Package.swift').write_text(manifest)
    (kit / 'Tests').symlink_to(original / 'Tests', target_is_directory=True)
    for path in (original / 'Sources').iterdir():
        target = kit / 'Sources' / path.name
        if path.name == 'Window.swift':
            target.write_text(path.read_text() + '''
public extension Window {
    func fixtureSwipe(_ navigation: NavigationViewController, _ direction: SwipeDirection, animated: Bool = true) -> SwipeHandlerResult {
        return swipeHandlers[navigation.description]!.handler(direction, animated)
    }
}
''')
        elif path.name == 'NavigationViewController.swift':
            source = subprocess.check_output(['git', 'show', args.revision + ':packages/TGUIKit/Sources/' + path.name], cwd=root, text=True) if args.revision else path.read_text()
            target.write_text(source + '''
public extension NavigationViewController {
    func fixtureFrame(_ controller: ViewController) -> NSRect {
        return containerOf(controller).frame
    }
}
''')
        else:
            target.symlink_to(path, target_is_directory=path.is_dir())
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "NavigationSwipeChecks", platforms: [.macOS(.v12)], dependencies: [.package(path: "TGUIKit"), .package(path: COLOR)], targets: [.executableTarget(name: "NavigationSwipeChecks", dependencies: ["TGUIKit", "ColorPalette"], path: "Sources")])
'''.replace('COLOR', json.dumps(str(root / 'packages/ColorPalette'))))
    (directory / 'Sources').mkdir()
    source = (fixtures / 'main.swift').read_text().replace('__SNAPSHOTS__', json.dumps(str(args.snapshots.resolve())) if args.snapshots else 'nil')
    (directory / 'Sources/main.swift').write_text(source)
    command = ['swift', 'run', '--package-path', str(directory), '--scratch-path', str(args.scratch_path.resolve()), '--disable-sandbox', '--jobs', '4', 'NavigationSwipeChecks']
    if args.expect_bug:
        command.append('--expect-bug')
    raise SystemExit(subprocess.run(command).returncode)
