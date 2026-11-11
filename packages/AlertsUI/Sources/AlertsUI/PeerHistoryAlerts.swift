import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import TGUIKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils

public func clearHistory(context: any AccountContextProtocol, peer: Peer, mainPeer: Peer, canDeleteForAll: Bool? = nil) {
    var thridTitle: String? = nil
    var canRemoveGlobally: Bool = canDeleteForAll ?? false
    if peer.id.namespace == Namespaces.Peer.CloudUser && peer.id != context.account.peerId && !peer.isBot {
        if context.limitConfiguration.maxMessageRevokeIntervalInPrivateChats == LimitsConfiguration.timeIntervalForever {
            canRemoveGlobally = true
        }
    }
    if canRemoveGlobally {
        if let peer = peer as? TelegramUser {
            thridTitle = strings().chatMessageDeleteForMeAndPerson(TelegramUtilsHooks.shared.peerTitle(peer))
        } else {
            thridTitle = strings().chatMessageDeleteForAll
        }
    }

    let information = mainPeer is TelegramUser || mainPeer is TelegramSecretChat ? peer.id == context.peerId ? strings().peerInfoConfirmClearHistorySavedMesssages : canRemoveGlobally || peer.id.namespace == Namespaces.Peer.SecretChat ? strings().peerInfoConfirmClearHistoryUserBothSides : strings().peerInfoConfirmClearHistoryUser : strings().peerInfoConfirmClearHistoryGroup

    verifyAlert(for: context.window, information:information , ok: strings().peerInfoConfirmClear, option: thridTitle, optionIsSelected: false, successHandler: { result in
        _ = context.engine.messages.clearHistoryInteractively(peerId: peer.id, threadId: nil, type: result == .thrid ? .forEveryone : .forLocalPeer).start()
    })
}

public func protectedCopyText(_ peer: Peer) -> String {
    if peer.isGroup || peer.isSupergroup {
        return strings().copyRestrictedGroup
    } else if peer is TelegramUser {
        return strings().copyRestrictedChat
    } else {
        return strings().copyRestrictedChannel
    }
}

public func showProtectedCopyAlert(_ message: Message, for window: Window) {
    if let peer = message.peers[message.id.peerId] {
        showModalText(for: window, text: message.paidContent != nil ? strings().contextCopyPaidMediaRestricted : protectedCopyText(peer))
    }
}

public func showProtectedCopyAlert(_ peer: Peer, for window: Window) {
    showModalText(for: window, text: protectedCopyText(peer))
}

public func showSuccess(window: Window) {
    _ = showModalSuccess(for: window, icon: theme.icons.successModalProgress, delay: 2.0).start()
}
