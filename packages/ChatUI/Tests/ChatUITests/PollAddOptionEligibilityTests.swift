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

    private func results(selected: [Int]) -> TelegramMediaPollResults {
        return TelegramMediaPollResults(
            voters: (0 ..< 2).map { index in
                TelegramMediaPollOptionVoters(selected: selected.contains(index), opaqueIdentifier: Data([UInt8(index)]), count: 1, isCorrect: false)
            },
            totalVoters: 2,
            recentVoters: [],
            solution: nil,
            hasUnseenVotes: nil,
            canViewStats: false
        )
    }

    private func poll(openAnswers: Bool = true, revotingDisabled: Bool = false, isClosed: Bool = false, hideResults: Bool = false, kind: TelegramMediaPollKind = .poll(multipleAnswers: false), selected: [Int] = []) -> TelegramMediaPoll {
        return TelegramMediaPoll(
            pollId: MediaId(namespace: Namespaces.Media.CloudPoll, id: 1),
            publicity: .public,
            kind: kind,
            text: "Question",
            textEntities: [],
            options: [
                TelegramMediaPollOption(text: "First", entities: [], opaqueIdentifier: Data([0]), date: nil, addedBy: nil),
                TelegramMediaPollOption(text: "Second", entities: [], opaqueIdentifier: Data([1]), date: nil, addedBy: nil)
            ],
            correctAnswers: nil,
            results: results(selected: selected),
            isClosed: isClosed,
            deadlineTimeout: nil,
            deadlineDate: nil,
            pollHash: 0,
            openAnswers: openAnswers,
            revotingDisabled: revotingDisabled,
            hideResultsUntilClose: hideResults
        )
    }

    func testVotedPollKeepsAddOptionWhenRevotingIsAllowed() {
        for kind in kinds {
            let selections = kind == .poll(multipleAnswers: true) ? [[0], [1], [0, 1]] : [[0], [1]]
            for selected in selections {
                let poll = poll(kind: kind, selected: selected)
                XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed))
            }
        }
    }

    func testVotedPollKeepsAddOptionWhenRevotingIsDisabled() {
        for kind in kinds {
            let selections = kind == .poll(multipleAnswers: true) ? [[0], [1], [0, 1]] : [[0], [1]]
            for selected in selections {
                let poll = poll(revotingDisabled: true, kind: kind, selected: selected)
                XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed))
            }
        }
    }

    func testBeforeVotingEitherRevotingModeAllowsAddingOptions() {
        for kind in kinds {
            for revotingDisabled in [false, true] {
                let poll = poll(revotingDisabled: revotingDisabled, kind: kind)
                XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed))
            }
        }
    }

    func testClosedPollNeverAllowsAddingOptions() {
        for revotingDisabled in [false, true] {
            for selected in [[], [0], [1]] {
                let poll = poll(revotingDisabled: revotingDisabled, isClosed: true, selected: selected)
                XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed))
            }
        }
    }

    func testPollWithoutOpenAnswersNeverAllowsAddingOptions() {
        for revotingDisabled in [false, true] {
            for selected in [[], [0], [1]] {
                let poll = poll(openAnswers: false, revotingDisabled: revotingDisabled, selected: selected)
                XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed))
            }
        }
    }

    func testEffectiveClosurePreventsAddingEvenBeforeMediaIsMarkedClosed() {
        for revotingDisabled in [false, true] {
            for selected in [[], [0], [1]] {
                let poll = poll(revotingDisabled: revotingDisabled, selected: selected)
                XCTAssertFalse(poll.isClosed)
                XCTAssertFalse(ChatPollItem.canAddOption(poll: poll, isClosed: true))
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
                XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed))
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
            XCTAssertTrue(ChatPollItem.canAddOption(poll: poll, isClosed: poll.isClosed))
        }
    }
}
