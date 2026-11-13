import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--ref', help='read the sources at this git ref, for example origin/master')
args = parser.parse_args()
root = args.root


def uncommented(path):
    if args.ref:
        text = subprocess.run(['git', '-C', str(root), 'show', f'{args.ref}:{path}'], capture_output=True, text=True, check=True).stdout
    else:
        text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def block(text, start):
    begin = text.index(start) + len(start)
    depth = 1
    for index in range(begin, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index]
    raise SystemExit(f'no end for {start}')


def function(path, signature):
    return signature + block(uncommented(path), signature) + '}'


apply_rtf = function('packages/InputTextView/Sources/InputTextView/AttributedStringRtf.swift', 'func applyRtf() -> (NSAttributedString, [NSTextAttachment]) {')
trim_new_lines = block(uncommented('packages/TGUIKit/Sources/Extensions.swift'), 'var trimNewLines: NSAttributedString {')
chat_text_attributes = function('packages/InputView/Sources/InputView/ChatTextInputState.swift', 'func chatTextAttributes(from attributedText: NSAttributedString) -> [ChatTextInputAttribute] {')

fixture = (Path(__file__).with_name('PasteRichFormatTests.swift.in').read_text()
           .replace('__TRIM_NEW_LINES__', trim_new_lines)
           .replace('__APPLY_RTF__', apply_rtf)
           .replace('__CHAT_TEXT_ATTRIBUTES__', chat_text_attributes))

with tempfile.TemporaryDirectory(prefix='paste-rich-format-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    try:
        raise SystemExit(subprocess.run([str(binary)], timeout=120).returncode)
    except subprocess.TimeoutExpired:
        print('FAILED: the tests did not finish in 120 s', flush=True)
        raise SystemExit(1)
