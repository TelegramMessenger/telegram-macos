import argparse
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--dependency-root', type=Path, default=root)
parser.add_argument('--scratch-path', type=Path, required=True)
parser.add_argument('--revision')
parser.add_argument('--prepare-app', action='store_true')
args = parser.parse_args()
deps = args.dependency_root.resolve()
fixtures = Path(__file__).resolve().parent

def source(path):
    return subprocess.check_output(['git', 'show', args.revision + ':' + path], cwd=root, text=True) if args.revision else (root / path).read_text()

peers = source('packages/ChatListUI/Sources/ChatListUI/PeersListController.swift')
search = source('packages/ChatListUI/Sources/ChatListUI/SearchController.swift')
chat_insets = next(line.strip() for line in peers.splitlines() if 'tableView.scrollerInsets = .init(' in line)
search_insets = '\n'.join(line.strip() for line in search.splitlines() if 'genericView.contentInsets.bottom = ' in line or 'genericView.scrollerInsets.bottom = ' in line)
assert chat_insets and search_insets
settings = source('packages/SettingsUI/Sources/SettingsUI/AccountViewController.swift')
calls = source('packages/CallsUI/Sources/CallsUI/RecentCallsViewController.swift')
forms = source('packages/InputDataUI/Sources/InputDataUI/InputDataController.swift')
settings_insets = next(line.strip() for line in settings.splitlines() if 'tableView.scrollerInsets.bottom = ' in line)
calls_insets = next(line.strip() for line in calls.splitlines() if 'genericView.tableView.scrollerInsets.bottom = ' in line)
forms_insets = next(line.strip() for line in forms.splitlines() if 'tableView.scrollerInsets.bottom = ' in line)
history = source('packages/ChatUI/Sources/ChatUI/ChatController.swift')
history_content = next(line.strip() for line in history.splitlines() if 'tableView.contentInsets = .init(top:' in line and 'state.height' not in line)
history_scroller = next(line.strip() for line in history.splitlines() if 'tableView.scrollerInsets = NSEdgeInsets(bottom: scrollInset)' in line)
entertainment = source('packages/EntertainmentUI/Sources/EntertainmentUI/EntertainmentViewController.swift')
assert 'let insets = NSEdgeInsets(bottom: EntertainmentView.tabsAreaHeight)' in entertainment
picker_bottom = next((line.strip() for line in entertainment.splitlines() if 'table.scrollerInsets.bottom = ' in line), '')
picker_cases = []
for case, name in [('emoji', 'EmojiesController'), ('stickers', 'StickersViewController'), ('gifs', 'GifKeyboardController')]:
    text = source('packages/EntertainmentUI/Sources/EntertainmentUI/' + name + '.swift')
    line = next(line.strip() for line in text.splitlines() if 'tableView.scrollerInsets = .init(' in line and not line.strip().startswith('//'))
    picker_cases.append('    case .' + case + ':\n        ' + line + '\n        ' + picker_bottom)
kit = args.scratch_path.resolve() / 'scrollbar-dependencies/TGUIKit'
kit.mkdir(parents=True, exist_ok=True)
for folder in ['Sources', 'Tests']:
    shutil.copytree(deps / 'packages/TGUIKit' / folder, kit / folder, dirs_exist_ok=True)
for name in ['ScrollView.swift', 'TableView.swift', 'ThemedScroller.swift']:
    target = kit / 'Sources' / name
    try:
        target.write_text(source('packages/TGUIKit/Sources/' + name))
    except (subprocess.CalledProcessError, FileNotFoundError):
        if name != 'ThemedScroller.swift':
            raise
        target.unlink(missing_ok=True)
manifest = (deps / 'packages/TGUIKit/Package.swift').read_text()
manifest = re.sub(r'path: "(\.\.[^"]+)"', lambda m: 'path: ' + json.dumps(str((deps / 'packages/TGUIKit' / m.group(1)).resolve())), manifest)
(kit / 'Package.swift').write_text(manifest)
themed = (kit / 'Sources/ThemedScroller.swift').exists()
with tempfile.TemporaryDirectory(prefix='telegram-sidebar-scroll-') as tmp:
    tmp = Path(tmp)
    sources = tmp / 'Sources'
    sources.mkdir()
    dependencies = ', '.join('.package(path: ' + json.dumps(str(path)) + ')' for path in [kit, deps / 'packages/ColorPalette'])
    (tmp / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SidebarScrollValidation", platforms: [.macOS(.v12)], dependencies: [DEPENDENCIES], targets: [.executableTarget(name: "SidebarScrollValidation", dependencies: ["TGUIKit", "ColorPalette"], path: "Sources")])
'''.replace('DEPENDENCIES', dependencies))
    main = (fixtures / 'main.swift').read_text().replace('__CHAT_INSETS__', chat_insets).replace('__SEARCH_INSETS__', search_insets).replace('__SETTINGS_INSETS__', settings_insets).replace('__CALLS_INSETS__', calls_insets).replace('__FORMS_INSETS__', forms_insets).replace('__HISTORY_CONTENT__', history_content).replace('__HISTORY_SCROLLER__', history_scroller).replace('__PICKER_CASES__', '\n'.join(picker_cases)).replace('__THEMED_CHECKS__', (fixtures / 'ThemedChecks.swift.txt').read_text() if themed else '')
    (sources / 'main.swift').write_text(main)
    images = {}
    for name in ['Icon_SearchField', 'Icon_SearchClear', 'Icon_Quote', 'Icon_Quote_Collapse', 'Icon_Quote_Expand']:
        folder = deps / 'Telegram-Mac/Assets.xcassets' / (name + '.imageset')
        variants = json.loads((folder / 'Contents.json').read_text())['images']
        filename = next(v['filename'] for v in variants if v.get('filename') and v.get('scale') == '1x')
        images[name] = str(folder / filename)
    (sources / 'Assets.swift').write_text('let imagePaths: [String: String] = [' + ', '.join(json.dumps(n) + ': ' + json.dumps(p) for n, p in images.items()) + ']')
    options = ['--package-path', str(tmp), '--scratch-path', str(args.scratch_path.resolve()), '--disable-sandbox', '--jobs', '2']
    if args.prepare_app:
        subprocess.run(['swift', 'build'] + options + ['--product', 'SidebarScrollValidation'], check=True)
        binary = subprocess.check_output(['swift', 'build'] + options + ['--show-bin-path'], text=True).strip()
        app = args.scratch_path.resolve() / 'SidebarScrollValidation.app'
        (app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
        shutil.copy2(Path(binary) / 'SidebarScrollValidation', app / 'Contents/MacOS/SidebarScrollValidation')
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.codex.telegram.SidebarScrollValidation', 'CFBundleExecutable': 'SidebarScrollValidation', 'CFBundleName': 'Sidebar Scroll Validation', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1'}))
        print(app)
    else:
        raise SystemExit(subprocess.run(['swift', 'run'] + options + ['SidebarScrollValidation']).returncode)
