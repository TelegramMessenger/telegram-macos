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
controller_ui = read('packages/InputDataUI/Sources/InputDataUI/InputDataController.swift')
model(controller_ui, 'self.validateInput(data: [identifier : value])', 'InputDataController select')
model(controller_ui, 'proccessValidation(self.validateData(data))', 'InputDataController validateInput')
model(controller_ui, 'if event.type == .keyDown, containsString.isEmpty || autoInputAction {\n                        self.validateInput(data: self.fetchData())', 'InputDataController returnKeyAction')
model(controller_ui, 'let result = self.updateDoneValue(self.fetchData())', 'InputDataController Done state')
topics = read('packages/ChatListUI/Sources/ChatListUI/ForumUIMethods.swift')
model(topics, 'mimeType: "bundle/jpeg"', 'ForumUI.makeIconFile for General')
model(topics, 'mimeType: "bundle/topic"', 'ForumUI.makeIconFile for letter icons')

source = read('packages/ForumSettingsUI/Sources/ForumSettingsUI/ForumTopicInfoController.swift')
model(source, 'controller.autoInputAction = true', 'ForumTopicInfoController')
signal_text = source[source.index('let signal = combineLatest('):]
signal_map = block(signal_text[signal_text.index('|> map ') + len('|> map '):], r'\{')
render = f'({{ () -> [InputDataEntry] in\n            let map: (State, Bool) -> InputDataSignalValue = {signal_map}\n            return map(stateValue.with {{ $0 }}, true).entries\n        }})()'
ids = '\n'.join(re.sub(r'^private ', '', line) for line in source.splitlines() if re.match(r'^private let _id_\w+ = InputDataIdentifier\("\w+"\)$', line))
pieces = {
    '__IDS__': ids,
    '__ARGUMENTS_CLASS__': block(source, r'private final class Arguments\s*\{'),
    '__STATE_STRUCT__': block(source, r'private struct State\s*:\s*Equatable\s*\{'),
    '__ENTRIES__': block(source, r'private func entries\(_ state: State, arguments: Arguments[^)]*\) -> \[InputDataEntry\]\s*\{'),
    '__PURPOSE__': block(source, r'public enum ForumTopicInfoPurpose\s*:\s*Equatable\s*\{'),
    '__RENDER__': render,
    '__INITIAL_STATE__': between(source, 'let initialState: State', 'let statePromise'),
    '__ARGUMENTS_INIT__': between(source, 'let arguments = Arguments(', 'let signal = combineLatest('),
    '__EDIT_CHECKS__': between(source, 'return InputDataSignalValue(entries: entries(state, arguments: arguments', 'let controller = InputDataController(').split('\n', 2)[2],
    '__CONTROLLER__': between(source, 'let controller = InputDataController(', 'controller.validateData ='),
    '__VALIDATE__': between(source, 'controller.validateData =', 'controller.onDeinit'),
}

fixture = Path(__file__).with_name('ForumTopicDoneTests.swift.in').read_text()
for key, value in pieces.items():
    fixture = fixture.replace(key, value)

with tempfile.TemporaryDirectory(prefix='forum-topic-done-unchanged-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
