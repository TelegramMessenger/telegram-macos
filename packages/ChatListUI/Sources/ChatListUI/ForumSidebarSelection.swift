import Foundation

struct ForumSidebarSelection {
    private(set) var isActive = false
    private(set) var selectedIds = Set<Int64>()

    mutating func setActive(_ active: Bool) {
        isActive = active
        if !active { selectedIds.removeAll() }
    }

    mutating func toggle(_ id: Int64) {
        guard isActive else { return }
        if !selectedIds.insert(id).inserted { selectedIds.remove(id) }
    }

    mutating func retain(_ available: Set<Int64>) {
        selectedIds.formIntersection(available)
    }
}

struct ForumTopicActionPermissions: Equatable {
    let canClose: Bool
    let canDelete: Bool

    init(threadId: Int64, ownedByMe: Bool, managesTopics: Bool, deletesMessages: Bool) {
        canClose = threadId != 1 && (ownedByMe || managesTopics)
        canDelete = threadId != 1 && deletesMessages
    }
}

enum ForumTopicSwipeAction: Equatable {
    case mute, unmute, delete, close, reopen
}

struct ForumTopicSwipePolicy {
    static func actions(isMuted: Bool, isClosed: Bool, canClose: Bool, canDelete: Bool) -> [ForumTopicSwipeAction] {
        var actions: [ForumTopicSwipeAction] = [isMuted ? .unmute : .mute]
        if canDelete { actions.append(.delete) }
        if canClose { actions.append(isClosed ? .reopen : .close) }
        return actions
    }
}
