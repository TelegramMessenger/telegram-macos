#if DEBUG
import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import ChatModeTypes

final class ChatSyntheticContents: ChatCustomContentsProtocol {
    let kind: ChatCustomContentsKind
    let messageLimit: Int? = nil
    var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in }

    let peer: TelegramGroup
    private let messages: [Message]
    private(set) var photos: [(resource: LocalFileMediaResource, size: NSSize, index: Int)] = []

    private static let sentences = [
        "Has anyone else noticed the sidebar jumping after the last update?",
        "Works fine here on 27.0, but I only use one account.",
        "Try turning off the chat backgrounds and see whether it still happens.",
        "The folder badges are wrong again, they count muted chats too.",
        "Yes!",
        "I can reproduce it every time I switch between two large groups quickly, especially when both have a lot of stickers and the second one is scrolled far up.",
        "Thanks, that fixed it.",
        "Is there a way to export a single topic instead of the whole group?",
        "Not yet as far as I know.",
        "Logs attached in the previous message, let me know if you need more.",
        "The new reactions picker is much faster now 👍",
        "Could be the GPU switching on battery, I had the same thing on an old MacBook Pro.",
        "ok",
        "Scrolling through long threads feels smoother than in the previous beta, but the date header still flickers once in a while when you fling hard.",
    ]

    private static let reactionValues = ["👍", "❤", "🔥", "😁", "🤔", "👏"]

    init(accountPeerId: PeerId, count: Int, media: Bool = false, widgets: [TelegramMediaWidget] = [], widgetEvery: Int = 3, title: String = "Perf Lab", status: String = "synthetic") {
        self.kind = .htmlDemo(title: title, status: status)
        let peerId = PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(990_000_001))
        let peer = TelegramGroup(id: peerId, title: title, photo: [], participantCount: 12, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
        self.peer = peer
        let names = ["Alice Moreau", "Bogdan Petrenko", "Chen Wei", "Dana Cohen", "Emil Novak", "Farah Haddad", "Goran Ilic", "Hana Sato", "Ivan Orlov", "Julia Santos", "Kofi Mensah"]
        let users: [Peer] = names.enumerated().map { index, name in
            let parts = name.components(separatedBy: " ")
            let id = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(990_000_100 + Int64(index)))
            return TelegramUser(id: id, accessHash: nil, firstName: parts[0], lastName: parts[1], username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        }
        let me = TelegramUser(id: accountPeerId, accessHash: nil, firstName: "You", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)

        var result: [Message] = []
        var photos: [(resource: LocalFileMediaResource, size: NSSize, index: Int)] = []
        let start: Int32 = 1_792_000_000 - Int32(count) * 300
        for index in 0 ..< count {
            let outgoing = index % 9 == 4
            let author = outgoing ? me : users[(index * 7 + index / 3) % users.count]
            let sentences = ChatSyntheticContents.sentences
            var parts: [String] = []
            for part in 0 ..< 1 + (index * 5) % 3 {
                parts.append(sentences[(index * 3 + part * 5) % sentences.count])
            }
            var attributes: [MessageAttribute] = []
            var associated = SimpleDictionary<MessageId, Message>()
            var associatedIds: [MessageId] = []
            if index % 4 == 1, index > 3 {
                let target = result[index - 1 - (index % 3)]
                attributes.append(ReplyMessageAttribute(messageId: target.id, threadMessageId: nil, quote: nil, isQuote: false, innerSubject: nil))
                associated[target.id] = target
                associatedIds.append(target.id)
            }
            if index % 3 == 0 {
                let values = ChatSyntheticContents.reactionValues
                let kinds = 1 + index % 4
                var reactions = (0 ..< kinds).map { offset in
                    MessageReaction(value: .builtin(values[(index + offset) % values.count]), count: Int32(1 + (index * (offset + 3)) % 17), chosenOrder: nil)
                }
                if index % 11 == 0 {
                    reactions.insert(MessageReaction(value: .stars, count: Int32(5 + index % 40), chosenOrder: nil), at: 0)
                }
                attributes.append(ReactionsMessageAttribute(canViewList: false, isTags: false, reactions: reactions, recentPeers: [], topPeers: []))
            }
            var peers = SimpleDictionary<PeerId, Peer>()
            peers[peer.id] = peer
            peers[author.id] = author
            var messageMedia: [Media] = []
            var text = parts.joined(separator: " ")
            var forwardInfo: MessageForwardInfo?
            if !widgets.isEmpty, index % max(1, widgetEvery) == 1 {
                messageMedia.append(widgets[(index / max(1, widgetEvery)) % widgets.count])
                text = ""
            } else if media {
                if index % 5 == 2 {
                    let resource = LocalFileMediaResource(fileId: 990_000_000 + Int64(index))
                    let width: CGFloat = index % 2 == 0 ? 1280 : 960
                    let height: CGFloat = index % 3 == 0 ? 960 : 1280
                    let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(NSMakeSize(width, height)), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
                    photos.append((resource, NSMakeSize(width, height), index))
                    messageMedia.append(TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: 990_000_000 + Int64(index)), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: []))
                    if index % 10 != 2 {
                        text = ""
                    }
                } else if index % 7 == 3 {
                    let resource = LocalFileMediaResource(fileId: 991_000_000 + Int64(index))
                    messageMedia.append(TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: 991_000_000 + Int64(index)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/pdf", size: Int64(40_000 + index * 1_000), attributes: [.FileName(fileName: "report-\(index).pdf")], alternativeRepresentations: []))
                    text = ""
                }
                if index % 13 == 6 {
                    let source = users[(index + 5) % users.count]
                    peers[source.id] = source
                    forwardInfo = MessageForwardInfo(author: source, source: nil, sourceMessageId: nil, date: start - 86_400, authorSignature: nil, psaType: nil, flags: [])
                }
            }
            let message = Message(stableId: 4_000_000 + UInt32(index), stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: Int32(index + 1)), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: start + Int32(index) * 300, flags: outgoing ? [] : [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo, author: author, text: text, attributes: attributes, media: messageMedia, peers: peers, associatedMessages: associated, associatedMessageIds: associatedIds, associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
            result.append(message)
        }
        self.messages = result
        self.photos = photos
    }

    func storePhotoData(in mediaBox: MediaBox) {
        for photo in photos {
            let width = Int(photo.size.width / 4), height = Int(photo.size.height / 4)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
                continue
            }
            let ctx = graphics.cgContext
            let hue = CGFloat(photo.index * 37 % 360) / 360
            ctx.setFillColor(NSColor(hue: hue, saturation: 0.6, brightness: 0.8, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(NSColor(hue: 1 - hue, saturation: 0.7, brightness: 0.5, alpha: 1).cgColor)
            let stripe = CGFloat(8 + photo.index % 24)
            var x: CGFloat = -CGFloat(height)
            while x < CGFloat(width) {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + stripe, y: 0))
                ctx.addLine(to: CGPoint(x: x + stripe + CGFloat(height), y: CGFloat(height)))
                ctx.addLine(to: CGPoint(x: x + CGFloat(height), y: CGFloat(height)))
                ctx.fillPath()
                x += stripe * 3
            }
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                mediaBox.storeResourceData(photo.resource.id, data: data, synchronous: true)
            }
        }
    }

    var historyView: Signal<(MessageHistoryView, ViewUpdateType), NoError> {
        let entries = messages.map {
            MessageHistoryEntry(message: $0, isRead: true, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false))
        }
        let view = MessageHistoryView(tag: nil, namespaces: .just(Set([Namespaces.Message.Local])), entries: entries, holeEarlier: false, holeLater: false, isLoading: false)
        return .single((view, .Initial))
    }

    func enqueueMessages(messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
        return .single([])
    }

    func deleteMessages(ids: [EngineMessage.Id]) {
    }

    func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
    }

    func messagesAtIds(_ ids: [MessageId], album: Bool) -> Signal<[Message], NoError> {
        let set = Set(ids)
        return .single(messages.filter { set.contains($0.id) })
    }

    func hashtagSearchUpdate(query: String) {
    }

    func loadMore() {
    }
}
#endif
