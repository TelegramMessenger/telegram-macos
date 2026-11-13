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


def code(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def between(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def line_with(text, needle):
    lines = [line.strip() for line in text.splitlines() if needle in line]
    if len(lines) != 1:
        raise ValueError(f'{len(lines)} lines with {needle!r}')
    return lines[0]


def after(text, label):
    return text.split(label, 1)[1].strip()


try:
    interaction = code('packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift')
    state = code('packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatInterfaceState.swift')
    account = code('Telegram-Mac/account/AccountContext.swift')
    history_install = code('Telegram-Mac/packages-integration/hooks/ChatHistoryModelHooksInstall.swift')
    interface_install = code('Telegram-Mac/packages-integration/hooks/ChatInterfaceHooksInstall.swift')
    history_hooks = code('packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatHistoryModelHooks.swift')
    interface_hooks = code('packages/ChatUI/Sources/ChatUI/ChatInterfaceHooks.swift')
    controller = code('packages/ChatUI/Sources/ChatUI/ChatController.swift')
    history_view = code('packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatHistoryViewForLocation.swift')

    parts = {
        '__TEMP_STATE__': between(state, 'public struct ChatInterfaceTempState', 'public struct ChatInterfaceState: Codable').replace('public ', ''),
        '__PARSE__': between(state, '    public static func parse(', '    public func encode(to encoder: Encoder)').replace('public static func parse(', 'static func parse('),
        '__SAVE_STATE__': between(interaction, '    public func saveState(', '    deinit {').replace('public func saveState(', 'func saveState('),
        '__TEMP_STORE__': line_with(account, 'private var chatInterfaceTempState:'),
        '__TEMP_ACCESS__': between(account, '    func setChatInterfaceTempState(', '    var premiumLimits:'),
        '__GET_INSTALL__': after(between(history_install, 'getChatInterfaceTempState: {', '}, isLite:'), 'getChatInterfaceTempState:') + '\n}',
        '__SET_INSTALL__': after(between(interface_install, 'setChatInterfaceTempState: {', '}, inputSource:'), 'setChatInterfaceTempState:') + '\n}',
        '__GET_TYPE__': after(line_with(history_hooks, 'public let getChatInterfaceTempState:'), 'public let getChatInterfaceTempState:'),
        '__SET_TYPE__': after(line_with(interface_hooks, 'public let setChatInterfaceTempState:'), 'public let setChatInterfaceTempState:'),
        '__CONTROLLER_PARSE__': line_with(controller, 'ChatInterfaceState.parse('),
        '__HISTORY_PARSE__': line_with(history_view, 'ChatInterfaceState.parse('),
    }
except ValueError as error:
    print(f'the source changed shape: {error}')
    raise SystemExit(2)

fixture = Path(__file__).with_name('ForumEditPerTopicTests.swift.in').read_text()
for name, body in parts.items():
    fixture = fixture.replace(name, body)

with tempfile.TemporaryDirectory(prefix='forum-edit-per-topic-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
