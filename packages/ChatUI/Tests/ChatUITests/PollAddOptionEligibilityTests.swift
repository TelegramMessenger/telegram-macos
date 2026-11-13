import XCTest
import Foundation
import Postbox
import TelegramCore
@testable import ChatUI

final class PollAddOptionEligibilityTests: XCTestCase {
    private let kinds: [TelegramMediaPollKind] = [
        .poll(multipleAnswers: false),
        .poll(multipleAnswers: true),
        .quiz(multipleAnswers: false)
    ]

    private func results(selected: [Int], optionCount: Int = 2) -> TelegramMediaPollResults {
        return TelegramMediaPollResults(
            voters: (0 ..< optionCount).map { index in
                TelegramMediaPollOptionVoters(selected: selected.contains(index), opaqueIdentifier: Data([UInt8(index)]), count: 1, isCorrect: false)
            },
            totalVoters: 2,
            recentVoters: [],
            solution: nil,
            hasUnseenVotes: nil,
            canViewStats: false
        )
    }

    private func poll(openAnswers: Bool = true, revotingDisabled: Bool = false, isClosed: Bool = false, hideResults: Bool = false, kind: TelegramMediaPollKind = .poll(multipleAnswers: false), selected: [Int] = [], optionCount: Int = 2) -> TelegramMediaPoll {
        return TelegramMediaPoll(
            pollId: MediaId(namespace: Namespaces.Media.CloudPoll, id: 1),
            publicity: .public,
            kind: kind,
            text: "Question",
            textEntities: [],
            options: (0 ..< optionCount).map { index in
                TelegramMediaPollOption(text: "Option \(index)", entities: [], opaqueIdentifier: Data([UInt8(index)]), date: nil, addedBy: nil)
            },
            correctAnswers: nil,
            results: results(selected: selected, optionCount: optionCount),
            isClosed: isClosed,
            deadlineTimeout: nil,
            deadlineDate: nil,
            pollHash: 0,
            openAnswers: openAnswers,
            revotingDisabled: revotingDisabled,
            hideResultsUntilClose: hideResults
        )
    }

    private func configuration(_ limit: Int) -> AppConfiguration {
        var configuration = AppConfiguration.defaultValue
        configuration.data = .dictionary(["poll_answers_max": .number(Double(limit))])
        return configuration
    }

