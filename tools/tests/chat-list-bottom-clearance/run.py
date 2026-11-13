import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[3]
SOURCES = {
    'main': 'Telegram-Mac/app/MainViewController.swift',
    'peers': 'packages/ChatListUI/Sources/ChatListUI/PeersListController.swift',
    'chat_list': 'packages/ChatListUI/Sources/ChatListUI/ChatListController.swift',
    'base': 'packages/TGUIKit/Sources/ViewController.swift',
    'navigation': 'packages/TGUIKit/Sources/NavigationViewController.swift',
    'tabs': 'packages/TGUIKit/Sources/TabBarController.swift',
    'tab_layout': 'packages/TGUIKit/Sources/TabBarView.swift',
    'scroll': 'packages/TGUIKit/Sources/ScrollView.swift',
    'clip': 'packages/TGUIKit/Sources/TGClipView.swift',
    'table': 'packages/TGUIKit/Sources/TableView.swift',
    'scroller': 'packages/ChatUI/Sources/ChatUI/ChatNavigateScroller.swift',
    'image_button': 'packages/TGUIKit/Sources/ImageButton.swift',
}


def declaration(source, marker):
    if source.count(marker) != 1:
        raise ValueError(f'Expected one declaration: {marker!r}')
    start = source.index(marker)
    opening = start
    parentheses = 0
    while opening < len(source):
        if source[opening] == '{' and parentheses == 0:
            break
        parentheses += (source[opening] == '(') - (source[opening] == ')')
        opening += 1
    depth = 1
    index = opening + 1
    while depth:
        if index >= len(source):
            raise ValueError(f'Unclosed declaration: {marker!r}')
        if source.startswith('//', index):
            end = source.find('\n', index)
            index = len(source) if end < 0 else end
            continue
        if source.startswith('/*', index):
            end = source.find('*/', index + 2)
            if end < 0:
                raise ValueError('Unclosed source comment')
            index = end + 2
            continue
        if source[index] == '"':
            index += 1
            while index < len(source):
                if source[index] == '\\':
                    index += 2
                elif source[index] == '"':
                    index += 1
                    break
                else:
                    index += 1
            continue
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[start:index]


