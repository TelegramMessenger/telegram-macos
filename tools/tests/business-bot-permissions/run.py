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
    '__APPLY_BOT__': block(source, 'func applyBot(') if not args.baseline else '',
    '__SEARCH__': block(source, 'private extension Array where Element == State.Permission'),
    '__MAKE_PERMISSIONS__': block(source, 'let makePermissions:'),
    '__TOGGLE__': toggle,
}
for key, value in replacements.items():
    fixture = fixture.replace(key, value)
if args.baseline:
    fixture = fixture[:fixture.index('final class BusinessBotRestorationTests:')]
    start = fixture.index('    func restore(')
    end = fixture.index('    func with<T>', start)
    fixture = fixture[:start] + fixture[end:]

with tempfile.TemporaryDirectory(prefix='business-bot-permissions-') as directory:
    directory = Path(directory)
    (directory / 'Tests').mkdir()
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "BusinessBotPermissions", targets: [.testTarget(name: "BusinessBotPermissionsTests", path: "Tests")])
''')
    (directory / 'Tests/BusinessBotPermissionsTests.swift').write_text(fixture)
    print(f'Testing {"baseline" if args.baseline else "working tree"} permissions', flush=True)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--jobs', '4']).returncode)
