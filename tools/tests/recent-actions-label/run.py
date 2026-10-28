import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--scratch-path', type=Path, required=True)
parser.add_argument('--snapshots', type=Path, required=True)
args = parser.parse_args()
args.snapshots.mkdir(parents=True, exist_ok=True)
source = (root / 'packages/ChannelAdminUI/Sources/ChannelAdminUI/ChannelEventLogController.swift').read_text()
start = source.index('        settings.autohighlight = false')
end = source.index('        setFrameSize(frameRect.size)', start)
setup = '\n'.join(line for line in source[start:end].splitlines() if 'settings.' in line)
start = source.index('        settings.set(text: strings().channelEventFilterFilters')
end = source.index('        info.set(image:', start)
style = source[start:end].replace('strings().channelEventFilterFilters', 'title')
strings = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(root / 'Telegram-Mac/en.lproj/Localizable.strings')], text=True))
new_key = 'Channel.EventFilter.Filters'
assert strings[new_key] == 'Filters'
assert new_key in (root / 'packages/Localization/Sources/Localization/Localizable.swift').read_text()
assert 'self?.showFilter()' in source
with tempfile.TemporaryDirectory(prefix='telegram-recent-actions-label-') as directory:
    directory = Path(directory)
    dependencies = ', '.join('.package(path: ' + json.dumps(str(root / 'packages' / name)) + ')' for name in ['TGUIKit', 'ColorPalette'])
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RecentActionsLabel", platforms: [.macOS(.v12)], dependencies: [DEPENDENCIES], targets: [.executableTarget(name: "RecentActionsLabel", dependencies: ["TGUIKit", "ColorPalette"], path: "Sources")])
'''.replace('DEPENDENCIES', dependencies))
    (directory / 'Sources').mkdir()
    text = (Path(__file__).with_name('main.swift')).read_text()
    for marker, value in {'__SETUP__': setup, '__STYLE__': style, '__BEFORE__': json.dumps(strings['Chanel.EventFilter.Settings']), '__AFTER__': json.dumps(strings[new_key]), '__SNAPSHOTS__': json.dumps(str(args.snapshots.resolve()))}.items():
        text = text.replace(marker, value)
    (directory / 'Sources/main.swift').write_text(text)
    raise SystemExit(subprocess.run(['swift', 'run', '--package-path', str(directory), '--scratch-path', str(args.scratch_path.resolve()), '--disable-sandbox', '--jobs', '4', 'RecentActionsLabel']).returncode)
