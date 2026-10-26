import Foundation
import FocusFilterCore

public struct FocusNotificationFilter {
    private let configuration: FocusFilterConfiguration

    public init(configuration: FocusFilterConfiguration) {
        self.configuration = configuration
    }

    public func criteria(for chat: FocusChatIdentifier, catalog: FocusFilterCatalog) -> String {
        let folders = catalog.folders.filter {
            $0.id.accountId == chat.accountId && $0.peerIds.contains(chat.peerId)
        }.map { folderToken($0.id) }.sorted().joined()
        return chatPrefix(chat) + folders
    }

    public var predicate: NSPredicate {
        guard configuration.effect.contains(.notifications), !configuration.accountIds.isEmpty else {
            return NSPredicate(value: true)
        }
        let chats = configuration.chatIds.filter { configuration.accountIds.contains($0.accountId) }.map {
            NSPredicate(format: "SELF BEGINSWITH %@", chatPrefix($0))
        }
        let folders = configuration.folderIds.filter { configuration.accountIds.contains($0.accountId) }.map {
            NSPredicate(format: "SELF CONTAINS %@", folderToken($0))
        }
        let membership = NSCompoundPredicate(orPredicateWithSubpredicates: chats + folders)
        if configuration.mode == .excludeSelected {
            return NSCompoundPredicate(notPredicateWithSubpredicate: membership)
        }
        let targetedAccounts = NSCompoundPredicate(orPredicateWithSubpredicates: configuration.accountIds.map {
            NSPredicate(format: "SELF BEGINSWITH %@", accountPrefix($0))
        })
        return NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSCompoundPredicate(notPredicateWithSubpredicate: targetedAccounts), membership
        ])
    }

    private func accountPrefix(_ accountId: Int64) -> String {
        "telegram-focus:\(accountId):"
    }

    private func chatPrefix(_ chat: FocusChatIdentifier) -> String {
        accountPrefix(chat.accountId) + String(chat.peerId) + ";"
    }

    private func folderToken(_ folder: FocusFolderIdentifier) -> String {
        "|folder:\(folder.accountId):\(folder.folderId)|"
    }
}
