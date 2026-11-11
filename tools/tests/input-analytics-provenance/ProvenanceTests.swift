import Foundation
import AppKit
import XCTest
import SwiftSignalKit

struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringLiteral value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
struct MediaId: Hashable {}
protocol Media {}
extension Int64 { func _internalGetInt64Value() -> Int64 { self } }
struct TextEntitiesMessageAttribute { let entities: [MessageTextEntity] }
struct TelegramMediaFile: Codable, Equatable { let id: Int64; var isPremiumEmoji: Bool { false } }
struct ItemCollectionId: Codable, Equatable { let id: Int64 }
struct PeerId: Equatable {
    let id: Int64
    init(_ id: Int64) { self.id = id }
    init(namespace: Int, id: Int64) { self.id = id }
    func toInt64() -> Int64 { id }
    enum Id { static func _internalFromInt64Value(_ value: Int64) -> Int64 { value } }
}
enum Namespaces { enum Peer { static let CloudUser = 0 } }
final class ChatTextInputTextMentionAttribute { let peerId: PeerId; init(peerId: PeerId) { self.peerId = peerId } }
final class TextInputTextUrlAttribute { let url: String; init(url: String) { self.url = url } }
final class TextInputTextDateAttribute { let date: Int32; init(date: Int32) { self.date = date } }
final class TextInputTextQuoteAttribute { let collapsed: Bool; init(collapsed: Bool) { self.collapsed = collapsed } }
final class TextInputTextCustomEmojiAttribute {
    let collectionId: ItemCollectionId?
    let fileId: Int64
    let file: TelegramMediaFile?
    let emoji: String
    init(collectionId: ItemCollectionId?, fileId: Int64, file: TelegramMediaFile?, emoji: String) {
        self.collectionId = collectionId; self.fileId = fileId; self.file = file; self.emoji = emoji
    }
}
struct EmbeddedCustomEmojiAttributeValue { let customEmojiAttribute: TextInputTextCustomEmojiAttribute? }
struct Updated_ChatTextInputState {
    let inputText: NSAttributedString
    let selectionRange: Range<Int>
    init(inputText: NSAttributedString, selectionRange: Range<Int>) { self.inputText = inputText; self.selectionRange = selectionRange }
}
enum TextInputAttributes {
    static let bold = NSAttributedString.Key("bold"), italic = NSAttributedString.Key("italic"), code = NSAttributedString.Key("code"), monospace = NSAttributedString.Key("monospace"), textMention = NSAttributedString.Key("mention"), textUrl = NSAttributedString.Key("url"), customEmoji = NSAttributedString.Key("emoji"), embedded = NSAttributedString.Key("embedded"), strikethrough = NSAttributedString.Key("strike"), underline = NSAttributedString.Key("underline"), spoiler = NSAttributedString.Key("spoiler"), formattedDate = NSAttributedString.Key("date"), quote = NSAttributedString.Key("quote")
    static let allAttributes = [bold, italic, code, monospace, textMention, textUrl, customEmoji, embedded, strikethrough, underline, spoiler, formattedDate, quote]
}
struct ChatTextFontAttributes: OptionSet {
    let rawValue: Int
    static let bold = Self(rawValue: 1), italic = Self(rawValue: 2), monospace = Self(rawValue: 4)
}
extension NSFont {
    static func normal(_ size: CGFloat) -> NSFont { systemFont(ofSize: size) }
    static func semiboldItalicMonospace(_ size: CGFloat) -> NSFont { normal(size) }
    static func semiboldMonospace(_ size: CGFloat) -> NSFont { normal(size) }
    static func italicMonospace(_ size: CGFloat) -> NSFont { normal(size) }
    static func boldItalic(_ size: CGFloat) -> NSFont { normal(size) }
    static func semibold(_ size: CGFloat) -> NSFont { normal(size) }
    static func italic(_ size: CGFloat) -> NSFont { normal(size) }
    static func code(_ size: CGFloat) -> NSFont { normal(size) }
}
extension String { var length: Int { utf16.count }; var nsstring: NSString { self as NSString } }
extension NSRange { var min: Int { location }; var max: Int { location + length } }
extension NSAttributedString { var trimmed: NSAttributedString { trimChatInputText(self) } }
func arc4random64() -> UInt64 { 7 }
struct MessageTextEntity: Equatable {
    enum Kind: Equatable {
        enum Format: Equatable { enum Part { case short }; case full(timeFormat: Part?, dateFormat: Part?, dayOfWeek: Bool) }
        case Bold, Strikethrough, Spoiler, Underline, Italic, Pre(language: String?), Code, TextMention(peerId: PeerId), TextUrl(url: String), CustomEmoji(stickerPack: Int?, fileId: Int64), BlockQuote(isCollapsed: Bool), FormattedDate(format: Format, date: Int32)
    }
    let range: Range<Int>
    let type: Kind
}
__ATTRIBUTES__
__PARSE__
__MODEL__
__FORMAT__
__TRANSFORMS__

