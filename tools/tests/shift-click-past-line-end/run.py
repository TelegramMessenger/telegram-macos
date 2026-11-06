import argparse
from pathlib import Path
import re
import signal
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def code(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def between(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def block(text, start):
    begin = text.index(start)
    depth = 0
    for index in range(text.index('{', begin), len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index + 1]
    raise ValueError(start)


def internal(text):
    return re.sub(r'(?<![\w.])(public|fileprivate|open)\s+', '', text)


def lines_up_to(text, marker, count):
    lines = text.splitlines()
    index = next(number for number, line in enumerate(lines) if marker in line)
    return '\n'.join(lines[index - count + 1:index + 1])


text_view = code('packages/TGUIKit/Sources/TextView.swift')
extensions = code('packages/TGUIKit/Sources/Extensions.swift')
folding = code('packages/InputTextView/Sources/InputTextView/FoldingTextView.swift')
menu = code('packages/ChatUI/Sources/ChatUI/ChatMessageMenuItems.swift')
layer = code('packages/ChatUI/Sources/ChatUI/ChatLayerTextNode.swift')

shift_marker = 'layout.selectedRange.hasSelectText && event.clickCount == 1 && event.modifierFlags.contains(.shift) {'
layer_marker = 'event.modifiers.contains(.shift), layout.selectedRange.hasSelectText {'
copy_marker = 'thirdBlock.append(ContextMenuItem(strings().chatCopySelectedText, handler: { [weak textLayout] in'

fixture = (Path(__file__).with_name('ShiftClickPastLineEndTests.swift.in').read_text()
           .replace('__RANGE__', between(extensions, '    var min:Int {', '    var isEmpty: Bool {'))
           .replace('__OFFSET__', block(extensions, '    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {'))
           .replace('__ALIGNMENT__', internal(block(text_view, 'public enum CursorSelectAlignment {')))
           .replace('__SELECTED_RANGE__', internal(block(text_view, 'public struct TextSelectedRange: Equatable {')))
           .replace('__SELECTED_RANGE_EQUAL__', internal(block(text_view, 'public func ==(lhs:TextSelectedRange, rhs:TextSelectedRange) -> Bool {')))
           .replace('__FIND_INDEX__', internal(block(text_view, '    public func findIndex(location: NSPoint) -> Int {')))
           .replace('__FIND_CHARACTER_INDEX__', internal(block(text_view, '    public func findCharacterIndex(at point:NSPoint) -> Int {')))
           .replace('__SHIFT_CLICK__', 'if ' + block(text_view, shift_marker))
           .replace('__LAYER_SHIFT_CLICK__', block(layer[layer.index(layer_marker):], 'if index >= 0 {'))
           .replace('__COPY__', internal(block(text_view, '    @objc public func copy(_ sender:Any) -> Void {')).replace('NSPasteboard.general', 'testPasteboard'))
           .replace('__MERGED__', internal(block(folding, '    public var merged: TextViewLayout {')))
           .replace('__QUOTE__', lines_up_to(menu, 'let selectedString = layout.attributedString.attributedSubstring(from: selectedRange)', 3))
           .replace('__COPY_SELECTED__', between(menu, copy_marker, '}, itemImage: MenuAnimation.menu_copy.value))')[len(copy_marker):].replace('NSPasteboard.general', 'testPasteboard')))

with tempfile.TemporaryDirectory(prefix='shift-click-past-line-end-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-Onone', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    listed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    cases = listed.stdout.split()
    if listed.returncode != 0 or not cases:
        print(listed.stdout + listed.stderr)
        raise SystemExit(2)
    passed = failed = 0
    for case in cases:
        try:
            result = subprocess.run([str(binary), case], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            print(f'the case {case} did not finish in 60 s')
            raise SystemExit(2)
        consumer = None
        for line in result.stdout.splitlines():
            if line.startswith('at '):
                consumer = line[3:]
                continue
            print(line)
            if line.startswith('ok '):
                passed += 1
            elif line.startswith('FAIL '):
                failed += 1
        if result.returncode < 0:
            reason = next((line.strip() for line in result.stderr.splitlines() if 'NSRangeException' in line or 'Fatal error' in line or 'reason:' in line), '')
            print(f'FAIL {case}: crashed in {consumer} with {signal.Signals(-result.returncode).name} {reason}'.rstrip())
            failed += 1
        elif result.returncode not in (0, 1):
            print(result.stdout + result.stderr)
            raise SystemExit(2)
    print(f'{passed} passed, {failed} failed')
    raise SystemExit(1 if failed else 0)
