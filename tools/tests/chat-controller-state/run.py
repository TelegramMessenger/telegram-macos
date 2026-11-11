import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
path = 'packages/ChatUI/Sources/ChatUI/ChatController.swift'
source = subprocess.check_output(['git', '-C', str(root), 'show', 'HEAD:' + path], text=True) if args.baseline else (root / path).read_text()

def section(start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]

parts = {
    '__READ_SETUP__': section('        var canRead: Signal<Bool, NoError>', '        let previousMaxIncomingMessageIdByNamespace'),
    '__READ_METHODS__': section('    private func canInteractiveRead()', '    private func messageInCurrentHistoryView('),
    '__REPLY_SETUP__': section('        chatInteraction.setupReplyMessage =', '        chatInteraction.removeAd ='),
}
edit_offset = source.index('context.engine.messages.requestEditMessage(messageId: state.message.id')
callback_offset = source.index('.start(next:', edit_offset)
callback_end = source.index('\n                }))', callback_offset) + len('\n                }))')
parts['__EDIT_REQUEST__'] = '        self.chatInteraction.editDisposable.set((signal |> deliverOnMainQueue)' + source[callback_offset:callback_end]
interaction = (root / 'packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift').read_text()
identity_start = interaction.index('    func isCurrentMediaEditSubmission(')
parts['__EDIT_IDENTITY__'] = interaction[identity_start:interaction.index('    func blockMediaEdit(', identity_start)]
cleanup = section('    private func cleanup()', '    public override func readyToDetach()')
parts['__CLEANUP__'] = '\n'.join(line for line in cleanup.splitlines() if any(name + '.dispose()' in line for name in ['interactiveReadStateDisposable', 'interactiveReadingDisposable', 'interactiveReadReactionsDisposable', 'replyMessageDisposable']))
fixture = Path(__file__).with_name('StateTests.swift').read_text()
for name, body in parts.items():
    fixture = fixture.replace(name, body)
with tempfile.TemporaryDirectory(prefix='chat-controller-state-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatControllerState", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ChatControllerStateTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StateTests.swift').write_text(fixture)
    print('Testing ' + ('HEAD' if args.baseline else 'working tree') + ' ChatController methods', flush=True)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
