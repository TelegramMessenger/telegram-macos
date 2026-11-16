from pathlib import Path
import json
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
def assignment_block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (text[cursor] == '{') - (text[cursor] == '}')
        cursor += 1
    return text[start:cursor]

fixture = Path(__file__).with_name('TranslationContextTests.swift').read_text()
analytics = root / 'packages/AppAnalytics/Sources/AppAnalytics'
fixture = fixture.replace('__POLICY__', (analytics / 'AnalyticsScope.swift').read_text().replace('public ', ''))
source = (analytics / 'AnalyticsContext.swift').read_text()
a = source.index('public final class AnalyticsContext {')
b = source.index('\nextension AnalyticsPrivacy', a)
fixture = fixture.replace('__CONTEXT__', source[a:b].replace('public ', ''))
a = source.index('    func captureContext(owner:')
b = source.index('\n    func excludedContext()', a)
fixture = fixture.replace('__CAPTURE__', source[a:b])
source = (root / 'packages/TranslateUI/Sources/TranslateUI/TranslateModalController.swift').read_text()
source = source[source.index('public func TranslateModalController('):]
def between(start, end):
    a = source.index(start)
    return source[a:source.index(end, a)]
fixture = fixture.replace('__ADMISSION__', between('    let origin =', '    let actionsDisposable ='))
fixture = fixture.replace('__STATE__', between('    let statePromise =', '    let reloadStyles:'))
fixture = fixture.replace('__LOADING__', between('    let reloadStyles:', '    let input = ChatTextInputState(').replace('TelegramEngine.EngineData.Item.Peer.Peer(id:', 'PeerRequest(id:'))
fixture = fixture.replace('__REQUEST_GUARD__', between('    let request:()->Void = {', '        let state = stateValue.with'))
fixture = fixture.replace('__REQUEST_RESULT__', between('        disposable.set(getAnalyticsContext().preservingPresentation(signal).start', '    var getController:'))
fixture = fixture.replace('__RENDER__', between('    let signal = getAnalyticsContext().preservingPresentation(statePromise.get()', '    let controller = InputDataController('))
fixture = fixture.replace('__CLEANUP__', between('    controller.onDeinit =', '    let modalInteractions:'))
fixture = fixture.replace('__CLOSE__', between('    close = { [weak modalController]', '    return modalController'))
fixture = fixture.replace('__ACTIONS__', between('    let modalInteractions: ModalInteractions', '    let modalController ='))
fixture = fixture.replace('__TONE__', between('    }, updateTone: { tone in', '    }, copyTranslation: {').split('tone in', 1)[1])
fixture = fixture.replace('__COPY__', between('    }, copyTranslation: {', '    }, translateEntireChat:').split('copyTranslation: {', 1)[1])
fixture = fixture.replace('__ENTIRE_CHAT__', between('    }, translateEntireChat: translateEntireChat != nil ? {', '    } : nil, updateMode:').split('translateEntireChat != nil ? {', 1)[1])
input_source = (root / 'packages/InputView/Sources/InputView/ChatTextInputState.swift').read_text()
a = input_source.index('public let chatInputAnalyticsExcludedAttribute')
b = input_source.index('public func chatTextAttributes(from entities:', a)
helper = input_source[a:input_source.index('private func concatAttributes', a)]
fixture = fixture.replace('__TEXT_HELPER__', helper.replace('public ', ''))
hooks = (root / 'packages/InputDataUI/Sources/InputDataUI/FeatureNavigationHooks.swift').read_text()
a = hooks.index('public enum PremiumBoardingSource:')
b = hooks.index('public enum PremiumLimitKind:', a)
fixture = fixture.replace('__PREMIUM_SOURCE__', hooks[a:b].replace('public ', ''))
premium = (root / 'packages/PremiumUI/Sources/PremiumUI/PremiumBoardingController.swift').read_text()
a = premium.index('public enum PremiumLogEventsSource :')
b = premium.index('    public var value: String {', a)
fixture = fixture.replace('__PREMIUM_LOG_SOURCE__', premium[a:b].replace('public ', '') + '}')
navigation = (root / 'Telegram-Mac/packages-integration/hooks/FeatureNavigationHooksInstall.swift').read_text()
a = navigation.index('private extension PremiumBoardingSource {')
b = navigation.index('private extension PremiumLimitKind {', a)
fixture = fixture.replace('__PREMIUM_SOURCE_MAPPING__', navigation[a:b])
a = hooks.index('    public func showPremiumBoardingObserved(')
b = hooks.index('    public var showPremiumLimit:', a)
method = hooks[a:b].replace('public ', '').replace('any AccountContextProtocol', 'Context').replace('Window', 'Int').replace('TelegramPresentationTheme', 'Int')
fixture = fixture.replace('__PREMIUM_HOOK__', method)
for marker, assignment in [('CONTENT', 'controller.analyticsContext = origin'), ('MODAL', 'modalController.analyticsContext = origin')]:
    assert assignment in source
    fixture = fixture.replace('__' + marker + '__', assignment)