final class InputAnalyticsProvenanceTests: XCTestCase {
    func marked(_ text: String = "A😀B", range: Range<Int> = 1..<3) -> ChatTextInputState {
        ChatTextInputState(inputText: text, selectionRange: 0..<0, attributes: [.bold(0..<1), .analyticsExcluded(range)])
    }
    func rendered(_ state: ChatTextInputState) -> NSAttributedString {
        textAttributedStringForStateText(state.attributedString(), fontSize: 13, textColor: .black, accentTextColor: .blue, writingDirection: nil, spoilersRevealed: true, availableEmojis: [])
    }
    func testCodableRoundTripKeepsUTF16ExclusionWithoutAddingLegacyAttribute() throws {
        let state = marked(); let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ChatTextInputState.self, from: data)
        XCTAssertEqual(decoded, state); XCTAssertTrue(decoded.hasExcludedAnalytics)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["t.ae"] as? [Int], [1, 3])
        let legacy = try XCTUnwrap(object["t.a"] as? [[String: Any]])
        XCTAssertEqual(legacy.count, 1); XCTAssertEqual(legacy.first?["_rawValue"] as? Int, 0)
        XCTAssertEqual(Set(object.keys), Set(["t", "t.a", "t.ae", "s0", "s1"]))
    }
    func testExplicitEmptyProvenancePreservesOrdinaryLocalDraft() throws {
        let state = ChatTextInputState(inputText: "plain")
        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["t.ae"] as? [Int], [])
        XCTAssertFalse(try JSONDecoder().decode(ChatTextInputState.self, from: data).hasExcludedAnalytics)
    }
    func testMalformedMetadataFailsClosedWithoutChangingText() throws {
        for value: Any in ["bad", NSNull(), [-1, 3], [1, 500], [3, 1], [1], [[1, 3]]] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatTextInputState(inputText: "abc"))) as? [String: Any])
            object["t.ae"] = value
            let decoded = try JSONDecoder().decode(ChatTextInputState.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertTrue(decoded.hasExcludedAnalytics); XCTAssertEqual(decoded.inputText, "abc")
            XCTAssertEqual(decoded.attributedString().attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) as? Bool, true)
        }
    }
    func testLegacyMissingMetadataIsUnknownAndExcluded() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatTextInputState(inputText: "legacy"))) as? [String: Any])
        object.removeValue(forKey: "t.ae")
        let restored = try JSONDecoder().decode(ChatTextInputState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(restored.hasExcludedAnalytics)
        XCTAssertEqual(restored.inputText, "legacy")
        let empty = ChatTextInputState(inputText: "")
        XCTAssertFalse(try JSONDecoder().decode(ChatTextInputState.self, from: JSONEncoder().encode(empty)).hasExcludedAnalytics)
    }
    func testRenderingAndStateConversionPreserveMarker() {
        let value = rendered(marked())
        let stateText = stateAttributedStringForText(value)
        let restored = ChatTextInputState(attributedText: stateText, selectionRange: 0..<0)
        XCTAssertTrue(restored.hasExcludedAnalytics)
        XCTAssertEqual(restored.attributes, marked().attributes)
        XCTAssertEqual(value.string, "A😀B")
        XCTAssertNil(value.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil))
    }
    func testNativeUndoSnapshotRestoresMarkerAfterDeletion() {
        let original = rendered(marked())
        let storage = NSMutableAttributedString(attributedString: original)
        let manager = UndoManager()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: storage) { target in target.setAttributedString(original) }
        storage.deleteCharacters(in: NSRange(location: 1, length: 2))
        manager.endUndoGrouping()
        XCTAssertFalse(ChatTextInputState(attributedText: storage, selectionRange: 0..<0).hasExcludedAnalytics)
        manager.undo()
        XCTAssertTrue(ChatTextInputState(attributedText: storage, selectionRange: 0..<0).hasExcludedAnalytics)
        XCTAssertEqual(storage.string, "A😀B")
    }
    func testMessageEntitiesNeverContainProvenance() {
        let plain = ChatTextInputState(inputText: "A😀B", selectionRange: 0..<0, attributes: [.bold(0..<1)])
        XCTAssertEqual(marked().messageTextEntities(), plain.messageTextEntities())
    }
    func testSelectionAndEmojiTransformsKeepMarker() {
        XCTAssertTrue(marked().withUpdatedRange(3..<3).hasExcludedAnalytics)
        XCTAssertTrue(marked().withoutAnimatedEmoji.hasExcludedAnalytics)
        XCTAssertTrue(marked().unique(isPremium: false).hasExcludedAnalytics)
    }
    func testSubstringExclusionDoesNotSpreadToUnrelatedSlice() {
        let state = marked()
        XCTAssertFalse(state.subInputState(from: NSRange(location: 0, length: 1)).hasExcludedAnalytics)
        XCTAssertTrue(state.subInputState(from: NSRange(location: 1, length: 2)).hasExcludedAnalytics)
        XCTAssertFalse(state.subInputState(from: NSRange(location: 3, length: 1)).hasExcludedAnalytics)
    }
    func testProvenanceDoesNotPreventMarkdownConversion() {
        let text = "**hello**"
        let state = ChatTextInputState(inputText: text, selectionRange: 0..<0, attributes: [.analyticsExcluded(0..<text.utf16.count)])
        let converted = state.subInputState(from: NSRange(location: 0, length: text.utf16.count))
        XCTAssertEqual(converted.inputText, "hello"); XCTAssertTrue(converted.hasExcludedAnalytics)
        XCTAssertTrue(converted.attributes.contains(.bold(0..<5)))
        XCTAssertTrue(converted.attributes.contains(.analyticsExcluded(0..<5)))
    }
    func testEmptyRangesDoNotExcludeEmptyDraft() {
        let state = ChatTextInputState(inputText: "", selectionRange: 0..<0, attributes: [.analyticsExcluded(0..<0)])
        XCTAssertFalse(state.hasExcludedAnalytics)
    }
}

