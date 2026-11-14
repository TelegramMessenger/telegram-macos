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


def require(text, needle, where):
    if needle not in text:
        print(f'FAIL {where} no longer has `{needle}`; update the harness')
        raise SystemExit(1)
    return text.index(needle)


def block(text, needle, where):
    start = require(text, needle, where)
    return text[start:matching_brace(text, text.index('{', start))]


def through(text, first, last, where):
    start = require(text, first, where)
    end = require(text[start:], last, where) + start
    return text[start:matching_brace(text, text.index('{', end))]


def plain(code):
    return re.sub(r'\bpublic ', '', code)


input_view = root / 'packages/InputView/Sources/InputView'
text_view = (input_view / 'ChatInputTextView.swift').read_text()
attributes = (input_view / 'ChatTextInputAttribute.swift').read_text()
tgui = (root / 'packages/TGUIKit/Sources/TextView.swift').read_text()

where = 'ChatInputTextView.swift'
class_start = require(text_view, 'public final class InputTextView: BaseTextView', where)
text_class = text_view[class_start:]
properties_start = require(text_class, '    private var quoteContinuation:', where)
properties_end = require(text_class, '    private var initialTypingForegroundColor', where)

pieces = {
    '__INPUT_ATTRIBUTES__': block(tgui, 'public struct TextInputAttributes {', 'TextView.swift'),
    '__UNDO_ITEM__': block(text_view, '@objc public class InputViewUndoItem : NSObject {', where),
    '__ENTER__': block(text_view, 'private func isEnterEvent(', where),
    '__PROPERTIES__': text_class[properties_start:properties_end],
    '__ADD_UNDO__': block(text_class, '@objc func addUndoItem(_ item: InputViewUndoItem) {', where),
    '__REMOVE_UNDO__': block(text_class, '@objc func removeUndoItem(_ item: InputViewUndoItem) {', where),
    '__TYPING__': through(text_class, 'public override func keyDown(with theEvent: NSEvent) {', 'func convertDoubleDashIfNeeded() {', where),
    '__TEXT_DID_CHANGE__': block(text_view, '@objc public func textDidChange(_ notification: Notification) {', where),
    '__LISTS__': through(attributes, 'private let numberedListRegex', 'public func continueBulletListIfNeeded(', 'ChatTextInputAttribute.swift'),
}

fixture = Path(__file__).with_name('NoAutoreplaceInCodeTests.swift.in').read_text()
for placeholder, code in pieces.items():
    fixture = fixture.replace(placeholder, plain(code))
fixture = fixture.replace('__SHOW__', 'true' if args.show else 'false')

with tempfile.TemporaryDirectory(prefix='no-autoreplace-in-code-') as directory:
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
