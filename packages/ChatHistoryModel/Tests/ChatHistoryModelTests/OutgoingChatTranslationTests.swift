import Foundation
import XCTest
import Postbox
import TelegramCore
@testable import ChatHistoryModel

final class OutgoingChatTranslationTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let chatId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
    private let english = "This message is already written in English."
    private let russian = "Привет, как твои дела?"

    private func message(_ text: String, incoming: Bool = false, attributes: [MessageAttribute] = [], media: [Media] = [], stableVersion: UInt32 = 0) -> Message {
        return Message(stableId: 1, stableVersion: stableVersion, id: MessageId(peerId: chatId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: text, attributes: attributes, media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func state(_ message: Message, to: String = "en") -> ChatLiveTranslateContext.State {
        var state = ChatLiveTranslateContext.State.default
        state.canTranslate = true
        state.translate = true
        state.to = to
        state.result[.init(id: message.id, toLang: to)] = .loading(toLang: to)
        state.transcriptionResult[.init(id: message.id, toLang: to)] = .loading(toLang: to)
        return state
    }

    func testTargetLanguageSkipsQueueEligibilityAndLoadingState() {
        for text in [english, "Hi", "OK", "No", "12345", "😀"] {
            let message = message(text)
            XCTAssertFalse(canTranslateChatMessage(message, accountPeerId: accountId, toLang: "en"), text)
            XCTAssertNil(state(message).translationResult(for: message, accountPeerId: accountId), text)
        }
    }

    func testCachedTranslationCannotOverrideTargetLanguageOriginal() {
        let translation = TranslationMessageAttribute(text: "Old translation", entities: [], toLang: "en")
        let message = message(english, attributes: [translation])
        XCTAssertNil(state(message).translationResult(for: message, accountPeerId: accountId))
        let foreignMessage = self.message(russian, attributes: [translation])
        XCTAssertEqual(state(foreignMessage).translationResult(for: foreignMessage, accountPeerId: accountId), .complete(toLang: "en"))
    }

    func testForeignOutgoingAndIncomingKeepTranslation() {
        let foreignMessage = message(russian)
        XCTAssertTrue(canTranslateChatMessage(foreignMessage, accountPeerId: accountId, toLang: "en"))
        XCTAssertEqual(state(foreignMessage).translationResult(for: foreignMessage, accountPeerId: accountId), .loading(toLang: "en"))
        let incoming = message(english, incoming: true)
        XCTAssertTrue(canTranslateChatMessage(incoming, accountPeerId: accountId, toLang: "en"))
        XCTAssertEqual(state(incoming).translationResult(for: incoming, accountPeerId: accountId), .loading(toLang: "en"))
    }

    func testTargetLanguageChangeAndDisabledTranslation() {
        let message = message(english)
        XCTAssertTrue(canTranslateChatMessage(message, accountPeerId: accountId, toLang: "ru"))
        XCTAssertEqual(state(message, to: "ru").translationResult(for: message, accountPeerId: accountId), .loading(toLang: "ru"))
        var disabled = state(message, to: "ru")
        disabled.translate = false
        XCTAssertNil(disabled.translationResult(for: message, accountPeerId: accountId))
    }

    func testCaptionUsesSameEligibilityAndPresentationGate() {
        let image = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let caption = message(english, media: [image])
        XCTAssertFalse(canTranslateChatMessage(caption, accountPeerId: accountId, toLang: "en"))
        XCTAssertNil(state(caption).translationResult(for: caption, accountPeerId: accountId))
        XCTAssertTrue(canTranslateChatMessage(message(russian, media: [image]), accountPeerId: accountId, toLang: "en"))
    }

    func testTranscriptionUsesItsOwnTextAndSuppressesCachedResult() {
        func transcription(_ text: String, pending: Bool = false) -> Message {
            return message("", attributes: [AudioTranscriptionMessageAttribute(id: 1, text: text, isPending: pending, didRate: false, error: nil)])
        }
        let target = transcription(english)
        XCTAssertFalse(canTranslateChatMessage(target, accountPeerId: accountId, toLang: "en", transcription: true))
        var translated = state(target)
        translated.transcriptionResult[.init(id: target.id, toLang: "en")] = .complete(toLang: "en", text: "Old translation")
        XCTAssertNil(translated.transcriptionTranslationResult(for: target, accountPeerId: accountId))
        let foreign = transcription(russian)
        XCTAssertTrue(canTranslateChatMessage(foreign, accountPeerId: accountId, toLang: "en", transcription: true))
        XCTAssertEqual(state(foreign).transcriptionTranslationResult(for: foreign, accountPeerId: accountId), .loading(toLang: "en"))
        XCTAssertFalse(canTranslateChatMessage(transcription(russian, pending: true), accountPeerId: accountId, toLang: "en", transcription: true))
    }

    func testChecksTextBeyondFirstSampleAndNestedRichContent() {
        XCTAssertTrue(canTranslateChatMessage(message(String(repeating: english + " ", count: 10) + russian), accountPeerId: accountId, toLang: "en"))
        func rich(_ body: String) -> Message {
            let page = InstantPage(blocks: [.details(title: .plain(english), blocks: [.paragraph(.plain(body))], expanded: false)], media: [:], isComplete: true, rtl: false, url: "", views: nil)
            return message("", attributes: [RichTextMessageAttribute(instantPage: page, fullInstantPage: nil)])
        }
        XCTAssertFalse(canTranslateChatMessage(rich(english), accountPeerId: accountId, toLang: "en"))
        XCTAssertTrue(canTranslateChatMessage(rich(russian), accountPeerId: accountId, toLang: "en"))
    }

    func testChineseScriptAliasesAndRegionalEnglish() {
        for target in ["en", "en-US", "EN_us"] {
            XCTAssertFalse(canTranslateChatMessage(message(english), accountPeerId: accountId, toLang: target), target)
            XCTAssertTrue(canTranslateChatMessage(message(russian), accountPeerId: accountId, toLang: target), target)
        }
        for target in ["zh", "zh-CN", "zh-Hans", "ZH_hans_CN"] {
            XCTAssertFalse(canTranslateChatMessage(message("明天我们一起去公园散步。"), accountPeerId: accountId, toLang: target), target)
            XCTAssertTrue(canTranslateChatMessage(message("明天我們一起去公園散步。"), accountPeerId: accountId, toLang: target), target)
        }
        for target in ["zh-TW", "zh-Hant", "ZH_hant_TW", "zh-HK"] {
            XCTAssertFalse(canTranslateChatMessage(message("明天我們一起去公園散步。"), accountPeerId: accountId, toLang: target), target)
            XCTAssertTrue(canTranslateChatMessage(message(english), accountPeerId: accountId, toLang: target), target)
        }
    }

    func testRecognizedLanguageAliases() {
        for (text, targets) in [
            ("Denne meldingen er allerede skrevet på norsk.", ["no", "nb", "nb-NO", "NB_no"]),
            ("ההודעה הזאת כבר כתובה בשפה העברית.", ["he", "iw", "he-IL", "IW_il"])
        ] {
            for target in targets {
                XCTAssertFalse(canTranslateChatMessage(message(text), accountPeerId: accountId, toLang: target), target)
                XCTAssertTrue(canTranslateChatMessage(message(english), accountPeerId: accountId, toLang: target), target)
            }
        }
    }

    func testUnsupportedTargetsKeepAllOwnMessagesOriginal() {
        for (text, targets) in [
            ("Ova poruka je već napisana na srpskom jeziku.", ["sr", "sr-Latn", "SR_cyrl_RS"]),
            ("Гэта паведамленне ўжо напісана на беларускай мове.", ["be", "be-BY", "BE_by"]),
            ("Bu mesaj artıq Azərbaycan dilində yazılıb.", ["az", "az-Latn-AZ", "AZ_az"]),
            ("Bu xabar allaqachon o‘zbek tilida yozilgan.", ["uz", "uz-Cyrl-UZ", "UZ_uz"]),
            ("See sõnum on juba eesti keeles kirjutatud.", ["et", "et-EE", "ET_ee"]),
            ("Ang mensaheng ito ay nakasulat na sa wikang Tagalog.", ["tl", "tl-PH", "TL_ph", "fil-PH"])
        ] {
            for target in targets {
                for original in [text, english, russian, "OK", "12345"] {
                    let outgoing = message(original)
                    XCTAssertFalse(canTranslateChatMessage(outgoing, accountPeerId: accountId, toLang: target), target)
                    XCTAssertNil(state(outgoing, to: target).translationResult(for: outgoing, accountPeerId: accountId), target)
                }
                let incoming = message(text, incoming: true)
                XCTAssertTrue(canTranslateChatMessage(incoming, accountPeerId: accountId, toLang: target), target)
                XCTAssertEqual(state(incoming, to: target).translationResult(for: incoming, accountPeerId: accountId), .loading(toLang: target), target)
            }
        }
        for target in ["af", "bs", "eu", "und", "xx", ""] {
            XCTAssertFalse(canTranslateChatMessage(message(english), accountPeerId: accountId, toLang: target), target)
        }
    }

    func testUnsupportedTargetsSuppressCachedCaptionsAndTranscriptions() {
        let image = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        for target in ["sr", "be", "az", "uz", "et", "tl"] {
            let translation = TranslationMessageAttribute(text: "Old translation", entities: [], toLang: target)
            let caption = message(english, attributes: [translation], media: [image])
            XCTAssertFalse(canTranslateChatMessage(caption, accountPeerId: accountId, toLang: target), target)
            XCTAssertNil(state(caption, to: target).translationResult(for: caption, accountPeerId: accountId), target)
            let incomingCaption = message(english, incoming: true, attributes: [translation], media: [image])
            XCTAssertEqual(state(incomingCaption, to: target).translationResult(for: incomingCaption, accountPeerId: accountId), .complete(toLang: target), target)

            let transcription = AudioTranscriptionMessageAttribute(id: 1, text: english, isPending: false, didRate: false, error: nil)
            let outgoing = message("", attributes: [transcription])
            XCTAssertFalse(canTranslateChatMessage(outgoing, accountPeerId: accountId, toLang: target, transcription: true), target)
            var translated = state(outgoing, to: target)
            XCTAssertNil(translated.transcriptionTranslationResult(for: outgoing, accountPeerId: accountId), target)
            translated.transcriptionResult[.init(id: outgoing.id, toLang: target)] = .complete(toLang: target, text: "Old translation")
            XCTAssertNil(translated.transcriptionTranslationResult(for: outgoing, accountPeerId: accountId), target)
            let incoming = message("", incoming: true, attributes: [transcription])
            XCTAssertTrue(canTranslateChatMessage(incoming, accountPeerId: accountId, toLang: target, transcription: true), target)
            XCTAssertEqual(translated.transcriptionTranslationResult(for: incoming, accountPeerId: accountId), .complete(toLang: target, text: "Old translation"), target)
        }
    }

    func testOwnRepliesKeepOriginalTranslationPolicy() {
        for target in ["en", "sr", "be", "az", "uz", "et", "tl"] {
            for text in [english, russian, "OK", "12345"] {
                let reply = message(text)
                let batch = ChatTranslationMessages([], replies: [reply], accountPeerId: accountId, toLang: target)
                XCTAssertEqual(batch.messages.map { $0.id }, [reply.id], target)
                XCTAssertTrue(batch.eligibility.isEmpty, target)
                XCTAssertEqual(state(reply, to: target).replyTranslationResult(for: reply), .loading(toLang: target), target)

                let cached = message(text, attributes: [TranslationMessageAttribute(text: "Translated reply", entities: [], toLang: target)])
                XCTAssertEqual(state(cached, to: target).replyTranslationResult(for: cached), .complete(toLang: target), target)
            }
        }
    }

    func testReplyQueueDoesNotMakeOwnMessageEligible() {
        for target in ["en", "sr", "tl"] {
            let reply = message(english)
            let ordinary = ChatTranslationMessages([reply], replies: [], accountPeerId: accountId, toLang: target)
            XCTAssertTrue(ordinary.messages.isEmpty, target)
            let batch = ChatTranslationMessages([reply], replies: [reply], accountPeerId: accountId, toLang: target)
            XCTAssertEqual(batch.messages.map { $0.id }, [reply.id], target)
            var translated = state(reply, to: target)
            translated.translationEligibility = batch.eligibility
            XCTAssertEqual(translated.replyTranslationResult(for: reply), .loading(toLang: target), target)
            XCTAssertNil(translated.translationResult(for: reply, accountPeerId: accountId), target)
            XCTAssertTrue(translated.translationEligibility.isEmpty, target)
        }
    }

    func testReplyCacheRespectsTargetAndOriginalEnabledPolicy() {
        let reply = message(english, attributes: [TranslationMessageAttribute(text: "Translated reply", entities: [], toLang: "sr")])
        var translated = state(reply, to: "sr")
        XCTAssertEqual(translated.replyTranslationResult(for: reply), .complete(toLang: "sr"))
        translated.to = "be"
        XCTAssertNil(translated.replyTranslationResult(for: reply))
        translated.to = "sr"
        translated.translate = false
        XCTAssertEqual(translated.replyTranslationResult(for: reply), .loading(toLang: "sr"))
        translated.result = [:]
        XCTAssertNil(translated.replyTranslationResult(for: reply))
        translated.translate = true
        translated.canTranslate = false
        XCTAssertNil(translated.replyTranslationResult(for: reply))
    }

    func testEligibilityTracksContentInsteadOfMessageVersion() {
        let first = message(russian)
        let refreshed = message(russian, stableVersion: 1)
        let before = ChatTranslationMessages([first], replies: [], accountPeerId: accountId, toLang: "en")
        let after = ChatTranslationMessages([refreshed], replies: [], accountPeerId: accountId, toLang: "en")
        XCTAssertEqual(before.eligibility, after.eligibility)
        XCTAssertEqual(ChatTranslationSource(first), ChatTranslationSource(refreshed))
        XCTAssertNotEqual(ChatTranslationSource(first), ChatTranslationSource(message(english, stableVersion: 1)))
    }

    func testEditedSourceClearsStaleLoadingAndRetainsTargetGuard() {
        let first = message(russian, incoming: true)
        let edited = message("Теперь это совсем другое сообщение.", incoming: true, stableVersion: 1)
        var translated = state(first)
        translated.updateTranslation(ChatTranslationMessages([first], replies: [], accountPeerId: accountId, toLang: "en"), toLang: "en")
        translated.updateTranslation(ChatTranslationMessages([edited], replies: [], accountPeerId: accountId, toLang: "en"), toLang: "en")
        XCTAssertNil(translated.result[.init(id: first.id, toLang: "en")])
        XCTAssertEqual(translated.translationEligibility[.init(id: first.id, toLang: "en")], ChatTranslationSource(edited))
        let before = translated
        translated.updateTranslation(ChatTranslationMessages([first], replies: [], accountPeerId: accountId, toLang: "ru"), toLang: "ru")
        XCTAssertEqual(translated, before)
    }

    func testCompletedResultWithoutCachedAttributeIsCleared() {
        let first = message(russian, incoming: true, attributes: [TranslationMessageAttribute(text: "Hello", entities: [], toLang: "en")])
        var translated = state(first)
        translated.updateTranslation(ChatTranslationMessages([first], replies: [], accountPeerId: accountId, toLang: "en"), toLang: "en")
        XCTAssertEqual(translated.result[.init(id: first.id, toLang: "en")], .complete(toLang: "en"))
        let edited = message("Изменённое сообщение.", incoming: true, stableVersion: 1)
        translated.updateTranslation(ChatTranslationMessages([edited], replies: [], accountPeerId: accountId, toLang: "en"), toLang: "en")
        XCTAssertNil(translated.result[.init(id: first.id, toLang: "en")])
    }

    func testReplyAndMessageBatchDeduplicatesRequests() {
        let incoming = message(russian, incoming: true)
        let batch = ChatTranslationMessages([incoming, incoming], replies: [incoming, incoming], accountPeerId: accountId, toLang: "sr")
        XCTAssertEqual(batch.messages.map { $0.id }, [incoming.id])
        XCTAssertEqual(batch.eligibility[.init(id: incoming.id, toLang: "sr")], ChatTranslationSource(incoming))
    }

    func testTargetLanguageEditRemovesOutgoingEligibility() {
        let pinned = message(russian)
        var translated = state(pinned)
        translated.updateTranslation(ChatTranslationMessages([pinned], replies: [], accountPeerId: accountId, toLang: "en"), toLang: "en")
        let edited = message(english, stableVersion: 1)
        translated.updateTranslation(ChatTranslationMessages([edited], replies: [], accountPeerId: accountId, toLang: "en"), toLang: "en")
        XCTAssertTrue(translated.translationEligibility.isEmpty)
        XCTAssertNil(translated.translationResult(for: edited, accountPeerId: accountId))
        if #available(macOS 10.14, *) {
            XCTAssertNil(translated.result[.init(id: pinned.id, toLang: "en")])
            let foreignAgain = message("Теперь сообщение снова на русском языке.", stableVersion: 2)
            translated.updateTranslation(ChatTranslationMessages([foreignAgain], replies: [], accountPeerId: accountId, toLang: "en"), toLang: "en")
            XCTAssertNotNil(translated.translationEligibility[.init(id: pinned.id, toLang: "en")])
            XCTAssertNil(translated.result[.init(id: pinned.id, toLang: "en")])
        }
    }

    func testOwnReplyPolicyWithoutLanguageRecognition() {
        if #available(macOS 10.14, *) {
            return
        }
        let reply = message(english)
        XCTAssertFalse(canTranslateChatMessage(reply, accountPeerId: accountId, toLang: "ru"))
        XCTAssertNil(state(reply, to: "ru").translationResult(for: reply, accountPeerId: accountId))
        XCTAssertEqual(ChatTranslationMessages([], replies: [reply], accountPeerId: accountId, toLang: "ru").messages.map { $0.id }, [reply.id])
        XCTAssertEqual(state(reply, to: "ru").replyTranslationResult(for: reply), .loading(toLang: "ru"))
        let cached = message(english, attributes: [TranslationMessageAttribute(text: "Translated reply", entities: [], toLang: "ru")])
        XCTAssertEqual(state(cached, to: "ru").replyTranslationResult(for: cached), .complete(toLang: "ru"))
    }

    func testKazakhTargetRequiresMacOS13() {
        for target in ["kk", "kk-KZ", "KK_kz"] {
            let foreign = message(english)
            if #available(macOS 13.0, *) {
                XCTAssertTrue(canTranslateChatMessage(foreign, accountPeerId: accountId, toLang: target), target)
                XCTAssertEqual(state(foreign, to: target).translationResult(for: foreign, accountPeerId: accountId), .loading(toLang: target), target)
                XCTAssertFalse(canTranslateChatMessage(message("Бұл хабарлама қазақ тілінде жазылған."), accountPeerId: accountId, toLang: target), target)
            } else {
                XCTAssertFalse(canTranslateChatMessage(foreign, accountPeerId: accountId, toLang: target), target)
                XCTAssertNil(state(foreign, to: target).translationResult(for: foreign, accountPeerId: accountId), target)
            }
            XCTAssertTrue(canTranslateChatMessage(message(english, incoming: true), accountPeerId: accountId, toLang: target), target)
        }
    }
}