assert source.count('disposable.set(getAnalyticsContext().preservingPresentation(richSignal).start') == 2
assert 'promptRequestDisposable.set(getAnalyticsContext().preservingPresentation(Signal<Void, NoError>.single(Void())' in source
entry = Path(__file__).with_name('InputEntryBridgeTests.swift').read_text()
hooks = (root / 'packages/InputTextView/Sources/InputTextView/InputTextViewHooks.swift').read_text()
a = hooks.index('    public var showTranslateWithContext:')
b = hooks.index('    public init(checkSendingAbility:', a)
entry = entry.replace('__INPUT_HOOKS__', hooks[a:b].replace('public ', '').replace('any AccountContextProtocol', 'Context').replace('Window', 'Int'))
bridge = (root / 'Telegram-Mac/packages-integration/hooks/InputTextViewHooksInstall.swift').read_text()
a = bridge.index('    hooks.showTranslateWithContext =')
b = bridge.index('    InputTextViewHooks.install(hooks)', a)
entry = entry.replace('__INPUT_BRIDGES__', bridge[a:b].replace('AccountContext', 'Context'))
fixture += '\n' + entry
message = Path(__file__).with_name('MessageEntryTests.swift').read_text()
hooks = (root / 'packages/ChatUI/Sources/ChatUI/ChatHistoryUIHooks.swift').read_text()
a = hooks.index('public enum ChatHistoryTranslationSource {')
b = hooks.index('public struct ChatHistoryUIHooks {', a)
message = message.replace('__MESSAGE_SOURCE__', hooks[a:b].replace('public ', ''))
a = hooks.index('    public let makeRichMessageTranslateModal:')
b = hooks.index('    public let communityFilterCategories:', a)
message = message.replace('__MESSAGE_HOOKS__', hooks[a:b].replace('public ', '').replace('any AccountContextProtocol', 'Context'))
bridge = (root / 'Telegram-Mac/packages-integration/hooks/ChatHistoryUIHooksInstall.swift').read_text()
a = bridge.index('    hooks.makeTranslateModalWithContext =')
b = bridge.index('    ChatHistoryUIHooks.install(hooks)', a)
message = message.replace('__MESSAGE_BRIDGE__', assignment_block(bridge, '    hooks.makeTranslateModalWithContext ='))
menu = (root / 'packages/ChatUI/Sources/ChatUI/ChatMessageMenuItems.swift').read_text()
a = menu.index('private func messageTranslationAnalyticsContext(')
b = menu.index('public func chatMenuItems(', a)
message = message.replace('__MESSAGE_PRIVACY__', menu[a:b])
capture = '    let translationOrigin = messageTranslationAnalyticsContext(message, chatInteraction: chatInteraction)'
assert capture in menu
message = message.replace('__MESSAGE_CAPTURE__', capture)
actions = []
for i, source_case in enumerate(['richMessage', 'poll', 'message', 'selectedText', 'transcription']):
    point = menu.index('source: .' + source_case, menu.index(capture))
    a = menu.rindex('handler: {', 0, point) + len('handler: {')
    b = menu.index('}, itemImage:', point)
    actions.append('case ' + str(i) + ': return {' + menu[a:b] + '}')
