from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift').read_text()
actions = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderPendingActions.swift').read_text()
deferred = (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text().split('\nfunc chatHasSameDeferredSendState')[0]
fixture = Path(__file__).with_name('PendingTests.swift').read_text().replace('__ACTIONS__', actions).replace('__DEFERRED__', deferred)
child = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderChildAction.swift').read_text().replace('import AppAnalytics\n', '')
fixture = fixture.replace('__CHILD__', child)
start = source.index('    private func capturePendingAction()')
end = source.index('    private var lockInteractiveChanges:', start)
fixture = fixture.replace('__CAPTURE__', source[start:end].replace('private func', 'func'))
start = source.index('    fileprivate func closeModal()')
end = source.index('    func send(', start)
fixture = fixture.replace('__CLOSE__', source[start:end].replace('fileprivate func', 'func', 1))
start = source.index('                let submissionAction = self.capturePendingSendAction()')
end = source.index('                    let batchCount =', start)
fixture = fixture.replace('__SUBMIT_PREFIX__', source[start:end])
start = source.index('    public override func viewWillDisappear(')
end = source.index('        if !sent {\n            chatInteraction.update', start)
fixture = fixture.replace('__DISAPPEAR__', source[start:end].replace('public override func', 'override func', 1) + '\n    }')
start = source.index('                FeatureNavigationHooks.shared.selectDateObserved(')
end = source.index('\n                })', start) + len('\n                })')
fixture = fixture.replace('__SCHEDULE__', source[start:end])
fixture = fixture.replace('__ATTACHMENT_EDITS__', (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderAttachmentEdits.swift').read_text())
start = source.index('    private func makeEffectPremiumAction()')
end = source.index('    func togglePaidContent()', start)
fixture = fixture.replace('__EFFECT_PREMIUM__', source[start:end].replace('private func', 'func', 1))
price_source = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/MediaPaidSetterController.swift').read_text()
price_fixture = Path(__file__).with_name('PriceTests.swift').read_text()
start = source.index('    func togglePaidContent()')
end = source.index('    deinit {', start)
fixture = fixture.replace('__PRICE__', source[start:end])
start = price_source.index('    controller.validateData =')
end = price_source.index('    controller.onDeinit =', start)
price_fixture = price_fixture.replace('__PRICE_VALIDATION__', price_source[start:end])
start = price_source.index('    controller.leftModalHeader =')
end = price_source.index('    close =', start)
price_fixture = price_fixture.replace('__PRICE_CANCEL__', price_source[start:end])
fixture += '\n' + price_fixture
start = source.index('        guard !pendingActions.isClosed, !sent else { return }', source.index('    func send(_ silent:'))
end = source.index('        pendingActions.invalidate()', start)
fixture = fixture.replace('__SEND_ENTRY__', source[start:end])
start = source.index('            guard let self, !self.pendingActions.isClosed', source.index('        self.sendCurrentMedia = { [weak self] silent, atDate, asSpoiler, via in'))
end = source.index('            if stateValue.with', start)
fixture = fixture.replace('__CURRENT_ENTRY__', source[start:end])
start = source.index('                guard let self, !self.pendingActions.isClosed', source.index('            self.sendCurrentMedia = { [weak self] silent, atDate, _, _ in'))
end = source.index('                let inputState =', start)
fixture = fixture.replace('__APP_FILE_ENTRY__', source[start:end])

start = source.index('                            guard self.validateSendSource()', source.index('                        for (index, collage) in collages.enumerated()'))
end = source.index('                            self.chatInteraction.sendMediasObserved', start)
fixture = fixture.replace('__BATCH_GUARD__', source[start:end])


with tempfile.TemporaryDirectory(prefix='preview-pending-actions-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PreviewPendingActions", targets: [.testTarget(name: "PreviewPendingActionsTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PendingTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
