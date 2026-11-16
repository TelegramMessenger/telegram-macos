from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
interaction = (root / 'packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift').read_text()
preview = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift').read_text()
fixture = Path(__file__).with_name('PreviewContextTests.swift').read_text()
a = interaction.index('    private func restrictRichTextDraftAnalyticsContext(')
b = interaction.index('    public func setRichTextDraft(', a)
fixture = fixture.replace('__RICH_RESTRICTION__', interaction[a:b].replace('ChatInteraction.globalRichTextDrafts.entry(for: richTextDraftKey)', 'richDraftEntry'))
start = interaction.index('    public func captureAnalyticsContext(sourcePeerId:')
end = interaction.index('    private let modifyDisposable:', start)
fixture = fixture.replace('__CAPTURE__', interaction[start:end].replace('public ', ''))
a = interaction.index('private final class ComposerAnalyticsScopeReference')
b = interaction.index('struct ChatMediaReplacementRequest', a)
fixture += '\n' + interaction[a:b]

start = interaction.index('    public var presentPreviewSender:')
end = interaction.index('\n    public ', interaction.index('\n    }', interaction.index('journey: AnalyticsMediaJourney?) {', start)) + len('\n    }'))
fixture = fixture.replace('__PRESENT__', interaction[start:end].replace('public ', ''))
start = preview.index('    private var mediaJourney:')
end = preview.index('    public override func viewDidAppear', start)
fixture = fixture.replace('__JOURNEY__', preview[start:end].replace('public ', ''))
for signature, marker in [('public init(appFile:', '__APP_FILE_INIT__'), ('public init(urls:', '__URL_INIT__')]:
    start = preview.index('\n', preview.index(signature)) + 1
    end = preview.index('        self.presentation =', start)
    fixture = fixture.replace(marker, preview[start:end])
controller = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
start = controller.index('        chatInteraction.presentPreviewSenderWithJourney =')
end = controller.index('                if let slowMode =', start)
prefix = controller[start:end]
end = controller.index('        chatInteraction.setChatMessageAutoremoveTimeout =', start)
tail = controller[controller.rindex('            } else {', start, end):end]
fixture = fixture.replace('__CONTROLLER_HANDOFF__', prefix + '                self.onOpen(analyticsContext, journey)\n' + tail)
direct = Path(__file__).with_name('DirectMediaTests.swift').read_text()
start = interaction.index('    public var sendMedia:')
end = interaction.index('    public var sendCreatedStickerWithAnalytics:', start)
fixture = fixture.replace('__DIRECT_API__', interaction[start:end].replace('public ', ''))
start = controller.index('        chatInteraction.sendMedia =')
end = controller.index('        chatInteraction.attachFile =', start)
direct = direct.replace('__DIRECT_CONTROLLER__', controller[start:end])
stories = (root / 'packages/StoriesUI/Sources/StoriesUI/StoryModalController.swift').read_text()
start = stories.index('            journey?.discard()', stories.index('        let sendStoryMedia:'))
end = stories.index('            if let timeout =', start)
direct = direct.replace('__STORY_PREFIX__', stories[start:end])
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
start = context.index('    public func preservingPresentation<')
end = context.index('\n}\n\npublic final class AnalyticsPresentation', start)
fixture = fixture.replace('__PRESERVING__', context[start:end].replace('public ', ''))
fixture += '\n' + direct
multipart = Path(__file__).with_name('MultipartTests.swift').read_text()
start = interaction.index('    public var sendMessage:')
end = interaction.index('    public var sendPlainText:', start)
api = interaction[start:end]
start = interaction.index('    public var sendMedias:')
end = interaction.index('    public var focusInputField:', start)
api += interaction[start:end]
fixture = fixture.replace('__MULTIPART_API__', api.replace('public ', ''))
for name, marker in [('sendMessageWithAnalytics', '__TEXT_ENTRY__'), ('sendMediasWithAnalytics', '__MEDIA_ENTRY__')]:
    start = controller.index('        chatInteraction.' + name + ' =')
    end = controller.index('            if let strongSelf = self', start)
    multipart = multipart.replace(marker, controller[start:end] + '            self?.onEntry(schedulingAnalyticsContext, submission, part)\n        }\n')
