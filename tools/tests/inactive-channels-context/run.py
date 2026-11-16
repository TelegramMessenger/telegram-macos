from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/InactiveChannelsUI/Sources/InactiveChannelsUI/InactiveChannelsController.swift').read_text()
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
fixture = Path(__file__).with_name('InactiveTests.swift').read_text()
def section(source, start, end):
    a = source.index(start)
    return source[a:source.index(end, a)].replace('public ', '')
fixture = fixture.replace('__FACTORY__', section(source, 'public func InactiveChannelsController(', 'public enum InactiveSource'))
fixture = fixture.replace('__PRESENT__', source[source.index('public func showInactiveChannels('):].replace('public ', ''))
fixture = fixture.replace('__ARGUMENTS__', section(source, 'private final class InactiveChannelsArguments', 'private func inactiveEntries').replace('private ', ''))
fixture = fixture.replace('__SIGNAL__', section(context, '    public func preservingPresentation<', '\n}\n\npublic final class AnalyticsPresentation'))
chat = (root / 'packages/ChatUI/Sources/ChatUI/ChatNavigationHooks.swift').read_text()
feature = (root / 'packages/InputDataUI/Sources/InputDataUI/FeatureNavigationHooks.swift').read_text()
fixture = fixture.replace('__CHAT_HOOK__', section(chat, '    public var showInactiveChannelsOnJoin:', '    public var showFrozenAccount:'))
fixture = fixture.replace('__FEATURE_HOOK__', section(feature, '    public var showInactiveChannels:', '    public var reportContent:'))
chat_install = (root / 'Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift').read_text()
feature_install = (root / 'Telegram-Mac/packages-integration/hooks/FeatureNavigationHooksInstall.swift').read_text()
fixture = fixture.replace('__CHAT_INSTALL__', section(chat_install, '    hooks.showInactiveChannelsOnJoin =', '    hooks.showFrozenAccount ='))
fixture = fixture.replace('__FEATURE_INSTALL__', section(feature_install, '    hooks.showInactiveChannels =', '    hooks.reportContent ='))
with tempfile.TemporaryDirectory(prefix='inactive-channels-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "InactiveContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "InactiveContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/InactiveTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
