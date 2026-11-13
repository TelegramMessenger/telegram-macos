import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--show', action='store_true')
args = parser.parse_args()
root = args.root


def skip_string(text, index):
    if text.startswith('"""', index):
        return text.index('"""', index + 3) + 3
    index += 1
    while text[index] != '"':
        index += 2 if text[index] == '\\' else 1
    return index + 1


def matching_brace(text, index):
    depth = 0
    while index < len(text):
        char = text[index]
        if char == '"':
            index = skip_string(text, index)
            continue
        if text.startswith('//', index):
            index = text.index('\n', index)
            continue
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    raise SystemExit('unbalanced braces')


def statement(text, start):
    end = matching_brace(text, text.index('{', start))
    rest = text[end:]
    following = re.match(r'\s*else\s*', rest)
    if following:
        end = matching_brace(text, end + following.end())
    return text[start:end]


def plain(text):
    text = re.sub(r'^import .*$', '', text, flags=re.M)
    return re.sub(r'\bpublic ', '', text)


def hand_backs(text):
    found = []
    for match in re.finditer(r'let attributes = chatTextAttributes\(from: TextEntitiesMessageAttribute\(entities: entities\)\)', text):
        restored = text.index('let restored = ChatTextInputState(attributedText:', match.start())
        body = text[match.start():text.index('\n', restored)]
        if 'makeAttributeString(addPreAsBlock: true)' in body:
            found.append(body)
    return found


state = plain((root / 'packages/InputView/Sources/InputView/ChatTextInputState.swift').read_text())

attributes = (root / 'packages/InputView/Sources/InputView/ChatTextInputAttribute.swift').read_text()
attributes = plain(attributes[:attributes.index('public func refreshChatTextInputTypingAttributes')])

updated = plain((root / 'packages/InputView/Sources/InputView/UpdatedChatTextInputState.swift').read_text())

view = (root / 'packages/TGUIKit/Sources/TextView.swift').read_text()
keys = plain(statement(view, view.index('public struct TextInputAttributes {')))

interface = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatInterfaceState.swift').read_text()
edit = interface[interface.index('public final class ChatEditState'):]
seed = statement(edit, edit.index('if let state = state {'))

extensions = (root / 'packages/TGUIKit/Sources/Extensions.swift').read_text()
trimmed = statement(extensions, extensions.index('var trimmed: NSAttributedString {'))

editor = hand_backs((root / 'packages/ChatUI/Sources/ChatUI/RichTextEditorWindowController.swift').read_text())
if len(editor) != 2:
    print(f'FAIL expected two article editor paths that hand fenced text back, found {len(editor)}')
    raise SystemExit(1)
functions = '\n\n'.join(f'func articleEditorHandBack{index}(text: String, entities: [MessageTextEntity], origin: AnalyticsOrigin) -> ChatTextInputState {{\n{body}\n    return restored\n}}' for index, body in enumerate(editor))
functions += '\n\nlet articleEditorHandBacks: [(String, [MessageTextEntity], AnalyticsOrigin) -> ChatTextInputState] = [' + ', '.join(f'articleEditorHandBack{index}' for index in range(len(editor))) + ']'

here = Path(__file__).resolve().parent
fixture = ((here / 'EditQuoteCodeBlockTests.swift.in').read_text()
           .replace('__TRIMMED__', trimmed)
           .replace('__TEXT_INPUT_ATTRIBUTES__', keys)
           .replace('__INPUT_ATTRIBUTES__', attributes)
           .replace('__UPDATED_STATE__', updated)
           .replace('__SEED__', seed)
           .replace('__HAND_BACKS__', functions)
           .replace('__SHOW__', 'true' if args.show else 'false')
           .replace('__STATE__', state))

with tempfile.TemporaryDirectory(prefix='edit-quote-code-block-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    built = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], capture_output=True, text=True)
    if built.returncode != 0:
        print('FAIL the extracted code does not compile')
        print(built.stderr[-3000:])
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