message = message.replace('__MESSAGE_ACTIONS__', '\n'.join(actions))
fixture += '\n' + message
removal = Path(__file__).with_name('StyleRemovalTests.swift').read_text()
core_translation = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Translate.swift').read_text()
a = core_translation.index('public enum DeleteAITextStyleError {')
b = core_translation.index('\n}', a) + 2
removal = removal.replace('__REMOVAL_ERROR__', core_translation[a:b].replace('public ', ''))
engine_messages = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift').read_text()
for operation in ['deleteAITextStyle', 'unsaveAITextStyle']:
    assert 'public func ' + operation + '(id: Int64, accessHash: Int64) -> Signal<Never, DeleteAITextStyleError>' in engine_messages
a = source.index('        menu.addItem(ContextMenuItem(strings().translateModalDeleteStyle, handler: {')
a += len('        menu.addItem(ContextMenuItem(strings().translateModalDeleteStyle, handler: {')
b = source.index('        }, itemMode: .destruct', a)
removal = removal.replace('__STYLE_REMOVAL__', source[a:b])
fixture += '\n' + removal
sharing = Path(__file__).with_name('StyleShareTests.swift').read_text()
hooks = (root / 'packages/TranslateUI/Sources/TranslateUI/TranslateUIHooks.swift').read_text()
hooks = hooks[hooks.index('public struct TranslateUIHooks {'):]
sharing = sharing.replace('__TRANSLATE_HOOKS__', hooks.replace('public ', '').replace('any AccountContextProtocol', 'Context'))
bridge = (root / 'Telegram-Mac/packages-integration/hooks/TranslateUIHooksInstall.swift').read_text()
a = bridge.index('    hooks.shareLinkWithContext =')
b = bridge.index('    TranslateUIHooks.install(hooks)', a)
sharing = sharing.replace('__SHARE_BRIDGE__', assignment_block(bridge, '    hooks.shareLinkWithContext ='))
a = source.index('menu.addItem(ContextMenuItem(strings().translateModalShareStyle, handler: {')
a += len('menu.addItem(ContextMenuItem(strings().translateModalShareStyle, handler: {')
b = source.index('        }, itemImage: MenuAnimation.menu_share.value))', a)
sharing = sharing.replace('__SHARE_ACTION__', source[a:b])
fixture += '\n' + sharing
about = Path(__file__).with_name('AboutContextTests.swift').read_text()
about_source = (root / 'packages/AboutFeatureUI/Sources/AboutFeatureUI/AboutFeatureModalController.swift').read_text()
a = about_source.index('public struct AboutFeatureConfiguration {')
b = about_source.index('private final class AboutFeatureHeaderItem:', a)
about = about.replace('__ABOUT_CONFIG__', about_source[a:b].replace('public ', ''))
a = about_source.index('public func AboutFeatureModalController(')
b = about_source.index('public func showAboutCocoonModal', a)
factory = about_source[a:b].replace('public ', '').replace('any AccountContextProtocol', 'Context').replace('InputDataModalController', 'AboutModal').replace('InputDataController', 'AboutController')
factory = re.sub(r'\bState\b', 'AboutState', factory)
factory = re.sub(r'\bArguments\b', 'AboutArguments', factory)
about = about.replace('__ABOUT_FACTORY__', factory)
a = b
b = about_source.index('public func showDisableSharingModal', a)
about = about.replace('__COCOON_FACTORY__', about_source[a:b].replace('public ', '').replace('showAboutCocoonModal<Context: AccountContextProtocol>', 'showAboutCocoonModal'))
history = (root / 'packages/ChatUI/Sources/ChatUI/ChatHistoryUIHooks.swift').read_text()
about = about.replace('__ABOUT_EXECUTE__', assignment_block(history, '    public static func execute(inapp: Any, analyticsContext:').replace('public ', ''))
bridge = (root / 'Telegram-Mac/packages-integration/hooks/TranslateUIHooksInstall.swift').read_text()
about = about.replace('__ABOUT_BRIDGE__', assignment_block(bridge, '    hooks.showAboutCocoonModalWithContext =').replace('AccountContext', 'Context'))
bridge = (root / 'Telegram-Mac/packages-integration/hooks/ChatHistoryUIHooksInstall.swift').read_text()
about = about.replace('__ABOUT_EXECUTE_BRIDGE__', assignment_block(bridge, '    hooks.executeLinkWithContext =').replace('hooks.executeLinkWithContext', 'historyHooks.executeLinkWithContext'))
a = source.index('controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionInfo, handler: {')
a += len('controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionInfo, handler: {')
b = source.index('        })', a)
about = about.replace('__ABOUT_HEADER__', source[a:b])
fixture += '\n' + about
editor = Path(__file__).with_name('StyleEditorTests.swift').read_text()
errors = []
for error_type in ['CreateAITextStyleError', 'EditAITextStyleError']:
    a = core_translation.index('public enum ' + error_type + ' {')
    b = core_translation.index('\n}', a) + 2
    errors.append(core_translation[a:b].replace('public ', ''))
