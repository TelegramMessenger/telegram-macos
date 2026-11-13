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


def read(name):
    if args.baseline:
        return subprocess.check_output(['git', '-C', str(root), 'show', args.baseline + ':' + name], text=True)
    return (root / name).read_text()


def block(text, marker):
    assert text.count(marker) == 1, marker
    start = text.index(marker)
    index = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[index] == '{') - (text[index] == '}')
        index += 1
    return text[start:index]


base = 'packages/PreviewSenderUI/Sources/PreviewSenderUI/'
source = read(base + 'PreviewSenderController.swift')
fixture = Path(__file__).with_name('CloseTests.swift.in').read_text()
button = block(source, '        closeButton.set(handler:')
replacements = {
    '__BUTTON__': button + ', for: .Click)',
    '__CLOSE__': block(source, '    public override func close(animationType:').replace('public override ', 'override ', 1),
    '__CLOSE_MODAL__': block(source, '    fileprivate func closeModal()').replace('fileprivate ', '', 1),
    '__CAPTURE__': block(source, '    private func capturePendingAction()').replace('private ', '', 1),
    '__PENDING__': read(base + 'PreviewSenderPendingActions.swift'),
    '__CHILD__': read(base + 'PreviewSenderChildAction.swift').replace('import AppAnalytics\n', '')
}
for key, value in replacements.items():
    fixture = fixture.replace(key, value)
assert '__' not in fixture
with tempfile.TemporaryDirectory(prefix='preview-close-confirmation-') as temporary:
    output = args.output.resolve() if args.output else Path(temporary)
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    (output / 'Tests').mkdir()
    (output / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "PreviewCloseConfirmation", targets: [.testTarget(name: "PreviewCloseConfirmationTests", path: "Tests")])\n')
    (output / 'Tests/CloseTests.swift').write_text(fixture)
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(output / 'module-cache')
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(output), '--jobs', '2'], env=env).returncode)
