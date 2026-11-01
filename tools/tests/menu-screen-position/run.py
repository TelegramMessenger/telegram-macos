from pathlib import Path
import argparse
import hashlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description='Run native TGUIKit context-menu screen-position tests.')
parser.add_argument('--signal-kit', type=Path, help='Existing SSignalKit package checkout.')
parser.add_argument('--source-revision', help='Read production AppMenuController.swift at this revision; negative-control baseline: 7b3a0836.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
dependency = (args.signal_kit or root / 'submodules/telegram-ios/submodules/SSignalKit').resolve()
if not (dependency / 'Package.swift').is_file():
    parser.error('SSignalKit checkout missing; supply --signal-kit /path/to/SSignalKit')
source_path = 'packages/TGUIKit/Sources/AppMenuController.swift'
source = subprocess.check_output(['git', '-C', str(root), 'show', args.source_revision + ':' + source_path]) if args.source_revision else (root / source_path).read_bytes()
with tempfile.TemporaryDirectory(prefix='menu-screen-position-') as temporary:
    directory = Path(temporary)
    for package in ['TGUIKit', 'ColorPalette', 'Colors', 'Strings', 'KeyboardKey', 'ObjcUtils']:
        shutil.copytree(root / 'packages' / package, directory / 'packages' / package, ignore=shutil.ignore_patterns('.build', '.swiftpm', '__pycache__'))
    shutil.copytree(dependency, directory / 'submodules/telegram-ios/submodules/SSignalKit', ignore=shutil.ignore_patterns('.build', '.swiftpm', '.git'))
    (directory / source_path).write_bytes(source)
    print('Production AppMenuController: ' + (args.source_revision or 'working tree') + '; sha256 ' + hashlib.sha256(source).hexdigest(), flush=True)
    result = subprocess.run(['swift', 'test', '--package-path', str(directory / 'packages/TGUIKit'), '--disable-sandbox', '--jobs', '4', '--filter', 'AppMenuScreenPositionTests|AppMenuBubbleAnimationTests|ContextMenuItemsTests|TableRowMenuLifecycleTests'])
    print('Scope: actual TGUIKit target, controllers, windows, menu sizing, AppKit screen coordinates and event anchoring. Synthetic menu items have inert handlers. Tests cover available screens; they do not trigger OS fullscreen transitions or mutate sticker packs.', flush=True)
    raise SystemExit(result.returncode)