editor = editor.replace('__EDITOR_ERRORS__', '\n'.join(errors))
editor_source = (root / 'packages/TranslateUI/Sources/TranslateUI/AIStyleModalController.swift').read_text()
editor_source = editor_source[editor_source.index('func AIStyleModalController('):]
editor_source = editor_source.replace('any AccountContextProtocol', 'Context').replace('InputDataModalController', 'EditorModal').replace('InputDataController', 'EditorController')
editor_source = re.sub(r'\bState\b', 'EditorState', editor_source)
editor_source = re.sub(r'\bArguments\b', 'EditorArguments', editor_source)
editor = editor.replace('__EDITOR_FACTORY__', editor_source)
bridge = (root / 'Telegram-Mac/packages-integration/hooks/TranslateUIHooksInstall.swift').read_text()
editor = editor.replace('__EDITOR_EMOJI_BRIDGE__', assignment_block(bridge, '    hooks.showStyleEmojiPickerWithContext =').replace('AccountContext', 'Context'))
a = source.index('    }, showStyleTooltip: showStyleTooltip, createNewStyle: {') + len('    }, showStyleTooltip: showStyleTooltip, createNewStyle: {')
b = source.index('    }, styleMenu:', a)
editor = editor.replace('__EDITOR_CREATE_ENTRY__', source[a:b])
a = source.index('menu.addItem(ContextMenuItem(strings().translateModalEditStyle, handler: {') + len('menu.addItem(ContextMenuItem(strings().translateModalEditStyle, handler: {')
b = source.index('            }, itemImage:', a)
editor = editor.replace('__EDITOR_EDIT_ENTRY__', source[a:b])
fixture += '\n' + editor
preview = Path(__file__).with_name('StylePreviewTests.swift').read_text()
preview_source = (root / 'packages/TranslateUI/Sources/TranslateUI/AiStylePreviewModalController.swift').read_text()
a = preview_source.index('public struct StylePreviewInfo:')
b = preview_source.index('public func fetchAiStylePreviewInfo(', a)
preview = preview.replace('__PREVIEW_INFO__', preview_source[a:b].replace('public ', ''))
a = b
b = preview_source.index('private typealias StyleExample', a)
preview = preview.replace('__PREVIEW_FETCH__', preview_source[a:b].replace('public ', '').replace('any AccountContextProtocol', 'Context'))
a = preview_source.index('public func AiStylePreviewModalController(')
body = preview_source[a:].replace('public ', '').replace('any AccountContextProtocol', 'Context').replace('InputDataModalController', 'PreviewModal').replace('InputDataController', 'PreviewController')
body = re.sub(r'\bState\b', 'PreviewState', body)
body = re.sub(r'\bArguments\b', 'PreviewArguments', body)
preview = preview.replace('__PREVIEW_FACTORY__', body)
bridge = (root / 'Telegram-Mac/packages-integration/hooks/TranslateUIHooksInstall.swift').read_text()
preview = preview.replace('__PREVIEW_AUTHOR_BRIDGE__', assignment_block(bridge, '    hooks.followResolvedNameWithContext =').replace('AccountContext', 'Context'))
links = (root / 'Telegram-Mac/utils/InAppLinks.swift').read_text()
a = links.index('    case let .addStyle(_, slug, context):') + len('    case let .addStyle(_, slug, context):')
b = links.index('        afterComplete(true)', a) + len('        afterComplete(true)')
preview = preview.replace('__PREVIEW_LINK__', links[a:b])
fixture += '\n' + preview
composer = Path(__file__).with_name('ComposerAIEntryTests.swift').read_text()
hooks = (root / 'packages/ChatUI/Sources/ChatUI/ChatInputUIHooks.swift').read_text()
a = hooks.index('    public var makeTranslateModalWithContext:')
b = hooks.index('    public let makeRichTranslateModal:', a)
composer = composer.replace('__COMPOSER_HOOK__', hooks[a:b].replace('public ', '').replace('any AccountContextProtocol', 'Context').replace('ModalViewController', 'Modal'))
attach = (root / 'packages/ChatUI/Sources/ChatUI/ChatInputAttachView.swift').read_text()
composer = composer.replace('__COMPOSER_ACTION__', assignment_block(attach, '    private func runAITranslate()').replace('private func', 'func'))
bridge = (root / 'Telegram-Mac/packages-integration/hooks/ChatInputUIHooksInstall.swift').read_text()
composer = composer.replace('__COMPOSER_BRIDGE__', assignment_block(bridge, '    hooks.makeTranslateModalWithContext =').replace('AccountContext', 'Context'))
caption = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift').read_text()
a = caption.index('        self.genericView.textView.context = context')
b = caption.index('        genericView.draggingView.controller = self', a)
composer = composer.replace('__CAPTION_BINDING__', caption[a:b])
fixture += '\n' + composer
rich = Path(__file__).with_name('RichDraftContextTests.swift').read_text()
interaction = (root / 'packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift').read_text()
a = interaction.index('    private func restrictRichTextDraftAnalyticsContext(')
b = interaction.index('    public func setRichTextDraft(', a)
rich = rich.replace('__RICH_RESTRICTION__', interaction[a:b].replace('private func', 'func').replace('ChatInteraction.globalRichTextDrafts', 'Self.store'))
rich = rich.replace('__RICH_EXCLUSION__', assignment_block(interaction, '    func excludeRichTextDraftAnalytics()').replace('ChatInteraction.globalRichTextDrafts', 'Self.store'))
fixture += '\n' + (root / 'packages/ChatUI/Sources/ChatUI/ChatRichTextDraftStore.swift').read_text() + '\n' + rich
rich_entry = Path(__file__).with_name('RichTranslationEntryTests.swift').read_text()
hooks = (root / 'packages/ChatUI/Sources/ChatUI/ChatInputUIHooks.swift').read_text()
a = hooks.index('    public var makeRichTranslateModalWithContext:')
b = hooks.index('    public let wallet:', a)
fixture = fixture.replace('__RICH_TRANSLATE_HOOK__', hooks[a:b].replace('public ', '').replace('any AccountContextProtocol', 'Context').replace('ModalViewController', 'Modal'))
bridge = (root / 'Telegram-Mac/packages-integration/hooks/ChatInputUIHooksInstall.swift').read_text()
rich_entry = rich_entry.replace('__RICH_TRANSLATE_BRIDGE__', assignment_block(bridge, '    hooks.makeRichTranslateModalWithContext =').replace('AccountContext', 'Context'))
editor = (root / 'packages/ChatUI/Sources/ChatUI/RichTextEditorWindowController.swift').read_text()
a = editor.index('onUse: { [weak coordinator] blocks, sourceContext in') + len('onUse: ')
b = editor.index('}), for: context.window)', a) + 1
rich_entry = rich_entry.replace('__RICH_EDITOR_RECEIVER__', editor[a:b])
fixture += '\n' + rich_entry
compose = Path(__file__).with_name('RichGenerationTests.swift').read_text()
source = (root / 'packages/ChatUI/Sources/ChatUI/RichTextAiComposeController.swift').read_text()
state = assignment_block(source, 'private struct State:')
state = state.replace('private struct State:', 'struct ComposeState:').replace('lhs: State, rhs: State', 'lhs: ComposeState, rhs: ComposeState').replace('.init(inputText: .init())', '.init(inputText: NSAttributedString(string: ""))')
compose = compose.replace('__COMPOSE_STATE__', state)
body = source[source.index('public func RichTextAiComposeController('):]
body = body.replace('public ', '').replace('any AccountContextProtocol', 'Context')
for old, new in [('State', 'ComposeState'), ('Arguments', 'ComposeArguments'), ('InputDataController', 'ComposeController'), ('InputDataModalController', 'ComposeModal'), ('ModalInteractions', 'ComposeInteractions')]:
    body = re.sub(r'\b' + old + r'\b', new, body)
