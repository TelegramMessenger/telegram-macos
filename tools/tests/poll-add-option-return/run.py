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


def read(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def model(text, needle, what):
    if needle not in text:
        print(f'model out of date: {what} no longer has {needle!r}')
        raise SystemExit(2)


def find(text, needle, start=0):
    index = text.find(needle, start)
    if index < 0:
        print(f'not found: {needle!r}')
        raise SystemExit(2)
    return index


def braces(text, start):
    begin = find(text, '{', start)
    depth = 0
    for index in range(begin, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index + 1]
    print(f'unbalanced braces after {text[start:start + 60]!r}')
    raise SystemExit(2)


def member(text, needle):
    start = find(text, needle)
    body = braces(text, start)
    return re.sub(r'^(private|public|fileprivate) ', '', text[start:find(text, '{', start)] + body)


def between(text, start, *ends):
    begin = find(text, start)
    found = [index for index in (text.find(end, begin + len(start)) for end in ends) if index >= 0]
    if not found:
        print(f'not found: {ends}')
        raise SystemExit(2)
    return text[begin:min(found)]


def strip_access(text):
    return re.sub(r'(^|\n)(\s*)(?:private|public|fileprivate) ', r'\1\2', text)


source = read('packages/PollResultsUI/Sources/PollResultsUI/NewPollController.swift')

poll_option = strip_access(member(source, 'private struct NewPollOption'))
poll_mode = strip_access(member(source, 'private enum NewPollMode'))
poll_source = strip_access(member(source, 'public enum NewPollSource'))

state_text = member(source, 'private struct NewPollState')
state_members = '\n\n'.join(strip_access(member(state_text, needle)) for needle in (
    'public var title: String',
    'public var isEnabled: Bool',
    'public var shouldShowTooltipForQuiz: Bool',
    'public func indexOf(',
    'public func withAddedOption(',
    'public func withDeleteOption(',
))
model(state_text, 'public var isAddOption: Bool = false', 'NewPollState')
model(state_text, 'state.isAddOption = self.isAddOption', 'NewPollState.copy')

entries_function = member(source, 'private func entries(_ state: NewPollState')
add_entries = braces(entries_function, find(entries_function, 'if case let .addOption(_, existingOptions) = source'))
visible = re.search(r'let option = state\.options\[(\w+)\]', add_entries)
if visible is None:
    print('not found: the field of the Add an Option window')
    raise SystemExit(2)
model(add_entries, 'arguments.updateOptionState(option.identifier, state)', 'the Add an Option field')
model(add_entries, 'return entries', 'the Add an Option entries')

controller_function = source[find(source, 'public func NewPollController(chatInteraction: any NewPollChatInteraction'):]
setup = between(controller_function, 'let mode: NewPollMode', 'let animated: Atomic<Bool>')
handlers = between(controller_function, 'let addOption:(Bool)-> InputDataValidation', 'interactions.contentFlowsBehind = true')
model(handlers, 'ModalInteractions(', 'the Add and Send button')
model(controller_function, 'let context = chatInteraction.pollContext', 'NewPollController')

arguments_call = controller_function[find(controller_function, 'let arguments = Arguments(context: context'):]
update_title = braces(arguments_call, find(arguments_call, '}, updateState: '))
update_option = braces(arguments_call, find(arguments_call, '}, updateOptionState: '))
delete_option = braces(arguments_call, find(arguments_call, 'deleteOption: '))

input_controller_call = controller_function[find(controller_function, 'let controller = InputDataController(dataSignal: signal'):]
after_transaction = braces(input_controller_call, find(input_controller_call, 'afterTransaction: { controller in'))
model(after_transaction, 'done.isEnabled = state.isEnabled', 'afterTransaction')
return_key = braces(input_controller_call, find(input_controller_call, 'returnKeyInvocation: '))
delete_key = braces(input_controller_call, find(input_controller_call, 'deleteKeyInvocation: '))

tab_start = find(controller_function, 'chatInteraction.pollContext.window.set(handler: ')
tab_handler = braces(controller_function, tab_start)
model(controller_function[tab_start:tab_start + len(tab_handler) + 200], 'for: .Tab, priority: .supreme', 'the Tab handler')

data_ui = read('packages/InputDataUI/Sources/InputDataUI/InputDataController.swift')
model(data_ui, 'switch returnKeyInvocation(self.currentFirstResponderIdentifier, event) {\n            case .default:\n                if event.type != .keyDown || InputDataUIHooks.shared.checkSendingAbility(event) {\n                    self.validateInput(data: self.fetchData())', 'InputDataController.returnKeyAction')
model(data_ui, '            case .nextResponder:\n                _ = window?.makeFirstResponder(self.nextResponder())\n                return .invoked\n            case .nothing:\n                return .invoked\n            case .invokeEvent:\n                return .invokeNext', 'InputDataController.returnKeyAction')
model(data_ui, 'open override func returnKeyAction() -> KeyHandlerResult {\n        let result = current.returnKeyAction()', 'InputDataModalController.returnKeyAction')
model(data_ui, 'switch self.deleteKeyInvocation(self.currentFirstResponderIdentifier) {\n            case .default:\n                return .rejected\n            case .invoked:\n                return .invoked', 'the Delete handler of InputDataController')
modal = read('packages/TGUIKit/Sources/Modal.swift')
model(modal, 'return controller.returnKeyAction()\n                }\n                return .invokeNext\n            }, with: self, for: .Return, priority: controller.responderPriority)', 'Modal Return')
model(modal, 'return controller.returnKeyAction()\n                }\n                return .invokeNext\n            }, with: self, for: .KeypadEnter, priority: controller.responderPriority)', 'Modal KeypadEnter')
view_controller = read('packages/TGUIKit/Sources/ViewController.swift')
model(view_controller, '_ = self.window?.makeFirstResponder(self.nextResponder())\n                \n                return .invoked\n            }, with: self, for: .Tab, priority: responderPriority)', 'the default Tab handler')
fast_settings = read('packages/InAppSettings/Sources/InAppSettings/FastSettings.swift')
model(fast_settings, 'return isEnterAccessObjc(event, sendingType == .cmdEnter)', 'FastSettings.checkSendingAbility')
objc_utils = read('packages/ObjcUtils/Sources/ObjcUtils/ObjcUtils.m')
model(objc_utils, 'BOOL isEnter = (theEvent.keyCode == 0x24 || theEvent.keyCode ==  0x4C);', 'isEnterEventObjc')
model(objc_utils, 'return !byCmdEnter ? flags == 0 || flags == 65536 || flags == 2097152 : (theEvent.modifierFlags & NSCommandKeyMask) > 0;', 'isEnterAccessObjc')
extensions = read('packages/TGUIKit/Sources/Extensions.swift')
trimmed = member(extensions, 'var trimmed:String')

fixture = (Path(__file__).with_name('PollAddOptionReturnTests.swift.in').read_text()
           .replace('__POLL_OPTION__', poll_option)
           .replace('__POLL_MODE__', poll_mode)
           .replace('__POLL_SOURCE__', poll_source)
           .replace('__STATE_MEMBERS__', state_members)
           .replace('__TRIMMED__', trimmed)
           .replace('__VISIBLE__', visible.group(1))
           .replace('__SETUP__', setup)
           .replace('__UPDATE_TITLE__', update_title)
           .replace('__UPDATE_OPTION__', update_option)
           .replace('__HANDLERS__', handlers + 'interactions.contentFlowsBehind = true')
           .replace('__RETURN_KEY__', return_key)
           .replace('__DELETE_OPTION__', delete_option)
           .replace('__DELETE_KEY__', delete_key)
           .replace('__TAB__', tab_handler))

with tempfile.TemporaryDirectory(prefix='poll-add-option-return-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
