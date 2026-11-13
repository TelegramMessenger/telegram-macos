import XCTest
import Foundation
import Postbox
import TelegramCore
import InputView
import InputDataUI
@testable import PollResultsUI

final class PollPremiumEmojiTests: XCTestCase {
    private let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))

    private func file(_ id: Int64 = 10, premium: Bool = true, custom: Bool = true, namespace: Int32 = Namespaces.Media.CloudFile) -> TelegramMediaFile {
        return TelegramMediaFile(
            fileId: MediaId(namespace: namespace, id: id),
            partialReference: nil,
            resource: LocalFileMediaResource(fileId: id),
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: "application/x-tgsticker",
            size: nil,
            attributes: custom ? [.CustomEmoji(isPremium: premium, isSingleColor: false, alt: "😀", packReference: nil)] : [],
            alternativeRepresentations: []
        )
    }

    private func input(file: TelegramMediaFile?, fileId: Int64 = 10) -> ChatTextInputState {
        return ChatTextInputState(inputText: "😀 answer", selectionRange: 2 ..< 2, attributes: [.animated(0 ..< 2, "fixture", fileId, file, nil), .bold(3 ..< 9)])
    }

    private func customIds(_ entities: [MessageTextEntity]) -> [Int64] {
        return entities.compactMap { entity in
            if case let .CustomEmoji(_, fileId) = entity.type {
                return fileId
            }
            return nil
        }
    }

    private func state(_ input: ChatTextInputState) -> NewPollState {
        return NewPollState(
            options: [
                NewPollOption(identifier: InputDataIdentifier("first"), textState: input.textInputState(), selected: true),
                NewPollOption(identifier: InputDataIdentifier("second"), textState: input.textInputState(), selected: false)
            ],
            random: 1,
            mode: .quiz(anonymous: false),
            isQuiz: true,
            quizExplanation: input.attributedString(),
            textState: input.textInputState(),
            descriptionState: input.textInputState(),
            allowAddingOptions: true,
            allowRevoting: true,
            shuffleOptions: true,
            limitDuration: true,
            deadlineTimeout: 3600,
            hideResults: true,
            restrictToSubscribers: true
        )
    }

    func testNonPremiumDropsPaidEmojiEntityWithoutLosingTextOrFormatting() {
        let original = input(file: file())
        let result = pollTextInputForSending(original, isPremium: false)
        XCTAssertTrue(customIds(result.messageTextEntities()).isEmpty)
        XCTAssertEqual(result.inputText, original.inputText)
        XCTAssertEqual(result.selectionRange, original.selectionRange)
        XCTAssertEqual(result.attributes, [.bold(3 ..< 9)])
        XCTAssertEqual(customIds(original.messageTextEntities()), [10])
    }

    func testNonPremiumKeepsKnownFreeCustomEmoji() {
        let original = input(file: file(premium: false))
        let result = pollTextInputForSending(original, isPremium: false)
        XCTAssertEqual(customIds(result.messageTextEntities()), [10])
        XCTAssertEqual(result.inputText, original.inputText)
        XCTAssertEqual(result.selectionRange, original.selectionRange)
        XCTAssertEqual(result.messageTextEntities(), original.messageTextEntities())
    }

    func testNonPremiumFlattensUnresolvedEmojiInsteadOfAssumingItIsFree() {
        let original = input(file: nil)
        let result = pollTextInputForSending(original, isPremium: false)
        XCTAssertTrue(customIds(result.messageTextEntities()).isEmpty)
        XCTAssertEqual(result.inputText, original.inputText)
        XCTAssertEqual(result.attributes, [.bold(3 ..< 9)])
    }

    func testNonPremiumRejectsMismatchedFreeEmojiMetadata() {
        let original = input(file: file(11, premium: false))
        let result = pollTextInputForSending(original, isPremium: false)
        XCTAssertTrue(customIds(result.messageTextEntities()).isEmpty)
        XCTAssertEqual(result.inputText, original.inputText)
    }

    func testNonPremiumRejectsNonEmojiFileMetadata() {
        let original = input(file: file(premium: false, custom: false))
        let result = pollTextInputForSending(original, isPremium: false)
        XCTAssertTrue(customIds(result.messageTextEntities()).isEmpty)
        XCTAssertEqual(result.inputText, original.inputText)
    }

    func testNonPremiumRejectsNonCloudEmojiMetadata() {
        let original = input(file: file(premium: false, namespace: Namespaces.Media.LocalFile))
        let result = pollTextInputForSending(original, isPremium: false)
        XCTAssertTrue(customIds(result.messageTextEntities()).isEmpty)
        XCTAssertEqual(result.inputText, original.inputText)
    }

    func testPremiumInputRemainsUnchanged() {
        let files: [TelegramMediaFile?] = [file(), file(premium: false), nil]
        for file in files {
            let original = input(file: file)
            let result = pollTextInputForSending(original, isPremium: true)
            XCTAssertTrue(result === original)
            XCTAssertEqual(customIds(result.messageTextEntities()), [10])
        }
    }

    func testPlainUnicodeEmojiAndOtherFormattingAreUnchanged() {
        let original = ChatTextInputState(inputText: "😀 answer", selectionRange: 0 ..< 9, attributes: [.bold(3 ..< 9), .italic(0 ..< 2)])
        for isPremium in [false, true] {
            XCTAssertEqual(pollTextInputForSending(original, isPremium: isPremium), original)
        }
    }

    func testMixedPaidFreeAndUnknownEmojiPreserveOnlyKnownFreeEntities() {
        let original = ChatTextInputState(inputText: "😀😀😀", selectionRange: 6 ..< 6, attributes: [
            .animated(0 ..< 2, "paid", 10, file(), nil),
            .animated(2 ..< 4, "free", 11, file(11, premium: false), nil),
            .animated(4 ..< 6, "unknown", 12, nil, nil),
            .spoiler(0 ..< 6)
        ])
        let result = pollTextInputForSending(original, isPremium: false)
        XCTAssertEqual(customIds(result.messageTextEntities()), [11])
        XCTAssertEqual(result.inputText, original.inputText)
        XCTAssertEqual(result.selectionRange, original.selectionRange)
        XCTAssertTrue(result.messageTextEntities().contains(MessageTextEntity(range: 2 ..< 4, type: .CustomEmoji(stickerPack: nil, fileId: 11))))
        XCTAssertTrue(result.attributes.contains(.spoiler(0 ..< 6)))
    }

    func testQuestionPayloadIsSanitizedForNonPremium() {
        let original = input(file: file())
        let outgoing = state(original).forSending(isPremium: false).media(accountPeerId: accountPeerId)
        XCTAssertEqual(outgoing.text, original.inputText)
        XCTAssertTrue(customIds(outgoing.textEntities).isEmpty)
        XCTAssertTrue(outgoing.textEntities.contains(MessageTextEntity(range: 3 ..< 9, type: .Bold)))
    }

    func testEveryInitialAnswerPayloadIsSanitizedForNonPremium() {
        let original = input(file: file())
        let outgoing = state(original).forSending(isPremium: false).media(accountPeerId: accountPeerId)
        XCTAssertEqual(outgoing.options.count, 2)
        for option in outgoing.options {
            XCTAssertEqual(option.text, original.inputText)
            XCTAssertTrue(customIds(option.entities).isEmpty)
            XCTAssertEqual(option.addedBy, accountPeerId)
        }
        XCTAssertEqual(outgoing.correctAnswers, [Data("0".utf8)])
    }

    func testDescriptionCaptionIsSanitizedAlongsideThePoll() {
        let original = input(file: file())
        let outgoing = state(original).forSending(isPremium: false).descriptionState.textInputState()
        XCTAssertEqual(outgoing.inputText, original.inputText)
        XCTAssertTrue(customIds(outgoing.messageTextEntities()).isEmpty)
        XCTAssertEqual(outgoing.selectionRange, original.selectionRange)
    }

    func testQuizSolutionPayloadIsSanitizedForNonPremium() throws {
        let original = input(file: file())
        let poll = state(original).forSending(isPremium: false).media(accountPeerId: accountPeerId)
        let solution = try XCTUnwrap(poll.results.solution)
        XCTAssertEqual(solution.text, original.inputText)
        XCTAssertTrue(customIds(solution.entities).isEmpty)
    }

    func testAddedOptionPayloadIsSanitizedForNonPremium() throws {
        let original = input(file: file())
        let option = try XCTUnwrap(state(original).addedOption(existingOptionCount: 4, accountPeerId: accountPeerId, timestamp: 100, isPremium: false))
        XCTAssertEqual(option.text, original.inputText)
        XCTAssertTrue(customIds(option.entities).isEmpty)
        XCTAssertEqual(option.opaqueIdentifier, Data("4".utf8))
        XCTAssertEqual(option.addedBy, accountPeerId)
        XCTAssertEqual(option.date, 100)
    }

    func testFreeEmojiIsPreservedInAllOutgoingFields() throws {
        let original = input(file: file(premium: false))
        let draft = state(original)
        let prepared = draft.forSending(isPremium: false)
        let poll = prepared.media(accountPeerId: accountPeerId)
        XCTAssertEqual(customIds(poll.textEntities), [10])
        XCTAssertEqual(poll.options.map { customIds($0.entities) }, [[10], [10]])
        XCTAssertEqual(customIds(try XCTUnwrap(poll.results.solution).entities), [10])
        XCTAssertEqual(customIds(prepared.descriptionState.textInputState().messageTextEntities()), [10])
        let added = try XCTUnwrap(draft.addedOption(existingOptionCount: 2, accountPeerId: accountPeerId, timestamp: 100, isPremium: false))
        XCTAssertEqual(customIds(added.entities), [10])
    }

    func testPremiumEmojiIsPreservedInAllOutgoingFieldsForPremium() throws {
        let draft = state(input(file: file()))
        let prepared = draft.forSending(isPremium: true)
        XCTAssertEqual(prepared, draft)
        let poll = prepared.media(accountPeerId: accountPeerId)
        XCTAssertEqual(customIds(poll.textEntities), [10])
        XCTAssertEqual(poll.options.map { customIds($0.entities) }, [[10], [10]])
        XCTAssertEqual(customIds(try XCTUnwrap(poll.results.solution).entities), [10])
        XCTAssertEqual(customIds(prepared.descriptionState.textInputState().messageTextEntities()), [10])
        let added = try XCTUnwrap(draft.addedOption(existingOptionCount: 2, accountPeerId: accountPeerId, timestamp: 100, isPremium: true))
        XCTAssertEqual(customIds(added.entities), [10])
    }

    func testLatestEntitlementProtectsAlreadyAuthoredPremiumDraft() throws {
        let draft = state(input(file: file()))
        let previouslyPremium = draft.forSending(isPremium: true)
        let outgoing = previouslyPremium.forSending(isPremium: false)
        let poll = outgoing.media(accountPeerId: accountPeerId)
        XCTAssertTrue(customIds(poll.textEntities).isEmpty)
        XCTAssertTrue(poll.options.allSatisfy { customIds($0.entities).isEmpty })
        XCTAssertTrue(customIds(try XCTUnwrap(poll.results.solution).entities).isEmpty)
        XCTAssertTrue(customIds(outgoing.descriptionState.textInputState().messageTextEntities()).isEmpty)
        let added = try XCTUnwrap(draft.addedOption(existingOptionCount: 2, accountPeerId: accountPeerId, timestamp: 100, isPremium: false))
        XCTAssertTrue(customIds(added.entities).isEmpty)
        XCTAssertEqual(customIds(draft.textState.textInputState().messageTextEntities()), [10])
    }

    func testUnresolvedEmojiCannotLeakThroughAnyOutgoingField() throws {
        let draft = state(input(file: nil))
        let prepared = draft.forSending(isPremium: false)
        let poll = prepared.media(accountPeerId: accountPeerId)
        XCTAssertTrue(customIds(poll.textEntities).isEmpty)
        XCTAssertTrue(poll.options.allSatisfy { customIds($0.entities).isEmpty })
        XCTAssertTrue(customIds(try XCTUnwrap(poll.results.solution).entities).isEmpty)
        XCTAssertTrue(customIds(prepared.descriptionState.textInputState().messageTextEntities()).isEmpty)
        let added = try XCTUnwrap(draft.addedOption(existingOptionCount: 2, accountPeerId: accountPeerId, timestamp: 100, isPremium: false))
        XCTAssertTrue(customIds(added.entities).isEmpty)
    }

    func testSanitizationPreservesOtherSettingsMediaAndDraft() {
        let media = file(20, premium: false, custom: false)
        var draft = state(input(file: file()))
        draft.descriptionMedia = .cloud(media, thumbnail: nil)
        draft.solutionMedia = .cloud(media, thumbnail: nil)
        draft.options[0] = draft.options[0].withUpdatedMedia(.cloud(media, thumbnail: nil))
        draft.isAddOption = true
        draft.uploadingMedia = ["pending"]
        draft.uploadProgress = ["pending": 0.5]
        let prepared = draft.forSending(isPremium: false)
        XCTAssertEqual(prepared.mode, draft.mode)
        XCTAssertEqual(prepared.isQuiz, draft.isQuiz)
        XCTAssertEqual(prepared.isAddOption, draft.isAddOption)
        XCTAssertEqual(prepared.uploadingMedia, draft.uploadingMedia)
        XCTAssertEqual(prepared.uploadProgress, draft.uploadProgress)
        XCTAssertEqual(prepared.options.map { $0.identifier }, draft.options.map { $0.identifier })
        XCTAssertEqual(prepared.options.map { $0.selected }, draft.options.map { $0.selected })
        XCTAssertEqual(prepared.options.map { $0.media }, draft.options.map { $0.media })
        XCTAssertEqual(prepared.descriptionMedia, draft.descriptionMedia)
        XCTAssertEqual(prepared.solutionMedia, draft.solutionMedia)
        let poll = prepared.media(accountPeerId: accountPeerId)
        XCTAssertTrue(poll.openAnswers)
        XCTAssertFalse(poll.revotingDisabled)
        XCTAssertTrue(poll.shuffleAnswers)
        XCTAssertTrue(poll.hideResultsUntilClose)
        XCTAssertTrue(poll.restrictToSubscribers)
        XCTAssertEqual(poll.deadlineTimeout, 3600)
        XCTAssertTrue(poll.attachedMedia?.isEqual(to: media) == true)
        XCTAssertTrue(poll.options[0].media?.isEqual(to: media) == true)
        XCTAssertTrue(poll.results.solution?.media?.isEqual(to: media) == true)
        XCTAssertEqual(customIds(draft.textState.textInputState().messageTextEntities()), [10])
    }

    func testEmptyAddedOptionStillCannotBeSubmitted() {
        let empty = state(ChatTextInputState(inputText: "   "))
        for isPremium in [false, true] {
            XCTAssertNil(empty.addedOption(existingOptionCount: 2, accountPeerId: accountPeerId, timestamp: 100, isPremium: isPremium))
        }
    }
}
