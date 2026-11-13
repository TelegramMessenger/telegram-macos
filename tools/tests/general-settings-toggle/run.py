import argparse
from pathlib import Path
import os
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline-ref')
parser.add_argument('--emit-only', type=Path)
args = parser.parse_args()


def source(path):
    if args.baseline_ref:
        env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        return subprocess.check_output(['git', 'show', f'{args.baseline_ref}:{path}'], cwd=root, env=env, text=True)
    return (root / path).read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


controller = source('packages/SettingsUI/Sources/SettingsUI/GeneralSettingsViewController.swift')
settings = source('packages/InAppSettings/Sources/InAppSettings/FastSettings.swift')
row_view = source('packages/GeneralRows/Sources/GeneralRows/GeneralInteractedRowView.swift')
switch = source('packages/TGUIKit/Sources/SwitchView.swift')
item_method = block(controller, 'public func item(')
rows = [('enableRFTCopy', 'toggleRTFEnabled'), ('sendLargePhotos', 'toggleLargePhotos'), ('emojiReplacements', 'toggleEmojiReplacements')]
properties = []
callbacks = []
row_cases = []
read_cases = []
for name, argument in rows:
    properties.append(re.search(r'    public let ' + argument + r':[^\n]+', controller).group())
    callbacks.append(block(controller, argument + ': {'))
    case = re.search(r'        case let \.' + name + r'\([^\n]+\):\n(.*?)\n        case ', item_method, re.S).group(1)
    row_cases.append(f'    case .{name}:\n{case}')
    value = re.search(r'entries.append\(\.' + name + r'\(sectionId: sectionId, enabled: (.*?), viewType:', controller).group(1)
    read_cases.append(f'    case .{name}: return {value}')

members = [re.search(r'    private static let ' + key + r' = [^\n]+', settings).group() for key in ['kRTFEnable', 'kPhotoSize', 'kAutomaticConvertEmojiesType']]
for marker in ['public static var enableRTF:', 'public static var sendLargePhotos:', 'public static func sendLargePhotos(', 'public static var isPossibleReplaceEmojies:', 'public static func toggleAutomaticReplaceEmojies(']:
    members.append(block(settings, marker))

invoke = block(row_view, 'open func invokeAction(')
routing_start = invoke.index('            switch item.type {', invoke.index('case let .contextSelector'))
routing_end = invoke.index('            item.action()', routing_start) + len('            item.action()')
replacements = {
    '__SETTINGS__': '\n'.join(members),
    '__PROPERTIES__': '\n'.join(properties),
    '__CALLBACKS__': ',\n'.join(callbacks),
    '__ROW_CASES__': '\n'.join(row_cases),
    '__READ_CASES__': '\n'.join(read_cases),
    '__SWITCH_METHODS__': '\n'.join(block(switch, marker) for marker in ['public func setIsOn(', 'public func performToggle()', 'private func settle(', 'public func finishPendingChange()']),
    '__STATE_CHANGED__': block(row_view, 'switchView?.stateChanged ='),
    '__ROW_ACTION__': invoke[routing_start:routing_end],
}
fixture = Path(__file__).with_name('GeneralSettingsToggleTests.swift.in').read_text()
for marker, value in replacements.items():
    assert fixture.count(marker) == 1, marker
    fixture = fixture.replace(marker, value)
assert not re.search(r'__[A-Z_]+__', fixture)

if args.emit_only:
    args.emit_only.write_text(fixture)
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix='general-settings-toggle-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
