import Foundation

public struct HTMLDemoParticipant {
    public let id: String
    public let name: String
    public let isMe: Bool
}

public struct HTMLDemoMessageTemplate {
    public let senderId: String
    public let html: String
    public let minuteOfDay: Int
    public let delay: Double
    public let activeKeys: [String]
}

public final class HTMLDemoConversation {
    public let id: String
    public fileprivate(set) var title: String = "Untitled"
    public fileprivate(set) var subtitle: String = ""
    public fileprivate(set) var participants: [HTMLDemoParticipant] = []
    public fileprivate(set) var messages: [HTMLDemoMessageTemplate] = []
    public fileprivate(set) var actions: [String: [HTMLDemoMessageTemplate]] = [:]

    init(id: String) {
        self.id = id
    }

    public var isGroup: Bool {
        return participants.count > 2
    }

    public var me: HTMLDemoParticipant? {
        return participants.first(where: { $0.isMe })
    }

    public var firstOther: HTMLDemoParticipant? {
        return participants.first(where: { !$0.isMe })
    }

    public func participant(_ id: String) -> HTMLDemoParticipant? {
        return participants.first(where: { $0.id == id })
    }

    public static func parse(id: String, text: String) -> HTMLDemoConversation {
        let conversation = HTMLDemoConversation(id: id)
        let whitespace = CharacterSet.whitespaces

        var actionId: String?
        var actionMessages: [HTMLDemoMessageTemplate] = []
        var header: (sender: String, minute: Int, bare: Bool, delay: Double, keys: [String])?
        var body: [String] = []
        var fallbackMinute = 9 * 60

        func flush() {
            if let current = header {
                let content = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                let html = current.bare ? content : "<div class=\"widget\">\n" + content + "\n</div>"
                let template = HTMLDemoMessageTemplate(senderId: current.sender, html: html, minuteOfDay: current.minute, delay: current.delay, activeKeys: current.keys)
                if actionId != nil {
                    actionMessages.append(template)
                } else {
                    conversation.messages.append(template)
                }
            }
            header = nil
            body = []
        }

        func flushAction() {
            if let id = actionId {
                conversation.actions[id] = actionMessages
            }
            actionId = nil
            actionMessages = []
        }

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("--- ") || line == "---" {
                flush()
                let tokens = line.dropFirst(3).trimmingCharacters(in: whitespace).components(separatedBy: whitespace).filter { !$0.isEmpty }
                var bare = false
                var delay: Double = 0
                var keys: [String] = []
                var minute: Int?
                for token in tokens.dropFirst() {
                    if token == "bare" {
                        bare = true
                    } else if token.hasPrefix("delay=") {
                        delay = Double(token.dropFirst(6)) ?? 0
                    } else if token.hasPrefix("on=") {
                        keys.append(contentsOf: token.dropFirst(3).components(separatedBy: ",").filter { !$0.isEmpty })
                    } else if token.contains(":") {
                        let parts = token.components(separatedBy: ":")
                        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                            minute = h * 60 + m
                            fallbackMinute = h * 60 + m
                        }
                    }
                }
                let resolvedMinute: Int
                if let minute = minute {
                    resolvedMinute = minute
                } else {
                    resolvedMinute = fallbackMinute
                    fallbackMinute += 1
                }
                header = (tokens.first ?? "", resolvedMinute, bare, delay, keys)
                continue
            }
            if line.hasPrefix("@on ") {
                flush()
                flushAction()
                actionId = line.dropFirst(4).trimmingCharacters(in: whitespace)
                continue
            }
            if header != nil {
                body.append(line)
                continue
            }
            guard line.hasPrefix("@") else {
                continue
            }
            let key: String
            let value: String
            if let space = line.rangeOfCharacter(from: whitespace) {
                key = String(line[line.startIndex ..< space.lowerBound])
                value = line[space.lowerBound...].trimmingCharacters(in: whitespace)
            } else {
                key = line
                value = ""
            }
            switch key {
            case "@chat":
                conversation.title = value
            case "@subtitle":
                conversation.subtitle = value
            case "@participant":
                let fields = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: whitespace) }
                if fields.count >= 2 {
                    conversation.participants.append(HTMLDemoParticipant(id: fields[0], name: fields[1], isMe: fields.count > 3 && fields[3] == "me"))
                }
            default:
                break
            }
        }
        flush()
        flushAction()
        if conversation.me == nil {
            conversation.participants.insert(HTMLDemoParticipant(id: "me", name: "You", isMe: true), at: 0)
        }
        return conversation
    }

    static func load(from directory: URL?) -> [HTMLDemoConversation] {
        guard let directory else {
            return []
        }
        let files: [URL] = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let chats: [URL] = files.filter { $0.pathExtension == "chat" }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        var result: [HTMLDemoConversation] = []
        for url in chats {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                result.append(parse(id: url.deletingPathExtension().lastPathComponent, text: text))
            }
        }
        return result
    }
}
