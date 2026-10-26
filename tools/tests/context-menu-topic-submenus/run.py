import argparse
import hashlib
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PACKAGE = 'packages/TGUIKit'
MENU_SOURCES = ['Sources/ContextMenu.swift', 'Sources/AppMenuController.swift']


def export_package(revision, destination):
    if revision:
        archive = subprocess.check_output(['git', 'archive', '--format=tar', revision, PACKAGE], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(destination, filter='data')
        shutil.move(str(destination / PACKAGE), str(destination / 'TGUIKit'))
        shutil.rmtree(destination / 'packages')
    else:
        shutil.copytree(ROOT / PACKAGE, destination / 'TGUIKit', ignore=shutil.ignore_patterns('.build', '.swiftpm'))
    package = destination / 'TGUIKit'
    manifest = package / 'Package.swift'
    original = ROOT / PACKAGE
    manifest.write_text(re.sub(r'path: "(\.\./[^"]+)"', lambda match: f'path: "{(original / match.group(1)).resolve()}"', manifest.read_text()))
    tests = package / 'Tests/TGUIKitTests'
    shutil.rmtree(tests, ignore_errors=True)
    tests.mkdir(parents=True)
    shutil.copy2(ROOT / PACKAGE / 'Tests/TGUIKitTests/TGUIKitTestBootstrap.swift', tests)
    shutil.copy2(HERE / 'ContextMenuBuildTests.swift', tests)
    return package


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--revision', help='git revision of packages/TGUIKit to test; defaults to the working tree')
    parser.add_argument('--expect-bug', action='store_true', help='expect one native insertion per existing item on every addItem')
    parser.add_argument('--benchmark', action='store_true')
    parser.add_argument('--configuration', choices=['debug', 'release'], default='debug')
    parser.add_argument('--scratch-path', type=Path)
    args = parser.parse_args()

    scratch = args.scratch_path.resolve() if args.scratch_path else Path(tempfile.mkdtemp(prefix='telegram-context-menu-'))
    label = args.revision or 'working-tree'
    workspace = scratch / re.sub(r'[^A-Za-z0-9._-]', '_', label)
    shutil.rmtree(workspace / 'TGUIKit', ignore_errors=True)
    workspace.mkdir(parents=True, exist_ok=True)
    package = export_package(args.revision, workspace)

    print(f'TGUIKit source: {label}', flush=True)
    for name in MENU_SOURCES:
        print(f'{name} SHA256: {hashlib.sha256((package / name).read_bytes()).hexdigest()}', flush=True)

    environment = os.environ.copy()
    environment['CLANG_MODULE_CACHE_PATH'] = str(workspace / 'ModuleCache')
    environment['SWIFT_MODULECACHE_PATH'] = str(workspace / 'ModuleCache')
    environment['CONTEXT_MENU_EXPECT_BUG'] = '1' if args.expect_bug else '0'
    environment['CONTEXT_MENU_BENCHMARK'] = '1' if args.benchmark else '0'
    command = ['swift', 'test', '--package-path', str(package), '--scratch-path', str(workspace / 'build'),
               '--configuration', args.configuration, '--filter', 'ContextMenuBuildTests']
    process = subprocess.run(command, cwd=ROOT, env=environment, text=True, capture_output=True)
    output = process.stdout + process.stderr
    for line in output.splitlines():
        if line.startswith('CONTEXT_MENU_') or ' error: ' in line or line.startswith('error:') or re.search(r'Test Case .* (passed|failed|skipped)', line) or 'Executed' in line:
            print(line)
    if process.returncode != 0:
        print(f'FAIL: swift test exited with {process.returncode}; full log: {workspace / "test.log"}')
    else:
        print('PASS')
    (workspace / 'test.log').write_text(output)
    raise SystemExit(process.returncode)


if __name__ == '__main__':
    main()
