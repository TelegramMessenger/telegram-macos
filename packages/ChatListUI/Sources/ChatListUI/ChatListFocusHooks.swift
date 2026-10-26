import SwiftSignalKit
import FocusFilterCore

public struct ChatListFocusHooks {
    public var policies: () -> Signal<FocusFilterPolicy, NoError>

    public init(policies: @escaping () -> Signal<FocusFilterPolicy, NoError> = { .single(.init()) }) {
        self.policies = policies
    }

    public private(set) static var shared = ChatListFocusHooks()

    public static func install(_ hooks: ChatListFocusHooks) {
        shared = hooks
    }
}
