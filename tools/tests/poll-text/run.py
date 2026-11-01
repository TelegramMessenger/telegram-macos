import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--poll-ref')
args = parser.parse_args()
root = args.root


def source(path):
    return (root / path).read_text()


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


poll_path = 'packages/ChatUI/Sources/ChatUI/ChatPollItem.swift'
poll = subprocess.check_output(['git', '-C', str(root), 'show', f'{args.poll_ref}:{poll_path}'], text=True) if args.poll_ref else source(poll_path)
selection = source('packages/ChatUI/Sources/ChatUI/ChatSelectText.swift')
results = source('packages/PollResultsUI/Sources/PollResultsUI/PollResultController.swift')
sticky = source('packages/PollResultsUI/Sources/PollResultsUI/PollResultStickItem.swift')
peer = source('packages/TelegramUtils/Sources/TelegramUtils/PeerExtras.swift')
text = source('packages/TGUIKit/Sources/TextView.swift')
entities = source('packages/ChatUI/Sources/ChatUI/ChatMessageItem.swift')
menu = source('packages/ChatUI/Sources/ChatUI/ChatMessageMenuItems.swift')
assert 'mode.customChatContents == nil, data.textLayout?.0?.selectedRange.hasSelectText != true' in menu
assert 'if !isRichMessage, !(message.media.first is TelegramMediaPoll),' in menu
assert 'source: .selectedText' in menu

assert 'ignoreLinks: !object.additionalData.canHighlightLinks && isIncoming' in poll
assert 'nameLayout.interactions = LinkHooks.shared.globalLinkExecutor()' not in poll
assert 'self.titleText.interactions = LinkHooks.shared.globalLinkExecutor()' not in poll
binding_update = section(poll, '        contentNode.update(with: item, animated: animated)', '\n\n        contentNode.updateLayout').splitlines()[-1].strip()
assert binding_update.startswith('updateTextSelection(')
assert 'super.notify(with: value, oldValue: oldValue, animated: animated)\n        updateTextSelection()' in poll
assert 'if chatTextSelectionDidDrag(from: start, to: location)' in selection
assert 'InputDataEquatable(canCopy)' in results
assert 'canCopyText: { copyPermission.with { $0 } }' in results
assert 'lhs.isTextSelectable == rhs.isTextSelectable' in source('packages/InputDataUI/Sources/InputDataUI/InputDataControllerEntries.swift')
assert 'view.isSelectable = canCopy' in poll
if not args.poll_ref:
    assert binding_update == 'updateTextSelection(updatePermissions: true)'
    assert 'if view.isSelectable' not in poll
assert 'self.textView.textView.isSelectable = item.canCopy' in sticky
assert 'self.textView.textView.userInteractionEnabled = item.canCopy' in sticky
assert 'self.textView.userInteractionEnabled = item.canCopy' in sticky
assert 'self.descriptionText = layout' in poll

fixture = Path(__file__).with_name('PollTextTests.swift.in').read_text()
blocks = {
    '__THRESHOLD__': section(selection, 'func chatTextSelectionDidDrag(', 'public class ChatSelectText'),
    '__GESTURE__': section(poll, '    private var startMouseDownPoint:', '    private var option: PollOption?'),
    '__CLICK__': section(poll, '        set(handler: { [weak self] control in', '    required init?(coder: NSCoder) {').rsplit('    }', 1)[0],
    '__COPY_POLICY__': section(poll, '    fileprivate var canCopyText: Bool', '    public override init('),
    '__PEER_POLICY__': section(peer, '    func isCopyProtected(cachedData:', '    var maybePremiumRequired:'),
    '__INVALIDATE__': section(poll, '    private func updateTextSelection(', '    func menuTextLayout('),
    '__MENU_TARGET__': section(poll, '    func menuTextLayout(', '    public override func canStartTextSelecting'),
    '__BIND_SELECTION__': binding_update,
    '__RESULT_POLICY__': section(results, '        let peer = peerViewMainPeer(peerView)', '        return pollResultEntries'),
    '__QUESTION_COPY__': section(results, '    let interactions =', '    entries.append(.desc'),
    '__OPTION_INTERACTIONS__': section(sticky, '        self.leftLayout.interactions =', '        self.leftAdditionLayout ='),
    '__OPTION_MENU__': section(sticky, '    public override func menuItems(', '    public required init(_ initialSize:'),
    '__TEXT_COPY__': section(text, '    @objc public func copy(_ sender:', '    public func checkEmbeddedUnderSpoiler').replace('@objc public ', ''),
    '__DESCRIPTION_COPY__': section(poll, '            layout.interactions = LinkHooks.shared.globalLinkExecutor()', '        }\n\n        let titleAttr'),
    '__POLL_MENU__': section(poll, '    public override func menuItems(', '    public override func makeContentSize('),
    '__FULL_COPY_ITEM__': section(menu, '                        thirdBlock.append(ContextMenuItem(strings().chatContextCopyText, handler: { [weak textLayout] in', '\n                    }'),
    '__SELECTED_COPY_ITEM__': section(menu, '                        thirdBlock.append(ContextMenuItem(strings().chatCopySelectedText, handler: { [weak textLayout] in', '\n\n                    }'),
    '__LINK_COPY_ITEM__': section(menu, '                    thirdBlock.append(ContextMenuItem(text, handler: { [weak textLayout] in', '\n                } else if !protected'),
    '__ENTITY_FILTER__': section(entities, '        entities = concatMessageAttributes(entities).filter(', '        for entity in resolvedEntities'),
}
for key, value in blocks.items():
    fixture = fixture.replace(key, value)
assert '__' not in fixture

cases = ['click-selection', 'context-selection', 'radial-threshold', 'drag-return', 'intercepted-drag', 'accessibility', 'copy-policy', 'live-protection', 'unchanged-presentation', 'late-protected-selection', 'row-reuse', 'result-permission', 'question-clipboard', 'option-clipboard', 'description-actions', 'description-menu', 'description-menu-lifetime', 'description-protected-menu', 'poll-row-menu', 'incoming-entities']
with tempfile.TemporaryDirectory(prefix='poll-text-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    failed = 0
    for case in cases:
        result = subprocess.run([str(binary), case], capture_output=True, text=True)
        passed = result.returncode == 0
        failed += not passed
        print(f'{"PASS" if passed else "FAIL"} {case}')
        if not passed:
            print(result.stdout + result.stderr)
    print(f'{len(cases) - failed} passed; {failed} failed (extracted production code with Foundation adapters; no application/UI session)')
    raise SystemExit(bool(failed))
