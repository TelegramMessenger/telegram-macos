import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--revision')
parser.add_argument('--signal-kit', type=Path, default=root / 'submodules/telegram-ios/submodules/SSignalKit')
args = parser.parse_args()


def source(path):
    if args.revision:
        return subprocess.check_output(['git', '-C', str(root), 'show', args.revision + ':' + path], text=True)
    return (root / path).read_text()


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


header = source('packages/ChatUI/Sources/ChatUI/ChatHeaderBubblesView.swift')
controller = source('packages/ChatUI/Sources/ChatUI/ChatController.swift')
leave = source('packages/ChatUI/Sources/ChatUI/LeaveChatActions.swift')
navigation = source('packages/TGUIKit/Sources/NavigationViewController.swift')
if not args.revision:
    assert 'if mode.isSavedMessagesThread {\n            SavedChatControllerRegistry.shared.add(self)' in controller
registry = (root / 'packages/ChatUI/Sources/ChatUI/SavedChatControllerRegistry.swift').read_text()
registry = registry[registry.index('final class SavedChatControllerRegistry'):].replace('final class SavedChatControllerRegistry', 'private final class SavedChatControllerRegistry')
parts = {
    '__REGISTRY__': registry,
    '__HEADER__': section(header, '            case .savedMessages:', '            case .saved:'),
    '__COUNTER__': section(controller, '                        |> map { views -> Int32? in', '\n\n                    } else if isThread'),
    '__METADATA__': section(controller, '            if let peer = value.mainPeer, let oldPeer = oldValue.mainPeer {', '\n\n        }'),
    '__DELETE__': section(leave, '            let verify = verifyAlertSignal', '\n}'),
    '__REMOVE__': section(navigation, '    public func removeImmediately(_ controller: ViewController, upNext: Bool = true)', '    public func index(of controller:'),
    '__ENUMERATE__': section(navigation, '    public func enumerateControllers(', '    open override func viewWillAppear'),
    '__CLOSE__': section(navigation, '    public func close(animated:Bool = true)', '    public func set(modalAction:'),
}
parts['__HEADER__'] = parts['__HEADER__'].removeprefix('            case .savedMessages:\n')
strings = plistlib.loads(subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', str(root / 'Telegram-Mac/en.lproj/Localizable.strings')]))
keys = ['Chat.Title.Topic_other', 'Chat.Title.Topic_ZeroValueHolder', 'SharedMedia.SavedCount_other', 'Peer.MyNotes', 'Alert.OK']
parts['__STRINGS__'] = '[' + ', '.join(json.dumps(key) + ': ' + json.dumps(strings[key]) for key in keys) + ']'
fixture = Path(__file__).with_name('SavedChatTests.swift.in').read_text()
for key, body in parts.items():
    fixture = fixture.replace(key, body)

with tempfile.TemporaryDirectory(prefix='saved-chat-header-') as directory:
    directory = Path(directory)
    (directory / 'Tests').mkdir()
    (directory / 'Tests/SavedChatTests.swift').write_text(fixture)
    shutil.copytree(args.signal_kit / 'SwiftSignalKit2/Source', directory / 'SignalKit')
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SavedChatHeader", platforms: [.macOS(.v10_13)], targets: [.target(name: "SwiftSignalKit", path: "SignalKit"), .testTarget(name: "SavedChatTests", dependencies: ["SwiftSignalKit"], path: "Tests")])
''')
    print('Testing extracted production branches from ' + (args.revision or 'working tree'), flush=True)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--jobs', '4']).returncode)
