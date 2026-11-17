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
}
