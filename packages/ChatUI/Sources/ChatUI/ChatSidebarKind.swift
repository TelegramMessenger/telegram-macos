import InAppSettings

public enum ChatSidebarKind: Equatable {
    case forum
    case savedMessages
    case channelMessages

    public var showsNewTopic: Bool { self == .forum }
    public var usesSourceChats: Bool { self != .forum }

    static func resolve(isStandardMode: Bool, isSavedMessages: Bool, isMonoforum: Bool, canManageDirect: Bool, isGroupSidebar: Bool, hasChats: Bool, isThread: Bool) -> ChatSidebarKind? {
        guard isStandardMode else { return nil }
        if isSavedMessages {
            return hasChats || isThread ? .savedMessages : nil
        }
        if isMonoforum {
            return canManageDirect ? .channelMessages : nil
        }
        return isGroupSidebar ? .forum : nil
    }

    static func resolvedMonoforumState(topicListAvailable: Bool, currentState: MonoforumUIState?, savedState: MonoforumUIState, sidebarMode: Bool) -> MonoforumUIState? {
        guard topicListAvailable else { return nil }
        if sidebarMode { return .sidebar }
        if let currentState, currentState != .sidebar { return currentState }
        return savedState == .sidebar ? .vertical : savedState
    }

}