start = controller.index('                        func apply(_ controller: ChatController,', controller.index('        chatInteraction.sendMediasWithAnalytics ='))
end = controller.index('                        switch strongSelf.mode {', start)
multipart = multipart.replace('__APPLY_BATCH__', controller[start:end].replace('_ controller: ChatController', '_ controller: BatchHost'))
action = (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text()
fixture += '\n' + multipart
fixture = fixture.replace('__DEFERRED_ACTION__', action[:action.index('func chatHasSameDeferredSendState')].replace('public ', '').replace('ChatDeferredSendAction', 'DeferredAction'))
story = Path(__file__).with_name('StoryPaymentTests.swift').read_text()
a = stories.index('    func captureReplyValidity()')
b = stories.index('    func startRecording(', a)
story = story.replace('__STORY_ACTION__', stories[a:b])
a = stories.index('        let oldValue = self.presentation', stories.index('    func update(animated:Bool = true, _ f:(State)->State)'))
b = stories.index('        if oldValue != presentation {', a)
story = story.replace('__STORY_UPDATE__', stories[a:b])
a = stories.index('        let sendStoryMedia:')
b = stories.index('        chatInteraction.sendMediaWithJourney =', a)
story = story.replace('__STORY_SEND__', stories[a:b])
payment = (root / 'packages/ChatUI/Sources/ChatUI/ChatSendPaymentConfirmation.swift').read_text()
story = story.replace('__PAYMENT__', payment[payment.index('public func verifyChatSendPayment'):].replace('public ', ''))
fixture += '\n' + story
preview_story = Path(__file__).with_name('StoryPreviewTests.swift').read_text()
a = stories.index('        chatInteraction.presentPreviewSender =')
b = stories.index('        chatInteraction.sendMedia =', a)
preview_story = preview_story.replace('__STORY_PREVIEW__', stories[a:b])
a = stories.index('        let selectStoryAttachments:')
b = stories.index('        let signal = stories.state', a)
preview_story = preview_story.replace('__STORY_ATTACHMENTS__', stories[a:b])
fixture += '\n' + preview_story
files = Path(__file__).with_name('StoryFileTests.swift').read_text()
a = stories.index('        let sendStoryFile:')
b = stories.index('        chatInteraction.sendPlainText =', a)
files = files.replace('__STORY_FILE_SEND__', stories[a:b])
fixture += '\n' + files
text_story = Path(__file__).with_name('StoryTextTests.swift').read_text()
a = stories.index('        let captureStoryReplyContext:')
b = stories.index('        let toggleHide:', a)
text_story = text_story.replace('__STORY_TEXT__', stories[a:b])
a = stories.index('        }, reactStars:')
b = stories.index('        }, toggleMessages:', a)
text_story = text_story.replace('__STORY_STARS__', stories[a:b].replace('        }, reactStars:', '        starsAction =', 1) + '\n        }')

a = stories.index('                            let premiumAction =', stories.index('        let react:(StoryReactionAction)'))
b = stories.index('                        } else {', a)
text_story = text_story.replace('__PREMIUM_REPLY__', stories[a:b])
fixture += '\n' + text_story


a = preview.index('    private var sendSourceValidation:')
b = preview.index('    private var lockInteractiveChanges:', a)
fixture = fixture.replace('__SEND_SOURCE__', preview[a:b].replace('private func', 'func'))
fixture += '\n' + (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderPendingActions.swift').read_text()
bridge = (root / 'Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift').read_text()
a = bridge.index('    hooks.bindPreviewSendValidation =')
b = bridge.index('    ChatUIHooks.install(hooks)', a)
fixture = fixture.replace('__BIND_PREVIEW__', bridge[a:b].replace('hooks.bindPreviewSendValidation', 'self.bindPreviewSendValidation'))



with tempfile.TemporaryDirectory(prefix='media-preview-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MediaPreviewContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "MediaPreviewContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PreviewContextTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
