import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline')
parser.add_argument('--output', type=Path)
args = parser.parse_args()


def read(path):
    if args.baseline:
        return subprocess.check_output(['git', '-C', str(root), 'show', args.baseline + ':' + path], text=True)
    return (root / path).read_text()


def block(text, marker):
    assert text.count(marker) == 1, marker
    start = text.index(marker)
    index = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[index] == '{') - (text[index] == '}')
        index += 1
    return text[start:index]


source = read('packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift')
settings = read('packages/InAppSettings/Sources/InAppSettings/FastSettings.swift')
start = '\n        var canCollage: Bool = canCollagesFromUrl(self.urls)'
end = '\n        self.genericView.state = state\n        self.urlsAndStateValue.set'
assert source.count(start) == source.count(end) == 1
initial = source[source.index(start):source.index(end)]
fixture = Path(__file__).with_name('GroupingTests.swift.in').read_text()
replacements = {
    '__STATE__': block(source, 'fileprivate struct PreviewSendingState : Hashable').replace('fileprivate ', '', 1),
    '__PREFERENCE__': block(settings, '    public static var isNeedCollage: Bool').replace('public ', '', 1).replace('UserDefaults.standard', 'defaults'),
    '__INITIAL__': initial
}
for marker, name in [('__GROUPED__', 'Grouped'), ('__UNGROUPED__', 'Ungrouped')]:
    menu = block(source, 'menu.addItem(ContextMenuItem(strings().previewSender' + name + ', handler:')
    replacements[marker] = menu[menu.index('handler: {') + len('handler: {'):-1]
for marker, value in replacements.items():
    fixture = fixture.replace(marker, value)
assert '__' not in fixture
with tempfile.TemporaryDirectory(prefix='preview-grouping-preference-') as temporary:
    output = args.output.resolve() if args.output else Path(temporary)
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    (output / 'Tests').mkdir()
    (output / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "PreviewGroupingPreference", targets: [.testTarget(name: "PreviewGroupingPreferenceTests", path: "Tests")])\n')
    (output / 'Tests/GroupingTests.swift').write_text(fixture)
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(output / 'module-cache')
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(output), '--jobs', '2'], env=env).returncode)
