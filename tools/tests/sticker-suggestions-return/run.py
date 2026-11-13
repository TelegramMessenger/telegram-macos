import argparse
from pathlib import Path
import re
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


def internal(text):
    return re.sub(r'(?<![\w.])public\s+', '', text)


helper = code('packages/ChatUI/Sources/ChatUI/InputContextHelper.swift')
item = code('packages/ChatUI/Sources/ChatUI/ContextStickerRowItem.swift')
grid = code('packages/InlineMediaGrid/Sources/InlineMediaGrid/PrettyGridUtils.swift')
table = code('packages/TGUIKit/Sources/TableView.swift')
pixels = code('packages/TGUIKit/Sources/UIUtils.swift')

appear = between(helper, 'public override func viewDidAppear(_ animated: Bool) {', '\n    public func invoke() -> KeyHandlerResult {')
handlers = appear.split('super.viewDidAppear(animated)', 1)[1]
invoke = between(helper, '\n    public func invoke() -> KeyHandlerResult {', '\n    public func invokeTab() -> KeyHandlerResult {')
sticker_return = between(invoke, '} else if let selectedItem = selectedItem as? ContextStickerRowItem', '} else if let selectedItem = selectedItem as? ContextSearchMessageItem')

fixture = (Path(__file__).with_name('StickerSuggestionsReturnTests.swift.in').read_text()
           .replace('__PIXELS__', internal(between(pixels, 'public func floorToScreenPixels(_ scaleFactor: CGFloat, _ value: CGFloat) -> CGFloat {', 'public func floorToScreenPixels(_ value: CGFloat)')))
           .replace('__ROWS__', internal(between(grid, 'public struct InputMediaStickersRow :Equatable {', 'public func fitPrettyDimensions')))
           .replace('__MAKE_ROWS__', internal(between(grid, 'public func makeStickerEntries(', 'public func makeMediaEnties(')))
           .replace('__ITEM__', internal(between(item, 'public class ContextStickerRowItem: TableRowItem {', 'public class ContextStickerRowView')))
           .replace('__TABLE__', internal(
               between(table, '    public func selectedItem() -> TableRowItem? {', '    public func isSelected(') +
               between(table, '    public func select(item:TableRowItem, notify:Bool = true, byClick:Bool = false) -> Bool {', '    public func highlight(item:') +
               between(table, '    public func cancelSelection() -> Void {', '    public func cancelHighlight() -> Void {') +
               between(table, '    public func selectNext(_ scroll:Bool = true, _ animated:Bool = false, turnDirection: Bool = true) -> Void {', '    public func highlightNext(') +
               between(table, '    func selectRow(index: Int) {', '    func longAction(index: Int) {')))
           .replace('__HANDLERS__', internal(handlers))
           .replace('__STICKER_RETURN__', internal(sticker_return))
           .replace('__NAVIGATION__', internal(between(helper, '    public func deselectSelectedHorizontalItem() -> Int? {', '    public override func viewWillDisappear')))
           .replace('__DELEGATE__', internal(between(helper, '    public func selectionDidChange(row:Int', '    public func make(with transition'))))

with tempfile.TemporaryDirectory(prefix='sticker-suggestions-return-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-Onone', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    checks = subprocess.run([str(binary)], capture_output=True, text=True)
    lines = checks.stdout.splitlines()
    summary = re.fullmatch(r'(\d+) passed, (\d+) failed', lines[-1]) if lines else None
    count = re.fullmatch(r'cases (\d+)', lines[-2]) if len(lines) > 1 else None
    if checks.returncode not in (0, 1) or not summary or not count:
        print(checks.stdout + checks.stderr)
        raise SystemExit(2)
    expected = []
    for line in lines[:-2]:
        found = re.fullmatch(r'expect (\d+) (\d+) (.+)', line)
        if found:
            expected.append((int(found.group(1)), int(found.group(2)), found.group(3)))
        else:
            print(line)
    if len(expected) != int(count.group(1)):
        raise SystemExit(2)
    passed, failed = int(summary.group(1)), int(summary.group(2))
    names = re.findall(r'Case\(name: "([^"]+)"', fixture)
    for number, sends, finish in expected:
        pressed = subprocess.run([str(binary), '--finish', str(number)], capture_output=True, text=True)
        wanted = f'sent {sends} cleared 1' if sends else 'sent - cleared 0'
        if pressed.returncode == 0 and pressed.stdout.strip() == wanted:
            passed += 1
            continue
        failed += 1
        name = names[number] if number < len(names) else ''
        fatal = next((line.strip() for line in pressed.stderr.splitlines() if 'Fatal error' in line), None)
        if pressed.returncode < 0:
            print(f'FAILED: {number} {name}: {finish} crashed with signal {-pressed.returncode}: {fatal or "no message"}')
        else:
            print(f'FAILED: {number} {name}: {finish} should send {f"sticker {sends}" if sends else "nothing"}, got {pressed.stdout.strip() or pressed.returncode}')
    print(f'{passed} passed, {failed} failed')
    raise SystemExit(0 if failed == 0 else 1)
