import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import LocalAnimations
import TelegramTheme

private func canModerateChannelParticipant(channel: TelegramChannel, accountPeerId: PeerId, member: Peer, participant: ChannelParticipant?) -> Bool {
    guard !channel.isChannel, channel.hasPermission(.banMembers), member.id != accountPeerId, member.isUser || member.isBot,
          let participant = participant, participant.peerId == member.id else {
        return false
    }
    switch participant {
    case .creator:
        return false
    case let .member(_, _, adminInfo, _, _, _):
        if let adminInfo = adminInfo {
            return channel.flags.contains(.isCreator) || adminInfo.canBeEditedByAccountPeer || adminInfo.promotedBy == accountPeerId
        }
        return true
    }
}

final class ChannelParticipantModerationMenu {
    let authorizedParticipant: Signal<ChannelParticipant?, NoError>
    private let accountPeerId: PeerId
    private let member: Peer
    private let disposable = MetaDisposable()
    private(set) var isAuthorized = false

    init(accountPeerId: PeerId, member: Peer, participant: Signal<(TelegramChannel?, ChannelParticipant?), NoError>) {
        self.accountPeerId = accountPeerId
        self.member = member
        self.authorizedParticipant = participant
        |> map { channel, participant -> ChannelParticipant? in
            guard let channel, canModerateChannelParticipant(channel: channel, accountPeerId: accountPeerId, member: member, participant: participant) else {
                return nil
            }
            return participant
        }
        |> then(.single(nil))
        |> take(1)
        |> timeout(10.0, queue: .mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
    }

    func items(channel: TelegramChannel, participant: ChannelParticipant?, restrict: @escaping () -> Void, ban: @escaping () -> Void) -> [ContextMenuItem] {
        guard !channel.isChannel, channel.hasPermission(.banMembers), member.id != accountPeerId, member.isUser || member.isBot else {
            return []
        }
        if let participant, !canModerateChannelParticipant(channel: channel, accountPeerId: accountPeerId, member: member, participant: participant) {
            return []
        }
        let restrict = ChannelParticipantModerationMenuItem(strings().chatContextRestrict, authorization: self, handler: restrict, itemImage: MenuAnimation.menu_restrict.value)
        let ban = ChannelParticipantModerationMenuItem(strings().chatContextBan, authorization: self, handler: ban, itemMode: .destruct, itemImage: MenuAnimation.menu_ban.value)
        disposable.set(authorizedParticipant.start(next: { [weak self, weak restrict, weak ban] participant in
            let isAuthorized = participant != nil
            self?.isAuthorized = isAuthorized
            restrict?.updateAuthorization(isAuthorized)
            ban?.updateAuthorization(isAuthorized)
        }))
        return [restrict, ban]
    }

    deinit {
        disposable.dispose()
    }
}

private final class ChannelParticipantModerationMenuItem: ContextMenuItem, NSMenuItemValidation {
    private let authorization: ChannelParticipantModerationMenu
    private var isAuthorized: Bool?

    init(_ title: String, authorization: ChannelParticipantModerationMenu, handler: @escaping () -> Void, itemMode: AppMenu.ItemMode = .normal, itemImage: ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)?) {
        self.authorization = authorization
        super.init(title, handler: { [weak authorization] in
            guard authorization?.isAuthorized == true else { return }
            handler()
        }, itemMode: itemMode, itemImage: itemImage)
        self.isEnabled = false
    }

    required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var menu: NSMenu? {
        didSet {
            if menu != nil, isAuthorized == false {
                DispatchQueue.main.async { [weak self] in
                    if let self {
                        self.removeFromMenu(self)
                    }
                }
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return authorization.isAuthorized
    }

    func updateAuthorization(_ isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
        self.isEnabled = isAuthorized
        self.redraw?()
        if !isAuthorized {
            removeFromMenu(self)
        }
    }

    private func removeFromMenu(_ item: NSMenuItem) {
        guard let menu = item.menu as? ContextMenu else { return }
        var items: [NSMenuItem] = []
        for current in menu.items where current !== item {
            if current.isSeparatorItem, items.last == nil || items.last?.isSeparatorItem == true {
                continue
            }
            items.append(current)
        }
        if items.last?.isSeparatorItem == true {
            items.removeLast()
        }
        menu.items = items
        if items.isEmpty, let parent = menu.supermenu?.items.first(where: { $0.submenu === menu }) {
            removeFromMenu(parent)
        }
    }
}