def between(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError(f'Expected unique source boundaries: {start!r}, {end!r}')
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def output_directory(value):
    path = Path(os.path.abspath(value))
    for component in [path, *path.parents]:
        if component.is_symlink():
            raise ValueError(f'Output must not contain symlinks: {component}')
    if path.exists():
        raise ValueError(f'Output must be new: {path}')
    if not path.parent.is_dir():
        raise ValueError(f'Output parent must already exist: {path.parent}')
    path.mkdir(mode=0o700)
    return path


def run(directory, args):
    directory = directory.resolve(strict=True)
    temporary = directory / 'tmp'
    swift_cache = directory / 'cache' / 'swift'
    clang_cache = directory / 'cache' / 'clang'
    for path in (temporary, swift_cache, clang_cache):
        path.mkdir(mode=0o700, parents=True)
        if not path.resolve().is_relative_to(directory):
            raise ValueError('Temporary/cache path escaped the owned run directory')
    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    environment.update({
        'TMPDIR': str(temporary) + '/',
        'CLANG_MODULE_CACHE_PATH': str(clang_cache),
        'SWIFT_MODULE_CACHE_PATH': str(swift_cache),
    })
    revision = None
    if args.source_revision:
        revision = subprocess.check_output(
            ['git', '-C', str(ROOT), 'rev-parse', '--verify', args.source_revision + '^{commit}'],
            text=True, env=environment, cwd=directory,
        ).strip()
        if not re.fullmatch(r'[0-9a-f]{40}', revision):
            raise ValueError('Expected a local commit hash')
    sources = {}
    hashes = {}
    for name, path in SOURCES.items():
        data = subprocess.check_output(
            ['git', '-C', str(ROOT), 'show', revision + ':' + path],
            env=environment, cwd=directory,
        ) if revision else (ROOT / path).read_bytes()
        if name == 'peers' and args.peer_list_source:
            data = args.peer_list_source.read_bytes()
        sources[name] = data.decode()
        hashes[path] = digest(data)
    if not re.search(r'public class ChatListController<[^\n]+> : PeersListController<', sources['chat_list']):
        raise ValueError('ChatListController no longer inherits the tested peer-list layout')
    chunks = {
        '__BASE_INSETS__': declaration(sources['base'], '    open func updateContainerContentInsets('),
        '__NAVIGATION_INSETS__': declaration(sources['navigation'], '    open override func updateContainerContentInsets('),
        '__NAVIGATION_CHANGED__': declaration(sources['navigation'], '    open func currentControllerDidChange()'),
        '__NAVIGATION_ENUMERATE__': declaration(sources['navigation'], '    public func enumerateControllers('),
        '__TAB_BOTTOM_INSET__': declaration(sources['tabs'], '    public var contentBottomInset:'),
        '__TAB_CONTENT_INSETS__': declaration(sources['tabs'], '    private var contentInsetsForTabs:'),
        '__TAB_UPDATE_INSETS__': declaration(sources['tabs'], '    public override func updateContainerContentInsets('),
        '__TAB_HIDE__': declaration(sources['tabs'], '    public func hideTabView('),
        '__TAB_LAYOUT__': declaration(sources['tab_layout'], 'struct FloatingTabBarLayout {'),
        '__MAIN_OVERLAYS__': declaration(sources['main'], '    private func updateChatListBottomOverlays()'),
        '__MAIN_BOTTOM__': declaration(sources['main'], '    private func updateButtonBottomY('),
        '__PEERS_INSETS__': declaration(sources['peers'], '    open override func updateContainerContentInsets('),
        '__PEERS_BOTTOM_INSET__': declaration(sources['peers'], '    public var contentBottomInset:'),
        '__PEERS_CONTROLS__': declaration(sources['peers'], '    public func updateBottomControls('),
        '__PEERS_SCROLLER__': declaration(sources['peers'], '    public func updateScroller('),
        '__SCROLLER_INIT__': declaration(sources['scroller'], '    public init(_ source: Source)'),
        '__IMAGE_BUTTON_HIT_TEST__': declaration(sources['image_button'], '    open override func hitTest('),
        '__IMAGE_BUTTON_GLASS_LAYOUT__': declaration(sources['image_button'], '        if let glassView = _glassView {'),
        '__PEERS_DOWNLOADS_FRAME__': declaration(sources['peers'], '    private func downloadsFrame('),
        '__DOCUMENT_SIZE__': declaration(sources['scroll'], '    public var documentSize:'),
        '__CLIP_UPDATE_BOUNDS__': declaration(sources['clip'], '    public func updateBounds('),
        '__CLIP_SCROLL__': declaration(sources['clip'], '    public func scroll(to point: NSPoint, animated:Bool,'),
        '__CLIP_NATIVE_SCROLL__': declaration(sources['clip'], '    public override func scroll(to newOrigin:'),
        '__TABLE_SCROLL_TYPES__': between(sources['table'], 'public struct TableScrollFocus : Equatable {', 'public extension TableScrollState {'),
        '__TABLE_SCROLL__': declaration(sources['table'], '    public func scroll(to state:TableScrollState,'),
        '__TABLE_AT_BOTTOM__': declaration(sources['table'], '    public var isAtBottom:'),
    }
    fixture_path = Path(__file__).with_name('ChatListBottomClearanceTests.swift.in')
    fixture_bytes = fixture_path.read_bytes()
    fixture = fixture_bytes.decode()
    for marker, text in chunks.items():
        if fixture.count(marker) != 1:
            raise ValueError(f'Expected one fixture marker: {marker}')
        fixture = fixture.replace(marker, text)
    if re.search(r'__[A-Z_]+__', fixture):
        raise ValueError('Unresolved fixture marker')
    generated = directory / 'main.swift'
    generated.write_text(fixture)
    compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True, env=environment, cwd=directory).strip()
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True, env=environment, cwd=directory).strip()
    version = subprocess.check_output([compiler, '--version'], text=True, stderr=subprocess.STDOUT, env=environment, cwd=directory).strip()
    command = [compiler, '-j2', '-sdk', sdk, '-module-cache-path', str(swift_cache), str(generated), '-o', str(directory / 'tests')]
    compiled = subprocess.run(command, text=True, capture_output=True, env=environment, cwd=directory, timeout=180)
    (directory / 'compile.stdout').write_text(compiled.stdout)
    (directory / 'compile.stderr').write_text(compiled.stderr)
    report = {
        'source_revision': revision or 'working-tree',
        'peer_list_source_override': str(args.peer_list_source.resolve()) if args.peer_list_source else None,
        'source_sha256': hashes,
        'runner_sha256': digest(Path(__file__).read_bytes()),
        'fixture_sha256': digest(fixture_bytes),
        'generated_sha256': digest(fixture.encode()),
        'extracted_sha256': {marker: digest(text.encode()) for marker, text in chunks.items()},
        'compiler': version,
        'compile_exit_code': compiled.returncode,
        'compile_stderr': compiled.stderr,
        'temporary_and_caches_contained': True,
        'preserved_output': str(directory) if args.output else None,
        'execution': None,
    }
    status = 2
    if compiled.returncode == 0:
        result = subprocess.run([str(directory / 'tests')], text=True, capture_output=True, env=environment, cwd=directory, timeout=90)
        (directory / 'test.stdout').write_text(result.stdout)
        (directory / 'test.stderr').write_text(result.stderr)
        report['test_exit_code'] = result.returncode
        report['test_stderr'] = result.stderr
        try:
            report['execution'] = json.loads(result.stdout)
            status = 0 if result.returncode == 0 and report['execution']['failed_assertions'] == 0 else 1
        except (ValueError, KeyError):
            report['test_stdout'] = result.stdout
    (directory / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return status


def main():
    parser = argparse.ArgumentParser(description='Compile source-extracted chat-list clearance tests against native offscreen AppKit; no packages or network.')
    parser.add_argument('--source-revision', help='Read all production bodies from an existing local commit (negative control: 246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5).')
    parser.add_argument('--peer-list-source', type=Path, help='Override only PeersListController.swift with an exact preserved implementation; combine with --source-revision for unchanged baseline dependencies. The current test fixture is always used.')
    parser.add_argument('--output', help='Preserve generated source, logs, executable and caches in this new, non-symlink directory. Default: owned temporary directory, automatically removed.')
    args = parser.parse_args()
    if not sys.flags.isolated:
        parser.error('Run with python3 -I')
    try:
        if args.output:
            return run(output_directory(args.output), args)
        temporary_parent = Path(os.environ.get('TMPDIR', tempfile.gettempdir())).resolve(strict=True)
        with tempfile.TemporaryDirectory(prefix='chat-list-bottom-clearance-', dir=temporary_parent) as name:
            directory = Path(name)
            if not directory.resolve().is_relative_to(temporary_parent):
                raise ValueError('Run directory escaped TMPDIR')
            return run(directory, args)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(2, f'{error}\n')


if __name__ == '__main__':
    sys.exit(main())