compose = compose.replace('__COMPOSE_FACTORY__', body)
errors = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Translate.swift').read_text()
compose = compose.replace('__COMPOSE_ERROR__', assignment_block(errors, 'public enum TranslationError').replace('public ', ''))
editor = (root / 'packages/ChatUI/Sources/ChatUI/RichTextEditorWindowController.swift').read_text()
a = editor.index('completion: { [weak coordinator] result in') + len('completion: ')
b = editor.index('}), for: context.window)', a) + 1
compose = compose.replace('__COMPOSE_RECEIVER__', editor[a:b])
fixture += '\n' + compose
paste = Path(__file__).with_name('RichPasteContextTests.swift').read_text()
editor = (root / 'packages/ChatUI/Sources/ChatUI/RichTextEditorWindowController.swift').read_text()
paste = paste.replace('__FULL_PASTE_BINDING__', assignment_block(editor, '    coordinator.editor.withPasteContext ='))
row = (root / 'packages/ChatUI/Sources/ChatUI/ChatRichTextRowItem.swift').read_text()
paste = paste.replace('__INLINE_PASTE_BINDING__', assignment_block(row, '            editor.withPasteContext ='))
fixture += '\n' + paste
pickers = Path(__file__).with_name('RichMediaPickerTests.swift').read_text()
editor = (root / 'packages/ChatUI/Sources/ChatUI/RichTextEditorWindowController.swift').read_text()
methods = '\n'.join(assignment_block(editor, '    private static func present' + kind + 'Picker(') for kind in ['Image', 'File', 'Audio'])
for old, new in [('private static func', 'static func'), ('RichTextEditorView', 'PickerEditor'), ('any AccountContextProtocol', 'Context'), ('MediaFileCache', 'PickerCache'), ('NSOpenPanel', 'PickerPanel'), ('NSImage', 'PickerImage'), ('Sender.generateMedia', 'PickerSender.generateMedia')]:
    methods = methods.replace(old, new)