struct SynchronizeableChatInputState {
    let text: String
    let entities: [MessageTextEntity]
    var textSelection: Range<Int>?
    var replySubject: Int?
}
struct ChatInterfaceState {
    var inputState: ChatTextInputState
    var timestamp: Int32 = 17
    var historyScrollState: Int? = 5
    var reply: Int?
    func withUpdatedInputState(_ input: ChatTextInputState) -> Self { var value = self; value.inputState = input; return value }
    func withUpdatedReplyMessageId(_ id: Int?) -> Self { var value = self; value.reply = id; return value }
    func withUpdatedTimestamp(_ timestamp: Int32) -> Self { var value = self; value.timestamp = timestamp; return value }
    func withUpdatedHistoryScrollState(_ scroll: Int?) -> Self { var value = self; value.historyScrollState = scroll; return value }
__SYNC__
}
final class InputAnalyticsSynchronizationTests: XCTestCase {
    func sync(_ input: ChatTextInputState, selection: Range<Int>? = nil) -> SynchronizeableChatInputState {
        .init(text: input.inputText, entities: input.messageTextEntities(), textSelection: selection, replySubject: 8)
    }
    func testPrivateArchiveMarkerSurvivesSynchronizationAndSelectionChange() throws {
        let input = ChatTextInputState(attributedText: chatInputTextExcludingAnalytics(NSAttributedString(string: "😀hello")), selectionRange: 0..<0)
        let decoded = try JSONDecoder().decode(ChatTextInputState.self, from: JSONEncoder().encode(input))
        let restored = ChatInterfaceState(inputState: decoded).withUpdatedSynchronizeableInputState(sync(input, selection: 2..<2))
        XCTAssertTrue(restored.inputState.hasExcludedAnalytics)
        XCTAssertEqual(restored.inputState.selectionRange, 2..<2); XCTAssertEqual(restored.reply, 8)
        XCTAssertEqual(restored.timestamp, 17); XCTAssertEqual(restored.historyScrollState, 5)
    }
    func testOrdinaryCurrentArchiveRetainsItsExplicitUnmarkedState() throws {
        let input = ChatTextInputState(inputText: "ordinary")
        let decoded = try JSONDecoder().decode(ChatTextInputState.self, from: JSONEncoder().encode(input))
        let restored = ChatInterfaceState(inputState: decoded).withUpdatedSynchronizeableInputState(sync(input))
        XCTAssertFalse(restored.inputState.hasExcludedAnalytics)
    }
    func testImportedReplacementWithoutMatchingLocalDraftIsExcluded() {
        let input = ChatTextInputState(inputText: "remote")
        for old in [ChatTextInputState(), ChatTextInputState(inputText: "local")] {
            let restored = ChatInterfaceState(inputState: old).withUpdatedSynchronizeableInputState(sync(input))
            XCTAssertTrue(restored.inputState.hasExcludedAnalytics); XCTAssertEqual(restored.inputState.inputText, "remote")
            XCTAssertEqual(restored.inputState.messageTextEntities(), input.messageTextEntities())
        }
    }
    func testChangedEntitiesCannotReuseOrdinaryProvenanceByTextEqualityAlone() {
        let old = ChatTextInputState(inputText: "same")
        let updated = ChatTextInputState(inputText: "same", selectionRange: 0..<0, attributes: [.bold(0..<4)])
        let restored = ChatInterfaceState(inputState: old).withUpdatedSynchronizeableInputState(sync(updated))
        XCTAssertTrue(restored.inputState.hasExcludedAnalytics)
        XCTAssertEqual(restored.inputState.messageTextEntities(), updated.messageTextEntities())
    }
    func testNilOrEmptySynchronizationClearsActiveMarker() {
        let input = ChatTextInputState(attributedText: chatInputTextExcludingAnalytics(NSAttributedString(string: "private")), selectionRange: 0..<0)
        let state = ChatInterfaceState(inputState: input)
        for restored in [state.withUpdatedSynchronizeableInputState(nil), state.withUpdatedSynchronizeableInputState(sync(ChatTextInputState()))] {
            XCTAssertFalse(restored.inputState.hasExcludedAnalytics); XCTAssertEqual(restored.inputState.inputText, "")
        }
    }
    func testRepeatedSynchronizationNeverDropsExclusion() {
        let input = ChatTextInputState(inputText: "imported")
        var state = ChatInterfaceState(inputState: ChatTextInputState())
        for _ in 0..<3 { state = state.withUpdatedSynchronizeableInputState(sync(input)) }
        XCTAssertTrue(state.inputState.hasExcludedAnalytics)
    }
}

