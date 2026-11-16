from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
app = (root / 'Telegram-Mac/app/ApplicationContext.swift').read_text()
chat = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
installer = (root / 'Telegram-Mac/packages-integration/hooks/PremiumHooksInstall.swift').read_text()
fixture = Path(__file__).with_name('NavigationTests.swift').read_text()
start = app.index('func navigateToChat(')
end = app.index('private final class AuthModalController', start)
fixture = fixture.replace('__NAVIGATE__', app[start:end])
start = chat.index('    private var inheritedAnalyticsPresentation:')
end = chat.index('    private static func resolveAnalyticsScreen(', start)
fixture = fixture.replace('__INHERIT__', chat[start:end])
start = chat.index('    private func updateAnalyticsScreen(')
end = chat.index('    private func makeMessageSendObservation(', start)
fixture = fixture.replace('__UPDATE__', chat[start:end].replace('private func', 'func', 1))
start = context.index('    public func preservingPresentation<')
end = context.index('\n}\n\npublic final class AnalyticsPresentation', start)
fixture = fixture.replace('__SIGNAL__', context[start:end])
start = installer.index('    hooks.openChatWithContext =')
end = installer.index('    hooks.showStickerPackPreviewWithContext =', start)
fixture = fixture.replace('__PREMIUM__', installer[start:end])
with tempfile.TemporaryDirectory(prefix='chat-navigation-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatNavigationContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChatNavigationContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/NavigationTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
