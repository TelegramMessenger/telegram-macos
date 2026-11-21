import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--telegram-ios-source', type=Path, default=root / 'submodules/telegram-ios')
args = parser.parse_args()


def without_imports(source):
    return '\n'.join(line for line in source.splitlines() if not line.startswith('import '))


def declaration(source, name):
    start = source.index(name)
    opening = source.index('{', start)
    depth = 1
    for position in range(opening + 1, len(source)):
        depth += (source[position] == '{') - (source[position] == '}')
        if depth == 0:
            return source[start:position + 1]
    raise ValueError(name)


def run(command):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        print(result.stdout)
        raise SystemExit(result.returncode)
    return result.stdout


postbox = args.telegram_ios_source / 'submodules/Postbox/Sources'
signals = args.telegram_ios_source / 'submodules/SSignalKit/SwiftSignalKit2/Source'
signal_sources = sorted(signals.glob('*.swift'))
if not signal_sources:
    raise SystemExit('Provide a populated Telegram-iOS submodule with --telegram-ios-source')
fixture = Path(__file__).with_name('FocusEmptyFolderTests.swift').read_text()
fixture = fixture.replace('__PEER_GROUP__', without_imports((postbox / 'PeerGroup.swift').read_text()))
fixture = fixture.replace('__POSTBOX_PREDICATE__', declaration((postbox / 'ChatListView.swift').read_text(), 'public struct ChatListFilterPredicate {'))
for token, filename in [
    ('__FOCUS_PREDICATE__', 'ChatListFocusPredicate.swift'),
    ('__FOCUS_SUPPORT__', 'ChatListFocusSupport.swift'),
    ('__FOCUS_FILTERING__', 'ChatListFocusFiltering.swift'),
    ('__FOCUS_TEXT__', 'ChatListFocusEmptyText.swift'),
]:
    fixture = fixture.replace(token, without_imports((root / 'packages/ChatListUI/Sources/ChatListUI' / filename).read_text()))
core = sorted((root / 'packages/FocusFilterCore/Sources/FocusFilterCore').glob('*.swift'))
with tempfile.TemporaryDirectory(prefix='telegram-focus-empty-folder-') as directory:
    directory = Path(directory)
    common = ['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path', str(directory / 'ModuleCache')]
    run(common + ['-emit-module', '-emit-library', '-module-name', 'SwiftSignalKit',
                  *map(str, signal_sources), '-emit-module-path', str(directory / 'SwiftSignalKit.swiftmodule'),
                  '-o', str(directory / 'libSwiftSignalKit.dylib')])
    source = directory / 'Tests.swift'
    source.write_text(fixture)
    executable = directory / 'tests'
    run(common + ['-parse-as-library', '-I', str(directory), '-L', str(directory), '-lSwiftSignalKit',
                  '-Xlinker', '-rpath', '-Xlinker', str(directory), *map(str, core), str(source), '-o', str(executable)])
    bundle = directory / 'FocusEmptyTests.bundle'
    resources = bundle / 'Contents/Resources'
    resources.mkdir(parents=True)
    with (bundle / 'Contents/Info.plist').open('wb') as output:
        plistlib.dump({'CFBundleIdentifier': 'test.focus.empty-folder', 'CFBundleDevelopmentRegion': 'en'}, output)
    for language in ['en', 'ru']:
        target = resources / (language + '.lproj')
        target.mkdir()
        shutil.copyfile(root / 'Telegram-Mac' / (language + '.lproj') / 'Localizable.strings', target / 'Localizable.strings')
    print(run([str(executable), str(bundle)]), end='')
