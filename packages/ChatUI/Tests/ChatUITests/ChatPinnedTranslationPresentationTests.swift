import XCTest
import Postbox
import TelegramCore
import ChatHistoryModel
@testable import ChatUI

final class ChatPinnedTranslationPresentationTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let chatId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))

    private func message(_ text: String = "Pinned text", incoming: Bool = false, version: UInt32 = 0, attributes: [MessageAttribute] = []) -> Message {
        return Message(stableId: 1, stableVersion: version, id: MessageId(peerId: chatId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: text, attributes: attributes, media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func state(for message: Message) -> ChatLiveTranslateContext.State {
        var state = ChatLiveTranslateContext.State.default
        state.canTranslate = true
        state.translate = true
        state.to = "en"
        state.result[.init(id: message.id, toLang: "en")] = .loading(toLang: "en")
        return state
    }

    func testPreparedEligibilitySurvivesPresentationMappingAndChangesEquality() {
        let pinned = message()
        var source = state(for: pinned)
        let before = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertNil(before.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
        source.translationEligibility[.init(id: pinned.id, toLang: "en")] = ChatTranslationSource(pinned)
        let after = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.translationEligibility, source.translationEligibility)
        XCTAssertEqual(after.pinnedTranslationResult(for: pinned, accountPeerId: accountId), .loading(toLang: "en"))
        source.result[.init(id: pinned.id, toLang: "en")] = .complete(toLang: "en")
        XCTAssertEqual(ChatPresentationInterfaceState.TranslateState(source).pinnedTranslationResult(for: pinned, accountPeerId: accountId), .complete(toLang: "en"))
    }

    func testOwnPinnedTranslationSurvivesVersionOnlyRefreshWithoutCollectionPass() {
        let pinned = message()
        var source = state(for: pinned)
        source.translationEligibility[.init(id: pinned.id, toLang: "en")] = ChatTranslationSource(pinned)
        for result: ChatLiveTranslateContext.State.Result in [.loading(toLang: "en"), .complete(toLang: "en")] {
            source.result[.init(id: pinned.id, toLang: "en")] = result
            let projected = ChatPresentationInterfaceState.TranslateState(source)
            XCTAssertEqual(projected.pinnedTranslationResult(for: message(version: 1), accountPeerId: accountId), result)
            XCTAssertEqual(projected.pinnedTranslationResult(for: message(version: 9), accountPeerId: accountId), result)
        }
    }

    func testProjectionRejectsChangedContentTargetsAndDisabledState() {
        let pinned = message()
        var source = state(for: pinned)
        source.translationEligibility[.init(id: pinned.id, toLang: "en")] = ChatTranslationSource(pinned)
        var projected = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertNil(projected.pinnedTranslationResult(for: message("Edited text", version: 1), accountPeerId: accountId))
        projected.to = "ru"
        projected.result[.init(id: pinned.id, toLang: "ru")] = .complete(toLang: "ru")
        XCTAssertNil(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
        projected.to = "en"
        projected.translate = false
        XCTAssertNil(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
        projected.translate = true
        projected.canTranslate = false
        XCTAssertNil(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
    }

    func testEntityEditRequiresFreshEligibility() {
        let pinned = message()
        var source = state(for: pinned)
        source.translationEligibility[.init(id: pinned.id, toLang: "en")] = ChatTranslationSource(pinned)
        let edited = message(version: 1, attributes: [TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: 0..<6, type: .Bold)])])
        XCTAssertNil(ChatPresentationInterfaceState.TranslateState(source).pinnedTranslationResult(for: edited, accountPeerId: accountId))
        source.translationEligibility[.init(id: edited.id, toLang: "en")] = ChatTranslationSource(edited)
        XCTAssertEqual(ChatPresentationInterfaceState.TranslateState(source).pinnedTranslationResult(for: edited, accountPeerId: accountId), .loading(toLang: "en"))
    }

    func testRichTextEditsInvalidateButViewCountsDoNot() {
        func rich(_ text: String, views: Int32) -> Message {
            let page = InstantPage(blocks: [.paragraph(.plain(text))], media: [:], isComplete: true, rtl: false, url: "", views: views)
            return message("", version: UInt32(views), attributes: [RichTextMessageAttribute(instantPage: page, fullInstantPage: nil)])
        }
        let pinned = rich("Original rich text", views: 1)
        var source = state(for: pinned)
        source.translationEligibility[.init(id: pinned.id, toLang: "en")] = ChatTranslationSource(pinned)
        let projected = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertEqual(projected.pinnedTranslationResult(for: rich("Original rich text", views: 2), accountPeerId: accountId), .loading(toLang: "en"))
        XCTAssertNil(projected.pinnedTranslationResult(for: rich("Edited rich text", views: 2), accountPeerId: accountId))
    }

    func testIncomingPinsRetainLookupWithoutOutgoingEligibility() {
        let pinned = message(incoming: true)
        let source = state(for: pinned)
        let projected = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertTrue(projected.translationEligibility.isEmpty)
        XCTAssertEqual(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId), .loading(toLang: "en"))
        XCTAssertEqual(projected.pinnedTranslationResult(for: message(incoming: true, version: 1), accountPeerId: accountId), .loading(toLang: "en"))
    }
}
