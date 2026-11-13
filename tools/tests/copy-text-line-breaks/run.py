import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--rev', help='read FoldingTextView.swift from this git revision instead of the working tree')
args = parser.parse_args()
root = args.root

FOLDING = 'packages/InputTextView/Sources/InputTextView/FoldingTextView.swift'
EXTENSIONS = 'packages/TGUIKit/Sources/Extensions.swift'


def read(path):
    if args.rev and path == FOLDING:
        return subprocess.check_output(['git', 'show', f'{args.rev}:{path}'], cwd=root, text=True)
    return (root / path).read_text()


def strip_comments(text):
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def body(text, signature):
    start = text.index(signature)
    opening = text.index('{', start + len(signature) - 1)
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise SystemExit(f'no end for {signature}')


folding = strip_comments(read(FOLDING))
extensions = strip_comments(read(EXTENSIONS))

merged = body(folding, 'public var merged: TextViewLayout {')
breaking = body(folding, 'public static func breakString(_ string: NSAttributedString) -> [NSRange] {')
whitespace = body(extensions, 'func removeWhitespaceFromQuoteAttribute() {')

fixture = (Path(__file__).with_name('CopyTextLineBreaksTests.swift.in').read_text()
           .replace('__MERGED__', merged)
           .replace('__BREAK_STRING__', breaking)
           .replace('__REMOVE_WHITESPACE__', whitespace))

with tempfile.TemporaryDirectory(prefix='copy-text-line-breaks-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