func postboxLog(_ text: String) {}
final class InputAnalyticsPostboxTests: XCTestCase {
    func testRealEngineCodecRoundTripsMarkedAndOrdinaryInput() throws {
        let inputs = [ChatTextInputState(inputText: ""), ChatTextInputState(inputText: "ordinary"), ChatTextInputState(inputText: "A😀B", selectionRange: 3..<3, attributes: [.bold(0..<1), .analyticsExcluded(1..<3)])]
        for input in inputs {
            let data = try EngineEncoder.encode(input)
            let restored = try EngineDecoder.decode(ChatTextInputState.self, from: data)
            XCTAssertEqual(restored, input)
            XCTAssertEqual(restored.hasExcludedAnalytics, input.hasExcludedAnalytics)
            XCTAssertEqual(restored.messageTextEntities(), input.messageTextEntities())
        }
    }
    func testLegacyEngineArchiveWithoutMetadataFailsClosed() throws {
        let encoder = PostboxEncoder()
        encoder.encodeString("legacy", forKey: "t")
        encoder.encodeInt32(0, forKey: "s0"); encoder.encodeInt32(0, forKey: "s1")
        encoder.encodeInt32Array([], forKey: "t.a")
        let restored = try EngineDecoder.decode(ChatTextInputState.self, from: encoder.makeData())
        XCTAssertTrue(restored.hasExcludedAnalytics); XCTAssertEqual(restored.inputText, "legacy")
    }
}

func mdb_cmp_memn(_ lhs: UnsafeRawPointer, _ lhsCount: Int, _ rhs: UnsafeRawPointer, _ rhsCount: Int) -> Int32 {
    let result = memcmp(lhs, rhs, min(lhsCount, rhsCount))
    if result != 0 { return result }
    return lhsCount == rhsCount ? 0 : lhsCount < rhsCount ? -1 : 1
}


final class InputAnalyticsFormattingTests: XCTestCase {
    func state(_ text: String = "A😀BC", marked: Range<Int>? = 1..<3, selection: Range<Int> = 0..<5) -> Updated_ChatTextInputState {
        let value = NSMutableAttributedString(string: text)
        value.addAttribute(TextInputAttributes.bold, value: true, range: NSRange(location: 0, length: value.length))
        if let marked { value.addAttribute(chatInputAnalyticsExcludedAttribute, value: true, range: NSRange(location: marked.lowerBound, length: marked.count)) }
        return Updated_ChatTextInputState(inputText: value, selectionRange: selection)
    }
    func excludedRanges(_ state: Updated_ChatTextInputState) -> [Range<Int>] {
        chatTextAttributes(from: state.inputText).compactMap {
            if case let .analyticsExcluded(range) = $0 { return range }
            return nil
        }
    }
    func testClearFormattingPreservesOnlyProvenanceAndEmoji() {
        let input = state()
        let text = NSMutableAttributedString(attributedString: input.inputText)
        text.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(collectionId: nil, fileId: 7, file: nil, emoji: "😀"), range: NSRange(location: 1, length: 2))
        let cleared = chatTextInputClearFormattingAttributes(Updated_ChatTextInputState(inputText: text, selectionRange: input.selectionRange))
        XCTAssertEqual(excludedRanges(cleared), [1..<3])
        XCTAssertEqual(cleared.inputText.string, text.string)
        XCTAssertEqual(cleared.selectionRange, input.selectionRange)
        XCTAssertNil(cleared.inputText.attribute(TextInputAttributes.bold, at: 1, effectiveRange: nil))
        XCTAssertNotNil(cleared.inputText.attribute(TextInputAttributes.customEmoji, at: 1, effectiveRange: nil))
    }
    func testPartialAndTargetedClearCannotRemoveProvenance() {
        for key: NSAttributedString.Key? in [nil, TextInputAttributes.bold, chatInputAnalyticsExcludedAttribute] {
            let cleared = chatTextInputClearFormattingAttributes(state(selection: 1..<3), targetKey: key)
            XCTAssertEqual(excludedRanges(cleared), [1..<3])
        }
        XCTAssertEqual(excludedRanges(chatTextInputClearFormattingAttributes(state(selection: 3..<3))), [1..<3])
    }
    func testLinkReplacementRetainsSelectedOriginAcrossUTF16LengthChanges() {
        for replacement in ["x", "longer😀label", "😀"] {
            let linked = chatTextInputAddLinkAttribute(state(), selectionRange: 1..<3, url: "https://example.invalid", text: replacement)
            XCTAssertEqual(linked.inputText.string, "A" + replacement + "BC")
            XCTAssertEqual(excludedRanges(linked), [1..<(1 + replacement.utf16.count)])
            XCTAssertEqual(linked.selectionRange, 1..<(1 + replacement.utf16.count))
            XCTAssertEqual((linked.inputText.attribute(TextInputAttributes.textUrl, at: 1, effectiveRange: nil) as? TextInputTextUrlAttribute)?.url, "https://example.invalid")
        }
    }
    func testLinkReplacementOfMixedSelectionMarksWholeResult() {
        let linked = chatTextInputAddLinkAttribute(state(), selectionRange: 0..<4, url: "https://example.invalid", text: "new")
        XCTAssertEqual(linked.inputText.string, "newC")
        XCTAssertEqual(excludedRanges(linked), [0..<3])
    }
    func testUnrelatedMarkedSuffixSurvivesLinkLengthChange() {
        let linked = chatTextInputAddLinkAttribute(state("abcXYZ", marked: 3..<6, selection: 0..<3), selectionRange: 0..<3, url: "https://example.invalid", text: "q")
        XCTAssertEqual(linked.inputText.string, "qXYZ")
        XCTAssertEqual(excludedRanges(linked), [1..<4])
        XCTAssertNil(linked.inputText.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil))
    }
    func testEmptyReplacementRemovesSelectedProvenanceWithoutPersistingAFlag() {
        let linked = chatTextInputAddLinkAttribute(state(), selectionRange: 1..<3, url: "https://example.invalid", text: "")
        XCTAssertEqual(linked.inputText.string, "ABC")
        XCTAssertTrue(excludedRanges(linked).isEmpty)
    }
    func testOrdinaryFormattingDoesNotInventExcludedOrigin() {
        let input = state(marked: nil)
        let cleared = chatTextInputClearFormattingAttributes(input)
        let linked = chatTextInputAddLinkAttribute(input, selectionRange: 1..<3, url: "https://example.invalid", text: "ordinary")
        XCTAssertTrue(excludedRanges(cleared).isEmpty)
        XCTAssertTrue(excludedRanges(linked).isEmpty)
    }
    func testStyleQuoteAndDateTransformsKeepOriginThroughCodec() throws {
        let input = state()
        let results = [chatTextInputAddFormattingAttribute(input, attribute: TextInputAttributes.bold), chatTextInputAddFormattingAttribute(input, attribute: TextInputAttributes.italic), chatTextInputAddFormattingAttribute(input, attribute: TextInputAttributes.quote), chatTextInputAddQuoteAttribute(input, selectionRange: 1..<3, collapsed: true), chatTextInputAddDateAttribute(input, selectionRange: 1..<3, date: 42)]
        for result in results {
            let model = ChatTextInputState(attributedText: result.inputText, selectionRange: result.selectionRange)
            let restored = try EngineDecoder.decode(ChatTextInputState.self, from: EngineEncoder.encode(model))
            XCTAssertTrue(restored.hasExcludedAnalytics)
            XCTAssertEqual(restored.inputText, model.inputText)
            XCTAssertEqual(restored.selectionRange, model.selectionRange)
            XCTAssertEqual(restored.attributes, model.attributes.sorted(by: <))
            XCTAssertEqual(excludedRanges(result), [1..<3])
        }
    }
}

