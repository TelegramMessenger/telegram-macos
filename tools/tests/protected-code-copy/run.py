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


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def optional_section(text, start, end):
    return section(text, start, end) if start in text else ''


def code(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'(?m)^\s*//.*$', '', text)


chat = root / 'packages/ChatUI/Sources/ChatUI'
read = lambda name: code((chat / f'{name}.swift').read_text())
node = read('ChatLayerTextNode')
text_view = code((root / 'packages/TGUIKit/Sources/TextView.swift').read_text())
selection = read('ChatTextSelectionSource')
select_text = read('ChatSelectText')

headers = section(node, '    func updateCodeHeaders() throws {', '    override func updateOwnScale')
copy = section(text_view, '    @objc public func copy(_ sender:Any) -> Void {', '    public func checkEmbeddedUnderSpoiler')
source = section(selection, '    var textLayout: TextViewLayout? {', '    func selectionFrame')
header_click = section(text_view, '            if let blockHeader = blockHeaderRects.first(where: { $0.0.contains(point) })', '            } else if event.clickCount == 3, isSelectable {') + '            }\n'
restriction = optional_section(select_text, 'func showCopyRestriction(', '\npublic struct SelectContainer')
fallback = '''func showCopyRestriction(_ message: Message, chatInteraction: ChatInteraction) -> Bool { return false }
func restrictCopying(_ interactions: TextViewInteractions, message: Message, layout: TextViewLayout, chatInteraction: ChatInteraction) {}
func restrictCopying(_ interactions: TextViewInteractions, message: Message, layout: FoldingTextLayout, chatInteraction: ChatInteraction) {}
'''
if 'func restrictCopying(' not in restriction:
    restriction = restriction.replace('func showCopyRestriction(', 'func _unusedShowCopyRestriction(') + fallback

fixture = (Path(__file__).with_name('ProtectedCodeCopyTests.swift.in').read_text()
           .replace('__HEADERS__', headers.replace('private func', 'func'))
           .replace('__COPY__', copy.replace('@objc public func', 'func'))
           .replace('__SOURCE__', source)
           .replace('__HEADER_CLICK__', header_click)
           .replace('__RESTRICTION__', restriction))

checks = []


def check(name, passed):
    checks.append((name, bool(passed)))


def ordered(text, *parts):
    offset = 0
    for part in parts:
        found = text.find(part, offset)
        if found < 0:
            return False
        offset = found + len(part)
    return True


message_item = read('ChatMessageItem')
check('message-text-gets-the-restriction', ordered(message_item, 'interactions.copy = {', 'restrictCopying(interactions, message: message, layout: textLayout, chatInteraction: chatInteraction)', 'textLayout.set(interactions)'))
check('message-text-restriction-wraps-the-ad-link-handler', ordered(message_item, 'interactions.processURL = {', 'restrictCopying(interactions, message: message, layout: textLayout'))
for name, owner in (('ChatMediaItem', 'media'), ('ChatMediaPaidContentItem', 'paid'), ('ChatGroupedItem', 'grouped')):
    check(f'{owner}-caption-gets-the-restriction', 'restrictCopying(interactions, message: layout.message, layout: layout.layout, chatInteraction: self.chatInteraction)' in read(name))
for name, owner in (('ChatVoiceRowItem', 'voice'), ('ChatVideoMessageItem', 'video')):
    check(f'{owner}-transcription-gets-the-restriction', ordered(read(name), 'let layout = TextViewLayout(attr,', 'restrictCopying(layout.interactions, message: message, layout: layout, chatInteraction: chatInteraction)', 'return layout'))
check('contact-caption-gets-the-restriction', ordered(read('ChatContactRowItem'), 'takeLayout: { [self] string in', 'restrictCopying(textLayout.interactions, message: message, layout: textLayout, chatInteraction: chatInteraction)', 'return textLayout'))
check('layer-copy-command-shows-the-notice', re.search(r'if command == #selector\(ChatLayerSceneView\.copy\(_:\)\) \{\s*guard layout\.mayItems else \{\s*_ = layout\.interactions\.copy\?\(\)\s*return true\s*\}', node))
selection_copy = section(select_text, '} else if let chatInteraction = self.chatInteraction {', 'copyToClipboard(text)')
check('selected-messages-arrive-on-the-main-queue', '|> deliverOnMainQueue).start(next: { messages in' in selection_copy)
check('selected-protected-messages-show-the-notice', ordered(selection_copy, 'messages.first(where: { $0.isCopyProtected(cachedData: cachedData) })', 'showProtectedCopyAlert(blocked, for: window)'))
reply_line = section(select_text, 'func copiedMessageReplyLine(', '\npublic class SelectManager')
check('reply-line-leaves-out-protected-text', ordered(reply_line, 'let title = ', 'if replied.isCopyProtected(cachedData: nil) {', 'return title', '}', 'let source = '))
check('selected-protected-messages-are-left-out', ordered(selection_copy, 'let messages = messages.filter { !$0.isCopyProtected(cachedData: cachedData) }', 'guard !messages.isEmpty else', 'for message in messages'))
poll = read('ChatPollItem')
blocked = optional_section(poll, 'fileprivate func copyBlocked() -> Bool {', 'fileprivate var canCopyText')
check('poll-copy-shows-the-notice', ordered(blocked, 'guard !self.canCopyText else {', 'return false', 'showCopyRestriction(message, chatInteraction: self.chatInteraction)', 'return true'))
check('poll-text-copy-uses-it-everywhere', poll.count('return self?.copyBlocked() ?? true') == 3 and 'return self?.canCopyText != true' not in poll)
check('poll-inline-code-shows-the-notice', ordered(poll, 'if case .code = makeLinkType((link, "")), self?.canCopyText != true {', '_ = self?.copyBlocked()', 'return'))

with tempfile.TemporaryDirectory(prefix='protected-code-copy-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True)

lines = result.stdout.splitlines()
summary = lines.pop() if lines and 'passed;' in lines[-1] else ''
print('\n'.join(lines))
for name, passed in checks:
    print(f"{'PASS' if passed else 'FAIL'} {name}")
swift = re.match(r'(\d+) passed; (\d+) failed', summary)
passed = int(swift.group(1)) if swift else 0
failed = int(swift.group(2)) if swift else 1
passed += sum(1 for _, ok in checks if ok)
failed += sum(1 for _, ok in checks if not ok)
print(f'{passed} passed; {failed} failed (extracted production code with Foundation adapters and source checks; no application/UI session)')
raise SystemExit(0 if failed == 0 and result.returncode == 0 else 1)
