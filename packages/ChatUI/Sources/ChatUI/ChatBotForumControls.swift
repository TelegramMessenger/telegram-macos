enum ChatBotForumNavigationAction: Equatable {
    case hidden
    case search
    case more
}

enum ChatBotForumControls {
    static func showsStart(isBot: Bool, isScheduled: Bool, historyCount: Int?, threadId: Int64?, isBlocked: Bool) -> Bool {
        return isBot && !isScheduled && (isBlocked || (historyCount == 0 && threadId == nil))
    }

    static func navigationAction(hasForum: Bool, isPreview: Bool, isPinned: Bool, historyCount: Int?, threadId: Int64?) -> ChatBotForumNavigationAction? {
        guard hasForum else {
            return nil
        }
        if isPreview || isPinned {
            return .hidden
        }
        if threadId != nil {
            return .more
        }
        return (historyCount ?? 0) > 0 ? .search : .hidden
    }
}
