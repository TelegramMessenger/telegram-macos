import Foundation
import Postbox
import TelegramCore
import Localization

public struct SlowMode : Equatable {
    public let validUntil: Int32?
    public let timeout: Int32?
    public let sendingIds: [MessageId]
    public init(validUntil: Int32? = nil, timeout: Int32? = nil, sendingIds: [MessageId] = []) {
        self.validUntil = validUntil
        self.timeout = timeout.flatMap { $0 > 0 ? $0 : nil }
        self.sendingIds = sendingIds
    }
    public func withUpdatedValidUntil(_ validUntil: Int32?) -> SlowMode {
        return SlowMode(validUntil: validUntil, timeout: self.timeout, sendingIds: self.sendingIds)
    }
    public func withUpdatedTimeout(_ timeout: Int32?) -> SlowMode {
        return SlowMode(validUntil: self.validUntil, timeout: timeout, sendingIds: self.sendingIds)
    }
    public func withUpdatedSendingIds(_ sendingIds: [MessageId]) -> SlowMode {
        return SlowMode(validUntil: self.validUntil, timeout: self.timeout, sendingIds: sendingIds)
    }
    
    public var hasLocked: Bool {
        return timeout != nil || !sendingIds.isEmpty
    }
    
    public var errorText: String? {
        if let timeout = timeout {
            return slowModeTooltipText(timeout)
        } else if !sendingIds.isEmpty {
            return strings().slowModeMultipleError
        } else {
            return nil
        }
    }
}
