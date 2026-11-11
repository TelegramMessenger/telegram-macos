import Foundation
import Postbox
import TelegramCore

public final class HTMLDocumentAutoRefresh {
    public static let minimumInterval: TimeInterval = 30
    public static let sessionLimit = 60
    public static let checkInterval: TimeInterval = 5

    static let flagKey = "HTMLBubbles.documentAutoRefresh"

    public static var isEnabled: Bool {
        return isEnabled(UserDefaults.standard)
    }

    static func isEnabled(_ defaults: UserDefaults) -> Bool {
        return defaults.object(forKey: flagKey) as? Bool ?? true
    }

    private static let refreshRegex = try? NSRegularExpression(pattern: "^\\s*(?:<!--[\\s\\S]*?-->\\s*|<(style|script)\\b[^>]*>[\\s\\S]*?</\\1\\s*>\\s*|<meta\\b[^>]*>\\s*)*<[a-zA-Z][^>]*\\sdata-refresh\\s*=\\s*[\"']?\\s*(\\d{1,6})", options: [.caseInsensitive])

    public static func interval(_ html: String) -> TimeInterval? {
        let range = NSRange(html.startIndex..., in: html)
        guard let regex = refreshRegex, let match = regex.firstMatch(in: html, options: [], range: range), let group = Range(match.range(at: 2), in: html), let value = Double(html[group]), value > 0 else {
            return nil
        }
        return max(value, minimumInterval)
    }

    public static func isRefreshButton(text: String, data: Data) -> Bool {
        if text.contains("↻") || text.range(of: "refresh", options: .caseInsensitive) != nil {
            return true
        }
        let prefix = String(decoding: data.prefix(8), as: UTF8.self).lowercased()
        return prefix.hasPrefix("refresh") || prefix.hasPrefix("ar:")
    }

    public static func refreshCallback(in message: Message) -> MemoryBuffer? {
        guard let markup = message.attributes.first(where: { $0 is ReplyMarkupMessageAttribute }) as? ReplyMarkupMessageAttribute, markup.flags.contains(.inline) else {
            return nil
        }
        for row in markup.rows {
            for button in row.buttons {
                if case let .callback(requiresPassword, data) = button.action, !requiresPassword, isRefreshButton(text: button.title, data: data.makeData()) {
                    return data
                }
            }
        }
        return nil
    }

    public struct Conditions: Equatable {
        public var visible: Bool
        public var windowActive: Bool
        public var appActive: Bool

        public init(visible: Bool, windowActive: Bool, appActive: Bool) {
            self.visible = visible
            self.windowActive = windowActive
            self.appActive = appActive
        }

        var all: Bool {
            return visible && windowActive && appActive
        }
    }

    public enum Decision: Equatable {
        case wait
        case fire
        case reset
    }

    public static let shared = HTMLDocumentAutoRefresh()

    private var visibleSince: [MessageId: TimeInterval] = [:]
    private var inFlight: Set<MessageId> = []
    public private(set) var fired = 0
    private let limit: Int

    public init(limit: Int = HTMLDocumentAutoRefresh.sessionLimit) {
        self.limit = limit
    }

    public func check(_ id: MessageId, interval: TimeInterval, conditions: Conditions, now: TimeInterval) -> Decision {
        guard conditions.all else {
            visibleSince.removeValue(forKey: id)
            return .reset
        }
        guard fired < limit, !inFlight.contains(id) else {
            return .wait
        }
        guard let since = visibleSince[id] else {
            visibleSince[id] = now
            return .wait
        }
        if now - since >= max(interval, HTMLDocumentAutoRefresh.minimumInterval) {
            fired += 1
            inFlight.insert(id)
            visibleSince[id] = now
            return .fire
        }
        return .wait
    }

    public func finished(_ id: MessageId, now: TimeInterval) {
        inFlight.remove(id)
        if visibleSince[id] != nil {
            visibleSince[id] = now
        }
    }
}
