from pathlib import Path
import subprocess
import json
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/InputView/Sources/InputView/ChatTextInputState.swift').read_text()
formatting = (root / 'packages/InputView/Sources/InputView/ChatTextInputAttribute.swift').read_text()
def block(text, marker):
    start = text.index(marker)
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]
fixture = Path(__file__).with_name('ProvenanceTests.swift').read_text()
a = source.index('public let chatInputAnalyticsExcludedAttribute')
b = source.index('public func chatTextAttributes(from entities:', a)
fixture = fixture.replace('__ATTRIBUTES__', source[a:b])
fixture = fixture.replace('__PARSE__', block(source, 'public func chatTextAttributes(from attributedText:') + '\n' + block(source, 'public func chatTextAttributes(from entities:'))
a = source.index('public final class ChatTextInputState:')
b = source.index('    public var inlineMedia:', a)
model = source[a:b]
for marker in ['    public init(inputText: String) {', '    public init(from decoder:', '    public func encode(to encoder:', '    public func textInputState()', '    public func attributedString()', '    public func makeAttributeString(', '    public func subInputState(', '    public func withUpdatedRange(', '    public var withoutAnimatedEmoji:', '    public func unique(']:
    model += '\n' + block(source[a:], marker)
a = source.index('        var entities:', source.index('    public func messageTextEntities('))
b = source.index('        for link in detectedTextLinks', a)
model += '\n    func messageTextEntities() -> [MessageTextEntity] {\n' + source[a:b] + '\n        return entities\n    }\n}'
fixture = fixture.replace('__MODEL__', model)
fixture = fixture.replace('__FORMAT__', '\n'.join(block(formatting, marker) for marker in ['public func stateAttributedStringForText(', 'public func textAttributedStringForStateText(', 'private func trimRangesForChatInputText(', 'public func trimChatInputText(']))
transforms = (root / 'packages/InputView/Sources/InputView/ChatTextInputFormat.swift').read_text()
fixture = fixture.replace('__TRANSFORMS__', '\n'.join(block(transforms, marker) for marker in ['public func chatTextInputAddFormattingAttribute(', 'public func chatTextInputClearFormattingAttributes(', 'public func chatTextInputAddLinkAttribute(', 'public func chatTextInputAddQuoteAttribute(', 'public func chatTextInputAddDateAttribute(', 'public func chatTextInputReplaceSelectedText(']))
sync = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatInterfaceState.swift').read_text()
fixture = fixture.replace('__SYNC__', block(sync, '    public func withUpdatedSynchronizeableInputState('))
ui = (root / 'packages/InputTextView/Sources/InputTextView/UIInputView.swift').read_text()
a = ui.index('        case .url:', ui.index('    public func inputApplyTransform('))
b = ui.index('        case .date:', a)
fixture = fixture.replace('__LINK_CALLBACK__', ui[a + len('        case .url:'):b])
fixture = fixture.replace('__TRANSLATE_CALLBACK__', block(ui, '    public func inputTextTranslateSelected()'))
fixture = fixture.replace('__DATE_EDIT_CALLBACK__', block(ui, '    public func inputApplyDateEdit('))
a = ui.index('        case .date:', ui.index('    public func inputApplyTransform('))
b = ui.index('        case .clear:', a)
fixture = fixture.replace('__DATE_CALLBACK__', ui[a + len('        case .date:'):b])
fixture = fixture.replace('__INPUT_CAPTURE__', block(ui, '    private func captureInputAnalyticsContext(').replace('private ', ''))
hooks = (root / 'packages/InputTextView/Sources/InputTextView/InputTextViewHooks.swift').read_text()
a = hooks.index('    public var showTranslateWithContext:')
b = hooks.index('    public init(checkSendingAbility:', a)
fixture = fixture.replace('__INPUT_HOOKS__', hooks[a:b].replace('any AccountContextProtocol', 'FormattingAccountContext').replace('Window', 'Int'))
analytics = root / 'packages/AppAnalytics/Sources/AppAnalytics'
fixture = fixture.replace('__POLICY__', (analytics / 'AnalyticsScope.swift').read_text())
context_source = (analytics / 'AnalyticsContext.swift').read_text()
a = context_source.index('public final class AnalyticsContext {')
b = context_source.index('\nextension AnalyticsPrivacy', a)
fixture = fixture.replace('__CONTEXT__', context_source[a:b])
a = context_source.index('    func captureContext(owner:')
b = context_source.index('\n    func excludedContext()', a)
fixture = fixture.replace('__CAPTURE__', context_source[a:b])
rich = Path(__file__).with_name('RichDraftReturnTests.swift').read_text()
editor = (root / 'packages/ChatUI/Sources/ChatUI/RichTextEditorWindowController.swift').read_text()
a = editor.index('            let attributes = chatTextAttributes(', editor.index('onCancel: { composed in'))
b = editor.index('            chatInteraction.update', a)
rich = rich.replace('__RICH_RETURN__', editor[a:b])
other = editor.index('private func composerEditorController(')
a = editor.index('            let attributes = chatTextAttributes(', other)
b = editor.index('            chatInteraction.update', a)
rich = rich.replace('__PASTED_RETURN__', editor[a:b])
composer = (root / 'packages/ChatUI/Sources/ChatUI/ChatInputView.swift').read_text()
a = composer.index('                    var attributes = chatTextAttributes(', composer.index('chatInteraction.flushRichTextDraft ='))
b = composer.index('                    self.chatInteraction.update', a)
rich = rich.replace('__INLINE_RETURN__', composer[a:b])
fixture += '\n' + rich
fixture = fixture.replace('public ', '')
assert all(marker not in fixture for marker in ['__ATTRIBUTES__', '__PARSE__', '__MODEL__', '__FORMAT__', '__TRANSFORMS__', '__SYNC__', '__LINK_CALLBACK__', '__TRANSLATE_CALLBACK__', '__DATE_EDIT_CALLBACK__', '__DATE_CALLBACK__', '__INPUT_CAPTURE__', '__INPUT_HOOKS__', '__POLICY__', '__CONTEXT__', '__CAPTURE__'])
with tempfile.TemporaryDirectory(prefix='input-analytics-provenance-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/MurMurHash32'))
    signals = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "InputAnalyticsProvenance", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + dependency + '), .package(path: ' + signals + ')], targets: [.testTarget(name: "InputAnalyticsProvenanceTests", dependencies: [.product(name: "MurMurHash32", package: "MurMurHash32"), .product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ProvenanceTests.swift').write_text(fixture)
    postbox = root / 'submodules/telegram-ios/submodules/Postbox/Sources'
    for path in [postbox / 'Coding.swift', *sorted((postbox / 'Utils/Encoder').glob('*.swift')), *sorted((postbox / 'Utils/Decoder').glob('*.swift'))]:
        (directory / 'Tests' / path.name).write_text(path.read_text())
    engine = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/Utils/Coding.swift').read_text().replace('import Postbox\n', '')
    (directory / 'Tests/EngineCoding.swift').write_text(engine)

    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