final class FormattingInteractions {
    var presentation: Updated_ChatTextInputState
    var allowedLinkHosts: [String] = ["example.invalid"]
    init(_ presentation: Updated_ChatTextInputState) { self.presentation = presentation }
    func update(_ transform: (Updated_ChatTextInputState) -> Updated_ChatTextInputState) { presentation = transform(presentation) }
}
__POLICY__
__CONTEXT__
extension AnalyticsPrivacy {
    init(peerId: PeerId) { self = peerId.id < 0 ? .excluded : peerId.id == 0 ? .unresolved : .ordinary }
}
final class FormattingAccount {}
final class FormattingEngine { let account = FormattingAccount() }
final class FormattingAccountContext {
    var isPremium = true
    let engine = FormattingEngine()
    let peerId = PeerId(1)
}
final class Analytics {
    static var shared = Analytics()
    let policy = AnalyticsCollectionPolicy()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(analytics: self, privacy: .unresolved, scope: nil) }
    func captureContext(engine: FormattingEngine, peerId: PeerId, inherited: AnalyticsContext? = nil) -> AnalyticsContext {
        captureContext(owner: engine.account, privacy: AnalyticsPrivacy(peerId: peerId), inherited: inherited)
    }
__CAPTURE__
}
enum Translate { static func detectLanguage(for text: String) -> String? { "en" } }
struct InputTextViewHooks {
__INPUT_HOOKS__
    static var shared = InputTextViewHooks()
    var showPremiumBoarding: (FormattingAccountContext, Int) -> Void = { _, _ in }
    var showTranslate: (FormattingAccountContext, Int, String?, String, @escaping (NSAttributedString) -> Void) -> Void = { _, _, _, _, _ in }
    var showDateSelector: (FormattingAccountContext, Int, Date, @escaping (Date) -> Void) -> Void = { _, _, _, _ in }
    var showURLFormatter: (Int, String, String?, [String], @escaping (String, String?) -> Void) -> Void = { _, _, _, _, _ in }
}
final class FormattingInputView {
    var _window: Int? = 1
    var context: FormattingAccountContext? = FormattingAccountContext()
    let interactions: FormattingInteractions
    var isSecretChat = false
    var analyticsContextProvider: (() -> AnalyticsContext)?
    init(_ state: Updated_ChatTextInputState) {
        interactions = FormattingInteractions(state)
        let context = self.context!
        Analytics.shared = Analytics()
        Analytics.shared.policy.setOwner(context.engine.account)
        Analytics.shared.policy.isEnabled = true
        analyticsContextProvider = { Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId) }
    }
__INPUT_CAPTURE__
    func applyLinkFormat() {
__LINK_CALLBACK__
    }
