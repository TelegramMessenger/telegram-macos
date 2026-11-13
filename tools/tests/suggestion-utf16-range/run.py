import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--rev', help='read the four files that replace the query from this git revision instead of the working tree')
args = parser.parse_args()
root = args.root

HELPER = 'packages/ChatUI/Sources/ChatUI/InputContextHelper.swift'
CHAT = 'packages/ChatUI/Sources/ChatUI/ChatController.swift'
PREVIEW = 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift'
SHARE = 'packages/ShareUI/Sources/ShareUI/ShareModalController.swift'
QUERY = 'packages/ChatUI/Sources/ChatUI/ChatInterfaceInputContext.swift'
COMMAND = 'packages/ChatUI/Sources/ChatUI/TelegramCommandAutocomplete.swift'
STRINGS = 'packages/Strings/Sources/Strings/Strings.swift'
SITES = (HELPER, CHAT, PREVIEW, SHARE)
REPLACE = 'if let (range, _, _) = textInputStateContextQueryRangeAndType(textInputState, includeContext: false) {'


def read(path):
    if args.rev and path in SITES:
        return subprocess.check_output(['git', 'show', f'{args.rev}:{path}'], cwd=root, text=True)
    return (root / path).read_text()


def strip_comments(text):
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def block(text, start):
    opening = text.index('{', start)
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise SystemExit(f'no end for the block at {start}')


def body(text, signature):
    return block(text, text.index(signature))


def replacements(path, count):
    text = strip_comments(read(path))
    starts = [match.start() for match in re.finditer(re.escape(REPLACE), text)]
    if len(starts) != count:
        raise SystemExit(f'{path}: expected {count} query replacements, found {len(starts)}')
    blocks = [block(text, start) for start in starts]
    for found in blocks:
        if 'let distance = ' not in found:
            raise SystemExit(f'{path}: a query replacement has no distance')
    return blocks


helper = replacements(HELPER, 5)
chat = replacements(CHAT, 1)
preview = replacements(PREVIEW, 2)
share = replacements(SHARE, 1)

query_text = strip_comments(read(QUERY))
query_start = query_text.index('public struct PossibleContextQueryTypes')
query = query_text[query_start:query_text.index('\n}\n', query_text.index('public func textInputStateContextQueryRangeAndType')) + 2]

command = '\n'.join(line for line in strip_comments(read(COMMAND)).splitlines() if not line.startswith('import '))

strings = strip_comments(read(STRINGS))
scalar = body(strings, 'public extension UnicodeScalar {')

fixture = Path(__file__).with_name('SuggestionUTF16RangeTests.swift.in').read_text()
for key, value in {
    '__GLYPH_COUNT__': body(strings, 'var glyphCount: Int {'),
    '__IS_SINGLE_EMOJI__': body(strings, 'var isSingleEmoji: Bool {'),
    '__CONTAINS_EMOJI__': body(strings, 'var containsEmoji: Bool {'),
    '__CONTAINS_ONLY_EMOJI__': body(strings, 'var containsOnlyEmoji: Bool {'),
    '__UNICODE_SCALAR__': scalar,
    '__COMMAND_AUTOCOMPLETE__': command,
    '__QUERY__': query,
    '__HELPER_RETURN_EMOJI__': helper[0],
    '__HELPER_RETURN_HASHTAG__': helper[1],
    '__HELPER_RETURN_QUICK_HASHTAG__': helper[2],
    '__HELPER_TAB_EMOJI__': helper[3],
    '__HELPER_TAB_HASHTAG__': helper[4],
    '__CHAT_MENTION__': chat[0],
    '__PREVIEW_MENTION_FIRST__': preview[0],
    '__PREVIEW_MENTION_SECOND__': preview[1],
    '__SHARE_MENTION__': share[0],
}.items():
    fixture = fixture.replace(key, value)

with tempfile.TemporaryDirectory(prefix='suggestion-utf16-range-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    code = subprocess.run([str(binary)]).returncode
    if code < 0:
        print(f'the tests crashed with signal {-code}')
        raise SystemExit(1)
    raise SystemExit(code)