pickers = pickers.replace('__RICH_MEDIA_PICKERS__', methods)
a = editor.index('        let analyticsContext =', editor.index('    public init(context: any AccountContextProtocol, analyticsContext:'))
b = editor.index('        let editor = self.editor', a)
pickers = pickers.replace('__PICKER_COORDINATOR_INIT__', editor[a:b])
line = next(line for line in editor.splitlines() if 'let coordinator = RichTextEditorCoordinator(context:' in line)
pickers = pickers.replace('__PICKER_COORDINATOR_CALL__', line.replace('RichTextEditorCoordinator(', 'PickerCoordinatorHost('))
fixture += '\n' + pickers
location = Path(__file__).with_name('LocationSelectionTests.swift').read_text()
source = (root / 'packages/LocationUI/Sources/LocationUI/LocationModalController.swift').read_text()
states = '\n'.join(assignment_block(source, marker) for marker in ['private enum PickLocationState', 'private enum LocationViewState', 'public enum SelectLocationDestination'])
location = location.replace('__LOCATION_STATES__', states.replace('private ', '').replace('public ', ''))
hooks = (root / 'packages/LocationUI/Sources/LocationUI/LocationHooks.swift').read_text()
location = location.replace('__LOCATION_PROTOCOL__', assignment_block(hooks, 'public protocol LocationChatInteraction:').replace('public ', '').replace('any AccountContextProtocol', 'Context'))
location = location.replace('__LOCATION_CONFIRM_HOOK__', hooks[hooks.index('public struct LocationHooks {'):].replace('public ', ''))
for token, marker in [('INIT', '    public init(_ chatInteraction:'), ('SEND', '    private func sendLocation('), ('CLOSE', '    public override func close('), ('DEINIT', '    deinit {')]:
    location = location.replace('__LOCATION_' + token + '__', assignment_block(source, marker).replace('public ', '').replace('private ', ''))
