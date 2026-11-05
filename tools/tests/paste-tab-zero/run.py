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


def run(binary):
    try:
        return subprocess.run([str(binary)], timeout=120).returncode
    except subprocess.TimeoutExpired:
        print('FAILED: the tests did not finish in 120 s', flush=True)
        return 1


signature = 'func applyRtf() -> (NSAttributedString, [NSTextAttachment]) {'
apply_rtf = signature + block(uncommented('packages/InputTextView/Sources/InputTextView/AttributedStringRtf.swift'), signature) + '}'
trim_new_lines = block(uncommented('packages/TGUIKit/Sources/Extensions.swift'), 'var trimNewLines: NSAttributedString {')

fixture = (Path(__file__).with_name('PasteTabZeroTests.swift.in').read_text()
           .replace('__TRIM_NEW_LINES__', trim_new_lines)
           .replace('__APPLY_RTF__', apply_rtf))

with tempfile.TemporaryDirectory(prefix='paste-tab-zero-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-O', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    older = directory / 'tests-sdk15'
    relabelled = subprocess.run(['xcrun', 'vtool', '-set-version-min', 'macos', '10.13', '15.0', '-replace', '-output', str(older), str(binary)], capture_output=True)
    signed = relabelled.returncode == 0 and subprocess.run(['codesign', '-f', '-s', '-', str(older)], capture_output=True).returncode == 0
    if not signed:
        raise SystemExit(2)
    print('== built with the current SDK', flush=True)
    current = run(binary)
    print('== the same binary labelled as built with the macOS 15 SDK, as AppKit reads RTF for apps built before macOS 26', flush=True)
    previous = run(older)
    raise SystemExit(0 if current == 0 and previous == 0 else 1)
