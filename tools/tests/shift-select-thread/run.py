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


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


controller = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
state = (root / 'packages/ChatUI/Sources/ChatUI/ChatPresentationInterfaceState.swift').read_text()
interface = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatInterfaceState.swift').read_text()
location = (root / 'packages/TelegramContext/Sources/TelegramContext/ChatLocation.swift').read_text()
mode = (root / 'packages/ChatModeTypes/Sources/ChatModeTypes/ChatMode.swift').read_text()
history = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatHistoryViewForLocation.swift').read_text()

helper_start = 'private func chatHistoryContains('
helper = section(controller, helper_start, 'private func chatHistoryKeepsReadState(') if helper_start in controller else ''
selection = section(controller, '        chatInteraction.withToggledSelectedMessage = { [weak self] f in', '        chatInteraction.getGradientOffsetRect =')
selection_state = section(interface, 'public struct ChatInterfaceSelectionState: Equatable {', 'public struct ChatInterfaceMessageEffect')
methods = section(state, '    public func withUpdatedSelectedMessage(', '    public func withUpdatedSelectedMessages(') + section(state, '    public func withToggledSelectedMessage(', '    public func withRemovedSelectedMessage(')
methods = re.sub(r'return ChatPresentationInterfaceState\(.*?selectionState: (.+?), sidebarEnabled: .*', r'return self.updated(selectionState: \1)', methods)
thread_id = section(location, '    public var threadId: Int64? {', '    public var threadMsgId: MessageId? {')
tag_mask = section(mode, '    public var tagMask: MessageTags? {', '    public var isThreadMode: Bool {')
custom_contents = section(mode, '    public var customChatContents: ChatCustomContentsProtocol? {', '    public var customChatLink: ChatCustomLinkContent? {')
location_input = section(history, 'public struct ChatHistoryLocationInput: Equatable {', 'public enum ChatHistoryLocation: Equatable {')
search_mode = section(state, 'public struct ChatSearchModeState : Equatable {', 'public enum ChatState : Equatable {')
show_all = section(state, '                    chatInteraction.update { current in\n                        var search = current.searchMode', '                }, right: nil, left: nil)')
location_value = section(controller, '    private let location:Promise<ChatHistoryLocationInput> = Promise()', '    //    var content: ChatHistoryLocation')
next_location_id = section(controller, '    private var nextHistoryLocationId: Int32 = 1', '    private let maxVisibleIncomingMessageIndex')
set_location_tag = section(controller, '        chatInteraction.setLocationTag = { [weak self] tag in', '        chatInteraction.revealFactCheck =')
initial_location = section(controller, '                self.setLocation(.init(content: location, chatLocation: chatLocation, tag: self.mode.tagMask', '\n')
tag_update = section(controller, '            if value.searchMode.tag != oldValue.searchMode.tag || value.searchMode.showAll != oldValue.searchMode.showAll {', '            if value.interfaceState.forwardMessageIds != oldValue.interfaceState.forwardMessageIds {')
location_update = section(controller, '            if value.chatLocation != oldValue.chatLocation {', '            if value.chatLocation.threadId == nil {')

fixture = Path(__file__).with_name('ShiftSelectTests.swift.in').read_text()
for name, body in {
    '__HELPER__': helper,
    '__SELECTION__': selection,
    '__SELECTION_STATE__': selection_state,
    '__SELECTION_METHODS__': methods,
    '__THREAD_ID__': thread_id,
    '__TAG_MASK__': tag_mask,
    '__CUSTOM_CONTENTS__': custom_contents,
    '__LOCATION_INPUT__': location_input,
    '__SEARCH_MODE__': search_mode,
    '__SHOW_ALL__': show_all,
    '__LOCATION_VALUE__': location_value,
    '__NEXT_LOCATION_ID__': next_location_id,
    '__SET_LOCATION_TAG__': set_location_tag,
    '__INITIAL_LOCATION__': initial_location,
    '__TAG_UPDATE__': tag_update,
    '__LOCATION_UPDATE__': location_update,
}.items():
    fixture = fixture.replace(name, body.replace('public ', ''))

with tempfile.TemporaryDirectory(prefix='shift-select-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