hooks = (root / 'packages/ChatUI/Sources/ChatUI/ChatNavigationHooks.swift').read_text()
a = hooks.index('    public var showLocationSelector:')
b = hooks.index('    public var openPhotoEditor:', a)
location = location.replace('__LOCATION_HOOK__', hooks[a:b].replace('public ', '').replace('Window', 'Int'))
bridge = (root / 'Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift').read_text()
location = location.replace('__LOCATION_BRIDGE__', assignment_block(bridge, '    hooks.showLocationSelectorWithContext =').replace('LocationModalController(', 'LocationSelectionHost('))
method = assignment_block(editor, '    private static func presentLocationPicker(')
for old, new in [('private static func', 'static func'), ('RichTextEditorView', 'PickerEditor'), ('any AccountContextProtocol', 'Context'), ('MediaFileCache', 'LocationCache')]:
    method = method.replace(old, new)
location = location.replace('__LOCATION_PICKER__', method)
installer = (root / 'Telegram-Mac/packages-integration/hooks/LocationHooksInstall.swift').read_text()
location = location.replace('__LOCATION_CONFIRM_INSTALLER__', assignment_block(installer, 'func installLocationUIHooks()').replace('chatInteraction.presentation', 'chatInteraction.locationPresentation').replace('chatInteraction.context', 'chatInteraction.interactionContext'))
fixture += '\n' + location
emoji = Path(__file__).with_name('RichEmojiPickerTests.swift').read_text()
hooks = (root / 'packages/ChatUI/Sources/ChatUI/ChatInputUIHooks.swift').read_text()
a = hooks.index('    public var makeEmojiPickerWithContext:')
b = hooks.index('    public let isEntertainmentSidebarAvailable:', a)
emoji = emoji.replace('__RICH_EMOJI_HOOK__', hooks[a:b])
bridge = (root / 'Telegram-Mac/packages-integration/hooks/ChatInputUIHooksInstall.swift').read_text()
emoji = emoji.replace('__RICH_EMOJI_BRIDGE__', assignment_block(bridge, '    hooks.makeEmojiPickerWithContext ='))
emoji = emoji.replace('__RICH_EMOJI_PICKER__', assignment_block(editor, '    private static func presentEmojiPicker('))
emoji = emoji.replace('__RICH_PREMIUM_ACTION__', assignment_block(editor, '    let showPremiumFormatting:'))
assert editor.count('showPremiumFormatting()') == 3
for old, new in [('public ', ''), ('private static func', 'static func'), ('any AccountContextProtocol', 'Context'), ('AccountContext', 'Context'), ('StickerPackItem', 'RichEmojiSticker'), ('StarGift.UniqueGift', 'RichEmojiGift'), ('StickerPackCollectionInfo', 'RichEmojiCollection'), ('ViewController', 'RichEmojiController'), ('EmojiesController', 'RichEmojiController'), ('EntertainmentInteractions', 'RichEmojiInteractions'), ('RichTextEditorView', 'RichEmojiEditor'), ('EmojiFileCache', 'RichEmojiCache'), ('ChatInputUIHooks', 'RichEmojiHooks')]:
    emoji = emoji.replace(old, new)
