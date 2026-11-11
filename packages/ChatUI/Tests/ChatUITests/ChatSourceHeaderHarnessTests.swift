import AppKit
import XCTest
import Postbox
import TelegramCore
import TGUIKit
import ChatHistoryModel
import InAppSettings
import TelegramContext
import TelegramTheme
import TelegramUtils
import ThemeSettings
import ColorPalette
@testable import ChatUI

private final class SourceHarnessMessageItem: TableRowItem {
    let message: Message

    init(_ message: Message) {
        self.message = message
        super.init(NSSize(width: 480, height: 88), stableId: message.id)
    }

    override var height: CGFloat { 88 }
    override func viewClass() -> AnyClass { SourceHarnessMessageView.self }
}

private final class SourceHarnessMessageView: TableRowView {
    private let title = NSTextField(labelWithString: "")
    private let body = NSTextField(labelWithString: "")

    required init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .systemBlue
        body.font = .systemFont(ofSize: 14)
        body.textColor = .labelColor
        addSubview(title)
        addSubview(body)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? SourceHarnessMessageItem else { return }
        title.stringValue = "Forwarded from \(item.message.forwardInfo?.author?.displayTitle ?? "Self")"
        body.stringValue = item.message.text
        title.frame = NSRect(x: 30, y: 16, width: 420, height: 20)
        body.frame = NSRect(x: 30, y: 40, width: 420, height: 24)
    }
}

final class ChatSourceHeaderHarnessTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(100))
    private var presentation: TelegramPresentationTheme!

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        ChatHistoryModelHooks.install(.placeholder)
        TelegramUtilsHooks.install(.init(animationsAreLite: { false }, isLite: { _ in true }, peerTitle: { ($0 as? TelegramUser)?.firstName ?? ($0 as? TelegramChannel)?.title ?? "" }, peerLetters: { _ in [] }, peerIsForum: { _ in false }, peerCompactTitle: { _ in "" }, repliesPeerId: { .init(0) }))
        presentation = generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: true, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false)
    }

    private func user(_ id: Int64, _ title: String) -> TelegramUser {
        TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: title, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func channel(_ id: Int64, forum: Bool) -> TelegramChannel {
        TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(id)), accessHash: nil, title: forum ? "Forum" : "Channel direct messages", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: forum ? [.isForum] : [.isMonoforum], restrictionInfo: nil, adminRights: .init(rights: [.canManageDirect]), bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func fixture(chat: Peer, topicInfo: Bool = false, album: Bool = false) -> [MessageHistoryEntry] {
        let authors = [user(501, "Mike"), user(502, "Widget Bot")]
        let sequence = album ? [0, 0, 1, 1] : [0, 1, 0]
        return sequence.enumerated().map { index, source in
            let author = authors[source]
            var peers: [PeerId: Peer] = [chat.id: chat]
            if !topicInfo { authors.forEach { peers[$0.id] = $0 } }
            let image = TelegramMediaImage(imageId: MediaId(namespace: 0, id: Int64(index + 1)), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
            let message = Message(stableId: UInt32(index + 1), stableVersion: 0, id: MessageId(peerId: chat.id, namespace: Namespaces.Message.Cloud, id: Int32(index + 1)), globallyUniqueId: nil, groupingKey: album ? Int64(source + 1) : nil, groupInfo: album ? MessageGroupInfo(stableId: UInt32(source + 1)) : nil, threadId: author.id.toInt64(), timestamp: 1_793_673_600 + Int32(index), flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: .init(author: author, source: author, sourceMessageId: MessageId(peerId: author.id, namespace: Namespaces.Message.Cloud, id: Int32(index + 20)), date: 1_793_673_500, authorSignature: nil, psaType: nil, flags: []), author: author, text: "Source message \(index + 1)", attributes: [], media: album ? [image] : [], peers: SimpleDictionary(peers), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: topicInfo ? .init(title: source == 0 ? "Topic A" : "Topic B", icon: nil, iconColor: 0, isClosed: false) : nil, associatedStories: [:])
            return MessageHistoryEntry(message: message, isRead: true, location: nil, monthLocation: nil, attributes: .init(authorIsContact: false))
        }
    }

    private func history(_ input: [MessageHistoryEntry], location: ChatLocation?, state: MonoforumUIState? = .sidebar, album: Bool = false) -> [ChatHistoryEntry] {
        messageEntries(input, location: location, dayGrouping: true, renderType: .bubble, groupingPhotos: album, chatTheme: presentation, monoforumState: state, accountPeerId: accountId)
    }

    private func separators(_ entries: [ChatHistoryEntry]) -> [ChatHistoryEntry] {
        entries.filter { if case .topicSeparator = $0 { return true }; return false }
    }

    private func assertMessagesPreserved(_ input: [MessageHistoryEntry], _ output: [ChatHistoryEntry], file: StaticString = #filePath, line: UInt = #line) {
        let messages = output.flatMap { $0.messages }.sorted { $0.id.id < $1.id.id }
        XCTAssertEqual(messages.count, input.count, file: file, line: line)
        for (original, rendered) in zip(input.map { $0.message }, messages) {
            XCTAssertEqual(rendered.id, original.id, file: file, line: line)
            XCTAssertEqual(rendered.text, original.text, file: file, line: line)
            XCTAssertEqual(rendered.threadId, original.threadId, file: file, line: line)
            XCTAssertEqual(rendered.forwardInfo, original.forwardInfo, file: file, line: line)
            XCTAssertEqual(rendered.media.count, original.media.count, file: file, line: line)
        }
        XCTAssertEqual(output.filter { if case .DateEntry = $0 { return true }; return false }.count, 1, file: file, line: line)
    }

    private func render(_ entries: [ChatHistoryEntry], name: String) throws -> CGFloat {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 480, height: 400), isFlipped: false)
        table.backgroundColor = presentation.colors.background
        table.setSecondary(stickClass: ChatTopicSeparatorItem.self, handler: { _ in })
        for entry in entries.reversed() {
            let item: TableRowItem
            if case .topicSeparator = entry {
                item = ChatTopicSeparatorItem(NSSize(width: 480, height: 28), entry: entry, theme: presentation)
            } else if let message = entry.firstMessage {
                item = SourceHarnessMessageItem(message)
            } else {
                item = GeneralHarnessDateItem(entry)
            }
            _ = item.makeSize(480, oldWidth: 0)
            _ = table.addItem(item: item)
        }
        table.layoutSubtreeIfNeeded()
        let height = table.allItems.reduce(CGFloat(0)) { $0 + table.rectOf(item: $1).height }
        let pixels = ViewSnapshot.render(table)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = pixels.bytes
        let context = CGContext(data: &bytes, width: pixels.width, height: pixels.height, bitsPerComponent: 8, bytesPerRow: pixels.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SOURCE_HEADER_HARNESS_OUTPUT"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent(name + ".png"))
            let values: [String: Any] = ["messageCount": entries.flatMap { $0.messages }.count, "sourceHeaderCount": separators(entries).count, "sourceHeaderReservedHeight": separators(entries).count * 28, "measuredRowsHeight": height, "tableRowCount": table.count]
            try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: url.appendingPathComponent(name + ".json"))
        }
        return height
    }

    func testSavedMessagesHasNoSourceHeadersInEveryLayout() throws {
        let input = fixture(chat: user(100, "Saved Messages"))
        for state in [MonoforumUIState.sidebar, .vertical, .horizontal] {
            let output = history(input, location: .peer(accountId), state: state)
            assertMessagesPreserved(input, output)
            if state == .sidebar {
                let height = try render(output, name: "saved-messages")
                XCTAssertEqual(height, 3 * 88 + 28)
            }
            XCTAssertTrue(separators(output).isEmpty, "Saved Messages inserted source headers in \(state)")
        }
    }

    func testSavedMessagesWithoutExplicitLocationStillHasNoSourceHeaders() {
        let input = fixture(chat: user(100, "Saved Messages"))
        XCTAssertTrue(separators(history(input, location: nil)).isEmpty)
    }

    func testRepliesAndVerificationCodesFollowTheSameIOSExclusion() {
        for id: Int64 in [708513, 1271266957, 489000] {
            let chat = user(id, "Special chat")
            XCTAssertTrue(separators(history(fixture(chat: chat), location: .peer(chat.id))).isEmpty)
        }
    }

    func testSavedMediaAlbumsPreserveMessagesWithoutSourceHeaders() {
        let input = fixture(chat: user(100, "Saved Messages"), album: true)
        let output = history(input, location: .peer(accountId), album: true)
        assertMessagesPreserved(input, output)
        XCTAssertTrue(separators(output).isEmpty)
        XCTAssertEqual(output.filter { if case .groupedPhotos = $0 { return true }; return false }.count, 2)
    }

    func testForumTopicsRetainDividers() throws {
        let chat = channel(1000, forum: true)
        let input = fixture(chat: chat, topicInfo: true)
        let output = history(input, location: .peer(chat.id))
        assertMessagesPreserved(input, output)
        XCTAssertEqual(separators(output).count, 2)
        XCTAssertEqual(try render(output, name: "forum-topics"), 3 * 88 + 3 * 28)
    }

    func testChannelDirectMessagesRetainSourceDividers() throws {
        let chat = channel(1001, forum: false)
        let input = fixture(chat: chat)
        let output = history(input, location: .peer(chat.id))
        assertMessagesPreserved(input, output)
        XCTAssertEqual(separators(output).count, 2)
        _ = try render(output, name: "channel-direct-messages")
    }

    func testSelectedThreadAndDisabledTopicLayoutHaveNoDividers() {
        let chat = channel(1000, forum: true)
        let input = fixture(chat: chat, topicInfo: true)
        XCTAssertTrue(separators(history(input, location: .makeSaved(chat.id, threadId: 501))).isEmpty)
        XCTAssertTrue(separators(history(input, location: .peer(chat.id), state: nil)).isEmpty)
    }
}

private final class GeneralHarnessDateItem: TableRowItem {
    init(_ entry: ChatHistoryEntry) {
        super.init(NSSize(width: 480, height: 28), stableId: entry.stableId)
    }
    override var height: CGFloat { 28 }
}
