from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
base = root / 'packages/InviteLinksUI/Sources/InviteLinksUI'
preview = (base / 'JoinLinkPreviewModalController.swift').read_text()
request = (base / 'RequestJoinChatModalController.swift').read_text()
action = (base / 'InviteJoinAction.swift').read_text()
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
feature = (root / 'packages/InputDataUI/Sources/InputDataUI/FeatureNavigationHooks.swift').read_text()
install = (root / 'Telegram-Mac/packages-integration/hooks/FeatureNavigationHooksInstall.swift').read_text()
fixture = Path(__file__).with_name('InviteTests.swift').read_text()
def section(source, begin, end):
    start = source.index(begin)
    return source[start:source.index(end, start)].replace('public ', '')
fixture = fixture.replace('__ACTION__', action[action.index('final class InviteJoinAction'):])
fixture = fixture.replace('__PREVIEW__', preview[preview.index('public func JoinLinkPreviewModalController('):].replace('public ', ''))
fixture = fixture.replace('__REQUEST__', request[request.index('public func RequestJoinChatModalController('):].replace('public ', ''))
fixture = fixture.replace('__REQUEST_TYPES__', section(request, 'private final class Arguments', 'private func entries').replace('private ', ''))
fixture = fixture.replace('__SIGNAL__', section(context, '    public func preservingPresentation<', '\n}\n\npublic final class AnalyticsPresentation'))
fixture = fixture.replace('__JOIN_HOOK__', section(feature, '    public var openJoinChatBotWebView:', '    public var makeGroupCallAvatarMenuItem:'))
fixture = fixture.replace('__RECOVERY_HOOK__', section(feature, '    public var showInactiveChannels:', '    public var reportContent:'))
fixture = fixture.replace('__JOIN_INSTALL__', section(install, '    hooks.openJoinChatBotWebView =', '    hooks.makeGroupCallAvatarMenuItem ='))
fixture = fixture.replace('__RECOVERY_INSTALL__', section(install, '    hooks.showInactiveChannels =', '    hooks.reportContent ='))
with tempfile.TemporaryDirectory(prefix='invite-join-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "InviteContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "InviteContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/InviteTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
