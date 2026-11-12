from pathlib import Path
import argparse
import fcntl
import gzip
import hashlib
import json
import os
import platform
import subprocess
import tempfile
import zlib

root = Path(__file__).resolve().parents[3]
html = root / 'packages/HTMLBubbles/Sources/HTMLBubbles'
sandbox = root / 'third-party/widget-sandbox/packages/ios/Sources/WidgetSandbox'


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


state = (html / 'HTMLBubbleState.swift').read_text()
anchor = (root / 'packages/TGUIKit/Sources/TableRowResizeAnchor.swift').read_text()
anchor = anchor[anchor.index('public struct TableRowResizeAnchor'):anchor.index('    public func pin(')] + block(anchor, '    public static func offset(') + '\n}'
layout = '\n'.join(block(state, marker) for marker in [
    'private struct TwidgetLayout',
    'func twidgetSize(',
    'private func cachedTwidgetLayout(',
    'private func recordPrepared(',
    'private var followsWidgetResizeAnchor:',
    'public func twidgetMessageResizeAnchor(',
    'private func twidgetChanged(',
]).replace('private ', '')
sdk = (sandbox / 'WidgetSdk.swift').read_text()
renderer = (root / 'third-party/twidget/Sources/TwidgetRenderer/LiteHTMLWidgetRenderer.swift').read_text()
navigation = (root / 'packages/ChatUI/Sources/ChatUI/ChatNavigationLab.swift').read_text()
source = Path(__file__).with_name('Tests.swift').read_text()
source = source.replace('__ANCHOR__', anchor).replace('__LAYOUT__', layout)
source = source.replace('__RESIZE_ANCHOR__', block(sdk, 'public enum WidgetResizeAnchor'))
source = source.replace('__RENDERER_RESIZE__', block(renderer, 'private func noteResize(from previous:').replace('private ', ''))
source = source.replace('__FIXTURE_LOADER__', block(navigation, 'static func syntheticWidgets(') + '\n' + block(navigation, 'private static func zlib('))

text = '<html><body>' + 'Привет 👋 Widget resize '.join(str(i) for i in range(1500)) + '</body></html>'
raw = text.encode()
fixtures = {
    'html': text,
    'zlib': list(zlib.compress(raw, 9)),
    'gzip': list(gzip.compress(raw, mtime=0)),
    'raw': list(zlib.compress(raw, 9)[2:-4]),
    'invalidUTF8': list(zlib.compress(b'\xff\xfe', 9)),
    'limit': list(zlib.compress(b'x' * (4 * 1024 * 1024), 9)),
    'oversized': list(zlib.compress(b'x' * (4 * 1024 * 1024 + 1), 9)),
}
sources = [html / 'HTMLWidgetPayload.swift', root / 'third-party/twidget/Sources/TwidgetRenderer/WidgetResizeDiff.swift']


def run(path, cached):
    (path / 'Fixtures.json').write_text(json.dumps(fixtures, ensure_ascii=False))
    (path / 'main.swift').write_text(source)
    inputs = [*map(str, sources), str(path / 'main.swift')]
    for name, flags in ([('tests', ['-DDEBUG'])] if args.debug_only else [('tests', ['-DDEBUG']), ('release-tests', [])]):
        binary = path / name
        if not cached or not binary.is_file():
            temporary = path / (name + '.new')
            subprocess.run(['xcrun', 'swiftc', *flags, *inputs, '-lz', '-o', str(temporary)], check=True)
            temporary.replace(binary)
        else:
            print(f'Cached Swift {name}', flush=True)
    subprocess.run([str(path / 'tests'), str(path / 'Fixtures.json')], check=True)
    harness = ['-PerfLab', 'chat-navigation', '-PerfLabScenarios', 'manual', '-PerfLabSyntheticWidgets', str(path)]
    for mode in ['old', 'new']:
        subprocess.run([str(path / 'tests'), str(path / 'Fixtures.json'), '--check-mode', mode, *harness, '-PerfLabWidgetBehavior', mode], check=True)
    subprocess.run([str(path / 'tests'), str(path / 'Fixtures.json'), '--check-mode', 'new', '-PerfLabWidgetBehavior', 'old'], check=True)
    if not args.debug_only:
        subprocess.run([str(path / 'release-tests'), str(path / 'Fixtures.json'), '--check-mode', 'new', *harness, '-PerfLabWidgetBehavior', 'old'], check=True)


parser = argparse.ArgumentParser(description='Check the actual widget payload and resize code in Debug and Release.')
parser.add_argument('--cache', type=Path, help='Reuse binaries only when all source and compiler inputs match')
parser.add_argument('--debug-only', action='store_true', help='Run only the Debug payload checks')
args = parser.parse_args()
if args.cache:
    compiler = subprocess.check_output(['xcrun', 'swiftc', '--version'])
    digest = hashlib.sha256(compiler + platform.platform().encode() + source.encode())
    digest.update(Path(__file__).read_bytes())
    for path in sources:
        digest.update(str(path).encode() + path.read_bytes())
    for name in ['SDKROOT', 'DEVELOPER_DIR', 'MACOSX_DEPLOYMENT_TARGET']:
        digest.update((name + '=' + os.environ.get(name, '')).encode())
    path = args.cache.expanduser().resolve() / digest.hexdigest()
    path.mkdir(parents=True, exist_ok=True)
    with (path / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        run(path, cached=True)
else:
    with tempfile.TemporaryDirectory(prefix='widget-v013-') as directory:
        run(Path(directory), cached=False)
