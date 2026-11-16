from pathlib import Path
import subprocess
import json
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift').read_text()
start = source.index('    private func runVideoEditor(')
end = source.index('    private var canSendStickers:', start)
fixture = Path(__file__).with_name('EditorTests.swift').read_text().replace('__VIDEO__', source[start:end].replace('private func', 'func', 1))
for marker, name in [('__EDITS__', 'PreviewSenderAttachmentEdits'), ('__PENDING__', 'PreviewSenderPendingActions')]:
    fixture = fixture.replace(marker, (root / ('packages/PreviewSenderUI/Sources/PreviewSenderUI/' + name + '.swift')).read_text())
fixture = fixture.replace('__DEFERRED__', (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text().split('\nfunc chatHasSameDeferredSendState')[0])
start = source.index('    fileprivate func editVideoCover(')
end = source.index('    private func runVideoEditor(', start)
fixture = fixture.replace('__COVER__', source[start:end].replace('fileprivate func', 'func'))
start = source.index('    private func capturePendingAction()')
end = source.index('    private var lockInteractiveChanges:', start)
fixture = fixture.replace('__CAPTURE__', source[start:end].replace('private func', 'func', 1))
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
start = context.index('    public func preservingPresentation<')
end = context.index('\n}\n\npublic final class AnalyticsPresentation', start)
fixture = fixture.replace('__SIGNAL_CONTEXT__', context[start:end])
with tempfile.TemporaryDirectory(prefix='preview-editor-identity-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PreviewEditorIdentity", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "PreviewEditorIdentityTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/EditorTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
