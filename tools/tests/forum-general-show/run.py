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


def read(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def model(text, needle, what):
    if needle not in text:
        print(f'model out of date: {what} no longer has {needle!r}')
        raise SystemExit(2)


def block(text, pattern):
    match = re.search(pattern, text)
    if match is None:
        print(f'not found: {pattern}')
        raise SystemExit(2)
    begin = match.start()
    depth = 0
    for index in range(text.index('{', begin), len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return re.sub(r'^(private|public|fileprivate) ', '', text[begin:index + 1])
    raise SystemExit(2)


def between(text, start, *ends):
    begin = text.find(start)
    if begin < 0:
        print(f'not found: {start}')
        raise SystemExit(2)
    found = [index for index in (text.find(end, begin + len(start)) for end in ends) if index >= 0]
    if not found:
        print(f'not found: {ends}')
        raise SystemExit(2)
    return text[begin:min(found)]


entries_ui = read('packages/InputDataUI/Sources/InputDataUI/InputDataControllerEntries.swift')
model(entries_ui, 'data.action != nil ? data.action?() : arguments.select((identifier, value))', 'the .general row of InputDataEntry')
model(entries_ui, 'switchAction: data.switchAction', 'the .general row of InputDataEntry')
controller_ui = read('packages/InputDataUI/Sources/InputDataUI/InputDataController.swift')
model(controller_ui, 'self.validateInput(data: [identifier : value])', 'InputDataController select')
model(controller_ui, 'proccessValidation(self.validateData(data))', 'InputDataController validateInput')
row_view = read('packages/GeneralRows/Sources/GeneralRows/GeneralInteractedRowView.swift')
model(row_view, 'if item.switchAction == nil, let switchView {\n                    switchView.performToggle()', 'the row click of GeneralInteractedRowView')
model(row_view, '(item.switchAction ?? item.action)()', 'the switch of GeneralInteractedRowView')
model(row_view, 'if item.autoswitch, item.switchAction == nil, let switchView = self.switchView {\n                        item.type = .switchable(switchView.isOn)', 'the switch of GeneralInteractedRowView')
model(row_view, 'switchView?.autoswitch = item.autoswitch', 'the switch of GeneralInteractedRowView')
model(row_view, 'switchView?.userInteractionEnabled = item.enabled', 'the switch of GeneralInteractedRowView')
model(row_view, 'open func invokeAction(_ item: GeneralInteractedRowItem) {\n        if item.enabled {', 'the row click of GeneralInteractedRowView')
switch_view = read('packages/TGUIKit/Sources/SwitchView.swift')
model(switch_view, 'visualPosition = (autoswitch ? target : isOn) ? 1 : 0', 'SwitchView settle')
model(switch_view, 'if pendingChange.autoswitch {\n            isOn = pendingChange.target', 'SwitchView finishPendingChange')

source = read('packages/ForumSettingsUI/Sources/ForumSettingsUI/ForumTopicInfoController.swift')
entries_function = block(source, r'private func entries\(_ state: State, arguments: Arguments[^)]*\) -> \[InputDataEntry\]\s*\{')
permission_start = 'let canHideGeneral: Signal<Bool, NoError> = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> map '
if permission_start in source:
    permission = block(source[source.index(permission_start) + len(permission_start):], r'\{')
    can_hide = f'func canHideGeneral(_ peer: EnginePeer?) -> Bool {{\n    let map: (EnginePeer?) -> Bool = {permission}\n    return map(peer)\n}}'
else:
    can_hide = 'func canHideGeneral(_ peer: EnginePeer?) -> Bool {\n    return true\n}'
signal_start = 'let signal = combineLatest('
signal_text = source[source.index(signal_start):]
signal_map = block(signal_text[signal_text.index('|> map ') + len('|> map '):], r'\{')
parameters = signal_map[1:signal_map.index(' in')].split(',')
if len(parameters) == 3:
    render = f'({{ () -> [InputDataEntry] in\n            let map: (State, Bool, Bool) -> InputDataSignalValue = {signal_map}\n            return map(stateValue.with {{ $0 }}, true, canHideGeneral(peer)).entries\n        }})()'
else:
    render = f'({{ () -> [InputDataEntry] in\n            let map: (State, Bool) -> InputDataSignalValue = {signal_map}\n            return map(stateValue.with {{ $0 }}, true).entries\n        }})()'
wired = 'combineLatest(statePromise.get(), emojis.ready.get() |> filter { $0 }, canHideGeneral)' in signal_text.split('\n', 1)[0]
ids = '\n'.join(re.sub(r'^private ', '', line) for line in source.splitlines() if re.match(r'^private let _id_\w+ = InputDataIdentifier\("\w+"\)$', line))
pieces = {
    '__IDS__': ids,
    '__ARGUMENTS_CLASS__': block(source, r'private final class Arguments\s*\{'),
    '__STATE_STRUCT__': block(source, r'private struct State\s*:\s*Equatable\s*\{'),
    '__ENTRIES__': entries_function,
    '__CAN_HIDE__': can_hide,
    '__RENDER__': render,
    '__PERMISSION_WIRED__': 'true' if wired else 'false',
    '__PURPOSE__': block(source, r'public enum ForumTopicInfoPurpose\s*:\s*Equatable\s*\{'),
    '__INITIAL_STATE__': between(source, 'let initialState: State', 'let statePromise'),
    '__ARGUMENTS_INIT__': between(source, 'let arguments = Arguments(', 'let canHideGeneral', 'let signal = combineLatest('),
    '__EDIT_CHECKS__': between(source, 'return InputDataSignalValue(entries: entries(state, arguments: arguments', 'let controller = InputDataController(').split('\n', 2)[2],
    '__CONTROLLER__': between(source, 'let controller = InputDataController(', 'controller.validateData ='),
    '__VALIDATE__': between(source, 'controller.validateData =', 'controller.onDeinit'),
}

fixture = Path(__file__).with_name('ForumGeneralShowTests.swift.in').read_text()
for key, value in pieces.items():
    fixture = fixture.replace(key, value)

with tempfile.TemporaryDirectory(prefix='forum-general-show-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
