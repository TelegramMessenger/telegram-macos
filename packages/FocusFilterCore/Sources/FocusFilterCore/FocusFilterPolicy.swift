import Foundation

public enum FocusFilterEffect: String, Codable, Sendable {
    case notifications
    case chatList
    case both

    public func contains(_ effect: FocusFilterEffect) -> Bool {
        self == .both || self == effect
    }
}

public enum FocusFilterMode: String, Codable, Sendable {
    case allowSelected
    case excludeSelected
}

public struct FocusChatIdentifier: Hashable, Codable, Sendable {
    public let accountId: Int64
    public let peerId: Int64

    public init(accountId: Int64, peerId: Int64) {
        self.accountId = accountId
        self.peerId = peerId
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let accountId = Int64(parts[0]), let peerId = Int64(parts[1]) else {
            return nil
        }
        self.init(accountId: accountId, peerId: peerId)
    }

    public var rawValue: String { "\(accountId):\(peerId)" }
    public var notificationFilterCriteria: String { Self.notificationPrefix(accountId: accountId) + String(peerId) + ";" }

    public static func notificationPrefix(accountId: Int64) -> String {
        "telegram-focus:\(accountId):"
    }
}

public struct FocusFolderIdentifier: Hashable, Codable, Sendable {
    public let accountId: Int64
    public let folderId: Int32

    public init(accountId: Int64, folderId: Int32) {
        self.accountId = accountId
        self.folderId = folderId
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let accountId = Int64(parts[0]), let folderId = Int32(parts[1]) else {
            return nil
        }
        self.init(accountId: accountId, folderId: folderId)
    }

    public var rawValue: String { "\(accountId):\(folderId)" }
    public var notificationToken: String { "|folder:\(accountId):\(folderId)|" }
}

public struct FocusCatalogAccount: Equatable, Codable, Sendable {
    public let id: Int64
    public let title: String

    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
    }
}

public struct FocusCatalogChat: Equatable, Codable, Sendable {
    public let id: FocusChatIdentifier
    public let title: String
    public let isArchived: Bool

    public init(id: FocusChatIdentifier, title: String, isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.isArchived = isArchived
    }
}

public struct FocusCatalogFolder: Equatable, Codable, Sendable {
    public let id: FocusFolderIdentifier
    public let title: String
    public let peerIds: Set<Int64>

    public init(id: FocusFolderIdentifier, title: String, peerIds: Set<Int64>) {
        self.id = id
        self.title = title
        self.peerIds = peerIds
    }
}

public struct FocusFilterCatalog: Equatable, Codable, Sendable {
    public var accounts: [FocusCatalogAccount]
    public var chats: [FocusCatalogChat]
    public var folders: [FocusCatalogFolder]

    public init(accounts: [FocusCatalogAccount] = [], chats: [FocusCatalogChat] = [], folders: [FocusCatalogFolder] = []) {
        self.accounts = accounts
        self.chats = chats
        self.folders = folders
    }
}

public struct FocusFilterConfiguration: Equatable, Codable, Sendable {
    public var accountIds: Set<Int64>
    public var chatIds: Set<FocusChatIdentifier>
    public var folderIds: Set<FocusFolderIdentifier>
    public var mode: FocusFilterMode
    public var effect: FocusFilterEffect

    public init(accountIds: Set<Int64> = [], chatIds: Set<FocusChatIdentifier> = [], folderIds: Set<FocusFolderIdentifier> = [], mode: FocusFilterMode = .allowSelected, effect: FocusFilterEffect = .notifications) {
        self.accountIds = accountIds
        self.chatIds = chatIds
        self.folderIds = folderIds
        self.mode = mode
        self.effect = effect
    }
}

public struct FocusFilterSelection: Equatable, Sendable {
    public let mode: FocusFilterMode
    public let peerIds: Set<Int64>

    public init(mode: FocusFilterMode, peerIds: Set<Int64>) {
        self.mode = mode
        self.peerIds = peerIds
    }

    public func includes(peerId: Int64) -> Bool {
        mode == .allowSelected ? peerIds.contains(peerId) : !peerIds.contains(peerId)
    }
}

public struct FocusFilterPolicy: Equatable, Sendable {
    public let configuration: FocusFilterConfiguration
    public let catalog: FocusFilterCatalog
    private let selections: [Int64: FocusFilterSelection]

    public init(configuration: FocusFilterConfiguration = .init(), catalog: FocusFilterCatalog = .init()) {
        self.configuration = configuration
        self.catalog = catalog
        var selected: [Int64: Set<Int64>] = [:]
        for accountId in configuration.accountIds {
            selected[accountId] = []
        }
        for chat in configuration.chatIds where selected[chat.accountId] != nil {
            selected[chat.accountId, default: []].insert(chat.peerId)
        }
        for folder in catalog.folders where configuration.folderIds.contains(folder.id) && selected[folder.id.accountId] != nil {
            selected[folder.id.accountId, default: []].formUnion(folder.peerIds)
        }
        self.selections = selected.mapValues { FocusFilterSelection(mode: configuration.mode, peerIds: $0) }
    }

    public func selection(accountId: Int64, effect: FocusFilterEffect) -> FocusFilterSelection? {
        guard configuration.effect.contains(effect) else {
            return nil
        }
        return selections[accountId]
    }

    public func includes(accountId: Int64, peerId: Int64, effect: FocusFilterEffect) -> Bool {
        selection(accountId: accountId, effect: effect)?.includes(peerId: peerId) ?? true
    }

    public func notificationFilterCriteria(for chat: FocusChatIdentifier) -> String {
        chat.notificationFilterCriteria + catalog.folders.filter {
            $0.id.accountId == chat.accountId && $0.peerIds.contains(chat.peerId)
        }.map { $0.id.notificationToken }.sorted().joined()
    }

    public var notificationPredicate: NSPredicate {
        guard configuration.effect.contains(.notifications), !selections.isEmpty else {
            return NSPredicate(value: true)
        }
        let chats = configuration.chatIds.filter { configuration.accountIds.contains($0.accountId) }.map {
            NSPredicate(format: "SELF BEGINSWITH %@", $0.notificationFilterCriteria)
        }
        let folders = configuration.folderIds.filter { configuration.accountIds.contains($0.accountId) }.map {
            NSPredicate(format: "SELF CONTAINS %@", $0.notificationToken)
        }
        let membership = NSCompoundPredicate(orPredicateWithSubpredicates: chats + folders)
        if configuration.mode == .excludeSelected {
            return NSCompoundPredicate(notPredicateWithSubpredicate: membership)
        }
        let targetedAccount = NSCompoundPredicate(orPredicateWithSubpredicates: configuration.accountIds.map {
            NSPredicate(format: "SELF BEGINSWITH %@", FocusChatIdentifier.notificationPrefix(accountId: $0))
        })
        return NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSCompoundPredicate(notPredicateWithSubpredicate: targetedAccount), membership
        ])
    }
}
