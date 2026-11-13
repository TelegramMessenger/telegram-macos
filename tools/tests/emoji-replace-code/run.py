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


def block(text, start):
    return text[start:matching_brace(text, text.index('{', start))]


def require(text, needle, where):
    if needle not in text:
        print(f'FAIL {where} no longer has `{needle}`; update the harness')
        raise SystemExit(1)
    return text.index(needle)


state = (root / 'packages/InputView/Sources/InputView/ChatTextInputState.swift').read_text()
state = re.sub(r'^import .*$', '', state, flags=re.M)
state = re.sub(r'\bpublic ', '', state)

emoji = (root / 'packages/EmojiReplacements/Sources/EmojiReplacements/EmojiReplacements.swift').read_text()
table = block(emoji, require(emoji, 'let emojiReplacements:[String:String] = {', 'EmojiReplacements.swift')) + '()'
replacements = block(emoji, require(emoji, 'public extension NSAttributedString {', 'EmojiReplacements.swift'))
replacements = re.sub(r'\bpublic ', '', replacements)

extensions = (root / 'packages/TGUIKit/Sources/Extensions.swift').read_text()
trimmed_text = block(extensions, require(extensions, 'var trimmed: NSAttributedString {', 'Extensions.swift'))
trimmed_string = block(extensions, require(extensions, 'var trimmed:String {', 'Extensions.swift'))

sender = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/SenderController.swift').read_text()
start = require(sender, 'var input:ChatTextInputState = input', 'SenderController.swift')
replace = require(sender[start:], 'if FastSettings.isPossibleReplaceEmojies {', 'SenderController.swift') + start
front = sender[start:matching_brace(sender, sender.index('{', replace))]
rest = sender[replace:]
for needle in ['cut_long_message( input.inputText, 4096)', 'let subState = input.subInputState(from: NSMakeRange(inset, message.length))', 'subState.messageTextEntities(', 'dices.emojis.contains(input.inputText)']:
    require(rest, needle, 'Sender.enqueue after the replacement')

here = Path(__file__).resolve().parent
fixture = ((here / 'EmojiReplaceCodeTests.swift.in').read_text()
           .replace('__TRIMMED_TEXT__', trimmed_text)
           .replace('__TRIMMED_STRING__', trimmed_string)
           .replace('__TABLE__', table)
           .replace('__REPLACEMENTS__', replacements)
           .replace('__FRONT__', front)
           .replace('__SHOW__', 'true' if args.show else 'false')
           .replace('__STATE__', state))

with tempfile.TemporaryDirectory(prefix='emoji-replace-code-') as directory:
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