fixture += '\n' + emoji
delivery = Path(__file__).with_name('RichDeliveryTests.swift').read_text()
for token, marker in [('CLOSE', '    close = { [weak modalController] in'), ('DISCARD', '    let confirmDiscardIfNeeded:'), ('DELIVER', '    let deliver:'), ('PERFORM', '    let performSend:')]:
    method = assignment_block(editor, marker).replace('verifyAlert_button(', 'richDiscardAlert(').replace('verifyAlert(', 'richSendAlert(').replace('showModalText(', 'richSendToast(')
    delivery = delivery.replace('__RICH_' + token + '__', method)
for token, marker in [('SCHEDULE_REQUEST', 'private func richTextScheduleRequest('), ('SEND_MENU', 'private func richTextSendMenuItems(')]:
    method = assignment_block(editor, marker).replace('private func', 'func').replace('ChatInteraction', 'RichScheduleInteraction').replace('ContextMenuItem', 'RichScheduleItem')
    delivery = delivery.replace('__RICH_' + token + '__', method)
assert editor.count('requestScheduleDate: richTextScheduleRequest(chatInteraction: chatInteraction, analyticsContext: analyticsContext)') == 2
assert editor.count('sendMenuItems: richTextSendMenuItems(chatInteraction: chatInteraction, analyticsContext: analyticsContext)') == 2
fixture += '\n' + delivery
menu = Path(__file__).with_name('SendMenuTests.swift').read_text()
action = (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text()
menu = menu.replace('__SEND_MENU_ACTION__', assignment_block(action, 'public final class ChatDeferredSendAction').replace('public ', ''))
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift').read_text()
methods = '\n'.join(assignment_block(source, marker) for marker in ['public func sendMessageMenuItems(chatInteraction: ChatInteraction, send:', 'public func sendMessageMenuItems(chatInteraction: ChatInteraction, analyticsContext:'])
for old, new in [('public ', ''), ('ChatInteraction', 'SendMenuInteraction'), ('ContextMenuItem', 'SendMenuItem'), ('MenuAnimation', 'SendMenuAnimation'), ('chatDateSelector(', 'sendMenuDateSelector(')]:
    methods = methods.replace(old, new)
menu = menu.replace('__SEND_MENU_METHODS__', methods)
binding = assignment_block(editor, '        coordinator.setSendContextMenu({') + ')'
binding = binding.replace('!isClosed', '!isClosed()').replace('!didSend', '!didSend()')
menu = menu.replace('__RICH_MENU_BINDING__', binding)
fixture += '\n' + menu
group = Path(__file__).with_name('RichGroupMediaTests.swift').read_text()
methods = '\n'.join(assignment_block(editor, '    private static func ' + name + '(') for name in ['presentAddToGroupPicker', 'presentReplacePicker', 'presentMediaEditor'])
for old, new in [('private static func', 'static func'), ('RichTextEditorView', 'PickerEditor'), ('any AccountContextProtocol', 'Context'), ('MediaFileCache', 'GroupCache'), ('NSOpenPanel', 'PickerPanel'), ('Sender.generateMedia', 'PickerSender.generateMedia'), ('MediaControlsContext', 'GroupControlsContext'), ('TelegramMediaImage', 'GroupImage'), ('ChatNavigationHooks', 'GroupNavigationHooks'), ('Signal<Media, NoError>', 'Signal<PickerMedia, NoError>')]:
    methods = methods.replace(old, new)
group = group.replace('__GROUP_HELPERS__', methods)
fixture += '\n' + group
assert not re.search(r'__[A-Z_]+__', fixture)
with tempfile.TemporaryDirectory(prefix='translation-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "TranslationContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + dependency + ')], targets: [.testTarget(name: "TranslationContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/TranslationContextTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