__TRANSLATE_CALLBACK__
__DATE_EDIT_CALLBACK__
    func applyDateFormat() {
__DATE_CALLBACK__
    }
}
final class InputAnalyticsLinkCallbackTests: XCTestCase {
    override func tearDown() { InputTextViewHooks.shared = InputTextViewHooks(); super.tearDown() }
    func input(marked: Bool) -> Updated_ChatTextInputState {
        let text = NSAttributedString(string: "hello")
        return Updated_ChatTextInputState(inputText: marked ? chatInputTextExcludingAnalytics(text) : text, selectionRange: 0..<5)
    }
    func testDelayedLinkCommitRetainsOriginalExclusionAfterDraftReplacement() {
        let view = FormattingInputView(input(marked: true))
        var completion: ((String, String?) -> Void)?
        InputTextViewHooks.shared.showURLFormatter = { window, text, _, hosts, callback in
            XCTAssertEqual(window, 1); XCTAssertEqual(text, "hello"); XCTAssertEqual(hosts, ["example.invalid"])
            completion = callback
        }
        view.applyLinkFormat()
        view.interactions.presentation = input(marked: false)
        completion?("changed😀", "https://example.invalid")
        let current = view.interactions.presentation
        XCTAssertEqual(current.inputText.string, "changed😀")
        XCTAssertTrue(ChatTextInputState(attributedText: current.inputText, selectionRange: current.selectionRange).hasExcludedAnalytics)
    }
    func testOrdinaryDialogCommitPreservesOrdinaryEligibility() {
        let view = FormattingInputView(input(marked: false))
        var completion: ((String, String?) -> Void)?
        InputTextViewHooks.shared.showURLFormatter = { _, _, _, _, callback in completion = callback }
        view.applyLinkFormat(); completion?("updated", "https://example.invalid")
        let current = view.interactions.presentation
        XCTAssertEqual(current.inputText.string, "updated")
        XCTAssertFalse(ChatTextInputState(attributedText: current.inputText, selectionRange: current.selectionRange).hasExcludedAnalytics)
    }
    func testStaleDialogRangeDoesNotCrashOrOverwriteShorterDraft() {
        let view = FormattingInputView(input(marked: true))
        var completion: ((String, String?) -> Void)?
        InputTextViewHooks.shared.showURLFormatter = { _, _, _, _, callback in completion = callback }
        view.applyLinkFormat()
        view.interactions.presentation = Updated_ChatTextInputState(inputText: NSAttributedString(string: "x"), selectionRange: 1..<1)
        completion?("old text", "https://example.invalid")
        XCTAssertEqual(view.interactions.presentation.inputText.string, "x")
        XCTAssertEqual(view.interactions.presentation.selectionRange, 1..<1)
    }
    func testRemovingLinkKeepsCurrentPrivateOrigin() {
        let view = FormattingInputView(input(marked: true))
        var completion: ((String, String?) -> Void)?
        InputTextViewHooks.shared.showURLFormatter = { _, _, _, _, callback in completion = callback }
        view.applyLinkFormat(); completion?("hello", nil)
        let current = view.interactions.presentation
        XCTAssertTrue(ChatTextInputState(attributedText: current.inputText, selectionRange: current.selectionRange).hasExcludedAnalytics)
    }
    func testDismissalAndReleasedOwnerLeaveDraftUntouched() {
        var view: FormattingInputView? = FormattingInputView(input(marked: true))
        let interactions = view!.interactions
        weak var weakView = view
        var completion: ((String, String?) -> Void)?
        InputTextViewHooks.shared.showURLFormatter = { _, _, _, _, callback in completion = callback }
        view!.applyLinkFormat()
        XCTAssertEqual(interactions.presentation.inputText.string, "hello")
        view = nil
        XCTAssertNil(weakView)
        completion?("new text", "https://example.invalid")
        XCTAssertEqual(interactions.presentation.inputText.string, "hello")
    }
}

