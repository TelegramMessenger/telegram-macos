import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def body(source, marker):
    start = source.index('{', source.index(marker)) + 1
    depth = 1
    for index in range(start, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if depth == 0:
            return source[start:index]
    raise AssertionError('Unclosed Swift body: ' + marker)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--revision')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}

    def read(path):
        if args.revision:
            return subprocess.check_output(['git', '-C', str(ROOT), 'show', args.revision + ':' + path], env=env).decode()
        return (ROOT / path).read_text()

    main_source = read('Telegram-Mac/app/MainViewController.swift')
    account = read('packages/SettingsUI/Sources/SettingsUI/AccountViewController.swift')
    tab = read('packages/TGUIKit/Sources/TabBarController.swift')
    controller = read('packages/TGUIKit/Sources/ViewController.swift')
    assert 'bottomOverlayChanged?()' in body(main_source, 'override var isHidden: Bool')
    assert 'bottomOverlayChanged?()' in body(main_source, 'override func layout()')
    assert 'self?.updateChatListBottomOverlays()' in body(main_source, 'updateController.genericView.bottomOverlayChanged =')
    assert 'self?.updateChatListBottomOverlays()' in body(main_source, 'tabController.didChangedIndex =')
    assert 'updateChatListBottomOverlays()' in body(main_source, 'override func viewDidResized(')
    assert 'searchController.updateContainerContentInsets(containerContentInsets, transition: .immediate)' in body(account, 'private func showSearchController(')
    assert 'updateContainerContentInsets(containerContentInsets, transition: .immediate)' in body(account, 'open override func viewDidLoad()')
    assert 'insets.bottom += contentBottomInset' in body(tab, 'private var contentInsetsForTabs:')
    swift = Path(__file__).with_name('SettingsClearanceTests.swift.in').read_text()
    replacements = {
        '__UPDATE_OVERLAYS__': body(main_source, 'private func updateChatListBottomOverlays()'),
        '__UPDATE_BUTTON_Y__': body(main_source, 'private func updateButtonBottomY('),
        '__ACCOUNT_INSETS__': body(account, 'open override func updateContainerContentInsets('),
        '__BASE_INSETS__': body(controller, 'open func updateContainerContentInsets('),
    }
    for key, value in replacements.items():
        swift = swift.replace(key, value)
    assert not re.search(r'__[A-Z_]+__', swift)

    def run(output):
        source = output / 'main.swift'
        source.write_text(swift)
        binary = output / 'tests'
        print('Extracted overlay/inset methods with native offscreen NSView coordinates; no window or account operations.', flush=True)
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(output / 'module-cache'), str(source), '-o', str(binary)], env=env, check=True)
        subprocess.run([str(binary)], env=env, check=True)

    if args.output_dir:
        output = args.output_dir.absolute()
        output.mkdir(parents=True, exist_ok=False)
        run(output)
    else:
        with tempfile.TemporaryDirectory(prefix='settings-clearance-') as directory:
            run(Path(directory))


if __name__ == '__main__':
    main()
