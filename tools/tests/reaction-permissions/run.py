import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=root)
args = parser.parse_args()

def body(source, marker):
    start = source.index(marker) + len(marker)
    depth = 1
    end = start
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end - 1]

rows = (args.source_root / 'packages/ChatUI/Sources/ChatUI/ChatRowItem.swift').read_text()
chips = (args.source_root / 'packages/ChatUI/Sources/ChatUI/ChatReactionsView.swift').read_text()
fixture = Path(__file__).with_name('ReactionPermissionTests.swift').read_text()
fixture = fixture.replace('__CAN_REACT__', body(rows, 'public var canReact: Bool {'))
if 'private var reactionPermissionPeer: Peer? {' in rows:
    permission_peer = body(rows, 'private var reactionPermissionPeer: Peer? {')
else:
    selector = next(line.strip() for line in rows.splitlines() if 'let peer = chatInteraction.peer.flatMap' in line)
    permission_peer = 'guard let message = firstMessage else { return nil }\n' + selector.replace('let peer =', 'return', 1)
fixture = fixture.replace('__REACTION_PEER__', permission_peer)
fixture = fixture.replace('__CHIP_ACTION__', body(chips, 'action: { value, isFilterTag in'))
stars = body(rows, '}, starReact: {').replace(' [weak self] in', '', 1)
fixture = fixture.replace('__STAR_ACTION__', stars)
fixture = fixture.replace('__QUICK_ACTION__', body(rows, 'public func reactAction() -> Bool {'))
apply_guard = next((line.strip() for line in rows.splitlines() if 'let canApplyReaction: () -> Bool =' in line), 'let canApplyReaction: () -> Bool = { true }')
fixture = fixture.replace('__CAN_APPLY_REACTION__', apply_guard)
for token, marker in [
    ('__EXPANDED_ACTION__', 'let react: (StickerPackItem, NSRect?, Bool) -> Void = { sticker, fromRect, isLarge in'),
    ('__PICKER_ACTION__', 'list: available, add: { value, checkPrem, fromRect in'),
    ('__LARGE_ACTION__', '}, addLarge: isTags ? nil : { value, fromRect in'),
]:
    fixture = fixture.replace(token, body(rows, marker))

with tempfile.TemporaryDirectory(prefix='reaction-permissions-') as temp:
    temp = Path(temp)
    (temp / 'main.swift').write_text(fixture)
    binary = temp / 'tests'
    subprocess.run(['swiftc', str(temp / 'main.swift'), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
