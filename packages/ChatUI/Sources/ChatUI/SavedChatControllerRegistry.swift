import Cocoa
import Postbox
import TelegramCore
import TelegramContext
import TGUIKit

final class SavedChatControllerRegistry {
    static let shared = SavedChatControllerRegistry()
    private let controllers = NSHashTable<ViewController>.weakObjects()

    func add(_ controller: ViewController) {
        controllers.add(controller)
    }

    func remove(accountId: AccountRecordId, peerId: PeerId, threadId: Int64) {
        let matches = controllers.allObjects.filter { controller in
            guard let controller = controller as? ChatControllerKind else { return false }
            let interaction = controller.chatInteraction
            return interaction.interactionContext.account.id == accountId
                && interaction.mode.isSavedMessagesThread
                && interaction.chatLocation.peerId == peerId
                && interaction.chatLocation.threadId == threadId
        }
        for controller in matches {
            guard let navigation = controller.navigationController else { continue }
            if navigation.empty === controller {
                navigation.window?.performClose(nil)
            } else {
                navigation.removeImmediately(controller)
            }
        }
    }
}
