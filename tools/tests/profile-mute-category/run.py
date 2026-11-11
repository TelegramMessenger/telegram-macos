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

PEER_INFO = 'packages/PeerInfoUI/Sources/PeerInfoUI/'
CHAT = 'packages/ChatUI/Sources/ChatUI/'
CORE = 'submodules/telegram-ios/submodules/TelegramCore/Sources/'


def source(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def block(text, start):
    begin = text.find(start)
    if begin < 0:
        print(f'not found: {start}')
        raise SystemExit(2)
    depth = 0
    for index in range(text.index('{', begin), len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index + 1]
    print(f'no end: {start}')
    raise SystemExit(2)


def between(text, start, end):
    begin = text.find(start)
    finish = text.find(end, begin + len(start)) if begin >= 0 else -1
    if begin < 0 or finish < 0:
        print(f'not found: {start} .. {end}')
        raise SystemExit(2)
    return text[begin:finish]


def flat(text):
    return re.sub(r'\s+', ' ', text)


head = source(PEER_INFO + 'PeerInfoHeadItem.swift')
controller = source(PEER_INFO + 'PeerInfoController.swift')
dispatcher = block(source(PEER_INFO + 'PeerInfoEntries.swift'), 'func peerInfoEntries<')
group = source(PEER_INFO + 'GroupInfoEntries.swift')
channel = source(PEER_INFO + 'ChannelInfoEntries.swift')
user = source(PEER_INFO + 'UserInfoEntries.swift')
state = source(CHAT + 'ChatPresentationInterfaceState.swift')
chat = source(CHAT + 'ChatController.swift')

actions = block(head, 'private func actionItems<Context: AccountContextProtocol>(item: PeerInfoHeadItem<Context>')
user_marker = 'if let peer = item.peer as? TelegramUser, let arguments = item.arguments as? UserInfoArguments<Context>'
group_marker = '} else if let peer = item.peer, peer.isSupergroup || peer.isGroup, let arguments = item.arguments as? GroupInfoArguments<Context> {'
channel_marker = '} else if let peer = item.peer as? TelegramChannel, peer.isChannel, let arguments = item.arguments as? ChannelInfoArguments<Context> {'
topic_marker = '} else if let arguments = item.arguments as? TopicInfoArguments<Context>'
segments = {
    'user': between(actions, user_marker, group_marker),
    'group': between(actions, group_marker, channel_marker),
    'channel': between(actions, channel_marker, topic_marker),
}
button = re.compile(r'(?P<binding>if let value = |let value = )(?P<expr>[^\n]+?)(?P<brace> \{)?\n\s*items\.append\(ActionItem\(text: value \? strings\(\)\.peerInfoActionUnmute : strings\(\)\.peerInfoActionMute,[^\n]*action: \{\n\s*arguments\.toggleNotifications\((?P<argument>[^\n]*)\)\n')

buttons = {}
for name, segment in segments.items():
    found = list(button.finditer(segment))
    if len(found) != 1:
        print(f'{name} profile: expected one Mute button, found {len(found)}')
        raise SystemExit(2)
    match = found[0]
    expr = match.group('expr')
    if match.group('binding').startswith('if let'):
        body = f'if let value = {expr} {{\n        return value\n    }}\n    return nil'
    else:
        body = f'let value = {expr}\n    return value'
    buttons[name] = (body, match.group('argument'))

toggle_body = block(controller, 'func toggleNotifications(_ currentlyMuted: Bool) {')
toast = re.search(r'showModalText\(for: context\.window, text: (?P<toast>[^\n]+)\)\n', toggle_body)
if not toast:
    print('the profile toast is not found')
    raise SystemExit(2)
profile_toggles = 'context.engine.peers.togglePeerMuted(peerId: effectivePeerId, threadId: nil)' in toggle_body

profile_default = re.search(r'let mutedByDefault = (?P<expr>[^\n]+)\n', dispatcher)
if profile_default:
    profile_default_body = f'let mutedByDefault = {profile_default.group("expr")}\n    return mutedByDefault'
else:
    profile_default_body = 'return false'

builder_calls = re.findall(r'return (?:user|channel|group)InfoEntries\(view: view[^\n]*', dispatcher)
builders_get_default = len(builder_calls) == 4 and all(call.endswith(', mutedByDefault: mutedByDefault)') for call in builder_calls)

signal_source = 'Signal<GlobalNotificationSettings, NoError> = context.account.postbox.preferencesView(keys: [PreferencesKeys.globalNotifications]) |> map { view in return view.values[PreferencesKeys.globalNotifications]?.get(GlobalNotificationSettings.self) ?? GlobalNotificationSettings.defaultSettings }'


def follows_settings(text):
    start = text.find('let globalNotificationSettings: Signal<GlobalNotificationSettings, NoError> = ')
    if start < 0:
        return False
    statement = block(text, 'let globalNotificationSettings: Signal<GlobalNotificationSettings, NoError> = ')
    rest = text[start + len(statement):].lstrip(' \t')
    return flat('let globalNotificationSettings: ' + signal_source) == flat(statement) and rest.startswith('\n') and not rest.lstrip().startswith('|>')
profile_reads_settings = (
    follows_settings(controller)
    and re.search(r'savedMuicProfileState, globalNotificationSettings\)\n\s*\|> mapToQueue \{[^\n]*, globalNotificationSettings ->', controller) is not None
    and 'globalNotificationSettings: globalNotificationSettings).map({PeerInfoSortableEntry(entry: $0)})' in controller
)

group_info = block(group, 'case let .info(lhsSection, lhsPeerView')
group_checks = [
    ('group profile: the head entry carries the category default', re.search(r'entries\.append\(\.info\(section: GroupInfoSection\.header\.rawValue,[^\n]*mutedByDefault: mutedByDefault, viewType: \.singleItem\)\)', group) is not None),
    ('group profile: the button gets the category default', re.search(r'return PeerInfoHeadItem\([^\n]*updatePhoto: arguments\.updateGroupPhoto[^\n]*mutedByDefault: mutedByDefault\)', group) is not None),
    ('group profile: a category change updates the button', 'if lhsMutedByDefault != rhsMutedByDefault { return false }' in flat(group_info)),
]
channel_checks = [
    ('channel profile: the head entry carries the category default', re.search(r'entries\.append\(\.info\(sectionId: \.header,[^\n]*mutedByDefault: mutedByDefault, viewType: \.singleItem\)\)', channel) is not None),
    ('channel profile: the button gets the category default', re.search(r'return PeerInfoHeadItem\([^\n]*updatePhoto: arguments\.updateChannelPhoto[^\n]*mutedByDefault: mutedByDefault\)', channel) is not None),
    ('channel profile: a category change updates the button', 'case let .info(sectionId, lhsPeerView, editable, updatingPhotoState, stories, mutedByDefault, viewType):' in channel and 'case .info(sectionId, let rhsPeerView, editable, updatingPhotoState, stories, mutedByDefault, viewType):' in channel),
]
user_info = block(user, 'case let .info(lhsSectionId, lhsPeerView')
user_checks = [
    ('user profile: the head entry carries the category default', re.search(r'UserInfoEntry<Context>\.info\(sectionId: sectionId,[^\n]*mutedByDefault: mutedByDefault, viewType: \.singleItem\)\)', user) is not None),
    ('user profile: the button gets the category default', 'profileSavedMusic: arguments.getSavedMusicContext?(), mutedByDefault: mutedByDefault)' in user),
    ('user profile: a category change updates the button', 'if lhsMutedByDefault != rhsMutedByDefault { return false }' in flat(user_info)),
]

bar = re.compile(r'return \.action\((?P<expr>[^\n]+?) \? strings\(\)\.chatInputUnmute : strings\(\)\.chatInputMute, \{ chatInteraction in\n\s*chatInteraction\.toggleNotifications\((?P<argument>[^)\n]*)\)')
sites = []
functions = ['func barButton(_ index: Int, _ state: ChatState) -> Bool? {', '    switch index {']
for index, match in enumerate(bar.finditer(state)):
    before = state[:match.start()].splitlines()
    if 'chatLocation.peerId == repliesPeerId' in '\n'.join(before[-2:]):
        sites.append(('Replies', 'replies'))
    elif '.isGigagroup' in '\n'.join(before[-12:]):
        sites.append(('gigagroup', 'gigagroup'))
    else:
        sites.append(('channel' if not any(site[1] == 'channel' for site in sites) else 'channel, second check', 'channel'))
    expr = match.group('expr')
    functions.append(f'    case {index}:')
    functions.append('        let mutedByDefault = state.mutedByDefault')
    if 'notificationSettings?.' in expr:
        functions.append('        let notificationSettings = state.notificationSettings')
    else:
        functions.append('        guard let notificationSettings = state.notificationSettings else {')
        functions.append('            return nil')
        functions.append('        }')
    functions.append(f'        return {expr}')
    sites[-1] = sites[-1] + (match.group('argument'),)
functions += ['    default:', '        return nil', '    }', '}']

bar_toggles_core = len(sites) == 4 and all(site[2] == 'nil' for site in sites)
handler = block(chat, 'chatInteraction.toggleNotifications = { [weak self] isMuted in')
handler_toggles = 'if isMuted == nil || isMuted == true { _ = context.engine.peers.togglePeerMuted(peerId: peerId, threadId: self.chatLocation.threadId).start() } else {' in flat(handler)
handler_mutes = 'options.append(ModalOptionSet(title: strings().chatListMuteForever, selected: true, editable: true))' in handler and 'context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: self?.chatLocation.threadId, muteInterval: intervals[i])' in handler and 'Int32.max]' in handler

menu = block(chat, 'fileprivate func buildChatActionsMenu() -> ContextMenu? {')
menu_start = menu.find('if let notificationSettings = peerView.notificationSettings as? TelegramPeerNotificationSettings, !self.isAdChat {')
menu_guard = menu.find('if chatInteraction.peerId != context.peerId && chatSidebarKind(chatInteraction.presentation) == nil {', menu_start)
menu_item = menu.find('items.append(ContextMenuItem(', menu_guard)
if min(menu_start, menu_guard, menu_item) < 0:
    print('the chat header menu item is not found')
    raise SystemExit(2)
menu_prelude = menu[menu_guard + len('if chatInteraction.peerId != context.peerId && chatSidebarKind(chatInteraction.presentation) == nil {'):menu_item].strip()
menu_match = re.match(r'items\.append\(ContextMenuItem\((?P<label>.+?), handler: \{ \[weak self\] in\n\s*self\?\.chatInteraction\.toggleNotifications\((?P<argument>[^)\n]*)\)\n', menu[menu_item:])
if not menu_match:
    print('the chat header menu item has an unexpected shape')
    raise SystemExit(2)

chat_default = re.search(r'present = present\.updatedNotificationSettings\(notificationSettings, mutedByDefault: (?P<expr>[^\n]+)\)\n', chat)
chat_default_expr = chat_default.group('expr') if chat_default else 'false'
chat_reads_settings = (
    follows_settings(chat)
    and re.search(r'monoforumTopics\.get\(\), globalNotificationSettings\)\.start\(next: \{[^\n]*, monoforumTopics, globalNotificationSettings in', chat) is not None
)

constructors = state.count('ChatPresentationInterfaceState(interfaceState:')
keeps = state.count('mutedByDefault: self.mutedByDefault, inputQueryResult:')
setter = block(state, 'public func updatedNotificationSettings(')
state_keeps_default = (
    constructors > 0
    and keeps == constructors - 1
    and setter.startswith('public func updatedNotificationSettings(_ notificationSettings:TelegramPeerNotificationSettings?, mutedByDefault: Bool)')
    and 'notificationSettings: notificationSettings, mutedByDefault: mutedByDefault, inputQueryResult:' in setter
    and 'self.mutedByDefault = false' in block(state, 'public init(chatLocation: ChatLocation, chatMode: ChatMode) {')
    and 'self.mutedByDefault = mutedByDefault' in state
)

extras = flat(source('packages/TelegramUtils/Sources/TelegramUtils/CoreTypeExtras.swift'))
is_muted_model = 'public extension TelegramPeerNotificationSettings { var isMuted:Bool { switch self.muteState { case let .muted(until): return until > Int32(Date().timeIntervalSince1970) case .unmuted: return false case .default: return false } } }' in extras

core_checks = []
toggle_file = root / CORE / 'TelegramEngine/Peers/ChangePeerNotificationSettings.swift'
include_file = root / CORE / 'SyncCore/SyncCore_GlobalNotificationSettings.swift'
settings_file = root / CORE / 'SyncCore/SyncCore_TelegramPeerNotificationSettings.swift'
resolve_file = root / 'submodules/telegram-ios/submodules/Postbox/Sources/PeerNotificationSettings.swift'
if all(path.exists() for path in (toggle_file, include_file, settings_file, resolve_file)):
    core_toggle = flat(toggle_file.read_text())
    core_include = flat(include_file.read_text())
    core_settings = flat(settings_file.read_text())
    core_resolve = flat(resolve_file.read_text())
    core_checks = [
        ('missing settings count as unmuted in TelegramCore, as in the model', 'let previousSettings: TelegramPeerNotificationSettings if let currentSettings = currentSettings { previousSettings = currentSettings } else { previousSettings = TelegramPeerNotificationSettings.defaultSettings }' in core_toggle and 'return TelegramPeerNotificationSettings(muteState: .unmuted, messageSound: .default' in core_settings),
        ('a secret chat toggles its user in TelegramCore, as in the model', 'if peer is TelegramSecretChat, let associatedPeerId = peer.associatedPeerId { notificationPeerId = associatedPeerId }' in core_toggle),
        ('isRemovedFromTotalUnreadCount matches TelegramCore', 'public func isRemovedFromTotalUnreadCount(`default`: Bool) -> Bool { switch self.muteState { case .unmuted: return false case .muted: return true case .default: return `default` } }' in core_settings),
        ('the chat list rule matches Postbox', 'let defaultValue = !globalSettings.defaultIncludePeer(peer) if let peerSettings = peerSettings { return peerSettings.isRemovedFromTotalUnreadCount(default: defaultValue) } else { return defaultValue }' in core_resolve),
        ('the toggle model matches TelegramCore', 'switch previousSettings.muteState { case .default: let globalNotificationSettings = transaction.getGlobalNotificationSettings() if resolvedIsRemovedFromTotalUnreadCount(globalSettings: globalNotificationSettings, peer: peer, peerSettings: previousSettings) { updatedSettings = previousSettings.withUpdatedMuteState(.unmuted) } else { updatedSettings = previousSettings.withUpdatedMuteState(.muted(until: Int32.max)) } case .unmuted: updatedSettings = previousSettings.withUpdatedMuteState(.muted(until: Int32.max)) case .muted: updatedSettings = previousSettings.withUpdatedMuteState(.unmuted) }' in core_toggle),
        ('the category model matches TelegramCore', 'if peer is TelegramUser || peer is TelegramSecretChat { return settings.privateChats.enabled } else if peer is TelegramGroup { return settings.groupChats.enabled } else if let channel = peer as? TelegramChannel { switch channel.info { case .group: return settings.groupChats.enabled case .broadcast: return settings.channels.enabled } }' in core_include),
    ]
else:
    print('note: TelegramCore sources are not here, the toggle model is not compared with them')

source_checks = [
    ('the profile follows the notification category settings', profile_reads_settings),
    ('the profile passes the category default to every profile kind', builders_get_default),
    ('the profile button keeps the category default it gets', 'mutedByDefault: Bool = false) {' in head and 'self.mutedByDefault = mutedByDefault' in head),
    *group_checks,
    *channel_checks,
    *user_checks,
    ('the profile button toggles through togglePeerMuted', profile_toggles),
    ('the chat follows the notification category settings', chat_reads_settings),
    ('every chat state update keeps the category default', state_keeps_default),
    ('the input bar buttons toggle through togglePeerMuted', bar_toggles_core and handler_toggles),
    ('Mute in the chat header menu mutes forever by default', handler_mutes),
    ('the isMuted model matches TelegramUtils', is_muted_model),
    *core_checks,
]

fixture = (Path(__file__).with_name('ProfileMuteCategoryTests.swift.in').read_text()
           .replace('__PROFILE_MUTED_BY_DEFAULT__', profile_default_body)
           .replace('__USER_BUTTON__', buttons['user'][0])
           .replace('__GROUP_BUTTON__', buttons['group'][0])
           .replace('__CHANNEL_BUTTON__', buttons['channel'][0])
           .replace('__USER_ARGUMENT__', buttons['user'][1])
           .replace('__GROUP_ARGUMENT__', buttons['group'][1])
           .replace('__CHANNEL_ARGUMENT__', buttons['channel'][1])
           .replace('__TOAST__', toast.group('toast'))
           .replace('__CHAT_MUTED_BY_DEFAULT__', chat_default_expr)
           .replace('__HEADER_PRELUDE__', menu_prelude)
           .replace('__HEADER_LABEL__', menu_match.group('label'))
           .replace('__HEADER_ARGUMENT__', menu_match.group('argument'))
           .replace('__BAR_FUNCTIONS__', '\n'.join(functions))
           .replace('__BAR_SITES__', '[' + ', '.join(f'("{name}", .{kind})' for name, kind, _ in sites) + ']')
           .replace('__SOURCE_CHECKS__', '\n'.join(f'    ("{name}", {"true" if passed else "false"}),' for name, passed in source_checks)))

with tempfile.TemporaryDirectory(prefix='profile-mute-category-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
