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

}
