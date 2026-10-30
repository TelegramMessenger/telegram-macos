from pathlib import Path
import argparse
import re
import subprocess
import tempfile


def declaration(source, marker):
    assert source.count(marker) == 1, marker
    start = source.index(marker)
    masked = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', lambda m: ' ' * len(m.group()), source, flags=re.S)
    opening = masked.index('{', start)
    depth = 1
    for index in range(opening + 1, len(masked)):
        depth += (masked[index] == '{') - (masked[index] == '}')
        if depth == 0:
            return source[start:index + 1]
    raise AssertionError(marker)


parser = argparse.ArgumentParser(description='Run extracted production translation state and actual ChatUI projection tests with model adapters.')
parser.add_argument('--telegram-core', type=Path, help='Existing TelegramCore checkout containing Sources/SyncCore.')
parser.add_argument('--negative-control', action='store_true', help='Include stableVersion in source identity to reproduce version-only invalidation.')
parser.add_argument('--header-source-revision', help='Read only the pinned header update expressions from a Git revision; animation baseline: ea656cf0.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
core = args.telegram_core or root / 'submodules/telegram-ios/submodules/TelegramCore'
if not (core / 'Sources/SyncCore').is_dir():
    parser.error('TelegramCore checkout missing; supply --telegram-core /path/to/TelegramCore')
rich = (core / 'Sources/SyncCore/SyncCore_RichText.swift').read_text()
page = (core / 'Sources/SyncCore/SyncCore_InstantPage.swift').read_text()
rich_decl = rich[rich.index('public indirect enum RichText:'):rich.index('    public init(decoder:')].replace('PostboxCoding, ', '') + '}\n'
rich_decl += '\nextension RichText {\n' + declaration(rich, 'var plainText: String') + '\n}\n'
page_decl = page[page.index('public indirect enum InstantPageBlock:'):page.index('    public init(decoder:')].replace('PostboxCoding, ', '') + '}\n'
models = Path(__file__).with_name('Models.swift.in').read_text().replace('__RICH_TEXT__', rich_decl).replace('__PAGE_BLOCKS__', page_decl)
source = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatLiveTranslateContext.swift').read_text()
presentation = (root / 'packages/ChatUI/Sources/ChatUI/ChatPresentationInterfaceState.swift').read_text()
translation = source[source.index('private func chatTranslationLanguageCode'):source.index('public final class ChatLiveTranslateContext')]
if args.negative_control:
    translation = translation.replace('public struct ChatTranslationSource: Equatable {', 'public struct ChatTranslationSource: Equatable {\n    private let version: UInt32')
    translation = translation.replace('        self.text = message.text', '        self.version = message.stableVersion\n        self.text = message.text')
translation += '\npublic final class ChatLiveTranslateContext {\n' + declaration(source, 'public struct State : Equatable') + '\n}\n'
projection = 'public class ChatPresentationInterfaceState {\n' + declaration(presentation, 'public struct TranslateState : Equatable') + '\n}\n'
tests = []
for path, fixture in [
    ('packages/ChatHistoryModel/Tests/ChatHistoryModelTests/OutgoingChatTranslationTests.swift', '''private func message(_ text: String, incoming: Bool = false, attributes: [MessageAttribute] = [], media: [Media] = [], stableVersion: UInt32 = 0) -> Message {
        return Message(id: MessageId(peerId: chatId, namespace: 0, id: 1), stableVersion: stableVersion, text: text, incoming: incoming, attributes: attributes, media: media)
    }'''),
    ('packages/ChatUI/Tests/ChatUITests/ChatPinnedTranslationPresentationTests.swift', '''private func message(_ text: String = "Pinned text", incoming: Bool = false, version: UInt32 = 0, attributes: [MessageAttribute] = []) -> Message {
        return Message(id: MessageId(peerId: chatId, namespace: 0, id: 1), stableVersion: version, text: text, incoming: incoming, attributes: attributes, media: [])
    }''')
]:
    test = re.sub(r'^(?:@testable )?import .*\n', '', (root / path).read_text(), flags=re.M)
    tests.append(test.replace(declaration(test, 'private func message('), fixture))
header_path = 'packages/ChatUI/Sources/ChatUI/ChatHeaderController.swift'
header = (root / header_path).read_text()
if args.header_source_revision:
    header = subprocess.check_output(['git', '-C', str(root), 'show', args.header_source_revision + ':' + header_path], text=True)
update = declaration(header, '    private func update(_ pinnedMessage: ChatPinnedMessage,')
animation = next(line.strip() for line in update.splitlines() if line.strip().startswith('let animated ='))
rebuild = next(line.strip().removeprefix('if ').removesuffix(' {') for line in update.splitlines() if line.strip().startswith('if pinnedMessage.messageId !='))
animation_tests = Path(__file__).with_name('PinnedAnimationTests.swift.in').read_text()
animation_tests = animation_tests.replace('__ANIMATION_DECISION__', animation).replace('__REBUILD_DECISION__', rebuild)
with tempfile.TemporaryDirectory(prefix='pinned-translation-') as temporary:
    directory = Path(temporary)
    (directory / 'Tests').mkdir()
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PinnedTranslation", platforms: [.macOS(.v10_13)], targets: [.testTarget(name: "PinnedTranslationTests", path: "Tests")])
''')
    (directory / 'Tests/PinnedTranslationTests.swift').write_text('\n'.join([models, translation, projection] + tests))
    (directory / 'Tests/PinnedAnimationTests.swift').write_text(animation_tests)
    result = subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4'])
    if result.returncode:
        raise SystemExit(result.returncode)
    availability = directory / 'Availability.swift'
    availability.write_text('\n'.join([models.replace('import XCTest\n', ''), translation, projection]))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-typecheck', '-target', 'x86_64-apple-macosx10.13', str(availability)], check=True)
controller = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
assert 'pinnedTranslationResult' not in source
pinned = declaration(presentation, 'public func pinnedTranslationResult(')
assert 'stableVersion' not in pinned
assert not any(term in pinned for term in ['canTranslateChatMessage(', 'NLLanguageRecognizer(', 'chatTranslationNeedsTranslation('])
assert controller.count('translation = translate.pinnedTranslationResult(for: message, accountPeerId: chatInteraction.interactionContext.peerId)') == 2
assert 'if value.pinnedMessageId != oldValue.pinnedMessageId {\n                genericView.tableView.notifyScrollHandlers()' in controller
assert 'pinnedMessage.message?.stableVersion != self.pinnedMessage?.message?.stableVersion' in header
translate = declaration(source, 'public func translate(_ message:')
assert translate.index('prepareQueue.justDispatch') < translate.index('let batch = ChatTranslationMessages(') < translate.index('self.updateState {')
assert 'current.updateTranslation(batch, toLang: toLang)' in translate
assert 'if self.holder != sources' in translate
assert 'repliesToTranslate.append(replyMessage)' in controller and 'translate(messagesToTranslate, replies: repliesToTranslate)' in controller
print('PASS production state/projection and pinned-animation decision tests, macOS 10.13 availability typecheck and source integration checks. Model/queue/UI boundaries are adapters; animation checks execute real update expressions, not AppKit layer animations or a full application build.')
