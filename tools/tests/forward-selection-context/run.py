from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
fixture = Path(__file__).with_name('ForwardSelectionTests.swift').read_text()
analytics = root / 'packages/AppAnalytics/Sources/AppAnalytics'
registry = (analytics / 'AnalyticsRegistry.swift').read_text()
a = registry.index('    public enum ChatForwardPicker:')
b = registry.index('    public enum ChatQuickForward:', a)
fixture = fixture.replace('__FORWARD_PICKER_SPEC__', 'enum AnalyticsFlows {\n' + registry[a:b].replace('public ', '').replace(': AnalyticsFlowSpec', '') + '}')
fixture = fixture.replace('__JOURNEY__', (analytics / 'AnalyticsForwardPickerJourney.swift').read_text().replace('public ', ''))
fixture = fixture.replace('__POLICY__', (analytics / 'AnalyticsScope.swift').read_text())
context = (analytics / 'AnalyticsContext.swift').read_text()
start = context.index('public final class AnalyticsContext {')
end = context.index('    public func beginPresentation()', start)
fixture = fixture.replace('__CONTEXT__', context[start:end] + '}')
start = context.index('    public func preservingPresentation<')
end = context.index('\n}\n\npublic final class AnalyticsPresentation', start)
fixture = fixture.replace('__PRESERVING__', context[start:end])
start = context.index('public final class AnalyticsPresentation')
fixture = fixture.replace('__PRESENTATION__', context[start:context.index('\nextension AnalyticsPrivacy', start)])
start = context.index('    func captureContext(owner:')
fixture = fixture.replace('__CAPTURE__', context[start:context.index('\n    func excludedContext()', start)])
selection = (root / 'packages/ChatUI/Sources/ChatUI/ChatForwardSelection.swift').read_text()
fixture = fixture.replace('__SELECTION__', selection[selection.index('final class ChatForwardSelection'):])
interaction = (root / 'packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift').read_text()
start = interaction.index('    public var forwardMessages:')
fixture = fixture.replace('__FORWARD__', interaction[start:interaction.index('    public var reportMessages:', start)].replace('public ', ''))
start = interaction.index('    public func forwardSelectedMessages()')
fixture = fixture.replace('__LOAD__', interaction[start:interaction.index('    public func deleteSelectedMessages(', start)].replace('public ', ''))
start = interaction.index('        if oldValue.selectionState?.selectedIds !=')
end = interaction.index('        if oldValue.interfaceState.editState?', start)
fixture = fixture.replace('__INVALIDATE__', interaction[start:end])
hooks = (root / 'packages/ChatUI/Sources/ChatUI/ChatUIHooks.swift').read_text()
start = hooks.index('    public let makeForwardMessagesShareModal:')
fixture = fixture.replace('__HOOK__', hooks[start:hooks.index('    public let makeReplyForwardShareModal:', start)].replace('public ', ''))
with tempfile.TemporaryDirectory(prefix='forward-selection-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ForwardSelectionContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ForwardSelectionContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ForwardSelectionTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
