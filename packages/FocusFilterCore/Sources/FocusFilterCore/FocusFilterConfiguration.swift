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
