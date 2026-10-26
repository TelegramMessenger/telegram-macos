import argparse
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
path = 'packages/BusinessUI/Sources/BusinessUI/BusinessChatbotController.swift'
source = subprocess.check_output(['git', 'show', f'HEAD:{path}'], cwd=root, text=True) if args.baseline else (root / path).read_text()
core = (root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/QuickReplyMessages.swift').read_text()


def block(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


rights = core[core.index('public struct TelegramBusinessBotRights:'):core.index('    public init(from decoder:', core.index('public struct TelegramBusinessBotRights:'))]
toggle = source[source.index('    }, toggleRight: { id in') + len('    }, toggleRight: '):source.index('    }, removeSelected:') + 5]
fixture = Path(__file__).with_name('BusinessBotPermissionsTests.swift').read_text()
replacements = {
    '__RIGHTS__': rights.replace('OptionSet, Codable', 'OptionSet') + '}',
    '__STATE__': block(source, 'private struct State : Equatable').replace('private struct State', 'struct State'),
    '__APPLY_BOT__': block(source, 'func applyBot('),
    '__SEARCH__': block(source, 'private extension Array where Element == State.Permission'),
    '__MAKE_PERMISSIONS__': block(source, 'let makePermissions:'),
    '__TOGGLE__': toggle,
    '__REMOVE_SELECTED__': block(source, 'removeSelected: {').removeprefix('removeSelected: '),
    '__REMOVE_MENU__': block(source, 'ContextMenuItem(strings().contextRemove, handler: {').split('handler: ', 1)[1],
    '__SELECT_CHATS_CALLBACK__': block(source, 'callback: { peerIds in').removeprefix('callback: '),
    '__SELECTED_EXCLUSIONS__': source.split('selected = stateValue.with { Set(')[1].split(') }')[0],
    '__VALIDATE_DATA__': block(source, 'controller.validateData ='),
    '__ON_DEINIT__': block(source, 'controller.onDeinit ='),
}
fixture += Path(__file__).with_name('BusinessBotSaveTests.swift').read_text()
for key, value in replacements.items():
    fixture = fixture.replace(key, value)

with tempfile.TemporaryDirectory(prefix='business-bot-permissions-') as directory:
    directory = Path(directory)
    (directory / 'Tests').mkdir()
    (directory / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "BusinessBotPermissions", platforms: [.macOS(.v10_13)], dependencies: [.package(name: "SSignalKit", path: "{root / 'submodules/telegram-ios/submodules/SSignalKit'}")], targets: [.testTarget(name: "BusinessBotPermissionsTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests/BusinessBotPermissionsTests.swift').write_text(fixture)
    print(f'Testing {"baseline" if args.baseline else "working tree"} permissions', flush=True)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--jobs', '4']).returncode)
