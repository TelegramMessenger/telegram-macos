import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = 'packages/TGUIKit/Sources/Extensions.swift'
FIXTURES = ROOT / 'packages/TGUIKit/Tests/TGUIKitTests'


def extract(source):
    trimmed = source[source.index('    var trimmed: NSAttributedString {'):source.index('    var trimNewLines: NSAttributedString {')]
    newlines = source[source.index('    var trimNewLinesToSpace: NSAttributedString {'):source.index('    var range:NSRange {')]
    return 'import Foundation\n\npublic extension NSAttributedString {\n' + trimmed + newlines + '}\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--configuration', choices=['debug', 'release'], default='debug')
    parser.add_argument('--source-ref')
    parser.add_argument('--benchmark', action='store_true')
    parser.add_argument('--reverse', action='store_true')
    parser.add_argument('--render-output', type=Path)
    args = parser.parse_args()
    source = subprocess.check_output(['git', 'show', f'{args.source_ref}:{SOURCE}'], cwd=ROOT, text=True) if args.source_ref else (ROOT / SOURCE).read_text()
    bridge_source = (ROOT / 'packages/Strings/Sources/Strings/Strings.swift').read_text()
    bridge = bridge_source[bridge_source.index('public extension String {'):bridge_source.index('public extension String {', bridge_source.index('public extension String {') + 1)]
    reference = FIXTURES / 'AttributedTextNormalizationReference.swift'
    print(f'Production source SHA256: {hashlib.sha256(source.encode()).hexdigest()}', flush=True)
    print(f'Frozen reference SHA256: {hashlib.sha256(reference.read_bytes()).hexdigest()}', flush=True)
    with tempfile.TemporaryDirectory(prefix='telegram-text-normalization-') as temporary:
        package = Path(temporary)
        for folder in ['Sources/TGUIKit', 'Sources/Reference', 'Sources/Benchmark', 'Tests']:
            (package / folder).mkdir(parents=True)
        (package / 'Package.swift').write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "TextNormalization", platforms: [.macOS(.v10_13)], targets: [
    .target(name: "TGUIKit"),
    .target(name: "Reference", dependencies: ["TGUIKit"]),
    .executableTarget(name: "Benchmark", dependencies: ["TGUIKit", "Reference"]),
    .testTarget(name: "NormalizationTests", dependencies: ["TGUIKit"], path: "Tests")
])
''')
        (package / 'Sources/TGUIKit/Production.swift').write_text(extract(source))
        (package / 'Sources/TGUIKit/StringBridge.swift').write_text('import Foundation\n' + bridge)
        shutil.copy2(reference, package / 'Sources/Reference/Reference.swift')
        shutil.copy2(HERE / 'Benchmark.swift', package / 'Sources/Benchmark/main.swift')
        shutil.copy2(FIXTURES / 'AttributedTextNormalizationTests.swift', package / 'Tests')
        shutil.copy2(reference, package / 'Tests/Reference.swift')
        environment = os.environ.copy()
        environment['CLANG_MODULE_CACHE_PATH'] = str(package / 'ModuleCache')
        environment['SWIFT_MODULECACHE_PATH'] = str(package / 'ModuleCache')
        if args.render_output:
            environment['TEXT_NORMALIZATION_SNAPSHOTS'] = str(args.render_output.resolve())
        options = ['--package-path', str(package), '--disable-sandbox', '--jobs', '4']
        if args.benchmark:
            command = ['swift', 'run', *options, '-c', 'release', 'Benchmark']
            if args.reverse:
                command.append('--reverse')
        else:
            command = ['swift', 'test', *options, '-c', args.configuration]
        return subprocess.run(command, cwd=ROOT, env=environment).returncode


if __name__ == '__main__':
    raise SystemExit(main())
