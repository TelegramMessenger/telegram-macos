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


def handler(text, start, end, declaration):
    body = between(text, start, end)
    return declaration + body[len(start):] + '}'


selective = code('SelectivePrivacySettingsController')
privacy = code('PrivacyAndSecurityViewController')

removed = between(selective, 'open override func didRemovedFromStack() {', '\n    }')
removed = removed.split('{', 1)[1].replace('super.didRemovedFromStack()', '')
calls_caller = between(privacy, 'openVoiceCallPrivacy: {', '}, openBioPrivacy:')
caller_keeps_p2p = calls_caller.count('pushControllerImpl(SelectivePrivacySettingsController(') == 1 and \
    'kind: .voiceCalls, current: info.voiceCalls, callSettings: info.voiceCallsP2P,' in calls_caller and \
    'voiceCallsP2P: p2pUpdated ?? value.voiceCallsP2P' in calls_caller

fixture = (Path(__file__).with_name('CallsP2PPrivacyTests.swift.in').read_text()
           .replace('__TYPES__', between(selective, 'public enum SelectivePrivacySettingsKind', 'private final class SelectivePrivacySettingsControllerArguments').replace('private enum', 'enum'))
           .replace('__STATE__', between(selective, 'private struct SelectivePrivacySettingsControllerState', 'private func selectivePrivacySettingsControllerEntries').replace('private struct', 'struct'))
           .replace('__LOAD__', between(selective, 'var initialEnableFor:', 'let actionsDisposable = DisposableSet()'))
           .replace('__OPEN_ENABLE_FOR__', handler(selective, 'openEnableFor: { target in', '}, openDisableFor: { target in', 'let openEnableFor: (SelectivePrivacySettingsPeerTarget) -> Void = { target in'))
           .replace('__OPEN_DISABLE_FOR__', handler(selective, 'openDisableFor: { target in', '}, p2pMode: { mode in', 'let openDisableFor: (SelectivePrivacySettingsPeerTarget) -> Void = { target in'))
           .replace('__P2P_MODE__', handler(selective, 'p2pMode: { mode in', '}, updatePhoneDiscovery:', 'let p2pMode: (SelectivePrivacySettingType) -> Void = { mode in'))
           .replace('__SAVE__', between(selective, 'savePressed = {', 'let signal = statePromise.get()'))
           .replace('__REMOVED__', removed)
           .replace('__CALLER_KEEPS_P2P__', 'true' if caller_keeps_p2p else 'false'))

with tempfile.TemporaryDirectory(prefix='calls-p2p-privacy-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
