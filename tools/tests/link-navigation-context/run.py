from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'Telegram-Mac/utils/InAppLinks.swift').read_text()
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
fixture = Path(__file__).with_name('LinkTests.swift').read_text()
enum_start = source.index('enum inAppLink {')
enum_end = source.index('\nfunc inApp(for url:', enum_start)
fixture = fixture.replace('__LINK_ENUM__', source[enum_start:enum_end])
kind_start = source.index('private func analyticsLinkKind(')
fixture = fixture.replace('__LINK_KIND__', source[kind_start:source.index('private final class InAppLinkOrigin', kind_start)])
start = source.index('private final class InAppLinkOrigin')
end = source.index('func execute(inapp:', start)
fixture = fixture.replace('__LINK__', source[start:end])
invoice = (root / 'packages/WebAppUI/Sources/WebAppUI/BrowserInvoiceAction.swift').read_text()
fixture = fixture.replace('__BROWSER_INVOICE__', invoice[invoice.index('final class BrowserInvoiceAction'):])
hooks = (root / 'packages/WebAppUI/Sources/WebAppUI/BrowserHooks.swift').read_text()
hook_start = hooks.index('    public let openInvoice:')
fixture = fixture.replace('__INVOICE_HOOK__', hooks[hook_start:hooks.index('    public let showLoginWidget:', hook_start)].replace('public ', ''))
installer = (root / 'Telegram-Mac/packages-integration/hooks/BrowserHooksInstall.swift').read_text()
bridge_start = installer.index('    hooks.openInvoiceWithContext =')
fixture = fixture.replace('__INVOICE_INSTALL__', installer[bridge_start:installer.index('    hooks.openChatWithContext =', bridge_start)])
bridge_start = installer.index('private func presentBrowserInvoice(')
fixture = fixture.replace('__INVOICE_BRIDGE__', installer[bridge_start:])
page = (root / 'packages/WebAppUI/Sources/WebAppUI/WebpageModalController.swift').read_text()
page_start = page.index('        case "web_app_open_invoice":') + len('        case "web_app_open_invoice":')
fixture = fixture.replace('__INVOICE_INGRESS__', page[page_start:page.index('        case "web_app_set_background_color":', page_start)])
page_start = page.index('    public func cancelPendingInvoices()')
fixture = fixture.replace('__INVOICE_NAVIGATION__', page[page_start:page.index('    public func reloadPage()', page_start)].replace('public ', ''))


start = source.index('func execute(inapp:inAppLink, window: Window? = nil, isExternal: Bool = false, afterComplete: @escaping(Bool)->Void = { _ in }, analyticsContext: AnalyticsContext?) {', end)
start = source.index('\n', start) + 1
end = source.index('    switch inapp {', start)
fixture = fixture.replace('__ADMISSION__', source[start:end])
start = source.index('                let success:()->Void = {')
end = source.index('                if needConfirm {', start)
fixture = fixture.replace('__EXTERNAL_SUCCESS__', source[start:end])
start = context.index('    public func preservingPresentation<')
end = context.index('\n}\n\npublic final class AnalyticsPresentation', start)
fixture = fixture.replace('__SIGNAL__', context[start:end])
with tempfile.TemporaryDirectory(prefix='link-navigation-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "LinkNavigationContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "LinkNavigationContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/LinkTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