final class InputAnalyticsTranslationTests: XCTestCase {
    override func tearDown() { InputTextViewHooks.shared = InputTextViewHooks(); super.tearDown() }
    func input(marked: Bool, text: String = "hello") -> Updated_ChatTextInputState {
        let value = NSAttributedString(string: text)
        return Updated_ChatTextInputState(inputText: marked ? chatInputTextExcludingAnalytics(value) : value, selectionRange: 0..<value.length)
    }
    func testTranslationRetainsInitialAndCurrentExclusionWithFormatting() throws {
        for origins in [(true, false), (false, true), (true, true), (false, false)] {
            let view = FormattingInputView(input(marked: origins.0))
            var completion: ((NSAttributedString) -> Void)?
            InputTextViewHooks.shared.showTranslate = { _, window, from, text, callback in
                XCTAssertEqual(window, 1); XCTAssertEqual(from, "en"); XCTAssertEqual(text, "hello")
                completion = callback
            }
            view.inputTextTranslateSelected()
            view.interactions.presentation = input(marked: origins.1)
            let translated = NSAttributedString(string: "Hola😀", attributes: [TextInputAttributes.bold: true])
            completion?(translated)
            let current = view.interactions.presentation
            let model = ChatTextInputState(attributedText: current.inputText, selectionRange: current.selectionRange)
            XCTAssertEqual(current.inputText.string, "Hola😀")
            XCTAssertEqual(current.selectionRange, 6..<6)
            XCTAssertNotNil(current.inputText.attribute(TextInputAttributes.bold, at: 0, effectiveRange: nil))
            XCTAssertEqual(model.hasExcludedAnalytics, origins.0 || origins.1)
            let restored = try EngineDecoder.decode(ChatTextInputState.self, from: EngineEncoder.encode(model))
            XCTAssertEqual(restored.hasExcludedAnalytics, model.hasExcludedAnalytics)
            XCTAssertEqual(restored.messageTextEntities(), model.messageTextEntities())
        }
    }
    func testMixedSelectionMarksEntireTranslationAndPreservesOutsideText() {
        let value = NSMutableAttributedString(string: "AhelloZ")
        value.addAttribute(chatInputAnalyticsExcludedAttribute, value: true, range: NSRange(location: 3, length: 1))
        let view = FormattingInputView(Updated_ChatTextInputState(inputText: value, selectionRange: 1..<6))
        var completion: ((NSAttributedString) -> Void)?
        InputTextViewHooks.shared.showTranslate = { _, _, _, text, callback in XCTAssertEqual(text, "hello"); completion = callback }
        view.inputTextTranslateSelected(); completion?(NSAttributedString(string: "😀"))
        let current = view.interactions.presentation
        XCTAssertEqual(current.inputText.string, "A😀Z"); XCTAssertEqual(current.selectionRange, 3..<3)
        XCTAssertNil(current.inputText.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil))
        XCTAssertNotNil(current.inputText.attribute(chatInputAnalyticsExcludedAttribute, at: 1, effectiveRange: nil))
        XCTAssertNotNil(current.inputText.attribute(chatInputAnalyticsExcludedAttribute, at: 2, effectiveRange: nil))
        XCTAssertNil(current.inputText.attribute(chatInputAnalyticsExcludedAttribute, at: 3, effectiveRange: nil))
    }
    func testTranslationKeepsExistingMarkerInReturnedText() {
        let state = input(marked: false)
        let result = chatTextInputReplaceSelectedText(state, selectionRange: state.selectionRange, text: chatInputTextExcludingAnalytics(NSAttributedString(string: "returned")))
        XCTAssertTrue(ChatTextInputState(attributedText: result.inputText, selectionRange: result.selectionRange).hasExcludedAnalytics)
    }
    func testEmptyTranslationDeletesActiveMarkerAndStaleRangeLeavesNewInput() {
        let view = FormattingInputView(input(marked: true))
        var completion: ((NSAttributedString) -> Void)?
        InputTextViewHooks.shared.showTranslate = { _, _, _, _, callback in completion = callback }
        view.inputTextTranslateSelected(); completion?(NSAttributedString(string: ""))
        XCTAssertEqual(view.interactions.presentation.inputText.string, "")
        XCTAssertEqual(view.interactions.presentation.selectionRange, 0..<0)
        view.interactions.presentation = input(marked: false, text: "new")
        completion?(NSAttributedString(string: "old translated content"))
        XCTAssertEqual(view.interactions.presentation.inputText.string, "new")
        XCTAssertEqual(view.interactions.presentation.selectionRange, 0..<3)
    }
    func testPremiumEmptySelectionAndMissingHostKeepExistingBehavior() {
        var translations = 0
        var premium = 0
        InputTextViewHooks.shared.showTranslate = { _, _, _, _, _ in translations += 1 }
        InputTextViewHooks.shared.showPremiumBoarding = { _, _ in premium += 1 }
        let view = FormattingInputView(input(marked: true))
        view.context?.isPremium = false; view.inputTextTranslateSelected()
        XCTAssertEqual(premium, 1); XCTAssertEqual(translations, 0)
        view.context?.isPremium = true
        view.interactions.presentation = Updated_ChatTextInputState(inputText: NSAttributedString(string: "text"), selectionRange: 2..<2)
        view.inputTextTranslateSelected(); XCTAssertEqual(translations, 0)
        view.interactions.presentation = input(marked: true)
        view._window = nil; view.inputTextTranslateSelected(); XCTAssertEqual(translations, 0)
        view._window = 1; view.context = nil; view.inputTextTranslateSelected(); XCTAssertEqual(translations, 0)
    }
    func testCancelledAndReleasedTranslationOwnerDoesNotMutateDraft() {
        var view: FormattingInputView? = FormattingInputView(input(marked: true))
        let interactions = view!.interactions
        weak var owner = view
        var completion: ((NSAttributedString) -> Void)?
        InputTextViewHooks.shared.showTranslate = { _, _, _, _, callback in completion = callback }
        view!.inputTextTranslateSelected()
        XCTAssertEqual(interactions.presentation.inputText.string, "hello")
        view = nil; XCTAssertNil(owner)
        completion?(NSAttributedString(string: "returned"))
        XCTAssertEqual(interactions.presentation.inputText.string, "hello")
    }
    func testDateDialogsPreserveMarkersAndRejectStaleRanges() {
        for editingExistingDate in [true, false] {
            let view = FormattingInputView(input(marked: true))
            var completion: ((Date) -> Void)?
            InputTextViewHooks.shared.showDateSelector = { _, window, _, callback in XCTAssertEqual(window, 1); completion = callback }
            if editingExistingDate { view.inputApplyDateEdit(range: NSRange(location: 0, length: 5), currentDate: 10) }
            else { view.applyDateFormat() }
            completion?(Date(timeIntervalSince1970: 42))
            let result = view.interactions.presentation
            XCTAssertTrue(ChatTextInputState(attributedText: result.inputText, selectionRange: result.selectionRange).hasExcludedAnalytics)
            XCTAssertEqual((result.inputText.attribute(TextInputAttributes.formattedDate, at: 0, effectiveRange: nil) as? TextInputTextDateAttribute)?.date, 42)
            view.interactions.presentation = input(marked: false, text: "x")
            completion?(Date(timeIntervalSince1970: 99))
            XCTAssertEqual(view.interactions.presentation.inputText.string, "x")
            XCTAssertNil(view.interactions.presentation.inputText.attribute(TextInputAttributes.formattedDate, at: 0, effectiveRange: nil))
        }
    }
}

