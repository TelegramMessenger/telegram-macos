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
