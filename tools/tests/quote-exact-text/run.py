import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--rev', help='read ChatMessageMenuItems.swift and FoldingTextView.swift from this git revision instead of the working tree')
parser.add_argument('--ios', type=Path, help='a telegram-ios checkout that has the commit this tree pins, if submodules/telegram-ios is not checked out')
args = parser.parse_args()
root = args.root
ios = args.ios or root / 'submodules/telegram-ios'

MENU = 'packages/ChatUI/Sources/ChatUI/ChatMessageMenuItems.swift'
FOLDING = 'packages/InputTextView/Sources/InputTextView/FoldingTextView.swift'
EXTENSIONS = 'packages/TGUIKit/Sources/Extensions.swift'
INPUT = 'packages/InputView/Sources/InputView/ChatTextInputAttribute.swift'
DATES = 'packages/MessageUtils/Sources/MessageUtils/FormattedDateEntities.swift'
ENTITIES = 'submodules/TelegramCore/Sources/SyncCore/SyncCore_TextEntitiesMessageAttribute.swift'


def read(path):
    if path == ENTITIES:
        pinned = subprocess.check_output(['git', 'ls-tree', 'HEAD', 'submodules/telegram-ios'], cwd=root, text=True).split()[2]
        return subprocess.check_output(['git', 'show', f'{pinned}:{path}'], cwd=ios, text=True)
    if args.rev and path in (MENU, FOLDING):
        return subprocess.check_output(['git', 'show', f'{args.rev}:{path}'], cwd=root, text=True)
    return (root / path).read_text()


def strip_comments(text):
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def block(text, signature):
    start = text.index(signature)
    opening = text.index('{', start + len(signature) - 1)
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return re.sub(r'^public ', '', text[start:index + 1]), text[opening + 1:index]
    raise SystemExit(f'no end for {signature}')


menu = strip_comments(read(MENU))
folding = strip_comments(read(FOLDING))
extensions = strip_comments(read(EXTENSIONS))
entities = strip_comments(read(ENTITIES))

handler = block(menu, 'firstBlock.append(ContextMenuItem(strings().chatMessageContextQuote, handler: {')[1]
mapping = block(menu, 'func messageTextRange(of range: NSRange, in shown: NSAttributedString, message: Message) -> NSRange? {')[0] if 'func messageTextRange(' in menu else ''

fixture = (Path(__file__).with_name('QuoteExactTextTests.swift.in').read_text()
           .replace('__HANDLER__', handler)
           .replace('__MESSAGE_TEXT_RANGE__', mapping)
           .replace('__MERGED__', block(folding, 'public var merged: TextViewLayout {')[0])
           .replace('__BREAK_STRING__', block(folding, 'public static func breakString(_ string: NSAttributedString) -> [NSRange] {')[0])
           .replace('__REMOVE_WHITESPACE__', block(extensions, 'func removeWhitespaceFromQuoteAttribute() {')[0])
           .replace('__TRIMMED__', block(extensions, 'var trimmed: NSAttributedString {')[0])
           .replace('__ENTITIES_FOR_TEXT__', block(strip_comments(read(INPUT)), 'public func enititesAttributedStringForText(_ text: NSAttributedString) -> NSAttributedString {')[0])
           .replace('__RESOLVE_DATES__', block(strip_comments(read(DATES)), 'public func resolveFormattedDateEntities(')[0])
           .replace('__ENTITIES_IN_RANGE__', block(entities, 'public func messageTextEntitiesInRange(')[0])
           .replace('__TRIM_WITH_ENTITIES__', block(entities, 'public func trimStringWithEntities(')[0]))

with tempfile.TemporaryDirectory(prefix='quote-exact-text-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
