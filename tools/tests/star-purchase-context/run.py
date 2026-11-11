from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/StarsUI/Sources/StarsUI/Star_PurchaseInApp.swift').read_text()
session = (root / 'packages/StarsUI/Sources/StarsUI/StarPurchaseSession.swift').read_text()
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()
fixture = Path(__file__).with_name('PurchaseTests.swift').read_text()
fixture = fixture.replace('__FACTORY__', source[source.index('public func Star_PurschaseInApp('):].replace('public ', ''))
fixture = fixture.replace('__TYPES__', source[source.index('private final class Arguments'):source.index('private let _id_header')].replace('private ', '').replace('public ', ''))
fixture = fixture.replace('__SESSION__', session[session.index('final class StarPurchaseSession'):])
screen = (root / 'packages/StarsUI/Sources/StarsUI/StarsScreenContext.swift').read_text()
fixture = fixture.replace('__SCREEN__', screen[screen.index('final class StarsScreenContext'):])
listing = (root / 'packages/StarsUI/Sources/StarsUI/Star_ListScreen.swift').read_text()
start = listing.index('    let buyAppStore:(State.Option)->Void =')
fixture = fixture.replace('__STORE_TOPUP__', listing[start:listing.index('    let tonWithdrawal:', start)])
start = listing.index('    let buyNonStore:(State.Option)->Void =')
fixture = fixture.replace('__INVOICE_TOPUP__', listing[start:listing.index('    let buyAppStore:', start)])

start = context.index('    public func preservingPresentation<')
fixture = fixture.replace('__SIGNAL__', context[start:context.index('\n}\n\npublic final class AnalyticsPresentation', start)])
with tempfile.TemporaryDirectory(prefix='star-purchase-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StarPurchaseContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StarPurchaseContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PurchaseTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
