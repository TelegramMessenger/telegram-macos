from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
fixture = Path(__file__).with_name('ChatPaymentTests.swift').read_text()
def read(name):
    return (root / name).read_text()
def section(source, begin, end):
    start = source.index(begin)
    return source[start:source.index(end, start)].replace('public ', '').replace('private ', '')
action = read('packages/ChatUI/Sources/ChatUI/ChatPaymentAction.swift')
fixture = fixture.replace('__ACTION__', action[action.index('final class ChatPaidMediaPurchase'):])
receipt = read('packages/PaymentsUI/Sources/PaymentsUI/PaymentsReceiptController.swift')
fixture = fixture.replace('__RECEIPT__', receipt[receipt.index('public func PaymentsReceiptController('):].replace('public ', ''))
fixture = fixture.replace('__STATE__', section(receipt, 'private final class Arguments', 'private let _id_loading'))
context = read('packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift')
fixture = fixture.replace('__SIGNAL__', section(context, '    public func preservingPresentation<', '\n}\n\npublic final class AnalyticsPresentation'))
hooks = read('packages/ChatUI/Sources/ChatUI/ChatNavigationHooks.swift')
fixture = fixture.replace('__HOOKS__', section(hooks, '    public var showPaymentsReceipt:', '    public var applyExternalProxy:'))
installer = read('Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift')
fixture = fixture.replace('__INSTALL__', section(installer, '    hooks.showPaymentsReceipt =', '    hooks.applyExternalProxy ='))
row = read('packages/ChatUI/Sources/ChatUI/ChatMediaPaidContentItem.swift')
fixture = fixture.replace('__ROW__', section(row, '    public func buyProduct(image:', '\n}\n\nprivate class PreviewMediaView'))
interaction = read('packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift')
start = interaction.index('                    case .payment:') + len('                    case .payment:')
fixture = fixture.replace('__KEYBOARD__', interaction[start:interaction.index('                    case let .urlAuth', start)])
with tempfile.TemporaryDirectory(prefix='chat-payment-context-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatPaymentContext", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChatPaymentContextTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ChatPaymentTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
