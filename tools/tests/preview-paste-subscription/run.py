from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift').read_text()
start = source.index('    private func receivePasteURLs(')
end = source.index('    func processPaste(', start)
fixture = Path(__file__).with_name('PasteSubscriptionTests.swift').read_text().replace('__RECEIVE__', source[start:end].replace('private func', 'func', 1))
action = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderPendingActions.swift').read_text()
deferred = (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text().split('\nfunc chatHasSameDeferredSendState')[0]
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
start = context.index('    public func preservingPresentation<')
end = context.index('\n}\n\npublic final class AnalyticsPresentation', start)
fixture = fixture.replace('__ACTIONS__', action).replace('__DEFERRED__', deferred).replace('__SIGNAL_CONTEXT__', context[start:end])
start = source.index('    public override func viewWillDisappear(')
end = source.index('        if !sent { analyticsMediaJourney?', start)
close = source[start:end].split('\n', 1)[1]
fixture = fixture.replace('__CLOSE__', close)
start = source.index('    public override func draggingItems(for pasteboard: NSPasteboard)')
end = source.index('    public override func returnKeyAction()', start)
fixture = fixture.replace('__DROP__', source[start:end].replace('public override func', 'func', 1))
fixture = fixture.replace('__ATTACHMENT_EDITS__', (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderAttachmentEdits.swift').read_text())
addition = Path(__file__).with_name('AdditionTests.swift').read_text()
start = source.index('        self.insertAdditionUrls =')
end = source.index('        context.window.set(handler:', start)
addition = addition.replace('__INSERT__', source[start:end])
start = source.index('            let uniqueUrls = newValue.uniqueElements')
end = source.index('            attachmentEdits.update(_urls)', start)
addition = addition.replace('__NORMALIZE__', source[start:end])
extensions = (root / 'packages/TGUIKit/Sources/Extensions.swift').read_text()
start = extensions.index('public extension Sequence where Iterator.Element: Hashable {')
end = extensions.index('public extension Sequence where Iterator.Element: Equatable {', start)
addition = addition.replace('__UNIQUE__', extensions[start:end])
fixture += '\n' + addition
with tempfile.TemporaryDirectory(prefix='preview-paste-subscription-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PreviewPasteSubscription", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "PreviewPasteSubscriptionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PasteSubscriptionTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
