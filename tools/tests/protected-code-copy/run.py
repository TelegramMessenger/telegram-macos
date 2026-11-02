import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


node = (root / 'packages/ChatUI/Sources/ChatUI/ChatLayerTextNode.swift').read_text()
text_view = (root / 'packages/TGUIKit/Sources/TextView.swift').read_text()
selection = (root / 'packages/ChatUI/Sources/ChatUI/ChatTextSelectionSource.swift').read_text()
headers = section(node, '    func updateCodeHeaders() throws {', '    override func updateOwnScale')
copy = section(text_view, '    @objc public func copy(_ sender:Any) -> Void {', '    public func checkEmbeddedUnderSpoiler')
source = section(selection, '    var textLayout: TextViewLayout? {', '    func selectionFrame')
header_guarded = 'blockHeaderRects.first(where: { $0.0.contains(point) }), layout.mayItems {' in text_view
fixture = (Path(__file__).with_name('ProtectedCodeCopyTests.swift.in').read_text()
           .replace('__HEADERS__', headers.replace('private func', 'func'))
           .replace('__COPY__', copy.replace('@objc public func', 'func'))
           .replace('__SOURCE__', source)
           .replace('__HEADER_GUARDED__', 'true' if header_guarded else 'false'))

with tempfile.TemporaryDirectory(prefix='protected-code-copy-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
