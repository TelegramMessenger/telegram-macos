import XCTest
@testable import ChatUI

final class ChatInputDictationTextTests: XCTestCase {
    func testInsertionDoesNotAddASpaceBeforeRecognizedPunctuation() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "Hello", transcript: ", friend", suffix: ""), ", friend")
    }

    func testInsertionAnchorPreservesSurroundingFormatting() {
        let key = NSAttributedString.Key("format")
        let original = NSAttributedString(string: "Hello world", attributes: [key: true])
        let insertion = ChatInputDictationInsertion(text: original, selection: 5 ..< 5, consumedTranscript: "Hello world")
        let result = insertion.compose("Hello world again")
        XCTAssertEqual(result.text.string, "Hello again world")
        XCTAssertEqual(result.text.attribute(key, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(result.text.attribute(key, at: result.text.length - 1, effectiveRange: nil) as? Bool, true)
    }

    func testInsertionAnchorDoesNotInheritExcludedEmojiAttributes() {
        let key = NSAttributedString.Key("emoji")
        let original = NSAttributedString(string: "🙂", attributes: [key: true])
        let insertion = ChatInputDictationInsertion(text: original, selection: 2 ..< 2, excludingAttribute: { name, _ in name == key })
        let result = insertion.compose("hello")
        XCTAssertEqual(result.text.string, "🙂 hello")
        XCTAssertNil(result.text.attribute(key, at: 3, effectiveRange: nil))
    }

    func testEditedTranscriptPreservesDraftAndTranscriptAttributesAndUTF16Selection() {
        let draftKey = NSAttributedString.Key("draft")
        let transcriptKey = NSAttributedString.Key("transcript")
        let draft = NSAttributedString(string: "Draft🙂", attributes: [draftKey: true])
        let transcript = NSAttributedString(string: "hello🙂", attributes: [transcriptKey: true])
        let result = ChatInputDictationText.appending(transcript, selection: 5 ..< 7, to: draft)
        XCTAssertEqual(result.text.string, "Draft🙂 hello🙂")
        XCTAssertEqual(result.selection, 13 ..< 15)
        XCTAssertEqual(result.text.attribute(draftKey, at: 5, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(result.text.attribute(transcriptKey, at: 13, effectiveRange: nil) as? Bool, true)
        XCTAssertNil(result.text.attribute(draftKey, at: 8, effectiveRange: nil))
    }

    func testEditedTranscriptUsesExistingSpacingAndPunctuation() {
        for (draft, transcript, expected) in [("Hello ", "world", "Hello world"), ("Hello", "?", "Hello?"), ("(", "hello", "(hello"), ("", "hello", "hello")] {
            let result = ChatInputDictationText.appending(NSAttributedString(string: transcript), selection: 0 ..< 0, to: NSAttributedString(string: draft))
            XCTAssertEqual(result.text.string, expected)
            XCTAssertEqual(result.selection.lowerBound, (expected as NSString).length - (transcript as NSString).length)
        }
    }

    func testDeletingTheTranscriptKeepsTheOriginalDraft() {
        let draft = NSAttributedString(string: "Keep this", attributes: [NSAttributedString.Key("draft"): true])
        let result = ChatInputDictationText.appending(NSAttributedString(string: ""), selection: 0 ..< 0, to: draft)
        XCTAssertEqual(result.text, draft)
        XCTAssertEqual(result.selection, 9 ..< 9)
    }

    func testEditedTranscriptClampsSelectionToUTF16Bounds() {
        let draft = NSAttributedString(string: "Hi")
        let transcript = NSAttributedString(string: "🙂")
        let pastEnd = ChatInputDictationText.appending(transcript, selection: 10 ..< 12, to: draft)
        XCTAssertEqual(pastEnd.selection, 5 ..< 5)
        let beforeStart = ChatInputDictationText.appending(transcript, selection: -5 ..< -1, to: draft)
        XCTAssertEqual(beforeStart.selection, 3 ..< 3)
    }
    func testInsertionIntoEmptyInput() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "", transcript: "Hello world", suffix: ""), "Hello world")
    }

    func testInsertionTrimsTranscript() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "", transcript: "  Hello \n", suffix: ""), "Hello")
    }

    func testEmptyTranscriptInsertsNothing() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "Hi", transcript: "   ", suffix: " there"), "")
    }

    func testInsertionAddsLeadingSpaceAfterWord() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "Hi", transcript: "there", suffix: ""), " there")
    }

    func testInsertionKeepsExistingWhitespace() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "Hi ", transcript: "there", suffix: ""), "there")
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "Hi\n", transcript: "there", suffix: ""), "there")
    }

    func testInsertionAfterOpeningBracket() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "note (", transcript: "later", suffix: ")"), "later")
    }

    func testInsertionAddsTrailingSpaceBeforeWord() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "", transcript: "Hello", suffix: "world"), "Hello ")
    }

    func testInsertionNoTrailingSpaceBeforePunctuation() {
        XCTAssertEqual(ChatInputDictationText.insertion(prefix: "Say", transcript: "hello", suffix: ", friend"), " hello")
    }

    func testJoin() {
        XCTAssertEqual(ChatInputDictationText.join("", "Hello"), "Hello")
        XCTAssertEqual(ChatInputDictationText.join("Hello.", "How are you"), "Hello. How are you")
        XCTAssertEqual(ChatInputDictationText.join("Hello. ", "How"), "Hello. How")
        XCTAssertEqual(ChatInputDictationText.join("Hello", "?"), "Hello?")
        XCTAssertEqual(ChatInputDictationText.join("Hello", ""), "Hello")
    }

    func testDraftReplacesPartialAtCursor() {
        let draft = ChatInputDictationDraft(text: NSAttributedString(string: "Hello world"), selection: 5 ..< 5)
        let first = draft.compose("big")
        XCTAssertEqual(first.text.string, "Hello big world")
        XCTAssertEqual(first.cursor, 9)
        let second = draft.compose("big blue")
        XCTAssertEqual(second.text.string, "Hello big blue world")
        XCTAssertEqual(second.cursor, 14)
    }

    func testDraftReplacesSelection() {
        let draft = ChatInputDictationDraft(text: NSAttributedString(string: "Hello there friend"), selection: 6 ..< 11)
        let result = draft.compose("my")
        XCTAssertEqual(result.text.string, "Hello my friend")
        XCTAssertEqual(result.cursor, 8)
    }

    func testDraftEmptyTranscriptRestoresText() {
        let draft = ChatInputDictationDraft(text: NSAttributedString(string: "Hello"), selection: 5 ..< 5)
        let result = draft.compose("")
        XCTAssertEqual(result.text.string, "Hello")
        XCTAssertEqual(result.cursor, 5)
    }

    func testDraftClampsOutOfRangeSelection() {
        let draft = ChatInputDictationDraft(text: NSAttributedString(string: "Hi"), selection: 10 ..< 12)
        let result = draft.compose("there")
        XCTAssertEqual(result.text.string, "Hi there")
        XCTAssertEqual(result.cursor, 8)
    }

    func testDraftInheritsAttributesBeforeCursor() {
        let key = NSAttributedString.Key("test.bold")
        let skipped = NSAttributedString.Key("test.emoji")
        let text = NSMutableAttributedString(string: "Hello")
        text.addAttributes([key: true, skipped: true], range: NSMakeRange(0, 5))
        let draft = ChatInputDictationDraft(text: text, selection: 5 ..< 5, excludingAttribute: { name, _ in name == skipped })
        let result = draft.compose("there")
        XCTAssertNotNil(result.text.attribute(key, at: 7, effectiveRange: nil))
        XCTAssertNil(result.text.attribute(skipped, at: 7, effectiveRange: nil))
    }

    func testLanguageGroupSplitsChineseScriptsAndMergesRegions() {
        XCTAssertEqual(ChatInputDictationText.languageGroup(of: "zh-CN"), "zh-hans")
        XCTAssertEqual(ChatInputDictationText.languageGroup(of: "zh_TW"), "zh-hant")
        XCTAssertEqual(ChatInputDictationText.languageGroup(of: "zh-HK"), "yue")
        XCTAssertEqual(ChatInputDictationText.languageGroup(of: "yue-CN"), "yue")
        XCTAssertEqual(ChatInputDictationText.languageGroup(of: "en-US"), ChatInputDictationText.languageGroup(of: "en_GB"))
        XCTAssertEqual(ChatInputDictationText.languageGroup(of: "hi-IN-translit"), "hi")
    }

    func testResolveLocaleExactMatch() {
        XCTAssertEqual(ChatInputDictationText.resolveLocale(preferred: ["en-US"], supported: ["en_GB", "en_US"]), "en_US")
    }

    func testResolveLocaleRegionFromLanguage() {
        XCTAssertEqual(ChatInputDictationText.resolveLocale(preferred: ["ru-US"], supported: ["en_US", "ru_RU"]), "ru_RU")
        XCTAssertEqual(ChatInputDictationText.resolveLocale(preferred: ["en-RU"], supported: ["en_AU", "en_GB", "en_US"]), "en_US")
        XCTAssertEqual(ChatInputDictationText.resolveLocale(preferred: ["de-CH"], supported: ["de_AT", "de_CH", "de_DE"]), "de_CH")
        XCTAssertEqual(ChatInputDictationText.resolveLocale(preferred: ["en-RU", "ru_RU"], supported: ["en_US", "ru_RU"]), "en_US")
        XCTAssertEqual(ChatInputDictationText.resolveLocale(preferred: ["ru_RU@rg=dezzzz"], supported: ["en_US", "ru_RU"]), "ru_RU")
    }

    func testResolveLocaleFallsBackToNextPreference() {
        XCTAssertEqual(ChatInputDictationText.resolveLocale(preferred: ["xx-YY", "fr_FR"], supported: ["fr-CA", "fr-FR"]), "fr-FR")
    }

    func testResolveLocaleUnsupported() {
        XCTAssertNil(ChatInputDictationText.resolveLocale(preferred: ["xx-YY"], supported: ["en_US"]))
        XCTAssertNil(ChatInputDictationText.resolveLocale(preferred: [], supported: ["en_US"]))
    }

    func testInsertedRangeCoversOnlyTheDictatedText() {
        let text = NSAttributedString(string: "Hello world")
        let middle = ChatInputDictationInsertion(text: text, selection: 5 ..< 5)
        let composed = middle.compose("dear")
        let range = middle.insertedRange("dear")
        XCTAssertEqual((composed.text.string as NSString).substring(with: range), " dear")
        let end = ChatInputDictationInsertion(text: text, selection: 11 ..< 11)
        XCTAssertEqual((end.compose("again").text.string as NSString).substring(with: end.insertedRange("again")), " again")
        XCTAssertEqual(end.insertedRange("  ").length, 0)
        let continued = ChatInputDictationInsertion(text: NSAttributedString(string: "Hello there"), selection: 11 ..< 11, consumedTranscript: "there")
        XCTAssertEqual(continued.insertedRange("there").length, 0)
    }

    func testTheFieldNeverShrinksWhileDictatingAndFreesItsHeightAfter() {
        var hold = ChatDictationHeightHold()
        XCTAssertEqual(hold.fit(18, transcribing: true), 18)
        XCTAssertEqual(hold.fit(36, transcribing: true), 36)
        XCTAssertEqual(hold.fit(18, transcribing: true), 36)
        XCTAssertEqual(hold.fit(54, transcribing: true), 54)
        XCTAssertEqual(hold.fit(18, transcribing: false), 18)
        XCTAssertEqual(hold.fit(36, transcribing: false), 36)
        hold.release()
        XCTAssertEqual(hold.floor, 0)
        XCTAssertEqual(hold.fit(18, transcribing: true), 18)
    }

    func testOnlyTheCharactersTheFixChangedAreMarked() {
        func marked(_ old: String, _ new: String) -> [String] {
            return ChatInputDictationText.changedCharacters(from: old, to: new).map { (new as NSString).substring(with: $0) }
        }
        XCTAssertEqual(marked("hello how are you", "Hello, how are you?"), ["H", ",", "?"])
        XCTAssertEqual(marked("same text", "same text"), [])
        XCTAssertEqual(marked("i think its fine", "I think it's fine."), ["I", "'", "."])
        XCTAssertEqual(marked("привет как дела", "Привет, как дела?"), ["П", ",", "?"])
        XCTAssertEqual(marked("ok 👍🏽", "OK 👍🏽!"), ["OK", "!"])
        XCTAssertEqual(marked("", "New"), ["New"])
        XCTAssertEqual(marked("abc", ""), [])
        let wide = ChatInputDictationText.changedCharacters(from: "a b c d", to: "A b c D", limit: 1)
        XCTAssertEqual(wide.map { ("A b c D" as NSString).substring(with: $0) }, ["A b c D"])
    }

    func testChangedCharactersUseUTF16Ranges() {
        let new = "👍🏽 Yes!"
        let ranges = ChatInputDictationText.changedCharacters(from: "👍🏽 yes", to: new)
        XCTAssertEqual(ranges.map { (new as NSString).substring(with: $0) }, ["Y", "!"])
        XCTAssertEqual(ranges.first?.location, ("👍🏽 " as NSString).length)
    }

    func testOnlySegmentsWithSeveralWordsAreOfferedForEnhancing() {
        XCTAssertNil(ChatInputDictationText.enhanceableText("  hello  "))
        XCTAssertNil(ChatInputDictationText.enhanceableText(""))
        XCTAssertEqual(ChatInputDictationText.enhanceableText(" hello there "), "hello there")
        XCTAssertNil(ChatInputDictationText.enhanceableText("a " + String(repeating: "b", count: 4096)))
    }

    func testEnhancedTextReplacesOnlyTheSegmentAndKeepsItsSpacingAndStyle() throws {
        let bold = NSAttributedString.Key("bold")
        let text = NSMutableAttributedString(string: "Hi. ")
        text.append(NSAttributedString(string: " how are you\n", attributes: [bold: true]))
        text.append(NSAttributedString(string: "Bye"))
        let range = NSRange(location: 4, length: 13)
        let result = try XCTUnwrap(ChatInputDictationText.replacingSegment(text, range: range, with: "  How are you? "))
        XCTAssertEqual(result.text.string, "Hi.  How are you?\nBye")
        XCTAssertEqual(result.range, NSRange(location: 4, length: 14))
        XCTAssertEqual((result.text.string as NSString).substring(with: result.range), " How are you?\n")
        XCTAssertEqual(result.text.attribute(bold, at: 6, effectiveRange: nil) as? Bool, true)
        XCTAssertNil(result.text.attribute(bold, at: 19, effectiveRange: nil))
        XCTAssertNil(ChatInputDictationText.replacingSegment(text, range: range, with: "how are you"))
        XCTAssertNil(ChatInputDictationText.replacingSegment(text, range: range, with: "   "))
        XCTAssertNil(ChatInputDictationText.replacingSegment(text, range: NSRange(location: 20, length: 5), with: "x y"))
    }

    func testTheCaretFollowsTheEnhancedSegment() {
        let range = NSRange(location: 4, length: 10)
        XCTAssertEqual(ChatInputDictationText.selection(14 ..< 14, afterReplacing: range, length: 12), 16 ..< 16)
        XCTAssertEqual(ChatInputDictationText.selection(20 ..< 22, afterReplacing: range, length: 12), 22 ..< 24)
        XCTAssertEqual(ChatInputDictationText.selection(1 ..< 3, afterReplacing: range, length: 12), 1 ..< 3)
        XCTAssertEqual(ChatInputDictationText.selection(6 ..< 8, afterReplacing: range, length: 12), 16 ..< 16)
    }

    func testSessionRangeSpansEveryPartDictatedSinceTheStart() {
        let first = ChatInputDictationInsertion(text: NSAttributedString(string: "Hi"), selection: 2 ..< 2)
        let afterFirst = first.compose("there").text
        let second = ChatInputDictationInsertion(text: afterFirst, selection: afterFirst.length ..< afterFirst.length)
        let final = second.compose("hola").text.string as NSString
        let range = ChatInputDictationText.sessionRange(second.insertedRange("hola"), from: first.start)
        XCTAssertEqual(final.substring(with: range), " there hola")
        XCTAssertEqual(final.substring(with: ChatInputDictationText.sessionRange(second.insertedRange(""), from: first.start)), " there")
        XCTAssertEqual(ChatInputDictationText.sessionRange(NSRange(location: 3, length: 4), from: nil), NSRange(location: 3, length: 4))
        XCTAssertEqual(ChatInputDictationText.sessionRange(NSRange(location: 3, length: 4), from: 5), NSRange(location: 3, length: 4))
    }

    func testFlagComesFromTheLocaleRegion() {
        XCTAssertEqual(ChatInputDictationText.flag(for: "en_GB"), "🇬🇧")
        XCTAssertEqual(ChatInputDictationText.flag(for: "ru-RU"), "🇷🇺")
        XCTAssertEqual(ChatInputDictationText.flag(for: "zh-Hant-TW"), "🇹🇼")
        XCTAssertEqual(ChatInputDictationText.flag(for: "zh_CN"), "🇨🇳")
        XCTAssertNil(ChatInputDictationText.flag(for: "en"))
        XCTAssertNil(ChatInputDictationText.flag(for: "es-419"))
    }

    func testResolveLanguageUsesTheSystemRegion() {
        let supported = ["en_AU", "en_GB", "en_US", "ru_RU", "zh_CN", "zh_TW", "nb_NO"]
        XCTAssertEqual(ChatInputDictationText.resolveLanguage(["en"], preferred: ["ru-RU", "en-GB"], supported: supported), "en_GB")
        XCTAssertEqual(ChatInputDictationText.resolveLanguage(["en"], preferred: ["ru-RU"], supported: supported), "en_US")
        XCTAssertEqual(ChatInputDictationText.resolveLanguage(["ru"], preferred: [], supported: supported), "ru_RU")
        XCTAssertEqual(ChatInputDictationText.resolveLanguage(["ru_RU"], preferred: ["en-GB"], supported: supported), "ru_RU")
    }

    func testResolveLanguageKeepsTheCodeRegion() {
        let supported = ["zh_CN", "zh_HK", "zh_TW"]
        XCTAssertEqual(ChatInputDictationText.resolveLanguage(["zh-CN", "zh"], preferred: ["zh-Hant-TW"], supported: supported), "zh_CN")
        XCTAssertEqual(ChatInputDictationText.resolveLanguage(["zh-TW"], preferred: ["zh-Hans-CN"], supported: supported), "zh_TW")
    }

    func testResolveLanguageAliasesAndUnsupported() {
        XCTAssertEqual(ChatInputDictationText.resolveLanguage(["no"], preferred: [], supported: ["nb_NO", "en_US"]), "nb_NO")
        XCTAssertEqual(ChatInputDictationText.resolveLanguage(["he", "iw"], preferred: [], supported: ["he_IL"]), "he_IL")
        XCTAssertNil(ChatInputDictationText.resolveLanguage(["eo"], preferred: ["en-GB"], supported: ["en_GB"]))
    }

    func testAutomaticLocalesUseDistinctPreferredLanguages() {
        let supported = ["en_US", "en_GB", "ru_RU", "de_DE"]
        XCTAssertEqual(ChatInputDictationText.automaticLocales(preferred: ["ru-RU", "en-RU", "en-GB", "ru"], supported: supported, limit: 4), ["ru_RU", "en_US"])
        XCTAssertEqual(ChatInputDictationText.automaticLocales(preferred: ["en-GB", "ru-RU", "de-DE"], supported: supported, limit: 2), ["en_GB", "ru_RU"])
        XCTAssertEqual(ChatInputDictationText.automaticLocales(preferred: ["xx"], supported: supported, limit: 2), [])
    }

    func testLanguageCode() {
        XCTAssertEqual(ChatInputDictationText.languageCode(of: "ru_RU"), "RU")
        XCTAssertEqual(ChatInputDictationText.languageCode(of: "en-US@rg=gbzzzz"), "EN")
        XCTAssertEqual(ChatInputDictationText.languageCode(of: "zh-Hant-TW"), "ZH")
    }

    func testStabilityPrefersAppendingTranscripts() {
        var stable = ChatInputDictationStability()
        stable.update(previous: "", current: "Hello")
        stable.update(previous: "Hello", current: "Hello how")
        stable.update(previous: "Hello how", current: "Hello how are")
        stable.update(previous: "Hello how are", current: "Hello how are you")
        var unstable = ChatInputDictationStability()
        unstable.update(previous: "Privet", current: "Pre vet cock")
        unstable.update(previous: "Pre vet cock", current: "Previous cake ago")
        unstable.update(previous: "Previous cake ago", current: "Pretty cat a go")
        XCTAssertEqual(stable.value, 1, accuracy: 0.0001)
        XCTAssertLessThan(unstable.value, 0.5)
        XCTAssertEqual(ChatInputDictationStability().value, 0.5, accuracy: 0.0001)
    }

    func testScoreUsesConfidenceAndPriority() {
        XCTAssertGreaterThan(ChatInputDictationText.score(stability: 0.9, confidence: 0.9, priority: 1), ChatInputDictationText.score(stability: 0.9, confidence: 0.3, priority: 0))
        XCTAssertGreaterThan(ChatInputDictationText.score(stability: 0.8, confidence: nil, priority: 0), ChatInputDictationText.score(stability: 0.8, confidence: nil, priority: 1))
    }

    func testStablePrefixKeepsWholeWordsOnly() {
        XCTAssertEqual(ChatInputDictationText.stablePrefix(previous: "Hello wor", current: "Hello world how"), "Hello ")
        XCTAssertEqual(ChatInputDictationText.stablePrefix(previous: "Hello world", current: "Hello world"), "Hello ")
        XCTAssertEqual(ChatInputDictationText.stablePrefix(previous: "Hello world ", current: "Hello world how"), "Hello world ")
        XCTAssertEqual(ChatInputDictationText.stablePrefix(previous: "", current: "Hello"), "")
        XCTAssertEqual(ChatInputDictationText.stablePrefix(previous: "Privet kak", current: "Привет как"), "")
    }
}
