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


alerts = (root / 'packages/AlertsUI/Sources/AlertsUI/PeerHistoryAlerts.swift').read_text()
modal = (root / 'packages/TranslateUI/Sources/TranslateUI/TranslateModalController.swift').read_text()
texts = section(alerts, 'public func protectedCopyText(_ peer: Peer)', 'public func showProtectedCopyAlert(_ message: Message')
row_file = (root / 'packages/TranslateUI/Sources/TranslateUI/TranslateTableRowItem.swift').read_text()
page = (root / 'packages/ChatUI/Sources/ChatUI/InstantPageV2View.swift').read_text()
text_view = (root / 'packages/TGUIKit/Sources/TextView.swift').read_text()
assert 'initialState.canCopy = messageId == nil' in modal
assert 'current.canCopy = item.canCopy\n                current.update(layout: richLayout' in row_file
assert 'if self.canCopy, let layout = self.currentLayout {\n            if event.clickCount == 2, self.selectWord' in page
assert 'if self.canCopy, event.clickCount == 1, let layout = self.currentLayout {' in page
assert 'blockHeaderRects.first(where: { $0.0.contains(point) }), layout.mayItems {' in text_view
restriction = section(modal, '        let copyRestriction = context.account.postbox.transaction', '        actionsDisposable.add((copyRestriction |> deliverOnMainQueue)')
row = section(modal, '        if let copyRestriction = state.copyRestriction {', '        if showOriginal {')
update = section(modal, '            updateState { current in\n                var current = current\n                current.canCopy = copyRestriction == nil', '        }))')
fixture = (Path(__file__).with_name('TranslateCopyRestrictionTests.swift.in').read_text()
           .replace('__TEXTS__', texts.replace('public func', 'func'))
           .replace('__RESTRICTION__', restriction)
           .replace('__ROW__', row)
           .replace('__UPDATE__', update))

with tempfile.TemporaryDirectory(prefix='translate-copy-restriction-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
