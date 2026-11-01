import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import Localization
import LocalAnimations
import SwiftSignalKit
import TelegramContext
import AlertsUI
import TelegramUtils

func setStarGiftAsChatTheme(context: any AccountContextProtocol, window: Window, gift: StarGift.UniqueGift, completion: @escaping () -> Void) -> Disposable {
    let disposable = DisposableSet()
    disposable.add(StarsHooks.shared.selectContact(context, window, strings().selectPeersTitleSelectChat, { peerIds in
        if gift.themePeerId == peerIds.first {
            return .single(true)
        } else if let themePeerId = gift.themePeerId {
            return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: themePeerId))
            |> deliverOnMainQueue
            |> mapToSignal { peer in
                guard let peer else { return .single(false) }
                return verifyAlertSignal(for: window, header: "", information: strings().chatThemeUniqueGiftReplaceConfirm(peer._asPeer().displayTitle), ok: strings().modalYes, headerItem: ModalAlertData.Header(id: "header", value: { initialSize, stableId, _ in
                    return TransferUniqueGiftHeaderItem(initialSize, stableId: stableId, gift: gift, toPeer: peer, context: context, transferType: .resetTheme)
                })) |> map { $0 != nil }
            }
        } else {
            return .single(true)
        }
    }).start(next: { [weak disposable] peerIds in
        guard let peerId = peerIds.first else { return }
        disposable?.add((context.engine.themes.setChatTheme(peerId: peerId, chatTheme: .gift(.unique(gift), [])) |> deliverOnMainQueue).start(completed: {
            completion()
            StarsHooks.shared.openChat(context, peerId, nil)
        }))
    }))
    return disposable
}

func starGiftConversionDeadline(date: Int32, period: Int32) -> Int64 {
    return Int64(date) + Int64(max(0, period))
}

func starGiftCanConvert(date: Int32, period: Int32, timestamp: Int32, amount: Int64?, converted: Bool, upgraded: Bool, refunded: Bool) -> Bool {
    guard let amount, amount > 0, !converted, !upgraded, !refunded, date > 0, period > 0 else {
        return false
    }
    return Int64(timestamp) < starGiftConversionDeadline(date: date, period: period)
}

func starGiftCanDelete(gift: StarGift, reference: StarGiftReference?, owner: EnginePeer, accountPeerId: PeerId, converted: Bool, fromProfile: Bool, upgraded: Bool, refunded: Bool) -> Bool {
    guard let reference, case let .generic(gift) = gift, gift.availability == nil, !upgraded, !refunded, !converted || fromProfile else {
        return false
    }
    if case let .peer(peerId, _) = reference, peerId.namespace == Namespaces.Peer.CloudChannel {
        if owner.id == peerId, case let .channel(channel) = owner {
            return channel.flags.contains(.isCreator)
        }
        return false
    }
    return owner.id == accountPeerId
}

func genericGiftMenuItems(collections: ContextMenuItem?, savedToProfile: Bool, toggleVisibility: @escaping () -> Void, delete: (() -> Void)?) -> [ContextMenuItem] {
    var items: [ContextMenuItem] = []
    if let collections {
        items.append(collections)
        items.append(ContextSeparatorItem())
    }
    items.append(ContextMenuItem(savedToProfile ? strings().giftContextHide : strings().giftContextShow, handler: toggleVisibility, itemImage: savedToProfile ? MenuAnimation.menu_eye_slash.value : MenuAnimation.menu_eye.value))
    if let delete {
        items.append(ContextSeparatorItem())
        items.append(ContextMenuItem(strings().giftViewContextDelete, handler: delete, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
    }
    return items
}
