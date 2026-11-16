import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import ChatModeTypes
import TelegramTheme
import Localization

public final class HTMLDemoChatContents: ChatCustomContentsProtocol {
    private final class WeakContents {
        weak var value: HTMLDemoChatContents?
        init(_ value: HTMLDemoChatContents) { self.value = value }
    }
    private static var instances: [String: WeakContents] = [:]

    public static func reusing(chat: HTMLDemoChat, accountPeerId: PeerId, accountName: String) -> HTMLDemoChatContents {
        assert(Thread.isMainThread)
        let key = "\(accountPeerId.toInt64())|\(chat.id)"
        if let current = instances[key]?.value { return current }
        instances = instances.filter { $0.value.value != nil }
        let contents = HTMLDemoChatContents(chat: chat, accountPeerId: accountPeerId, accountName: accountName)
        instances[key] = WeakContents(contents)
        return contents
    }

    public func openGameLink(_ link: String) {
        multiplayerClient?.openLink(link, forceWatch: false)
    }
    public let kind: ChatCustomContentsKind
    public let messageLimit: Int? = nil
    public var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in }
    public var openExternalLink: ((String) -> Void)?
    public var openDemoRival: (() -> Void)?

    private let chat: HTMLDemoChat
    private let accountPeer: Peer
    private var messages: [Message] = []
    private let pipe = ValuePipe<(MessageHistoryView, ViewUpdateType)>()
    private let disposables = DisposableSet()
    private var nextId: Int32 = 1
    private var lastTimestamp: Int32
    private var typingIds: [MessageId] = []
    private var nextFallback = 0
    private var multiplayerClient: HTMLMultiplayerDemoSession?
    private weak var multiplayerState: HTMLBubbleState?

    private static var nextStableId: UInt32 = 3_000_000

    public init(chat: HTMLDemoChat, accountPeerId: PeerId, accountName: String = "You") {
        assert(Thread.isMainThread)
        self.chat = chat
        self.kind = .htmlDemo(title: chat.title, status: chat.status)
        self.accountPeer = HTMLDemoCatalog.makeUser(id: accountPeerId, name: strings().htmlDemoChatContentsYou, isBot: false)
        self.lastTimestamp = Int32(Date().timeIntervalSince1970)
        if #available(macOS 10.15, *), chat.id == "html-voxel-clash" {
            self.multiplayerClient = HTMLMultiplayerDemoClient(name: accountName, accountKey: String(accountPeerId.toInt64()))
        }
        if let preset = chat.preset {
            for file in HTMLDemoCatalog.widgetFiles(preset) {
                appendMessage(text: file.name, attributes: [], author: chat.peer, outgoing: false)
                appendState(makeState(file.html, outgoing: false, keys: [], conversationId: nil, selfContained: true, summary: file.summary), author: chat.peer, outgoing: false)
            }
        } else {
            appendBotHTML(HTMLDemoCatalog.welcomeHTML(engine: chat.engine), keys: [], conversationId: nil, selfContained: false, removesTyping: false)
        }
    }

    deinit {
        disposables.dispose()
    }

    public var botPeer: Peer {
        return chat.peer
    }

    public var botCommands: [BotCommand] {
        if multiplayerClient != nil {
            return [
                BotCommand(text: "rival", description: "Open another signed-in account in a new window"),
                BotCommand(text: "create", description: "Create a private match with invite and spectator links"),
                BotCommand(text: "join", description: "Join a match: /join followed by an invitation link"),
                BotCommand(text: "watch", description: "Watch a match: /watch followed by a spectator link"),
                BotCommand(text: "invite", description: "Copy this match’s invitation"),
                BotCommand(text: "spectate", description: "Copy this match’s live spectator link"),
                BotCommand(text: "practice", description: "Start a match against Clockwork"),
                BotCommand(text: "build", description: "Build a house, farm or tower: /build house C4"),
                BotCommand(text: "raid", description: "Attack an opponent’s building: /raid C4"),
                BotCommand(text: "newworld", description: "Start a rematch in this game")
            ]
        }
        return HTMLDemoCatalog.botCommands
    }

    public var historyView: Signal<(MessageHistoryView, ViewUpdateType), NoError> {
        return Signal { [weak self] subscriber in
            guard let self = self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            subscriber.putNext((self.makeView(), .Initial))
            return self.pipe.signal().start(next: { value in
                subscriber.putNext(value)
            })
        } |> runOn(Queue.mainQueue())
    }

    public func enqueueMessages(messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
        return Signal { [weak self] subscriber in
            var ids: [MessageId?] = []
            for message in messages {
                switch message {
                case let .message(text, _, _, _, _, _, _, _, _, _):
                    ids.append(self?.sendText(text) ?? nil)
                case .forward:
                    ids.append(nil)
                }
            }
            subscriber.putNext(ids)
            subscriber.putCompletion()
            return EmptyDisposable
        } |> runOn(Queue.mainQueue())
    }

    public func deleteMessages(ids: [EngineMessage.Id]) {
        Queue.mainQueue().async {
            let set = Set(ids)
            self.messages.removeAll(where: { set.contains($0.id) })
            self.publish()
        }
    }

    public func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
    }

    public func messagesAtIds(_ ids: [MessageId], album: Bool) -> Signal<[Message], NoError> {
        return Signal { [weak self] subscriber in
            let set = Set(ids)
            subscriber.putNext(self?.messages.filter { set.contains($0.id) } ?? [])
            subscriber.putCompletion()
            return EmptyDisposable
        } |> runOn(Queue.mainQueue())
    }

    public func hashtagSearchUpdate(query: String) {
    }

    public func loadMore() {
    }

    private func makeView() -> MessageHistoryView {
        let entries = messages.map {
            MessageHistoryEntry(message: $0, isRead: true, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false))
        }
        return MessageHistoryView(tag: nil, namespaces: .just(Set([Namespaces.Message.Local])), entries: entries, holeEarlier: false, holeLater: false, isLoading: false)
    }

    private func publish() {
        pipe.putNext((makeView(), .Generic))
    }

    private func author(for senderId: String, in conversation: HTMLDemoConversation) -> (Peer, Bool) {
        if let participant = conversation.participant(senderId), participant.isMe {
            return (accountPeer, true)
        }
        return (chat.peer, false)
    }

    @discardableResult
    private func append(_ template: HTMLDemoMessageTemplate, conversation: HTMLDemoConversation) -> MessageId {
        let (author, outgoing) = self.author(for: template.senderId, in: conversation)
        return appendHTML(template.html, author: author, outgoing: outgoing, keys: template.activeKeys, conversationId: conversation.id)
    }

    @discardableResult
    private func appendHTML(_ html: String, author: Peer, outgoing: Bool, keys: [String], conversationId: String?, selfContained: Bool = false) -> MessageId {
        return appendState(makeState(html, outgoing: outgoing, keys: keys, conversationId: conversationId, selfContained: selfContained), author: author, outgoing: outgoing)
    }

    private func makeState(_ html: String, outgoing: Bool, keys: [String], conversationId: String?, selfContained: Bool, summary: HTMLBubbleSummary? = nil) -> HTMLBubbleState {
        let state = HTMLBubbleState(html: html, outgoing: outgoing, activeKeys: keys, conversationId: conversationId, engine: chat.engine, selfContained: selfContained, summary: summary)
        if let client = multiplayerClient {
            multiplayerState = state
            state.showsStats = false
            client.start(state: state)
        }
        state.linkHandler = { [weak self] state, url in
            self?.handleLink(url, from: state)
        }
        state.start()
        return state
    }

    @discardableResult
    private func appendState(_ state: HTMLBubbleState, author: Peer, outgoing: Bool) -> MessageId {
        return appendMessage(text: state.plainText, attributes: [HTMLMessageAttribute(state: state)], author: author, outgoing: outgoing)
    }

    private func appendBotHTML(_ html: String, keys: [String], conversationId: String?, selfContained: Bool, removesTyping: Bool) {
        let state = makeState(html, outgoing: false, keys: keys, conversationId: conversationId, selfContained: selfContained)
        let append: () -> Void = { [weak self] in
            guard let self = self else {
                return
            }
            if removesTyping {
                self.removeTyping()
            }
            self.appendState(state, author: self.chat.peer, outgoing: false)
            self.publish()
        }
        if chat.engine.usesWidgetSandbox {
            state.measureTwidget(appearance: HTMLBubbleStyle.appearance(theme: theme, incoming: true), width: 440, timeout: 1.5, completion: append)
        } else {
            append()
        }
    }

    @discardableResult
    private func appendMessage(text: String, attributes: [MessageAttribute], author: Peer, outgoing: Bool) -> MessageId {
        let id = MessageId(peerId: chat.peer.id, namespace: Namespaces.Message.Local, id: nextId)
        nextId += 1
        lastTimestamp = max(lastTimestamp + 1, Int32(Date().timeIntervalSince1970))
        HTMLDemoChatContents.nextStableId += 1
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[chat.peer.id] = chat.peer
        peers[author.id] = author
        peers[accountPeer.id] = accountPeer
        let message = Message(stableId: HTMLDemoChatContents.nextStableId, stableVersion: 0, id: id, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: lastTimestamp, flags: outgoing ? [] : [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: author, text: text, attributes: attributes, media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        messages.append(message)
        return id
    }

    public func handleGameCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard multiplayerClient != nil, trimmed.hasPrefix("/") || trimmedGameLink(trimmed) != nil else { return false }
        respond(to: trimmed)
        return true
    }

    private func sendText(_ text: String, fromCard: Bool = false) -> MessageId? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if handleGameCommand(trimmed) {
            return messages.last?.id
        }
        let id: MessageId
        if HTMLBubbleState.looksLikeHTML(trimmed) {
            id = appendHTML(trimmed, author: accountPeer, outgoing: true, keys: [], conversationId: nil)
        } else {
            id = appendMessage(text: trimmed, attributes: [], author: accountPeer, outgoing: true)
        }
        publish()
        if !fromCard || trimmed.hasPrefix("/") {
            respond(to: trimmed)
        }
        return id
    }

    private func respond(to text: String) {
        let lowercased = text.lowercased()
        if let client = multiplayerClient, let state = multiplayerState {
            let parts = lowercased.split(separator: " ").map(String.init)
            if parts.first == "/rival" {
                openDemoRival?()
                return
            }
            var action: [String: Any]?
            if trimmedGameLink(text) != nil {
                client.openLink(text.trimmingCharacters(in: .whitespacesAndNewlines), forceWatch: false)
                return
            }
            if parts.first == "/create" { action = ["type": "create"] }
            else if parts.first == "/invite" { action = ["type": "copyInvite"] }
            else if parts.first == "/spectate" { action = ["type": "copyWatch"] }
            else if parts.first == "/practice" { action = ["type": "practice"] }
            else if parts.first == "/demo" { action = ["type": "demo"] }
            else if parts.first == "/claim" { action = ["type": "claim"] }
            else if parts.first == "/train" { action = ["type": "train"] }
            else if parts.first == "/shield" { action = ["type": "shield"] }
            else if parts.count == 2, ["/join", "/watch"].contains(parts[0]) {
                let link = text.split(separator: " ", maxSplits: 1).last.map(String.init) ?? ""
                action = ["type": parts[0] == "/watch" ? "watch" : "join", "url": link]
            } else if parts.first == "/newworld" {
                action = ["type": "rematch"]
            } else if parts.count == 3, parts[0] == "/build", let tile = multiplayerTile(parts[2]) {
                action = ["type": "build", "kind": parts[1], "tile": tile]
            } else if parts.count == 2, ["/raid", "/attack", "/upgrade", "/repair", "/meteor"].contains(parts[0]), let tile = multiplayerTile(parts[1]) {
                action = ["type": parts[0] == "/raid" ? "attack" : String(parts[0].dropFirst()), "tile": tile]
            }
            if let action = action, let data = try? JSONSerialization.data(withJSONObject: action), let json = String(data: data, encoding: .utf8) {
                client.receive(json, state: state)
            }
            return
        }
        let first = lowercased.components(separatedBy: .whitespacesAndNewlines).first ?? ""
        if first.hasPrefix("/") {
            let name = String(first.dropFirst())
            if name == "start" || name == "help" {
                reply(HTMLDemoCatalog.welcomeHTML(engine: chat.engine))
            } else if name == HTMLDemoCatalog.statsCommand {
                let enabled = !HTMLBubbleStatsOverlay.isEnabled
                HTMLBubbleStatsOverlay.isEnabled = enabled
                reply(HTMLDemoCatalog.statsHTML(enabled: enabled))
            } else if let command = HTMLDemoCatalog.command(name) {
                send(command, intro: nil)
            } else {
                reply(HTMLDemoCatalog.unknownCommandHTML(first))
            }
        } else if !HTMLBubbleState.looksLikeHTML(text) {
            let words = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
            if let command = words.lazy.compactMap({ HTMLDemoCatalog.command($0) }).first {
                send(command, intro: nil)
            } else if let command = nextFallbackCommand() {
                send(command, intro: HTMLDemoCatalog.fallbackHTML(command))
            }
        }
    }

    private func multiplayerTile(_ value: String) -> Int? {
        guard let column = value.utf8.first, column >= 97, column <= 110, let row = Int(value.dropFirst()), (1 ... 14).contains(row) else {
            return nil
        }
        return (row - 1) * 14 + Int(column - 97)
    }

    private func trimmedGameLink(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.host == "voxel-clash-production.up.railway.app" else { return nil }
        return url
    }

    private func nextFallbackCommand() -> HTMLDemoCommand? {
        let commands = HTMLDemoCatalog.commands
        guard !commands.isEmpty else {
            return nil
        }
        let command = commands[nextFallback % commands.count]
        nextFallback += 1
        return command
    }

    private func reply(_ html: String) {
        showTyping(after: 0.1)
        deliver(html, keys: [], conversationId: nil, after: 0.6)
    }

    private func send(_ command: HTMLDemoCommand, intro: String?) {
        guard let conversation = HTMLDemoCatalog.conversation(command.conversationId) else {
            return
        }
        showTyping(after: 0.1)
        var t: Double = 0.7
        if let intro = intro {
            deliver(intro, keys: [], conversationId: nil, after: t)
            t += 0.35
        }
        for index in command.messageIndices where conversation.messages.indices.contains(index) {
            let template = conversation.messages[index]
            if chat.engine.usesWidgetSandbox {
                guard let ported = HTMLDemoCatalog.portedHTML(conversationId: conversation.id, index: index) else {
                    continue
                }
                deliver(ported, keys: [], conversationId: conversation.id, after: t, selfContained: true)
            } else {
                deliver(template.html, keys: template.activeKeys, conversationId: conversation.id, after: t)
            }
            t += 0.35
        }
    }

    private func deliver(_ html: String, keys: [String], conversationId: String?, after timeout: Double, selfContained: Bool = false) {
        after(timeout) { [weak self] in
            guard let self = self else {
                return
            }
            self.appendBotHTML(html, keys: keys, conversationId: conversationId, selfContained: selfContained, removesTyping: true)
        }
    }

    private func runAction(_ actionId: String?, conversationId: String?) {
        guard let actionId = actionId, let conversation = conversationId.flatMap({ HTMLDemoCatalog.conversation($0) }), let templates = conversation.actions[actionId] else {
            NSSound.beep()
            return
        }
        var t: Double = 0
        for template in templates {
            let isMe = conversation.participant(template.senderId)?.isMe ?? false
            let start = t
            t += max(template.delay, 0.05)
            let typing = template.delay > 0.2 && !isMe
            if typing {
                showTyping(after: start + 0.15)
            }
            after(t) { [weak self] in
                guard let self = self else {
                    return
                }
                if typing {
                    self.removeTyping()
                }
                self.append(template, conversation: conversation)
                self.publish()
            }
        }
    }

    private func showTyping(after timeout: Double) {
        after(timeout) { [weak self] in
            guard let self = self else {
                return
            }
            let typing = self.chat.engine.usesWidgetSandbox ? HTMLDemoCatalog.staticTypingHTML : HTMLDemoCatalog.typingHTML
            let id = self.appendHTML(typing, author: self.chat.peer, outgoing: false, keys: [], conversationId: nil)
            self.typingIds.append(id)
            self.publish()
        }
    }

    private func removeTyping() {
        guard !typingIds.isEmpty else {
            return
        }
        let ids = Set(typingIds)
        typingIds.removeAll()
        messages.removeAll(where: { ids.contains($0.id) })
    }

    private func handleLink(_ url: String, from state: HTMLBubbleState) {
        if let (command, params) = HTMLBubbleState.parseChatLink(url) {
            switch command {
            case "run":
                runAction(params["id"], conversationId: state.conversationId)
            case "send":
                if let html = params["html"], !html.isEmpty {
                    appendHTML(html, author: accountPeer, outgoing: true, keys: [], conversationId: state.conversationId)
                    publish()
                } else {
                    _ = sendText(params["text"] ?? "", fromCard: true)
                }
                if let then = params["then"] {
                    runAction(then, conversationId: state.conversationId)
                }
            default:
                NSSound.beep()
            }
            return
        }
        let lower = url.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") {
            openExternalLink?(url)
        }
    }

    private func after(_ timeout: Double, _ action: @escaping () -> Void) {
        disposables.add((Signal<Void, NoError>.single(Void()) |> delay(timeout, queue: Queue.mainQueue())).start(next: { _ in
            action()
        }))
    }
}
