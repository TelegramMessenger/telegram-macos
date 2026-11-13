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


def code(relative):
    text = (root / relative).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def without_imports(text):
    return '\n'.join(line for line in text.splitlines() if not line.startswith('import ') and not line.startswith('@inline'))


def match(text, opening):
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return index
    raise SystemExit('unbalanced braces')


def braced(text, start):
    begin = text.index(start)
    opening = text.index('{', begin)
    return begin, opening, match(text, opening)


def statement(text, start):
    begin, _, end = braced(text, start)
    return text[begin:end + 1]


def body(text, start):
    _, opening, end = braced(text, start)
    return text[opening + 1:end]


def closure_body(text, start):
    begin, _, end = braced(text, start)
    return text[begin + len(start):end]


def through(text, start, last):
    begin = text.index(start)
    _, _, end = braced(text[begin:], last)
    return text[begin:begin + end + 1]


def if_else(text, start):
    begin, _, end = braced(text, start)
    while text[end + 1:].lstrip().startswith('else'):
        end = match(text, text.index('{', end + 1))
    return text[begin:end + 1]


def line(text, pattern):
    found = re.search(pattern, text)
    if not found:
        raise SystemExit(f'not found: {pattern}')
    return found.group(0)


menu = code('packages/ChatUI/Sources/ChatUI/ChatMessageMenuItems.swift')
interaction = code('packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift')
controller = code('packages/ChatUI/Sources/ChatUI/ChatController.swift')
ui_hooks = code('packages/ChatUI/Sources/ChatUI/ChatUIHooks.swift')
ui_install = code('Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift')
history_hooks = code('packages/ChatUI/Sources/ChatUI/ChatHistoryUIHooks.swift')
history_install = code('Telegram-Mac/packages-integration/hooks/ChatHistoryUIHooksInstall.swift')
share = code('packages/ShareUI/Sources/ShareUI/ShareModalController.swift')
hashtags = code('packages/ChatHistoryModel/Sources/ChatHistoryModel/HashtagSearchGlobalChatContents.swift')

forward_object = share[share.index('public final class ForwardMessagesObject : ShareObject {'):]
single_peer = forward_object[forward_object.index('private func performForward('):]
single_peer = single_peer[single_peer.index('if peerIds.count == 1 {'):]

parts = {
    '__FORWARD_MENU_ACTION__': without_imports(code('packages/ChatUI/Sources/ChatUI/ChatForwardMenuAction.swift')),
    '__DEFERRED_SEND_ACTION__': statement(code('packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift'), 'public final class ChatDeferredSendAction'),
    '__SELECTED_WITH_ALBUMS__': without_imports(code('packages/ChatHistoryModel/Sources/ChatHistoryModel/SelectedMessagesWithAlbums.swift')),
    '__MESSAGE_FOR_FORWARDING__': statement(code('packages/MessageUtils/Sources/MessageUtils/MessageExtras.swift'), 'public func messageForForwarding('),
    '__GET_MESSAGES__': body(interaction, 'public func getMessages(_ messageIds: [MessageId], _ album: Bool)'),
    '__FORWARD_MESSAGES_OBSERVED__': through(interaction, 'public var forwardMessages: ([Message]) -> Void = {_ in}', 'public func forwardMessagesObserved(_ messages: [Message], analyticsContext: AnalyticsContext, entry: AnalyticsFlows.ChatForwardPicker.EntryPoint?, journey: AnalyticsForwardPickerJourney?)'),
    '__CHAT_FORWARD_MESSAGES__': through(controller, 'chatInteraction.forwardMessages = { [weak self] messages in', 'chatInteraction.forwardMessagesWithJourney = { messages, origin, entry, journey in'),
    '__SHARE_MODAL_OBSERVED__': through(ui_hooks, 'public func makeForwardMessagesShareModalObserved(', 'journey: AnalyticsForwardPickerJourney?) -> ModalViewController'),
    '__SHARE_MODAL__': closure_body(ui_install, 'makeForwardMessagesShareModal: { context, messages, getMessages in'),
    '__SHARE_MODAL_WITH_CONTEXT__': closure_body(ui_install, 'hooks.makeForwardMessagesShareModalWithContext = { context, messages, getMessages, analyticsContext in'),
    '__SHARE_MODAL_WITH_SOURCE__': closure_body(ui_install, 'hooks.makeForwardMessagesShareModalWithSource = { context, messages, getMessages, analyticsContext, entry in'),
    '__ATTACH_FORWARD_JOURNEY__': closure_body(ui_install, 'hooks.attachForwardJourney = { controller, journey in'),
    '__OBJECT_OBSERVED__': body(history_hooks, 'public func makeForwardMessagesObjectObserved('),
    '__OBJECT_PLAIN__': closure_body(history_install, 'makeForwardMessagesObject: { context, messages, album, getMessages in'),
    '__OBJECT_WITH_CONTEXT__': closure_body(history_install, 'hooks.makeForwardMessagesObjectWithContext = { context, messages, album, getMessages, analyticsContext in'),
    '__OBJECT_IDS__': statement(forward_object, 'public var messageIds: [MessageId]'),
    '__OBJECT_CONVENIENCE_INIT__': statement(forward_object, 'public convenience init(_ context: any AccountContextProtocol, messages: [Message]'),
    '__OBJECT_INIT__': statement(forward_object, 'public init(_ context: any AccountContextProtocol, messages: [Message]'),
    '__OBJECT_ALBUM__': line(single_peer, r'let album = [^\n]+'),
    '__OBJECT_IDS_LINE__': line(single_peer, r'let messageIds = [^\n]+'),
    '__OBJECT_LOOKUP__': if_else(single_peer, 'let messages: Signal<[Message], NoError>'),
    '__HASHTAG_LOOKUP__': body(hashtags, 'func messagesAtIds(_ ids: [MessageId], album: Bool) -> Signal<[Message], NoError>'),
    '__FORWARD_BLOCK__': statement(menu, 'if canForwardMessage(data.message, chatInteraction: data.chatInteraction), !isService'),
}

fixture = Path(__file__).with_name('ForwardAlbumMoreTests.swift.in').read_text()
for key, value in parts.items():
    fixture = fixture.replace(key, re.sub(r'\bpublic\s+', '', value))

with tempfile.TemporaryDirectory(prefix='forward-album-more-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
