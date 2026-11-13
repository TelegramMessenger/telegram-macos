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


messages = code('MessagesPrivacyController')
privacy = code('PrivacyAndSecurityViewController')

caller = between(privacy, 'openMessagesPrivacy: {', '}, openPasscode:')
caller_keeps_exceptions = caller.count('pushControllerImpl(MessagesPrivacyController(') == 1 and \
    'MessagesPrivacyController(context: context, noPaidMessages: info.noPaidMessages, globalSettings: info.globalSettings, updated: { (noPaidMessages, updated) in' in caller and \
    caller.count('noPaidMessages: noPaidMessages,') == 1

fixture = (Path(__file__).with_name('PaidMessagesExceptionsTests.swift.in').read_text()
           .replace('__STATE__', between(messages, 'private struct State', 'private let _id_everyone').replace('private struct', 'struct'))
           .replace('__LOAD__', between(messages, 'let initialState = State(', 'let arguments = Arguments('))
           .replace('__TOGGLE__', handler(messages, 'toggle: { value in', '}, paidMessagesExceptions: {', 'let toggle: (GlobalPrivacySettings.NonContactChatsPrivacy) -> Void = { value in'))
           .replace('__EXCEPTIONS__', handler(messages, 'paidMessagesExceptions: {', '\n    })\n', 'let paidMessagesExceptions: () -> Void = {'))
           .replace('__DISAPPEAR__', between(messages, 'controller.afterDisappear = {', 'return controller'))
           .replace('__CALLER_KEEPS_EXCEPTIONS__', 'true' if caller_keeps_exceptions else 'false'))

with tempfile.TemporaryDirectory(prefix='paid-messages-exceptions-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
