import XCTest
import TelegramCore
import WidgetSandbox
import Postbox
@testable import HTMLBubbles

final class WidgetDataTests: XCTestCase {
    func testForwardNeverReceivesChatData() {
        let widget = TelegramMediaWidget(width: 300, height: 120, payload: Data(), isCopy: true, chatData: Data("private".utf8), publicData: Data("public".utf8))
        XCTAssertEqual(HTMLWidgetStore.data(widget), WidgetData(chatData: nil, publicData: "public"))
    }

    func testPreviewHasDataAndDisablesInteraction() {
        let widget = TelegramMediaWidget(width: 300, height: 120, payload: Data(), chatData: Data("chat".utf8), publicData: Data("public".utf8))
        let state = HTMLWidgetStore.preview(widget: widget, locale: "pt_br")
        XCTAssertTrue(state.widgetPreview)
        XCTAssertTrue(state.outgoing)
        XCTAssertEqual(state.widgetPreviewLocale, "pt-BR")
        XCTAssertNil(state.widgetContext)
        XCTAssertEqual(state.widgetData, WidgetData(chatData: "chat", publicData: "public"))
    }

    func testAutoHeightPreviewWaitsAtTheIOSPlaceholder() throws {
        let widget = try XCTUnwrap(TelegramMediaWidget(html: "<p>Tea, coffee or juice?</p>", width: 0, height: 0))
        let state = HTMLWidgetStore.preview(widget: widget)
        XCTAssertEqual(state.twidgetSize(width: 350), CGSize(width: 350, height: 160))
        XCTAssertNil(state.widgetRequestHandler)
        XCTAssertNil(state.widgetCopyHandler)
        XCTAssertNil(state.widgetContext)
    }

    func testInvalidUTF8IsNotPassedToRuntime() {
        let widget = TelegramMediaWidget(width: 300, height: 120, payload: Data(), chatData: Data(), publicData: Data([0xff]))
        XCTAssertEqual(HTMLWidgetStore.data(widget), WidgetData(chatData: "", publicData: nil))
    }

    private func message(_ widget: TelegramMediaWidget) -> Message {
        let bot = HTMLDemoCatalog.makeUser(id: PeerId(42), name: "Widget Bot", isBot: true)
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[bot.id] = bot
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: bot.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: bot, text: "Live poll", attributes: [], media: [widget], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    func testBotStateEditsReuseRuntimeButViewerAndLocaleChangesReplaceIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mediaBox = NSObject()
        let widget = try XCTUnwrap(TelegramMediaWidget(html: "<p>Live poll</p>", width: 0, height: 0))
        let context = HTMLWidgetContext(accountPeerId: PeerId(100), basePath: directory.path, messageId: message(widget).id, locale: "en", runtime: WidgetContext(canQuery: true, backgroundQuery: true, chatType: .private, viewer: WidgetViewer(id: 100, firstName: "First")))
        let store = HTMLWidgetStore()
        let initial = store.state(mediaBoxId: ObjectIdentifier(mediaBox), message: message(widget), widget: widget, context: context)
        let edited = TelegramMediaWidget(width: widget.width, height: widget.height, payload: widget.payload, chatData: Data("vote=tea".utf8), publicData: Data("tea=1".utf8))
        let updated = store.state(mediaBoxId: ObjectIdentifier(mediaBox), message: message(edited), widget: edited, context: context)
        XCTAssertTrue(initial === updated)
        XCTAssertEqual(updated.widgetData, WidgetData(chatData: "vote=tea", publicData: "tea=1"))

        let renamed = HTMLWidgetContext(accountPeerId: context.accountPeerId, basePath: context.basePath, messageId: context.messageId, locale: context.locale, runtime: WidgetContext(canQuery: true, backgroundQuery: true, chatType: .private, viewer: WidgetViewer(id: 100, firstName: "Renamed")))
        let newViewer = store.state(mediaBoxId: ObjectIdentifier(mediaBox), message: message(edited), widget: edited, context: renamed)
        XCTAssertFalse(updated === newViewer)
        XCTAssertEqual(newViewer.widgetContext, renamed)
        let translated = HTMLWidgetContext(accountPeerId: renamed.accountPeerId, basePath: renamed.basePath, messageId: renamed.messageId, locale: "ru", runtime: renamed.runtime)
        let newLanguage = store.state(mediaBoxId: ObjectIdentifier(mediaBox), message: message(edited), widget: edited, context: translated)
        XCTAssertFalse(newViewer === newLanguage)
        XCTAssertEqual(newLanguage.widgetData, updated.widgetData)
    }

    func testBotChatContextKeepsServerFlagsAndUsesAccountAsViewer() throws {
        let widget = TelegramMediaWidget(width: 0, height: 0, payload: Data(), canQuery: true, backgroundQuery: true)
        let viewer = HTMLDemoCatalog.makeUser(id: PeerId(100), name: "Account Owner", isBot: false)
        let context = HTMLWidgetContext(accountPeerId: viewer.id, basePath: "/tmp/widget-test", message: message(widget), widget: widget, locale: "ru", viewer: viewer, isPremium: true)
        XCTAssertEqual(context.runtime.chatType, .private)
        XCTAssertTrue(context.runtime.canQuery)
        XCTAssertTrue(context.runtime.backgroundQuery)
        XCTAssertEqual(context.runtime.viewer?.firstName, "Account")
        XCTAssertEqual(context.runtime.viewer?.id, viewer.id.id._internalGetInt64Value())
        XCTAssertTrue(context.runtime.viewer?.isPremium == true)
        let copy = widget.forwardedCopy()
        let copied = HTMLWidgetContext(accountPeerId: viewer.id, basePath: context.basePath, message: message(copy), widget: copy, locale: "ru", viewer: viewer, isPremium: true)
        XCTAssertNil(copied.runtime.chatType)
        XCTAssertNil(copied.runtime.viewer)
        XCTAssertFalse(copied.runtime.backgroundQuery)
    }
}
