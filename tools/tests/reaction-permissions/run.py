import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=root)
parser.add_argument('--revision')
args = parser.parse_args()

def body(source, marker):
    start = source.index(marker) + len(marker)
    depth = 1
    end = start
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end - 1]

def source(name):
    path = 'packages/ChatUI/Sources/ChatUI/' + name + '.swift'
    return subprocess.check_output(['git', 'show', args.revision + ':' + path], cwd=args.source_root, text=True) if args.revision else (args.source_root / path).read_text()

rows = source('ChatRowItem')
chips = source('ChatReactionsView')
fixture = Path(__file__).with_name('ReactionPermissionTests.swift').read_text()
fixture = fixture.replace('__MESSAGE_ELIGIBILITY__', body(rows, 'private var reactionMessageIsEligible: Bool {') if 'private var reactionMessageIsEligible: Bool {' in rows else body(rows, 'private var isReactable: Bool {') if 'private var isReactable: Bool {' in rows else body(rows, 'public var canReact: Bool {'))
fixture = fixture.replace('__APPLICATION_PERMISSION__', body(rows, 'private var reactionApplicationPermission: () -> Bool {') if 'private var reactionApplicationPermission: () -> Bool {' in rows else 'return reactionPermission')
fixture = fixture.replace('__MESSAGE_ACTION__', body(rows, 'private var reactionMessageAction: (@escaping (Message) -> Void) -> Void {') if 'private var reactionMessageAction:' in rows else 'return { action in if let message = self.firstMessage { action(message) } }')
fixture = fixture.replace('__PAID_ACTION__', body(rows, 'let applyStarsReaction: (NSRect?) -> Void = {') if 'let applyStarsReaction:' in rows else 'fromRect in context.reactions.sendStarsReaction(message.id, count: 1, fromRect: fromRect)')
presentation = source('ChatPresentationInterfaceState')
fixture = fixture.replace('__PRESENTATION_PERMISSION__', body(presentation, 'public func canSendReactions(to peer: Peer) -> Bool {'))
fixture = fixture.replace('__BASELINE_ELIGIBILITY__', body(rows, 'private var isReactable: Bool {') if 'private var isReactable: Bool {' in rows else 'return reactionMessageIsEligible')
fixture = fixture.replace('__BASELINE_PERMISSION__', body(rows, 'private var canSendReactionsHere: Bool {') if 'private var canSendReactionsHere: Bool {' in rows else 'return canSendReactions')
fixture = fixture.replace('__CAN_REACT__', body(rows, 'public var canReact: Bool {'))
permission = body(rows, 'private var canSendReactions: Bool {') if 'private var canSendReactions: Bool {' in rows else 'return canSendReactionsHere' if 'private var canSendReactionsHere: Bool {' in rows else 'guard let peer = reactionPermissionPeer else { return false }; return canSendReactionsToPeer(EnginePeer(peer))'
fixture = fixture.replace('__CAN_SEND_REACTIONS__', permission)
reaction_permission = body(rows, 'private var reactionPermission: () -> Bool {') if 'private var reactionPermission: () -> Bool {' in rows else 'return { [weak self] in self?.canSendReactions == true }'
fixture = fixture.replace('__REACTION_PERMISSION__', reaction_permission)
layout_start = rows.find('canSendReactions: ', rows.index('let layout = ChatReactionsLayout'))
layout_permission = rows[layout_start + len('canSendReactions: '):rows.index(', openInfo:', layout_start)] if layout_start >= 0 else '{ [weak self] in self?.canSendReactions == true }'
fixture = fixture.replace('__LAYOUT_PERMISSION__', layout_permission)
if 'private var reactionPermissionPeer: Peer? {' in rows:
    permission_peer = body(rows, 'private var reactionPermissionPeer: Peer? {')
else:
    permission_peer = 'guard let message = firstMessage else { return nil }; return chatInteraction.peer.flatMap { $0.id == message.id.peerId ? $0 : nil } ?? message.peers[message.id.peerId]'
fixture = fixture.replace('__REACTION_PEER__', permission_peer)
fixture = fixture.replace('__CHIP_ACTION__', body(chips, 'action: { value, isFilterTag in'))
stars = body(rows, '}, starReact: {')
fixture = fixture.replace('__STAR_CAPTURE__', ' [weak self] in' if ' [weak self] in' in stars else '')
stars = stars.replace(' [weak self] in', '', 1)
fixture = fixture.replace('__STAR_ACTION__', stars)
fixture = fixture.replace('__QUICK_ACTION__', body(rows, 'public func reactAction() -> Bool {'))
apply_guard = next((line.strip() for line in rows.splitlines() if 'let canApplyReaction: () -> Bool =' in line), 'let canApplyReaction: () -> Bool = { true }')
fixture = fixture.replace('__CAN_APPLY_REACTION__', apply_guard)
fixture = fixture.replace('__LATEST_REACTION__', body(rows, 'let applyReaction: (UpdateMessageReaction, NSRect?, Bool) -> Void = {') if 'let applyReaction: (UpdateMessageReaction, NSRect?, Bool) -> Void = {' in rows else '_, _, _ in return')
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
