from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
fixture = Path(__file__).with_name('MessageSendTests.swift').read_text()
analytics = root / 'packages/AppAnalytics/Sources/AppAnalytics'
fixture = fixture.replace('__POLICY__', (analytics / 'AnalyticsScope.swift').read_text())
fixture = fixture.replace('__OBSERVATION__', (analytics / 'AnalyticsMessageSend.swift').read_text())
context = (analytics / 'AnalyticsContext.swift').read_text()
start = context.index('public final class AnalyticsContext {')
end = context.index('    public func beginPresentation()', start)
fixture = fixture.replace('__CONTEXT__', context[start:end] + '}')
signal_start = context.index('    public func preservingPresentation<')
signal_end = context.index('\n}\n\npublic final class AnalyticsPresentation', signal_start)
fixture = fixture.replace('__PRESERVING__', context[signal_start:signal_end])
presentation_start = context.index('public final class AnalyticsPresentation')
presentation_end = context.index('\nextension AnalyticsPrivacy', presentation_start)
fixture = fixture.replace('__PRESENTATION__', context[presentation_start:presentation_end])
start = context.index('    func captureContext(owner:')
end = context.index('\n    func excludedContext()', start)
fixture = fixture.replace('__CAPTURE__', context[start:end])
controller = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
start = controller.index('    private func makeMessageSendObservation(')
end = controller.index('    public func notify(with value:', start)
fixture = fixture.replace('__SNAPSHOT__', controller[start:end].replace('private func', 'func', 1))
sender = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/SenderController.swift').read_text()
start = sender.index('        func observe(_ signal:')
end = sender.index('        if let customChatContents', start)
fixture = fixture.replace('__SENDER_OBSERVE__', sender[start:end])
start = controller.index('suggestPost: presentation.interfaceState.suggestPost, observedResult: { expectedCount, ids in')
start = controller.index('\n', start)
end = controller.index('                                })', start)
fixture = fixture.replace('__RESULT__', controller[start:end])
inline_start = controller.index('                    func apply(_ controller: ChatController, atDate: Int32?) {', controller.index('        chatInteraction.sendInlineResult ='))
inline_start = controller.index('\n', inline_start)
inline_end = controller.index('                    }\n                    switch strongSelf.mode', inline_start)
fixture = fixture.replace('__INLINE__', controller[inline_start:inline_end])
with tempfile.TemporaryDirectory(prefix='message-send-observation-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MessageSendObservation", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "MessageSendObservationTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/MessageSendTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
