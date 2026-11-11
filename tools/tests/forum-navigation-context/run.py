from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = root / 'packages/ChatListUI/Sources/ChatListUI'
forum = (source / 'ForumUIMethods.swift').read_text()
origin = (source / 'ForumNavigationOrigin.swift').read_text()
hooks = (source / 'ChatListUIHooks.swift').read_text()
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
fixture = Path(__file__).with_name('ForumTests.swift').read_text()
fixture = fixture.replace('__ORIGIN__', origin[origin.index('private var forumControllerOriginKey:'):])
start = forum.index('    public static func open(_ peerId:')
end = forum.index('    public static func openSavedMessages', start)
fixture = fixture.replace('__FORUM__', forum[start:end])
start = hooks.index('    public var navigateToChatWithContext:')
end = hooks.index('    public let mainEffectiveNavigation:', start)
fixture = fixture.replace('__HOOK__', hooks[start:end])
installer = (root / 'Telegram-Mac/packages-integration/hooks/ChatListUIHooksInstall.swift').read_text()
start = installer.index('    hooks.navigateToChatWithContext =')
end = installer.index('    ChatListUIHooks.install(hooks)', start)
fixture = fixture.replace('__INSTALL__', installer[start:end])
start = context.index('    public func preservingPresentation<')
end = context.index('\n}\n\npublic final class AnalyticsPresentation', start)
fixture = fixture.replace('__SIGNAL__', context[start:end])
with tempfile.TemporaryDirectory(prefix='forum-navigation-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ForumNavigationContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ForumNavigationContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ForumTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
