import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--rev')
args = parser.parse_args()


def code(relative):
    if args.rev:
        text = subprocess.check_output(['git', '-C', str(root), 'show', args.rev + ':' + relative], text=True)
    else:
        text = (args.root / relative).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def match(text, opening):
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return index
    raise SystemExit('unbalanced braces')


def braced(text, start):
    begin = text.index(start)
    opening = text.index('{', begin)
    return begin, opening, match(text, opening)


def statement(text, start):
    begin, _, end = braced(text, start)
    return text[begin:end + 1]


def closure_body(text, start):
    begin, _, end = braced(text, start)
    return text[begin + len(start):end]


def between(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def found(text, pattern, group=0):
    result = re.search(pattern, text)
    if not result:
        raise SystemExit(f'not found: {pattern}')
    return result.group(group)


state = code('packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatInterfaceState.swift')
accessory = code('packages/ChatUI/Sources/ChatUI/ChatInputAccessory.swift')
controller = code('packages/ChatUI/Sources/ChatUI/ChatController.swift')

struct = statement(state, 'public struct ChatInterfaceState: Codable, Equatable {')
another = statement(accessory, 'let anotherAction = { [weak self] in')
hide_action = statement(accessory, 'let setHideAction:(Bool)->Void = { [weak self] hide in')
hide_caption = statement(accessory, 'let setHideCaption:(Bool)->Void = { [weak self] hide in')
after_sent = statement(controller, 'let _afterSentTransition:(Bool)->Void = { [weak self] flushInput in')

parts = {
    '__PROPERTIES__': between(struct, 'public let historyScrollState: ChatInterfaceHistoryScrollState?', 'public static func parse('),
    '__ENCODE__': statement(struct, 'public func encode(to encoder: Encoder) throws'),
    '__EMPTY_INIT__': statement(struct, 'public init() {'),
    '__INIT__': statement(struct, 'public init(timestamp: Int32, inputState: ChatTextInputState,'),
    '__DECODE__': statement(struct, 'public init(from decoder: Decoder) throws'),
    '__METHODS__': struct[struct.index('public func withUpdatedInputState('):struct.rindex('}')],
    '__DISMISS__': found(accessory, r'dismissForward = \{ \[weak self\] in\s*self\?\.chatInteraction\.update\(\{\$0\.updatedInterfaceState\(\{\$0((?:\.\w+\([^)]*\))+)\}\)\}\)', 1),
    '__ANOTHER__': found(another, r'delay\(0\.15, closure: \{\s*self\?\.chatInteraction\.update\(\{\$0\.updatedInterfaceState\(\{\$0((?:\.\w+\([^)]*\))+)\}\)\}\)', 1),
    '__HIDE_NAMES__': found(hide_action, r'\$0((?:\.withUpdatedHideSendersName\([^)]*\))+)', 1),
    '__HIDE_CAPTION__': closure_body(hide_caption, '$0.updatedInterfaceState { current in'),
    '__AFTER_SENT__': found(after_sent, r'value = value\.withUpdatedReplyMessageId\(nil\)[\s\S]*?\.withoutEditMessage\(\)'),
    '__SEND_OPTIONS__': found(controller, r'let hideNames = presentation\.interfaceState\.hideSendersName\s*let hideCaptions = presentation\.interfaceState\.hideCaptions'),
}

fixture = Path(__file__).with_name('ForwardHideNamesResetTests.swift.in').read_text()
for key, value in parts.items():
    fixture = fixture.replace(key, re.sub(r'\bpublic\s+', '', value))

with tempfile.TemporaryDirectory(prefix='forward-hide-names-reset-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
