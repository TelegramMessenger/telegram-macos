import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]

def read(path):
    if args.baseline:
        return subprocess.check_output(['git', '-C', str(root), 'show', 'HEAD:' + path], text=True)
    return (root / path).read_text()

def section(source, start, end, include_end=False):
    offset = source.index(start)
    stop = source.index(end, offset)
    return source[offset:stop + (len(end) if include_end else 0)]

controller = read('packages/ChatUI/Sources/ChatUI/ChatController.swift')
interaction = read('packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift')
search_line = '        self.genericView.bubblesView.updateSearchButton(hidden: !searchAvailable, animated: transition.animated)\n'
parts = {
    '__EMPTY_BOT_START__': section(controller, '    private func updateEmptyBotStartAction()', '    func applyTransition('),
    '__APPLY_TRANSITION_TAIL__': section(controller, search_line, '        self.chatInteraction.invokeInitialAction(includeAuto: true, animated: false)\n', include_end=True)[len(search_line):],
    '__START_BOT__': section(interaction, '    public func startBot(', '    public func clearInput()'),
    '__START_CASE__': section(interaction, '            case let .start(parameter: parameter, behavior: behavior):', '            case let .inputText('),
}
fixture = Path(__file__).with_name('BotStartTests.swift').read_text()
for name, body in parts.items():
    fixture = fixture.replace(name, body)
with tempfile.TemporaryDirectory(prefix='bot-start-restriction-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BotStartRestriction", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BotStartRestrictionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BotStartTests.swift').write_text(fixture)
    print('Testing ' + ('HEAD' if args.baseline else 'working tree') + ' bot start flow', flush=True)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
