import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--signal-kit', type=Path, default=root / 'submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit2/Source')
args = parser.parse_args()
root = args.root


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def assert_before(text, first, second):
    assert text.index(first) < text.index(second), f'{first} must come before {second}'


manager = (root / 'packages/ChatExportUI/Sources/ChatExportUI/ChatExportManager.swift').read_text()
controller = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
navigation = (root / 'packages/ChatUI/Sources/ChatUI/ChatNavigationHooks.swift').read_text()
hooks = (root / 'Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift').read_text()
export_controller = (root / 'packages/ChatExportUI/Sources/ChatExportUI/ChatExportController.swift').read_text()
if 'chatExportIsRestricted' in manager:
    rules = section(manager, 'public func chatExportIsRestricted', 'public func exportChatToHtml').replace('public func', 'func')
    run_start = section(manager, 'public func run(isVerified: Bool = false) -> Bool {', 'let holder = Atomic<ChatLocationContextHolder?>')
    assert '''if !isVerified {
            let isRestricted = blockingFirst(chatExportVerifiedRestriction(context: context, peerId: peerId), timeout: 30.0) ?? nil
            if isRestricted != false {
                emit(.failed(isRestricted == true ? strings().copyRestrictedChat : chatExportUnverifiedText))
                return false
            }
        }''' in run_start
    assert_before(run_start, 'chatExportVerifiedRestriction', 'destinationURL()')
    full_loop = section(manager, 'for (index, chat) in chats.enumerated() {', 'jsonWriter?.endChat()')
    assert '''let isRestricted = blockingFirst(chatExportVerifiedRestriction(context: context, peerId: chat.peerId), timeout: 30.0) ?? nil
            if isRestricted != false {
                if isRestricted == nil, !isCancelled {
                    failedChats.append(FullExportChatFailure(peer: PeerEquatable(chat.peer), reason: chatExportUnverifiedText))
                }
                continue
            }''' in full_loop
    assert_before(full_loop, 'chatExportVerifiedRestriction', 'jsonWriter?.beginChat(')
    assert 'run.run(isVerified: true)' in full_loop
    assert manager.count('isVerified: true') == 1
    assert 'case let .failed(reason):\n                showModalText(for: context.window, text: reason)\n                self.finish(nil)' in export_controller
    assert 'if chatExportSkipsMessage(entry.message) {\n                    continue\n                }\n                appendMessage(entry.message)' in manager
    assert manager.count('appendMessage(entry.message)') == 1
    assert 'public var canExportChat: (Peer, CachedPeerData?) -> Bool = { _, _ in false }' in navigation
    assert 'hooks.canExportChat = { peer, cachedData in\n        return !chatExportIsRestricted(peer: peer, cachedData: cachedData)\n    }' in hooks
    menu = section(controller, 'if let peer = peerView.peers[peerView.peerId], let mainPeer = peerViewMainPeer(peerView), !mainPeer.isMonoForum {', 'itemImage: MenuAnimation.menu_file.value')
    assert 'if ChatNavigationHooks.shared.canExportChat(peer, peerView.cachedData) {\n                        items.append(ContextMenuItem(ChatNavigationHooks.shared.chatExportMenuTitle(), handler: {' in menu
else:
    rules = '''
func chatExportIsRestricted(peer: Peer, cachedData: CachedPeerData?) -> Bool {
    return false
}

func chatExportVerifiedRestriction(context: any AccountContextProtocol, peerId: PeerId) -> Signal<Bool?, NoError> {
    return .single(false)
}

func chatExportSkipsMessage(_ message: Message) -> Bool {
    return false
}
'''
fixture = Path(__file__).with_name('ProtectedChatExportTests.swift.in').read_text().replace('__RULES__', rules.replace('private func', 'func'))

with tempfile.TemporaryDirectory(prefix='protected-chat-export-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    sources = [str(path) for path in sorted(args.signal_kit.glob('*.swift'))]
    subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), *sources, str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
