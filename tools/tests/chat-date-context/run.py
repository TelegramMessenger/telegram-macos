from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
hooks = (root / 'packages/ChatUI/Sources/ChatUI/ChatNavigationHooks.swift').read_text()


def section(start, end):
    offset = hooks.index(start)
    return hooks[offset:hooks.index(end, offset)]


fixture = Path(__file__).with_name('DateContextTests.swift').read_text()
fixture = fixture.replace('__DATE_MODE__', section('public enum ChatDateSelectorMode', 'public enum ChatGalleryAppearType'))
fixture = fixture.replace('__DATE_HELPER__', section('func chatDateSelector(', 'func generateChatThemeThumb('))
controller = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
inline_start = controller.index('        chatInteraction.sendInlineResult =')
apply_start = controller.index('                    func apply(', inline_start)
apply_end = controller.index('                    switch strongSelf.mode', apply_start)
fixture = fixture.replace('__INLINE_APPLY__', controller[apply_start:apply_end])
deferred = Path(__file__).with_name('DeferredSendTests.swift').read_text()
action = (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text()
interaction = (root / 'packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift').read_text()
methods_start = interaction.index('    func invalidateDeferredSendActions(')
methods_end = interaction.index('    var isPreparingForwardSend:', methods_start)
update_start = interaction.index('        if !chatHasSameDeferredSendState(')
update_end = interaction.index('        if oldValue.selectionState?', update_start)
rich_start = interaction.index('        if ChatInteraction.globalRichTextDrafts.set(page, for: richTextDraftKey, origin: origin) {')
rich_end = interaction.index('        richTextDraftPromise.set(page)', rich_start)
deferred = deferred.replace('__DEFERRED_SOURCE__', action)
deferred = deferred.replace('__DEFERRED_METHODS__', interaction[methods_start:methods_end])
deferred = deferred.replace('__UPDATE_INVALIDATION__', interaction[update_start:update_end])
deferred = deferred.replace('__RICH_INVALIDATION__', interaction[rich_start:rich_end].replace('origin: origin', 'origin: nil').replace('        revokePrivateComposerAnalytics()\n', ''))
rich_store = (root / 'packages/ChatUI/Sources/ChatUI/ChatRichTextDraftStore.swift').read_text()
rich_key_start = interaction.index('    private static let globalRichTextDrafts =')
rich_key_end = interaction.index('    private let richTextDraftPromise', rich_key_start)
deferred = deferred.replace('__RICH_STORE__', rich_store)
deferred = deferred.replace('__RICH_KEY__', interaction[rich_key_start:rich_key_end].replace('AnalyticsContext', 'NSObject'))
date_guard = next(line.strip() for line in controller.splitlines() if 'guard deferredSendAction?.takeIfCurrent(onInvalidated:' in line)
confirmation_guard = next(line.strip() for line in controller.splitlines() if 'guard confirmationAction.takeIfCurrent(onInvalidated:' in line)
deferred = deferred.replace('__DATE_CALLBACK_GUARD__', date_guard)
deferred = deferred.replace('__CONFIRMATION_GUARD__', confirmation_guard)
payment = Path(__file__).with_name('PaymentConfirmationTests.swift').read_text()
payment_source = (root / 'packages/ChatUI/Sources/ChatUI/ChatSendPaymentConfirmation.swift').read_text()
payment = payment.replace('__PAYMENT_CONFIRMATION__', payment_source[payment_source.index('func verifyChatSendPayment('):payment_source.index('public func chatPaidMessagePriceIsCurrent(')])
with tempfile.TemporaryDirectory(prefix='chat-date-context-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatDateContext", targets: [.testTarget(name: "ChatDateContextTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/DateContextTests.swift').write_text(fixture)
    (directory / 'Tests/DeferredSendTests.swift').write_text(deferred)
    (directory / 'Tests/RichDraftStoreTests.swift').write_text(Path(__file__).with_name('RichDraftStoreTests.swift').read_text())
    (directory / 'Tests/PaymentConfirmationTests.swift').write_text(payment)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
