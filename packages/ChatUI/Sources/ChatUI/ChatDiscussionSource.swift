import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import ChatModeTypes

func chatDiscussionSourceMessageId(mode: ChatMode, location: ChatLocation) -> MessageId? {
    guard case let .thread(.comments(origin)) = mode, case let .thread(thread) = location else {
        return nil
    }
    if let source = thread.channelMessageId, source.peerId != thread.peerId {
        return source
    }
    if origin.peerId != thread.peerId {
        return origin
    }
    return nil
}

func openChatDiscussionSource(_ source: MessageId, interaction: ChatInteraction) {
    let navigation = interaction.interactionContext.bindings.rootNavigation()
    guard !navigation.isLocked else { return }
    var existing: ViewController?
    navigation.enumerateControllers { controller, _ in
        guard let chat = controller as? any ChatControllerKind,
              chat.chatInteraction.mode == .history,
              chat.chatInteraction.peerId == source.peerId else { return false }
        existing = controller
        return true
    }
    if let existing {
        let current = navigation.controller
        current.ableToNextController(existing, { [weak navigation, weak existing, weak current] _, allowed in
            guard allowed, let navigation, let existing, let current,
                  !navigation.isLocked, navigation.controller === current else { return }
            var targetIndex: Int?
            navigation.enumerateControllers { controller, index in
                guard controller === existing else { return false }
                targetIndex = index
                return true
            }
            guard let targetIndex, let chat = existing as? any ChatControllerKind else { return }
            navigation.to(index: targetIndex)
            chat.chatInteraction.focusMessageId(nil, .init(messageId: source, string: nil), .CenterEmpty)
        })
    } else {
        interaction.openInfoObserved(source.peerId, true, source, nil)
    }
}