final class InputAnalyticsEntryTests: XCTestCase {
    override func tearDown() { InputTextViewHooks.shared = InputTextViewHooks(); super.tearDown() }
    func view() -> FormattingInputView {
        FormattingInputView(Updated_ChatTextInputState(inputText: NSAttributedString(string: "hello"), selectionRange: 0..<5))
    }
    func excluded(_ view: FormattingInputView) -> Bool {
        ChatTextInputState(attributedText: view.interactions.presentation.inputText, selectionRange: view.interactions.presentation.selectionRange).hasExcludedAnalytics
    }
    func testOrdinaryEntryHandsExactComposerScopeToTranslation() {
        let view = view(); let context = view.context!
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId)
        view.analyticsContextProvider = { origin }
        var completion: ((NSAttributedString) -> Void)?
        InputTextViewHooks.shared.showTranslateWithContext = { _, _, language, text, received, callback in
            XCTAssertTrue(received.scope === origin.scope)
            XCTAssertFalse(Analytics.shared.policy.hasExclusions)
            XCTAssertEqual(language, "en"); XCTAssertEqual(text, "hello")
            completion = callback
        }
        view.inputTextTranslateSelected(); completion?(NSAttributedString(string: "translated"))
        XCTAssertEqual(view.interactions.presentation.inputText.string, "translated"); XCTAssertFalse(excluded(view))
    }
    func testUnknownSecretAndUnselectedMarkedInputFailClosedBeforeProvider() {
        for kind in 0..<4 {
            let view = view()
            if kind == 0 { view.analyticsContextProvider = nil }
            if kind == 1 { view.isSecretChat = true }
            if kind == 2 {
                let context = view.context!
                view.analyticsContextProvider = { Analytics.shared.captureContext(engine: context.engine, peerId: PeerId(-7)) }
            }
            if kind == 3 {
                let input = NSMutableAttributedString(string: "helloX")
                input.addAttribute(chatInputAnalyticsExcludedAttribute, value: true, range: NSRange(location: 5, length: 1))
                view.interactions.presentation = Updated_ChatTextInputState(inputText: input, selectionRange: 0..<5)
            }
            var calls = 0
            InputTextViewHooks.shared.showTranslateWithContext = { _, _, _, _, origin, callback in
                calls += 1; XCTAssertTrue(origin.isExcluded)
                XCTAssertTrue(Analytics.shared.policy.hasExclusions)
                callback(NSAttributedString(string: "returned"))
            }
            view.inputTextTranslateSelected()
            XCTAssertEqual(calls, 1); XCTAssertTrue(excluded(view)); XCTAssertFalse(Analytics.shared.policy.hasExclusions)
        }
    }
    func testCurrentComposerRestrictionAndAccountChangesExcludeDelayedReturn() {
        for kind in 0..<3 {
            let view = view()
            var completion: ((NSAttributedString) -> Void)?
            InputTextViewHooks.shared.showTranslateWithContext = { _, _, _, _, _, callback in completion = callback }
            view.inputTextTranslateSelected()
            if kind == 0 { view.isSecretChat = true }
            if kind == 1 { view.analyticsContextProvider = nil }
            if kind == 2 { Analytics.shared.policy.setOwner(FormattingAccount()) }
            completion?(NSAttributedString(string: "returned"))
            XCTAssertEqual(view.interactions.presentation.inputText.string, "returned"); XCTAssertTrue(excluded(view))
            XCTAssertFalse(Analytics.shared.policy.hasExclusions)
        }
    }
    func testNewProviderGrantCannotRecoverRevokedOrigin() {
        let view = view(); let context = view.context!
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId)
        view.analyticsContextProvider = { origin }
        var completion: ((NSAttributedString) -> Void)?
        InputTextViewHooks.shared.showTranslateWithContext = { _, _, _, _, _, callback in completion = callback }
        view.inputTextTranslateSelected(); origin.scope!.exclude()
        let fresh = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId)
        view.analyticsContextProvider = { fresh }
        completion?(NSAttributedString(string: "returned"))
        XCTAssertTrue(excluded(view)); XCTAssertFalse(Analytics.shared.policy.hasExclusions)
    }
    func testPremiumEntryCarriesContextAndLegacyFallbackKeepsGuard() {
        for observed in [true, false] {
            let view = view(); view.isSecretChat = true; view.context?.isPremium = false
            var called = false
            if observed {
                InputTextViewHooks.shared.showPremiumBoardingWithContext = { _, _, origin in
                    called = true; XCTAssertTrue(origin.isExcluded); XCTAssertTrue(Analytics.shared.policy.hasExclusions)
                }
            } else {
                InputTextViewHooks.shared.showPremiumBoardingWithContext = nil
                InputTextViewHooks.shared.showPremiumBoarding = { _, _ in called = true; XCTAssertTrue(Analytics.shared.policy.hasExclusions) }
            }
            view.inputTextTranslateSelected(); XCTAssertTrue(called)
            XCTAssertFalse(Analytics.shared.policy.hasExclusions)
        }
    }
    func testLegacyDelayedTranslationAndDisabledCollectionStayFunctionalAndExcluded() {
        let view = view(); Analytics.shared.policy.isEnabled = false
        var completion: ((NSAttributedString) -> Void)?
        InputTextViewHooks.shared.showTranslateWithContext = nil
        InputTextViewHooks.shared.showTranslate = { _, _, _, _, callback in
            XCTAssertTrue(Analytics.shared.policy.hasExclusions); completion = callback
        }
        view.inputTextTranslateSelected(); completion?(NSAttributedString(string: "returned"))
        XCTAssertEqual(view.interactions.presentation.inputText.string, "returned"); XCTAssertTrue(excluded(view))
        XCTAssertFalse(Analytics.shared.policy.hasExclusions)
    }
}