    func testDefaultLimitAllowsOneMoreAnswer() {
        let poll = poll(selected: [0], optionCount: 9)
        XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: false, appConfiguration: .defaultValue))
    }

    func testDefaultLimitHidesAddOptionAtCapacity() {
        for selected in [[], [0]] {
            let poll = poll(selected: selected, optionCount: 10)
            XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: false, appConfiguration: .defaultValue))
        }
    }

    func testDefaultLimitHidesAddOptionAboveCapacity() {
        let poll = poll(selected: [0], optionCount: 11)
        XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: false, appConfiguration: .defaultValue))
    }

    func testConfiguredLimitsApplyAcrossKindsAndVotingStates() {
        for limit in [3, 15] {
            for kind in kinds {
                for revotingDisabled in [false, true] {
                    for selected in [[], [0]] {
                        for count in [limit - 1, limit, limit + 1] {
                            let poll = poll(revotingDisabled: revotingDisabled, kind: kind, selected: selected, optionCount: count)
                            XCTAssertEqual(ChatPollItem.canAddOption(poll: poll, isClosed: false, appConfiguration: configuration(limit)), count < limit)
                        }
                    }
                }
            }
        }
    }

    func testNonPositiveConfiguredLimitDoesNotOfferAdding() {
        for limit in [0, -1] {
            let poll = poll(selected: [0])
            XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: false, appConfiguration: configuration(limit)))
        }
    }

    func testMissingConfigurationKeyUsesEditorDefaultLimit() {
        var configuration = AppConfiguration.defaultValue
        configuration.data = .dictionary([:])
        XCTAssertTrue(ChatPollItem.canAddOption(poll: poll(optionCount: 9), isClosed: false, appConfiguration: configuration))
        XCTAssertFalse(ChatPollItem.canAddOption(poll: poll(optionCount: 10), isClosed: false, appConfiguration: configuration))
    }

    func testNonNumericConfigurationUsesEditorDefaultLimit() {
        var configuration = AppConfiguration.defaultValue
        configuration.data = .dictionary(["poll_answers_max": .string("15")])
        XCTAssertTrue(ChatPollItem.canAddOption(poll: poll(optionCount: 9), isClosed: false, appConfiguration: configuration))
        XCTAssertFalse(ChatPollItem.canAddOption(poll: poll(optionCount: 10), isClosed: false, appConfiguration: configuration))
    }

    func testUpdatedConfigurationChangesEligibilityWithoutChangingVote() {
        let poll = poll(revotingDisabled: true, selected: [0], optionCount: 10)
        let results = poll.results
        XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: false, appConfiguration: configuration(15)))
        XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: false, appConfiguration: configuration(10)))
        XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: false, appConfiguration: configuration(15)))
        XCTAssertEqual(poll.results, results)
    }

    func testOptionsGrowthReachesLimitRegardlessOfRevoting() {
        for revotingDisabled in [false, true] {
            let pollBefore = poll(revotingDisabled: revotingDisabled, selected: [0], optionCount: 9)
            let pollAfter = poll(revotingDisabled: revotingDisabled, selected: [0], optionCount: 10)
            XCTAssertTrue(ChatPollItem.canAddOption(poll: pollBefore, isClosed: false, appConfiguration: .defaultValue))
            XCTAssertFalse(ChatPollItem.canAddOption(poll: pollAfter, isClosed: false, appConfiguration: .defaultValue))
        }
    }

    func testCapacityDoesNotOverrideClosedOrDisabledOpenAnswers() {
        for selected in [[], [0]] {
            let closed = poll(isClosed: true, selected: selected)
            let fixedAnswers = poll(openAnswers: false, selected: selected)
            XCTAssertFalse(ChatPollItem.canAddOption(poll: closed, isClosed: true, appConfiguration: configuration(15)))
            XCTAssertFalse(ChatPollItem.canAddOption(poll: fixedAnswers, isClosed: false, appConfiguration: configuration(15)))
        }
    }

    func testVotedPollKeepsAddOptionWhenRevotingIsAllowed() {
        for kind in kinds {
            let selections = kind == .poll(multipleAnswers: true) ? [[0], [1], [0, 1]] : [[0], [1]]
            for selected in selections {
                let poll = poll(kind: kind, selected: selected)
                XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed, appConfiguration: .defaultValue))
            }
        }
    }

    func testVotedPollKeepsAddOptionWhenRevotingIsDisabled() {
        for kind in kinds {
            let selections = kind == .poll(multipleAnswers: true) ? [[0], [1], [0, 1]] : [[0], [1]]
            for selected in selections {
                let poll = poll(revotingDisabled: true, kind: kind, selected: selected)
                XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed, appConfiguration: .defaultValue))
            }
        }
    }

    func testBeforeVotingEitherRevotingModeAllowsAddingOptions() {
        for kind in kinds {
            for revotingDisabled in [false, true] {
                let poll = poll(revotingDisabled: revotingDisabled, kind: kind)
                XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed, appConfiguration: .defaultValue))
            }
        }
    }

    func testClosedPollNeverAllowsAddingOptions() {
        for revotingDisabled in [false, true] {
            for selected in [[], [0], [1]] {
                let poll = poll(revotingDisabled: revotingDisabled, isClosed: true, selected: selected)
                XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed, appConfiguration: .defaultValue))
            }
        }
    }

    func testPollWithoutOpenAnswersNeverAllowsAddingOptions() {
        for revotingDisabled in [false, true] {
            for selected in [[], [0], [1]] {
                let poll = poll(openAnswers: false, revotingDisabled: revotingDisabled, selected: selected)
                XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed, appConfiguration: .defaultValue))
            }
        }
    }

    func testEffectiveClosurePreventsAddingEvenBeforeMediaIsMarkedClosed() {
        for revotingDisabled in [false, true] {
            for selected in [[], [0], [1]] {
                let poll = poll(revotingDisabled: revotingDisabled, selected: selected)
                XCTAssertFalse(poll.isClosed)
                XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: true, appConfiguration: .defaultValue))
            }
        }
    }

    func testVotingAndResultsUpdatesKeepAddOptionWithoutChangingTheVote() {
        for revotingDisabled in [false, true] {
            var poll = poll(revotingDisabled: revotingDisabled)
            let selections = revotingDisabled ? [[], [0], [0]] : [[], [0], [0], [1]]
            for selected in selections {
                let results = results(selected: selected)
                poll = poll.withUpdatedResults(results, min: false)
                let options = poll.options
                XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed, appConfiguration: .defaultValue))
                XCTAssertEqual(poll.results, results)
                XCTAssertEqual(poll.options, options)
                XCTAssertEqual(poll.revotingDisabled, revotingDisabled)
                XCTAssertTrue(poll.openAnswers)
            }
        }
    }

    func testHiddenResultsDoNotDisableAddingOptionsAfterVoting() {
        for revotingDisabled in [false, true] {
            let poll = poll(revotingDisabled: revotingDisabled, hideResults: true, selected: [0])
            XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed, appConfiguration: .defaultValue))
        }
    }
}
