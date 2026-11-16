import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def code(name):
    text = (root / f'packages/SettingsUI/Sources/SettingsUI/{name}.swift').read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def between(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


selective = code('SelectivePrivacySettingsController')
messages = code('MessagesPrivacyController')
privacy = code('PrivacyAndSecurityViewController')

removed = between(selective, 'open override func didRemovedFromStack() {', '\n    }')
removed = removed.split('{', 1)[1].replace('super.didRemovedFromStack()', '')
pages = privacy.count('pushControllerImpl(SelectivePrivacySettingsController(')
callers_keep_fresh_values = pages == privacy.count('globalSettings: globalSettings ?? value.globalSettings') and \
    privacy.count('voiceCallsP2P: p2pUpdated') == privacy.count('voiceCallsP2P: p2pUpdated ?? value.voiceCallsP2P')

fixture = (Path(__file__).with_name('PrivacyPageSaveTests.swift.in').read_text()
           .replace('__TYPES__', between(selective, 'public enum SelectivePrivacySettingsKind', 'enum SelectivePrivacySettingsPeerTarget').replace('private enum', 'enum'))
           .replace('__STATE__', between(selective, 'private struct SelectivePrivacySettingsControllerState', 'private func selectivePrivacySettingsControllerEntries').replace('private struct', 'struct'))
           .replace('__LOAD__', between(selective, 'var initialEnableFor:', 'let actionsDisposable = DisposableSet()'))
           .replace('__SAVE__', between(selective, 'savePressed = {', 'let signal = statePromise.get()'))
           .replace('__REMOVED__', removed)
           .replace('__MESSAGES_STATE__', between(messages, 'private struct State', 'private let _id_everyone').replace('private struct', 'struct'))
           .replace('__MESSAGES_LOAD__', between(messages, 'let initialState = State(', 'let arguments = Arguments('))
           .replace('__MESSAGES_DISAPPEAR__', between(messages, 'controller.afterDisappear = {', 'return controller'))
           .replace('__CALLERS_KEEP_FRESH_VALUES__', 'true' if callers_keep_fresh_values else 'false'))

with tempfile.TemporaryDirectory(prefix='privacy-page-save-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
