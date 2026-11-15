import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def code(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def between(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def around(text, needle, start, end):
    middle = text.index(needle)
    return text[text.rindex(start, 0, middle):text.index(end, middle)]


def after(text, label):
    return text.split(label, 1)[1]


try:
    interaction = code('packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift')
    controller = code('packages/ChatUI/Sources/ChatUI/ChatController.swift')
    state = code('packages/ChatUI/Sources/ChatUI/ChatPresentationInterfaceState.swift')
    row = code('packages/ChatUI/Sources/ChatUI/ChatRowItem.swift')
    hooks = code('packages/ChatUI/Sources/ChatUI/ChatInterfaceHooks.swift')
    navigation = code('packages/TGUIKit/Sources/NavigationViewController.swift')

    parts = {
        '__INTERFACE_CONTROLLER__': between(hooks, 'public protocol ChatInterfaceController: ViewController {', 'public enum ChatInterfaceInAppLink').replace('public protocol', 'protocol'),
        '__PREVIOUS_CONTROLLER__': between(navigation, '    open var previousController: ViewController? {', '    open var canSwipeBack: Bool {').replace('open var', 'var'),
        '__PINNED_FIELDS__': between(interaction, '    public var openPinnedMessages:', '    public var setLocation:').replace('public ', ''),
        '__OPEN_PINNED__': between(controller, '        chatInteraction.openPinnedMessages = {', '        chatInteraction.unpinAllMessages = {'),
        '__FOOTER__': around(state, 'strings().chatPinnedUnpinAllOther(', '            case .pinned:', '            default:'),
        '__GOTO_PINNED__': after(between(row, '    public func gotoSourceMessage() {', '            default:'), 'case .pinned:'),
    }
except ValueError as error:
    print(f'the source changed shape: {error}')
    raise SystemExit(2)

fixture = Path(__file__).with_name('PreviewUnpinAllTests.swift.in').read_text()
for name, body in parts.items():
    fixture = fixture.replace(name, body)

with tempfile.TemporaryDirectory(prefix='preview-unpin-all-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
