import XCTest
import Postbox
import TelegramCore
@testable import HTMLBubbles

final class HTMLDocumentBubblesTests: XCTestCase {
    private let botId: Int64 = 8736535756

    private func peerId(_ id: Int64, namespace: PeerId.Namespace = Namespaces.Peer.CloudUser) -> PeerId {
        return PeerId(namespace: namespace, id: PeerId.Id._internalFromInt64Value(id))
    }

    private func file(mimeType: String, name: String?, size: Int64?) -> TelegramMediaFile {
        let attributes: [TelegramMediaFileAttribute] = name.map { [.FileName(fileName: $0)] } ?? []
        return TelegramMediaFile(fileId: MediaId(namespace: 0, id: 1), partialReference: nil, resource: LocalFileMediaResource(fileId: 1), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: size, attributes: attributes, alternativeRepresentations: [])
    }

    private func message(author: Int64, media: [Media], incoming: Bool = true, namespace: MessageId.Namespace = Namespaces.Message.Cloud) -> Message {
        let user = HTMLDemoCatalog.makeUser(id: peerId(author), name: "Bot", isBot: true)
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[user.id] = user
        let id = MessageId(peerId: user.id, namespace: namespace, id: 10)
        return Message(stableId: 1, stableVersion: 0, id: id, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: user, text: "", attributes: [], media: media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    func testMimeAndName() {
        XCTAssertTrue(HTMLDocumentBubbles.isHTMLDocument(mimeType: "text/html", fileName: nil, size: 100))
        XCTAssertTrue(HTMLDocumentBubbles.isHTMLDocument(mimeType: "TEXT/HTML", fileName: "x.bin", size: 100))
        XCTAssertTrue(HTMLDocumentBubbles.isHTMLDocument(mimeType: "application/octet-stream", fileName: "weather.HTML", size: 100))
        XCTAssertFalse(HTMLDocumentBubbles.isHTMLDocument(mimeType: "text/plain", fileName: "notes.txt", size: 100))
        XCTAssertFalse(HTMLDocumentBubbles.isHTMLDocument(mimeType: "text/plain", fileName: "page.htm", size: 100))
        XCTAssertFalse(HTMLDocumentBubbles.isHTMLDocument(mimeType: "text/html", fileName: nil, size: nil))
        XCTAssertFalse(HTMLDocumentBubbles.isHTMLDocument(mimeType: "text/html", fileName: nil, size: 0))
    }

    func testSizeLimit() {
        XCTAssertTrue(HTMLDocumentBubbles.isHTMLDocument(mimeType: "text/html", fileName: nil, size: 256 * 1024))
        XCTAssertFalse(HTMLDocumentBubbles.isHTMLDocument(mimeType: "text/html", fileName: nil, size: 256 * 1024 + 1))
        XCTAssertNil(HTMLDocumentBubbles.decode(Data(count: 256 * 1024 + 1)))
        XCTAssertEqual(HTMLDocumentBubbles.decode("<b>hi</b>".data(using: .utf8)!), "<b>hi</b>")
        XCTAssertNil(HTMLDocumentBubbles.decode(Data([0xFF, 0xFE, 0xFD])))
        XCTAssertNil(HTMLDocumentBubbles.decode(Data()))
    }

    func testAllowlist() {
        XCTAssertTrue(HTMLDocumentBubbles.botIds.contains(botId))
        XCTAssertTrue(HTMLDocumentBubbles.isAllowedAuthor(peerId(botId)))
        XCTAssertFalse(HTMLDocumentBubbles.isAllowedAuthor(peerId(123456)))
        XCTAssertFalse(HTMLDocumentBubbles.isAllowedAuthor(peerId(botId, namespace: Namespaces.Peer.CloudChannel)))
        XCTAssertFalse(HTMLDocumentBubbles.isAllowedAuthor(nil))
    }

    func testDebugAllowlist() {
        let defaults = UserDefaults(suiteName: "HTMLDocumentBubblesTests")!
        defaults.removePersistentDomain(forName: "HTMLDocumentBubblesTests")
        XCTAssertEqual(HTMLDocumentBubbles.debugBotIds(defaults), [])
        defaults.set([NSNumber(value: 42), "77", "junk"], forKey: HTMLDocumentBubbles.debugBotIdsKey)
        XCTAssertEqual(HTMLDocumentBubbles.debugBotIds(defaults), [42, 77])
        defaults.removePersistentDomain(forName: "HTMLDocumentBubblesTests")
    }

    func testMessageDetection() {
        let html = file(mimeType: "text/html", name: "weather.html", size: 2048)
        XCTAssertNotNil(HTMLDocumentBubbles.document(in: message(author: botId, media: [html])))
        XCTAssertNil(HTMLDocumentBubbles.document(in: message(author: 123456, media: [html])))
        XCTAssertNil(HTMLDocumentBubbles.document(in: message(author: botId, media: [html], incoming: false)))
        XCTAssertNil(HTMLDocumentBubbles.document(in: message(author: botId, media: [html], namespace: Namespaces.Message.Local)))
        XCTAssertNil(HTMLDocumentBubbles.document(in: message(author: botId, media: [file(mimeType: "text/html", name: "big.html", size: 300 * 1024)])))
        XCTAssertNil(HTMLDocumentBubbles.document(in: message(author: botId, media: [file(mimeType: "image/png", name: "pic.png", size: 2048)])))
        XCTAssertNil(HTMLDocumentBubbles.document(in: message(author: botId, media: [])))
        XCTAssertNotNil(HTMLDocumentBubbles.document(in: message(author: 99, media: [html]), allowlist: [99]))
    }

    func testHeightHint() {
        XCTAssertEqual(HTMLDocumentBubbles.heightHint("<div class=\"widget\" data-height=\"320\">x</div>"), 320)
        XCTAssertEqual(HTMLDocumentBubbles.heightHint("<div DATA-HEIGHT='210'>"), 210)
        XCTAssertEqual(HTMLDocumentBubbles.heightHint("<div data-height=90>"), 90)
        XCTAssertEqual(HTMLDocumentBubbles.heightHint("<div data-height=\"5\">"), 40)
        XCTAssertEqual(HTMLDocumentBubbles.heightHint("<div data-height=\"99999\">"), 1200)
        XCTAssertNil(HTMLDocumentBubbles.heightHint("<div data-width=\"300\">"))
        XCTAssertNil(HTMLDocumentBubbles.heightHint("<div data-height=\"auto\">"))
    }

    func testStyleSetting() {
        let defaults = UserDefaults(suiteName: "HTMLDocumentBubblesStyleTests")!
        defaults.removePersistentDomain(forName: "HTMLDocumentBubblesStyleTests")
        XCTAssertEqual(HTMLDocumentBubbles.style(defaults), .bare)
        defaults.set("full", forKey: HTMLDocumentBubbles.styleKey)
        XCTAssertEqual(HTMLDocumentBubbles.style(defaults), .full)
        defaults.set("Bubble", forKey: HTMLDocumentBubbles.styleKey)
        XCTAssertEqual(HTMLDocumentBubbles.style(defaults), .bubble)
        defaults.set("CARD", forKey: HTMLDocumentBubbles.styleKey)
        XCTAssertEqual(HTMLDocumentBubbles.style(defaults), .card)
        defaults.set("bare", forKey: HTMLDocumentBubbles.styleKey)
        XCTAssertEqual(HTMLDocumentBubbles.style(defaults), .bare)
        defaults.set("weird", forKey: HTMLDocumentBubbles.styleKey)
        XCTAssertEqual(HTMLDocumentBubbles.style(defaults), .bare)
        defaults.removePersistentDomain(forName: "HTMLDocumentBubblesStyleTests")
    }

    func testBubbleWidth() {
        XCTAssertEqual(HTMLDocumentBubbles.bubbleWidth("<div class=\"widget\">x</div>"), HTMLDocumentBubbles.bubbleWidth)
        XCTAssertEqual(HTMLDocumentBubbles.bubbleWidth("<div data-width=\"320\">"), 320)
        XCTAssertEqual(HTMLDocumentBubbles.bubbleWidth("<div data-width=\"50\">"), 200)
        XCTAssertEqual(HTMLDocumentBubbles.bubbleWidth("<div data-width=\"900\">"), 480)
        XCTAssertLessThanOrEqual(HTMLDocumentBubbles.bubbleWidth, HTMLDocumentBubbles.bubbleWidthRange.upperBound)
    }

    func testDocumentsHideStatsByDefault() {
        UserDefaults.standard.removeObject(forKey: HTMLDocumentBubbles.statsKey)
        let state = HTMLDocumentBubbles.makeState(html: "<div class=\"widget\" data-height=\"200\">x</div>")
        XCTAssertFalse(state.showsStats)
        XCTAssertEqual(state.heightHint, 200)
        XCTAssertEqual(HTMLBubbleStatsOverlay.reservedHeight(state), 0)
    }
}
