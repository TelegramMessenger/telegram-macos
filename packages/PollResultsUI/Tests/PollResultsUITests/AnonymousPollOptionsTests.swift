import XCTest
import Foundation
import Postbox
import TelegramCore
import InputView
import InputDataUI
@testable import PollResultsUI

final class AnonymousPollOptionsTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let modes: [NewPollMode] = [.normal(anonymous: false), .multiple(anonymous: false), .quiz(anonymous: false)]

    private func state(mode: NewPollMode = .normal(anonymous: true), allowAddingOptions: Bool = false) -> NewPollState {
        return NewPollState(
            options: [
                NewPollOption(identifier: InputDataIdentifier("first"), textState: .init(inputText: NSAttributedString(string: "First")), selected: false),
                NewPollOption(identifier: InputDataIdentifier("second"), textState: .init(inputText: NSAttributedString(string: "Second")), selected: false),
            ],
            random: 1,
            mode: mode,
            isQuiz: nil,
            quizExplanation: NSAttributedString(),
            textState: .init(inputText: NSAttributedString(string: "Question")),
            allowAddingOptions: allowAddingOptions
        )
    }

    func testTurningNamesOffDisablesAddingOptionsInEveryMode() {
        for mode in modes {
            let original = state(mode: mode, allowAddingOptions: true)
            let updated = original.withUpdatedMode(mode.withUpdatedIsAnonymous(true))
            XCTAssertTrue(updated.mode.isAnonymous)
            XCTAssertFalse(updated.allowAddingOptions)
            XCTAssertEqual(updated.mode.kind, mode.kind)
        }
    }

    func testTurningAddingOptionsOnEnablesNamesInEveryMode() {
        for mode in modes {
            let original = state(mode: mode.withUpdatedIsAnonymous(true))
            let updated = original.withUpdatedAllowAddingOptions(true)
            XCTAssertFalse(updated.mode.isAnonymous)
            XCTAssertTrue(updated.allowAddingOptions)
            XCTAssertEqual(updated.mode.kind, mode.kind)
        }
    }

    func testReportedToggleSequenceNeverLeavesAnonymousOpenPoll() {
        var current = state()
        XCTAssertTrue(current.mode.isAnonymous)
        XCTAssertFalse(current.allowAddingOptions)
        current = current.withUpdatedAllowAddingOptions(true)
        XCTAssertFalse(current.mode.isAnonymous)
        XCTAssertTrue(current.allowAddingOptions)
        current = current.withUpdatedMode(current.mode.withUpdatedIsAnonymous(true))
        XCTAssertTrue(current.mode.isAnonymous)
        XCTAssertFalse(current.allowAddingOptions)
        let poll = current.media(accountPeerId: accountId)
        XCTAssertEqual(poll.publicity, .anonymous)
        XCTAssertFalse(poll.openAnswers)
    }

    func testTurningAddingOptionsOffDoesNotChangePublicity() {
        for mode in modes {
            for anonymous in [false, true] {
                let initialMode = mode.withUpdatedIsAnonymous(anonymous)
                let updated = state(mode: initialMode, allowAddingOptions: !anonymous).withUpdatedAllowAddingOptions(false)
                XCTAssertEqual(updated.mode, initialMode)
                XCTAssertFalse(updated.allowAddingOptions)
            }
        }
    }

    func testTurningNamesOnDoesNotEnableAddingOptions() {
        for mode in modes {
            let updated = state(mode: mode.withUpdatedIsAnonymous(true)).withUpdatedMode(mode)
            XCTAssertFalse(updated.mode.isAnonymous)
            XCTAssertFalse(updated.allowAddingOptions)
        }
    }

    func testChangingPublicPollModePreservesAddingOptions() {
        for sourceMode in modes {
            for targetMode in modes {
                let updated = state(mode: sourceMode, allowAddingOptions: true).withUpdatedMode(targetMode)
                XCTAssertEqual(updated.mode, targetMode)
                XCTAssertTrue(updated.allowAddingOptions)
            }
        }
    }

    func testOrdinaryAnonymousPollRemainsAnonymous() {
        let current = state()
        let poll = current.media(accountPeerId: accountId)
        XCTAssertEqual(poll.publicity, .anonymous)
        XCTAssertFalse(poll.openAnswers)
        XCTAssertEqual(poll.kind, .poll(multipleAnswers: false))
        XCTAssertEqual(poll.text, "Question")
        XCTAssertEqual(poll.options.map { $0.text }, ["First", "Second"])
    }

    func testPublicPollWithAddingOptionsKeepsItsPayload() {
        for mode in modes {
            let current = state(mode: mode, allowAddingOptions: true)
            let poll = current.media(accountPeerId: accountId)
            XCTAssertEqual(poll.publicity, .public)
            XCTAssertTrue(poll.openAnswers)
            XCTAssertEqual(poll.kind, mode.kind)
            XCTAssertEqual(poll.options.map { $0.addedBy }, [accountId, accountId])
        }
    }

    func testInvalidAnonymousStateCannotExportOpenAnswers() {
        for mode in modes {
            let invalid = state(mode: mode.withUpdatedIsAnonymous(true), allowAddingOptions: true)
            let poll = invalid.media(accountPeerId: accountId)
            XCTAssertEqual(poll.publicity, .anonymous)
            XCTAssertFalse(poll.openAnswers)
            XCTAssertEqual(poll.kind, mode.kind)
        }
    }

    func testAnonymizingPreservesQuestionAnswersAndOtherSettings() {
        var original = state(mode: .multiple(anonymous: false), allowAddingOptions: true)
        original.descriptionState = .init(inputText: NSAttributedString(string: "Description"))
        original.quizExplanation = NSAttributedString(string: "Explanation")
        original.allowRevoting = true
        original.shuffleOptions = true
        original.hideResults = true
        original.limitDuration = true
        original.deadlineTimeout = 3600
        original.restrictToSubscribers = true
        original.limitByCountry = true
        let updated = original.withUpdatedMode(original.mode.withUpdatedIsAnonymous(true))
        XCTAssertEqual(updated.textState, original.textState)
        XCTAssertEqual(updated.descriptionState, original.descriptionState)
        XCTAssertEqual(updated.options, original.options)
        XCTAssertEqual(updated.quizExplanation, original.quizExplanation)
        XCTAssertEqual(updated.allowRevoting, original.allowRevoting)
        XCTAssertEqual(updated.shuffleOptions, original.shuffleOptions)
        XCTAssertEqual(updated.hideResults, original.hideResults)
        XCTAssertEqual(updated.limitDuration, original.limitDuration)
        XCTAssertEqual(updated.deadlineTimeout, original.deadlineTimeout)
        XCTAssertEqual(updated.restrictToSubscribers, original.restrictToSubscribers)
        XCTAssertEqual(updated.limitByCountry, original.limitByCountry)
        XCTAssertTrue(updated.mode.isAnonymous)
        XCTAssertFalse(updated.allowAddingOptions)
        let poll = updated.media(accountPeerId: accountId)
        XCTAssertFalse(poll.revotingDisabled)
        XCTAssertTrue(poll.shuffleAnswers)
        XCTAssertTrue(poll.hideResultsUntilClose)
        XCTAssertEqual(poll.deadlineTimeout, 3600)
        XCTAssertFalse(poll.openAnswers)
    }

    func testRepeatedPrivacyAndOpenAnswerTogglesStayConsistent() {
        var current = state()
        for _ in 0 ..< 5 {
            current = current.withUpdatedAllowAddingOptions(true)
            XCTAssertFalse(current.mode.isAnonymous)
            XCTAssertTrue(current.allowAddingOptions)
            current = current.withUpdatedMode(current.mode.withUpdatedIsAnonymous(true))
            XCTAssertTrue(current.mode.isAnonymous)
            XCTAssertFalse(current.allowAddingOptions)
            current = current.withUpdatedMode(current.mode.withUpdatedIsAnonymous(false))
            XCTAssertFalse(current.allowAddingOptions)
        }
    }

    func testEveryToggleSequenceProducesValidPayload() {
        for initialMode in modes {
            for sequence in 0 ..< 256 {
                var current = state(mode: initialMode)
                for index in 0 ..< 8 {
                    if sequence & (1 << index) == 0 {
                        current = current.withUpdatedMode(current.mode.withUpdatedIsAnonymous(!current.mode.isAnonymous))
                    } else {
                        current = current.withUpdatedAllowAddingOptions(!current.allowAddingOptions)
                    }
                    XCTAssertFalse(current.mode.isAnonymous && current.allowAddingOptions)
                    let poll = current.media(accountPeerId: accountId)
                    XCTAssertFalse(poll.publicity == .anonymous && poll.openAnswers)
                }
            }
        }
    }
}
