from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
base = root / 'packages/WebAppUI/Sources/WebAppUI'
origin = (base / 'BrowserAnalyticsOrigin.swift').read_text()
state = (base / 'BrowserState.swift').read_text()
browser = (base / 'WebappBrowser.swift').read_text()
hooks = (base / 'BrowserHooks.swift').read_text()
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
fixture = Path(__file__).with_name('BrowserTests.swift').read_text()
def section(source, start, end, offset=0):
    a = source.index(start, offset)
    b = source.index(end, a)
    return source[a:b].replace('public ', '')
fixture = fixture.replace('__ORIGIN__', origin[origin.index('private var browserAnalyticsOriginKey'):])
fixture = fixture.replace('__STATE_SHOW__', section(state, '    public func show(_ browser:', '    public func hide(close:'))
fixture = fixture.replace('__STATE_HIDE__', section(state, '    public func hide(close:', '    private let statePromise'))
fixture = fixture.replace('__STATE_CLOSE__', section(state, '    public func closeTab(uniqueId:', '    public func clearRecent'))
fixture = fixture.replace('__STATE_OPEN__', section(state, '    public func open(tab:', '\n}\n'))
fixture = fixture.replace('__SIGNAL__', section(context, '    public func preservingPresentation<', '\n}\n\npublic final class AnalyticsPresentation'))
fixture = fixture.replace('__BROWSER_CHAT__', section(hooks, '    public var openChatWithContext:', '    public let sharePreparedMessage:'))
start = browser.index('public final class WebappBrowserController')
fixture = fixture.replace('__LIFECYCLE_FIELDS__', section(browser, '    public private(set) var markAsDeinit:', '    private let publicStateValue:', start))
fixture = fixture.replace('__BROWSER_HIDE__', section(browser, '    public func hide(_ completion:', '    public override func viewDidResized', start))
fixture = fixture.replace('__BROWSER_SHOW_START__', section(browser, '    public func show()', '        browser.onToggleFullScreen', start))
fixture = fixture.replace('__BROWSER_FRONT__', section(browser, '    public func makeKeyAndOrderFront()', '    public func closeTab()', start))
fixture = fixture.replace('__BROWSER_CLOSE__', section(browser, '    public func closeTab()', '    private var browser:', start))
fixture = fixture.replace('__BROWSER_INIT_ADD__', section(browser, '    public convenience init(', '    public func makeKeyAndOrderFront', start))
fixture = fixture.replace('__INSERT__', section(browser, '        let insertTab:', '        let arguments = Arguments', start))
fixture = fixture.replace('__CLOSE_TAB__', section(browser, '        }, closeTab: { [weak self] unique, checkAdmission in', '        }, removeTab:', start).replace('        }, closeTab: ', '        arguments.closeTab = ', 1) + '        }\n')
fixture = fixture.replace('__REMOVE_TAB__', section(browser, '        }, removeTab: { [weak self] unique in', '        }, selectAtIndex:', start).replace('        }, removeTab: ', '        arguments.removeTab = ', 1) + '        }\n')
fixture = fixture.replace('__INITIAL_INSERT__', section(browser, '        if let initialTab {', '        publicStateValue.set', start))
start = browser.index('private final class WebpageContainerController')
fixture = fixture.replace('__CONTAINER_INIT__', section(browser, '    public init(data:', '    public func contextMenu', start))
fixture = fixture.replace('__CONTAINER_ADD__', section(browser, '    public func add(_ tab:', '    deinit', start))
fixture = fixture.replace('__LINK_MANAGER__', section(browser, 'public final class BrowserLinkManager', 'public final class WebappBrowserController'))
installer = (root / 'Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift').read_text()
fixture = fixture.replace('__INSTALL__', section(installer, '    let browserTabData:', '    hooks.installAttachMenuBot ='))
with tempfile.TemporaryDirectory(prefix='browser-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BrowserContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BrowserContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BrowserTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
