import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', metavar='REVISION')
parser.add_argument('--scratch-path', type=Path)
args = parser.parse_args()


def source(path, baseline=True):
    if args.baseline and baseline:
        return subprocess.check_output(['git', '-C', str(root), 'show', args.baseline + ':' + path], text=True)
    return (root / path).read_text()


def section(text, start, end):
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError(f'Expected unique boundaries: {start!r}, {end!r}')
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def block(text, marker):
    if text.count(marker) != 1:
        raise ValueError(f'Expected unique marker: {marker!r}')
    begin = text.index(marker)
    end = text.index('{', begin) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[begin:end]


chat = 'packages/ChatUI/Sources/ChatUI/'
gui = 'packages/TGUIKit/Sources/'
input_source = source(chat + 'ChatInputView.swift')
interaction = source(chat + 'ChatInterfaceInteraction.swift')
controller = source(chat + 'ChatController.swift')
editor = source(chat + 'RichTextEditorWindowController.swift')
menu = source(gui + 'AppMenuController.swift')
context = source(chat + 'InputContextHelper.swift')
objc = source('packages/ObjcUtils/Sources/ObjcUtils/ObjcUtils.m')
parts = {
    '__PLAIN_ENTER__': block(input_source, '    public func textViewEnterPressed('),
    '__RICH_HANDLERS__': block(input_source, '    private func updateRichDraftKeyHandlers()'),
    '__RICH_SHORTCUT__': block(input_source, '    private func processRichDraftSilentSendShortcut(') if '    private func processRichDraftSilentSendShortcut(' in input_source else '',
    '__SEND_MENU__': interaction[interaction.index('public func sendMessageMenuItems('):],
    '__RICH_ATTRIBUTES__': section(block(controller, '                func applyRichDraft('), '                    var attributes: [MessageAttribute]', '                    let message: EnqueueMessage') if '                    let message: EnqueueMessage' in block(controller, '                func applyRichDraft(') else section(block(controller, '                func applyRichDraft('), '                    var attributes: [MessageAttribute]', '                    richTextEnqueue('),
    '__CONTROLLER_RETURN__': block(controller, '    public override func returnKeyAction()'),
    '__MENU_INVOKE__': block(menu, '    private func invokeReturnKeyEquivalent(') if '    private func invokeReturnKeyEquivalent(' in menu else '    private func invokeReturnKeyEquivalent(_ event: NSEvent) -> Bool { false }',
}
end_marker = '        }, with: self, for: .Return, priority: .modal)'
assert context.count(end_marker) == 1
end = context.index(end_marker) + len(end_marker)
begin = context.rfind('        context.window.set(handler:', 0, end)
parts['__CONTEXT_RETURN__'] = context[begin:end]
flag = '    var allowsSilentSendShortcut: Bool = false'
parts['__SUGGESTION_FLAG__'] = flag if flag in context else ''
opt_in = '        inputContextHelper.controller.allowsSilentSendShortcut = true'
parts['__MAIN_SUGGESTION_OPT_IN__'] = opt_in.replace('inputContextHelper.controller', 'fixture') if opt_in in controller else ''
marker = '        controller.returnKeyInvocation = { [weak coordinator] _, event in'
if marker in editor:
    parts['__MODAL_RETURN__'] = block(editor, marker)
else:
    original = block(editor, '    let controller = InputDataController(dataSignal: signal, title: "", hasDone: false, returnKeyInvocation:')
    parts['__MODAL_RETURN__'] = 'controller.returnKeyInvocation = ' + original[original.index('{'):]
row_source = source(gui + 'AppMenuRowItem.swift')
if '        let keyEquivalent = ' in row_source:
    parts['__MENU_LABEL__'] = row_source.split('        let keyEquivalent = ', 1)[1].split('\n', 1)[0]
else:
    parts['__MENU_LABEL__'] = 'item.returnKeyEquivalentText ?? item.keyEquivalent' if 'item.returnKeyEquivalentText ?? item.keyEquivalent' in row_source else 'item.keyEquivalent'
parts['__KEY_EQUIVALENT__'] = block(source(gui + 'ContextMenu.swift'), '    public enum KeyEquiavalent: String {')
fixture = Path(__file__).with_name('SilentSendShortcutTests.swift.in').read_text()
for marker, text in parts.items():
    if fixture.count(marker) != 1:
        raise ValueError(f'Expected one fixture marker: {marker}')
    fixture = fixture.replace(marker, text)
helper = source(chat + 'ChatSilentSendShortcut.swift', baseline=False).replace('import TGUIKit\n', '')
native = block(objc, 'BOOL isEnterEventObjc(') + '\n' + block(objc, 'BOOL isEnterAccessObjc(')
action = source(chat + 'ChatDeferredSendAction.swift')
action = action[:action.index('\nfunc chatHasSameDeferredSendState(')]
key_result = block(source(gui + 'Window.swift'), 'public enum KeyHandlerResult {')
with tempfile.TemporaryDirectory(prefix='silent-send-shortcut-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SilentSendShortcut", platforms: [.macOS(.v10_15)], dependencies: [.package(path: ''' + json.dumps(str(root / 'packages/KeyboardKey')) + ''')], targets: [.target(name: "SendingPreference", path: "Native", publicHeadersPath: "include"), .testTarget(name: "SilentSendShortcutTests", dependencies: ["SendingPreference", .product(name: "KeyboardKey", package: "KeyboardKey")], path: "Tests")])
''')
    (directory / 'Native/include').mkdir(parents=True)
    (directory / 'Native/include/SendingPreference.h').write_text('#import <Cocoa/Cocoa.h>\nBOOL isEnterEventObjc(NSEvent *event);\nBOOL isEnterAccessObjc(NSEvent *event, BOOL byCmdEnter);\n')
    (directory / 'Native/SendingPreference.m').write_text('#import "SendingPreference.h"\n' + native)
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ChatSilentSendShortcut.swift').write_text(helper)
    (directory / 'Tests/ContextMenuKeyEquivalent.swift').write_text(source(gui + 'ContextMenuKeyEquivalent.swift', baseline=False))
    (directory / 'Tests/ChatDeferredSendAction.swift').write_text(action + '\n' + key_result)
    (directory / 'Tests/SilentSendShortcutTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--jobs', '2']
    if args.scratch_path:
        command += ['--scratch-path', str(args.scratch_path.resolve())]
    raise SystemExit(subprocess.run(command).returncode)
