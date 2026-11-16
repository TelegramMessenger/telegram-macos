import Foundation

public enum ForumSidebarMenuAction: Equatable {
    case mute, newTopic, addMembers, select, markAllRead
}

public struct ForumSidebarMenuPolicy {
    public static func actions(kind: ChatSidebarKind, canCreateTopics: Bool, canInviteMembers: Bool) -> [ForumSidebarMenuAction] {
        switch kind {
        case .savedMessages:
            return []
        case .channelMessages:
            return [.mute, .markAllRead]
        case .forum:
            var result: [ForumSidebarMenuAction] = [.mute]
            if canCreateTopics { result.append(.newTopic) }
            if canInviteMembers { result.append(.addMembers) }
            result.append(.select)
            return result
        }
    }
}
