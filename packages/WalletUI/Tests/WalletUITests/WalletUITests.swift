import XCTest
import Cocoa
import WalletContext
import TelegramCore
import Postbox
import InputDataUI
import TGUIKit
import TelegramUtils
import SwiftSignalKit
@testable import WalletUI

final class WalletUITests: XCTestCase {
    private let address = "0:" + String(repeating: "0", count: 64)

    override func setUp() {
        super.setUp()
        applyMacEnglishStrings()
    }

    override func tearDown() {
        applyMacEnglishStrings([:])
        super.tearDown()
    }

    private func state(_ phase: WalletContext.Phase = .empty, balance: WalletContext.Resource<Int64> = .idle, fiat: WalletContext.FiatState = .init(selectedCurrency: .usd, rates: .idle)) -> WalletContext.State {
        WalletContext.State(phase: phase, balance: balance, transactions: .init(items: [], offset: 0, canLoadMore: false, isLoadingMore: false, error: nil), pendingTransfers: [], activeOperation: nil, fiat: fiat)
    }

    private func transaction(_ id: String, direction: WalletContext.Transaction.Direction = .outgoing, amount: Int64 = 20_000_000, status: WalletContext.Transaction.Status = .completed, kind: WalletContext.Transaction.Kind = .transfer) -> WalletContext.Transaction {
        .init(id: id, logicalTime: id, timestamp: 0, direction: direction, amount: amount, fee: 0, peer: .unsupported, comment: nil, status: status, kind: kind)
    }

    private func peer(_ id: Int64, title: String) -> EnginePeer {
        .legacyGroup(TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(id)), title: title, photo: [], participantCount: 1, role: .creator(rank: nil), membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0))
    }

    private func sendState() -> WalletSendState {
        var state = WalletSendState()
        state.amount = 1_000_000_000
        state.balance = 2_000_000_000
        state.isLoading = false
        state.resolved = .init(address: address, displayName: "Recipient")
        return state
    }

    private func importState(_ count: Int = 12) -> WalletImportState {
        .init(words: Array(repeating: "", count: count), displayNumbers: Array(1 ... count))
    }

    private func request(messages: [WalletContext.TonConnectOperationRequest.Message]) -> WalletContext.TonConnectOperationRequest {
        .init(id: "request", applicationName: "Test App", domain: "example.test", icon: nil, method: .sendTransaction, messages: messages, feeNanograms: "1", validUntil: nil, relayerWillSubmit: false, needsWalletStateInit: false, warnings: [], actions: [])
    }

    func testListCornersPreserveHeaderAndPagination() {
        XCTAssertEqual(walletListEntries([1], hasLoadMore: false).map(\.viewType), [.singleItem])
        XCTAssertEqual(walletListEntries([1], hasLoadMore: true).map(\.viewType), [.firstItem])
        XCTAssertEqual(walletListEntries([1], hasLoadMore: false, hasHeader: true).map(\.viewType), [.lastItem])
        XCTAssertEqual(walletListEntries([1, 2, 3], hasLoadMore: true, hasHeader: true).map(\.viewType), [.innerItem, .innerItem, .innerItem])
        XCTAssertEqual(walletListEntries([1, 2, 3], hasLoadMore: false).map(\.value), [1, 2, 3])
    }

    func testHistoryFilteringPreservesOrderAndFailedTransfers() {
        let input = [transaction("deploy", kind: .deployContract), transaction("small", direction: .incoming, amount: 1), transaction("out"), transaction("failed", direction: .unknown, status: .failed), transaction("unknown", direction: .unknown), transaction("in", direction: .incoming)]
        XCTAssertEqual(walletVisibleTransactions(input).map(\.id), ["out", "failed", "in"])
    }

    func testHomeEntryIdentityAndDefaultTab() {
        XCTAssertEqual(walletHomeTransactionIdentifier("pending:1"), InputDataIdentifier("_id_transaction_pending:1"))
        XCTAssertEqual(walletHomeCollectibleIdentifier("item"), InputDataIdentifier("_id_collectible_item"))
        XCTAssertNotEqual(walletHomeCollectibleIdentifier("item"), walletHomeTransactionIdentifier("item"))
        var state = WalletHomeState()
        XCTAssertEqual(state.selectedTab, .transactions)
        state.selectedTab = .collectibles
        XCTAssertEqual(state.selectedTab, .collectibles)
    }

    func testCollectibleSuppressionSurvivesRestoringButClearsOnWalletSwitch() {
        var home = WalletHomeState()
        home.walletState = state(.wallet(.init(address: "A", publicKey: "key")))
        home.updateSuppressedCollectibles(previous: nil)
        home.suppressedCollectibleAddresses = ["sent"]
        home.walletState = state(.restoring)
        home.updateSuppressedCollectibles(previous: nil)
        XCTAssertEqual(home.suppressedCollectibleAddresses, ["sent"])
        home.walletState = state(.wallet(.init(address: "A", publicKey: "key")))
        home.updateSuppressedCollectibles(previous: nil)
        XCTAssertEqual(home.suppressedCollectibleAddresses, ["sent"])
        home.walletState = state(.wallet(.init(address: "B", publicKey: "key")))
        home.updateSuppressedCollectibles(previous: nil)
        XCTAssertTrue(home.suppressedCollectibleAddresses.isEmpty)
    }

    func testCollectibleSuppressionClearsForEmptyCreatingAndFailedWallets() {
        for phase: WalletContext.Phase in [.empty, .creating, .failed(.corrupted)] {
            var home = WalletHomeState()
            home.suppressedCollectibleAddresses = ["sent"]
            home.suppressedCollectiblesWalletAddress = "A"
            home.walletState = state(phase)
            home.updateSuppressedCollectibles(previous: nil)
            XCTAssertTrue(home.suppressedCollectibleAddresses.isEmpty)
            XCTAssertNil(home.suppressedCollectiblesWalletAddress)
        }
    }

    func testFiatFallsBackToUsdAndRequiresBalance() {
        let usd = WalletContext.FiatRate(unitsPerUsd: 1, unitsPerGram: 2)
        let eur = WalletContext.FiatRate(unitsPerUsd: 0.9, unitsPerGram: 1.8)
        let balance: WalletContext.Resource<Int64> = .value(1_000_000_000, updatedAt: 0)
        let fallback = state(balance: balance, fiat: .init(selectedCurrency: .eur, rates: .value([.usd: usd], updatedAt: 0)))
        XCTAssertEqual(walletFiatText(fallback), formatTonFiatValue(1_000_000_000, rate: 2, currencySymbol: WalletContext.FiatCurrency.usd.symbol))
        let selected = state(balance: balance, fiat: .init(selectedCurrency: .eur, rates: .value([.usd: usd, .eur: eur], updatedAt: 0)))
        XCTAssertEqual(walletFiatText(selected), formatTonFiatValue(1_000_000_000, rate: 1.8, currencySymbol: WalletContext.FiatCurrency.eur.symbol))
        XCTAssertNil(walletFiatText(state()))
        XCTAssertNil(walletFiatText(state(balance: balance)))
    }

    func testDisplayBalanceHidesDustBelowMilligram() {
        XCTAssertNil(walletDisplayBalance(state()))
        XCTAssertEqual(walletDisplayBalance(state(balance: .value(0, updatedAt: 0))), 0)
        XCTAssertEqual(walletDisplayBalance(state(balance: .value(999_999, updatedAt: 0))), 0)
        XCTAssertEqual(walletDisplayBalance(state(balance: .value(-999_999, updatedAt: 0))), 0)
        XCTAssertEqual(walletDisplayBalance(state(balance: .value(1_000_000, updatedAt: 0))), 1_000_000)
        XCTAssertEqual(walletDisplayBalance(state(balance: .value(2_500_000_000, updatedAt: 0))), 2_500_000_000)

        let usd = WalletContext.FiatRate(unitsPerUsd: 1, unitsPerGram: 2)
        let dust = state(balance: .value(500_000, updatedAt: 0), fiat: .init(selectedCurrency: .usd, rates: .value([.usd: usd], updatedAt: 0)))
        XCTAssertEqual(walletFiatText(dust, balance: walletDisplayBalance(dust)), formatTonFiatValue(0, rate: 2, currencySymbol: WalletContext.FiatCurrency.usd.symbol, maxDecimalPositions: 0))
        XCTAssertEqual(walletFiatText(dust, balance: 1_000_000_000), formatTonFiatValue(1_000_000_000, rate: 2, currencySymbol: WalletContext.FiatCurrency.usd.symbol))
        XCTAssertNil(walletFiatText(dust, balance: nil))
    }

    func testRecipientTransferLinkExtractsAmountAndComment() {
        let parsed = walletParseRecipient("  ton://transfer/\(address)?amount=1000000001&text=hello%20world  ")
        XCTAssertEqual(parsed.address, address)
        XCTAssertEqual(parsed.amount, 1_000_000_001)
        XCTAssertEqual(parsed.comment, "hello world")
        XCTAssertEqual(walletParseRecipient("  alice.ton  ").address, "alice.ton")
    }

    func testRecipientRejectsNonpositiveAndOverflowLinkAmounts() {
        for value in ["0", "-1", "999999999999999999999", "oops"] {
            XCTAssertNil(walletParseRecipient("ton://transfer/\(address)?amount=\(value)").amount)
        }
        XCTAssertNil(walletParseRecipient("ton://transfer/\(address)?text=").comment)
    }

    func testRecipientSearchShowsOnlySearchResultsAndDeduplicates() {
        let alice = peer(1, title: "Alice Example")
        let bob = peer(2, title: "Bob")
        var state = WalletRecipientState()
        state.address = "ex"
        state.recentPeers = [alice, bob]
        XCTAssertTrue(walletMatchingPeers(state).isEmpty)
        state.localSearchResults = [bob, bob, alice]
        XCTAssertEqual(walletMatchingPeers(state).map(\.id), [bob.id, alice.id])
    }

    func testRecipientListShowsRecentPeersWithoutQueryAndCapsThirtyPeers() {
        let stale = peer(99, title: "Stale")
        var state = WalletRecipientState()
        state.localSearchResults = [stale]
        state.recentPeers = (1...40).map { peer(Int64($0), title: "Peer \($0)") }
        XCTAssertEqual(walletMatchingPeers(state).count, 30)
        XCTAssertFalse(walletMatchingPeers(state).contains { $0.id == stale.id })
        state.resolved = .init(address: address, displayName: nil)
        XCTAssertTrue(walletMatchingPeers(state).isEmpty)
    }

    func testTonDomainRecipientValidation() {
        XCTAssertTrue(walletNeedsRecipientResolution(address))
        XCTAssertTrue(walletNeedsRecipientResolution(" alice.ton "))
        XCTAssertTrue(walletNeedsRecipientResolution("name.t.me"))
        XCTAssertFalse(walletNeedsRecipientResolution(""))
        XCTAssertFalse(walletNeedsRecipientResolution("bad name.ton"))
        var state = WalletRecipientState()
        state.address = "alice.ton"
        XCTAssertFalse(walletRecipientAddressLooksInvalid(state))
    }

    func testAmountPrecisionLocaleAndOverflow() {
        XCTAssertEqual(walletSendNanograms(text: "1.000000001", mode: .gram, rate: nil, decimalSeparator: "."), 1_000_000_001)
        XCTAssertEqual(walletSendNanograms(text: "0,000000001", mode: .gram, rate: nil, decimalSeparator: ","), 1)
        XCTAssertNil(walletSendNanograms(text: "1.0000000001", mode: .gram, rate: nil, decimalSeparator: "."))
        XCTAssertNil(walletSendNanograms(text: "9223372037", mode: .gram, rate: nil, decimalSeparator: "."))
        XCTAssertNil(walletSendNanograms(text: "-1", mode: .gram, rate: nil, decimalSeparator: "."))
        XCTAssertEqual(walletSendNanograms(text: "", mode: .gram, rate: nil, decimalSeparator: "."), 0)
    }

    func testFiatAmountsRequireFinitePositiveRate() {
        XCTAssertEqual(walletSendNanograms(text: "2", mode: .fiat, rate: 2, decimalSeparator: "."), 1_000_000_000)
        for rate in [0, -1, Double.infinity, Double.nan] {
            XCTAssertNil(walletSendNanograms(text: "2", mode: .fiat, rate: rate, decimalSeparator: "."))
        }
        XCTAssertNil(walletSendNanograms(text: "2", mode: .fiat, rate: nil, decimalSeparator: "."))
    }

    func testSendValidationBlocksLoadingResolvingAndDuplicateSubmission() {
        var state = sendState()
        XCTAssertTrue(walletCanSend(state))
        state.isSending = true
        XCTAssertFalse(walletCanSend(state))
        state.isSending = false
        state.isResolvingSigningAccess = true
        XCTAssertFalse(walletCanSend(state))
        state.isResolvingSigningAccess = false
        state.isLoading = true
        XCTAssertFalse(walletCanSend(state))
        state.isLoading = false
        state.resolved = nil
        XCTAssertFalse(walletCanSend(state))
    }

    func testSendAllIsOnlyForManualExactBalance() {
        var state = sendState()
        state.amount = state.balance!
        XCTAssertTrue(walletShouldSendAll(state))
        state.amountSource = .transferLink
        XCTAssertFalse(walletShouldSendAll(state))
        state.amountSource = .manual
        state.amount += 1
        XCTAssertTrue(walletSendIsInsufficient(state))
        XCTAssertFalse(walletCanSend(state))
        state.isLoading = true
        XCTAssertFalse(walletSendIsInsufficient(state))
    }

    func testSendAllIsSkippedWhenGaslessCoversFees() {
        var state = sendState()
        state.amount = state.balance!
        state.gaslessMinAmount = 1_000_000_000
        state.gaslessInfo = WalletGaslessInfo(available: true, left: 5, resetAt: 0, minAmount: 1_000_000_000, relayerAddress: address)
        XCTAssertFalse(walletShouldSendAll(state))
        state.gaslessInfo = WalletGaslessInfo(available: true, left: 0, resetAt: 0, minAmount: 1_000_000_000, relayerAddress: address)
        XCTAssertTrue(walletShouldSendAll(state))
        state.gaslessInfo = WalletGaslessInfo(available: true, left: 5, resetAt: 0, minAmount: 3_000_000_000, relayerAddress: address)
        XCTAssertTrue(walletShouldSendAll(state))
        state.gaslessInfo = WalletGaslessInfo(available: true, left: 5, resetAt: 0, minAmount: 1_000_000_000, relayerAddress: address)
        state.walletPhase = .wallet(WalletContext.WalletInfo(address: address, publicKey: "key"))
        state.walletAddress = address
        XCTAssertTrue(walletShouldSendAll(state))
    }

    func testCommentsPreserveContentButTrimEmptyEdges() {
        XCTAssertNil(walletTransactionComment(nil))
        XCTAssertNil(walletTransactionComment(" \n "))
        XCTAssertEqual(walletTransactionComment("  hello\nworld  "), "hello\nworld")
    }

    func testTransferPreviewKindsAndFailureSubtitles() {
        let incoming = WalletTransferPresentation.PreviewItem(id: "in", kind: .transfer, direction: .incoming, address: nil, amount: "1", comment: nil, succeeded: true)
        XCTAssertEqual(walletTransferPreviewRowContent(incoming).subtitle, "Deposit")
        let outgoing = WalletTransferPresentation.PreviewItem(id: "out", kind: .transfer, direction: .outgoing, address: nil, amount: "1", comment: nil, succeeded: false)
        XCTAssertEqual(walletTransferPreviewRowContent(outgoing).subtitle, "Withdrawal · Failed")
        let contract = WalletTransferPresentation.PreviewItem(id: "call", kind: .callContract, direction: nil, address: nil, amount: nil, comment: nil, succeeded: false)
        XCTAssertEqual(walletTransferPreviewRowContent(contract).title, "Call Contract")
        XCTAssertEqual(walletTransferPreviewRowContent(contract).subtitle, "Failed")
    }

    func testDetachedSubmissionWaitsForBothRequestAndObservation() {
        var state = WalletDetachedSubmissionState()
        state.submitCompleted = true
        XCTAssertFalse(state.shouldCleanUp)
        XCTAssertEqual(state.observe(matchesWallet: true, status: .pending, hasTransfer: true), .none)
        XCTAssertTrue(state.hasObservedTransfer)
        XCTAssertEqual(state.observe(matchesWallet: true, status: .completed, hasTransfer: true), .completed)
        state.observationStopped = true
        XCTAssertTrue(state.shouldCleanUp)
        XCTAssertEqual(state.observe(matchesWallet: true, status: .completed, hasTransfer: true), .none)
    }

    func testDetachedSubmissionStopsForFailureDisappearanceOrWalletChange() {
        var state = WalletDetachedSubmissionState()
        XCTAssertEqual(state.observe(matchesWallet: true, status: nil, hasTransfer: false), .none)
        XCTAssertEqual(state.observe(matchesWallet: true, status: .pending, hasTransfer: true), .none)
        XCTAssertEqual(state.observe(matchesWallet: true, status: nil, hasTransfer: false), .stop)
        XCTAssertEqual(state.observe(matchesWallet: false, status: .completed, hasTransfer: true), .stop)
        XCTAssertEqual(state.observe(matchesWallet: true, status: .failed, hasTransfer: true), .stop)
        state.observationStopped = true
        XCTAssertFalse(state.shouldCleanUp)
    }

    func testRecoveryNormalizationAndWordIdentifiers() {
        XCTAssertEqual(walletRecoveryWords("  ALPHA, beta\n\tGamma  "), ["alpha", "beta", "gamma"])
        XCTAssertEqual(walletWordFieldIndex(of: walletWordIdentifier(23)), 23)
        XCTAssertNil(walletWordFieldIndex(of: InputDataIdentifier("unrelated")))
    }

    func testRecoveryPasteStripsNumberingBulletsAndQuotes() {
        let words = ["spirit", "sock", "salmon", "echo", "canvas", "gorilla", "bicycle", "frozen", "pencil", "orbit", "candy", "muffin"]
        let numbered: [(Int, String) -> String] = [
            { "\($0). \($1)" },
            { "\($0).\($1)" },
            { "\($0)) \($1)" },
            { "(\($0)) \($1)" },
            { "[\($0)] \($1)" },
            { "\($0): \($1)" },
            { "\($0) \($1)" }
        ]
        for format in numbered {
            let text = words.enumerated().map { format($0.offset + 1, $0.element) }.joined(separator: "\n")
            XCTAssertEqual(walletRecoveryWords(text), words)
        }
        XCTAssertEqual(walletRecoveryWords(words.map { "• \($0)" }.joined(separator: "\n")), words)
        XCTAssertEqual(walletRecoveryWords(words.map { "“\($0)”" }.joined(separator: "; ")), words)
        XCTAssertEqual(walletRecoveryWords("\"spirit\""), ["spirit"])
        XCTAssertEqual(walletRecoveryWords("• — 12. ;"), [])
        XCTAssertEqual(walletRecoveryWords("2"), [])
    }

    func testRecoveryPasteReordersOnlyCompleteNumberedLists() {
        let words = ["spirit", "sock", "salmon", "echo", "canvas", "gorilla", "bicycle", "frozen", "pencil", "orbit", "candy", "muffin"]
        let rowOrder = [1, 7, 2, 8, 3, 9, 4, 10, 5, 11, 6, 12]
        XCTAssertEqual(walletRecoveryWords(rowOrder.map { "\($0). \(words[$0 - 1])" }.joined(separator: " ")), words)
        let incomplete = rowOrder.dropLast().map { "\($0). \(words[$0 - 1])" }.joined(separator: " ") + " muffin"
        XCTAssertEqual(walletRecoveryWords(incomplete), rowOrder.dropLast().map { words[$0 - 1] } + ["muffin"])
    }

    func testRecoveryPasteFilterReplacesOnlyForSeveralWords() {
        XCTAssertTrue(walletRecoveryPasteFilter("1. spirit 2. sock") == (true, "spirit sock"))
        XCTAssertTrue(walletRecoveryPasteFilter("“Spirit”") == (false, "spirit"))
        XCTAssertTrue(walletRecoveryPasteFilter("•") == (false, ""))
    }

    func testRecoveryPasteSelectsTwelveOrTwentyFourFields() {
        for count in [12, 24] {
            var state = importState()
            state.suggestions = .init(index: 0, words: ["old"])
            let words = (0..<count).map { "word\($0)" }
            let result = walletDistributeRecoveryWords(&state, index: 4, words: words, verification: false)
            XCTAssertEqual(result, .inserted(0..<count))
            XCTAssertEqual(state.words, words)
            XCTAssertEqual(state.displayNumbers, Array(1...count))
            XCTAssertNil(state.suggestions)
        }
    }

    func testInvalidRecoveryPasteLeavesWordsAndClearsSuggestions() {
        var state = importState()
        state.suggestions = .init(index: 0, words: ["old"])
        XCTAssertEqual(walletDistributeRecoveryWords(&state, index: 0, words: ["one", "two"], verification: false), .invalidCount)
        XCTAssertEqual(state.words.count, 12)
        XCTAssertTrue(state.words.allSatisfy(\.isEmpty))
        XCTAssertNil(state.suggestions)
    }

    func testVerificationPasteTruncatesAndPreservesDisplayedNumbers() {
        var state = WalletImportState(words: ["", "", ""], displayNumbers: [2, 8, 11])
        state.mismatchedIndices = [1, 2]
        XCTAssertEqual(walletDistributeRecoveryWords(&state, index: 1, words: ["a", "b", "c"], verification: true), .inserted(1..<3))
        XCTAssertEqual(state.words, ["", "a", "b"])
        XCTAssertEqual(state.displayNumbers, [2, 8, 11])
        XCTAssertTrue(state.mismatchedIndices.isEmpty)
        XCTAssertEqual(walletDistributeRecoveryWords(&state, index: 0, words: ["first"], verification: true), .inserted(0..<1))
    }

    func testPhraseValidationDistinguishesVerificationFromImport() {
        var state = importState()
        XCTAssertFalse(walletIsPhraseValid(state, verification: true, isMnemonicWord: { _ in true }))
        state.words = [" alpha ", "beta"]
        XCTAssertTrue(walletIsPhraseValid(state, verification: true, isMnemonicWord: { _ in false }))
        XCTAssertFalse(walletIsPhraseValid(state, verification: false, isMnemonicWord: { $0 == "beta" }))
        state.words = ["alpha", "beta"]
        XCTAssertTrue(walletIsPhraseValid(state, verification: false, isMnemonicWord: { _ in true }))
        state.isImporting = true
        XCTAssertFalse(walletIsPhraseValid(state, verification: false, isMnemonicWord: { _ in true }))
    }

    func testImportReadinessFollowsWalletPhaseAndActiveOperation() {
        var input = importState()
        input.words = Array(repeating: "alpha", count: 12)
        for phase: WalletContext.Phase in [.empty, .wallet(.init(address: address, publicKey: "key")), .failed(.corrupted)] {
            XCTAssertTrue(walletCanSubmitImport(input, walletState: state(phase), isMnemonicWord: { _ in true }))
        }
        for phase: WalletContext.Phase in [.restoring, .creating] {
            XCTAssertFalse(walletCanSubmitImport(input, walletState: state(phase), isMnemonicWord: { _ in true }))
        }
        let busy = WalletContext.State(phase: .empty, balance: .idle, transactions: .init(items: [], offset: 0, canLoadMore: false, isLoadingMore: false, error: nil), pendingTransfers: [], activeOperation: .disablingBackup)
        XCTAssertFalse(walletCanSubmitImport(input, walletState: busy, isMnemonicWord: { _ in true }))
    }

    func testDetachedSuccessCanOnlyBePresentedOnce() {
        var state = WalletDetachedSubmissionState()
        XCTAssertTrue(state.beginPresentingSuccess())
        XCTAssertFalse(state.beginPresentingSuccess())
    }

    func testEmptyVerificationPasteDoesNotClearSuggestions() {
        var state = importState()
        state.suggestions = .init(index: 0, words: ["alpha"])
        XCTAssertEqual(walletDistributeRecoveryWords(&state, index: 0, words: [], verification: true), .unchanged)
        XCTAssertEqual(state.suggestions?.words, ["alpha"])
    }

    func testAuthorizationCompletionIsSingleAndReentrantSafe() {
        var results: [Bool] = []
        var completion: WalletUICompletion<Bool>!
        completion = WalletUICompletion { result in
            results.append(result)
            completion.finish(false)
        }
        completion.finish(true)
        completion.finish(false)
        XCTAssertEqual(results, [true])
    }

    func testAuthorizationCancellationWinsIfItFinishesFirst() {
        var results: [Bool] = []
        let completion = WalletUICompletion<Bool> { results.append($0) }
        completion.finish(false)
        completion.finish(true)
        XCTAssertEqual(results, [false])
    }

    func testRemovedPasswordRetriesExactlyOnce() {
        var retry = WalletPasswordRetryState()
        XCTAssertTrue(retry.consumeRemovedPasswordRetry())
        XCTAssertFalse(retry.consumeRemovedPasswordRetry())
        XCTAssertFalse(retry.consumeRemovedPasswordRetry())
    }

    func testAuthorizationDisposalStopsRequestBeforeQueuedPromptDismissal() {
        let handle = WalletAuthorizedOperationHandle()
        var events: [String] = []
        var pending: (() -> Void)?
        handle.operationDisposable.set(ActionDisposable { events.append("dispose request") })
        handle.dismissPrompt = {
            XCTAssertTrue(handle.finished)
            events.append("dismiss prompt")
        }
        handle.dispose(enqueue: { pending = $0 })
        XCTAssertEqual(events, ["dispose request"])
        XCTAssertFalse(handle.finished)
        pending?()
        XCTAssertEqual(events, ["dispose request", "dismiss prompt"])
        XCTAssertNil(handle.dismissPrompt)
        handle.dispose(enqueue: { $0() })
        XCTAssertEqual(events, ["dispose request", "dismiss prompt"])
    }

    func testAuthorizationErrorsKeepSpecificRecoveryAndSecurityMessages() {
        XCTAssertEqual(walletAuthorizationErrorMessage(.twoStepAuthMissing)?.title, "Two-Step Verification Required")
        XCTAssertEqual(walletAuthorizationErrorMessage(.passwordTooFresh(30))?.text, "Try again in \(timeIntervalString(30)).")
        XCTAssertEqual(walletAuthorizationErrorMessage(.keyRotationFailed)?.title, "Couldn’t Update Secret Phrase")
        XCTAssertEqual(walletAuthorizationErrorMessage(.commentEncryptionRecipientUnavailable)?.title, "Couldn’t Encrypt Comment")
        XCTAssertNil(walletAuthorizationErrorMessage(.authorizationCancelled))
        XCTAssertNil(walletAuthorizationErrorMessage(.network))
    }

    func testTonConnectSubjectAndMessageOrder() {
        let messages: [WalletContext.TonConnectOperationRequest.Message] = [
            .init(id: "first", destination: address, amountNanograms: "1000000001", payload: .comment("hello"), stateInit: nil),
            .init(id: "second", destination: address, amountNanograms: "2", payload: .raw("data"), stateInit: nil)
        ]
        let operation = request(messages: messages)
        let subject = WalletTonConnectSubject.operation(operation)
        XCTAssertEqual(subject.id, "request")
        XCTAssertEqual(subject.applicationName, "Test App")
        let presentation = WalletTransferPresentation(request: operation, walletState: nil)
        XCTAssertEqual(presentation.amountNanograms, "1000000003")
        XCTAssertEqual(presentation.previewItems.map(\.id), ["first", "second"])
        XCTAssertEqual(presentation.previewItems.map(\.kind), [.transfer, .callContract])
        XCTAssertEqual(presentation.previewItems.first?.comment, "hello")
        XCTAssertEqual(walletTonConnectViewType(index: 0, count: 1), .singleItem)
        XCTAssertEqual(walletTonConnectViewType(index: 1, count: 3), .innerItem)
    }

    func testTonConnectSuccessFinishesBeforeCloseAndConnectionNotification() {
        var events: [String] = []
        var approve: ((Result<Void, WalletContext.WalletError>) -> Void)?
        walletBeginTonConnectApproval(isProcessing: false, requiresAuthorization: false, setProcessing: { events.append("processing:\($0)") }, approve: { approve = $0; events.append("approve") }, finish: { events.append("finish") }, close: { events.append("close") }, connectionSucceeded: { events.append("notification") }, failure: { XCTFail() })
        XCTAssertEqual(events, ["processing:true", "approve"])
        approve?(.success(()))
        XCTAssertEqual(events, ["processing:true", "approve", "finish", "close", "notification"])
    }

    func testTonConnectDuplicateSubmitDoesNothing() {
        walletBeginTonConnectApproval(isProcessing: true, requiresAuthorization: false, setProcessing: { _ in XCTFail() }, approve: { _ in XCTFail() }, finish: { XCTFail() }, close: { XCTFail() }, connectionSucceeded: { XCTFail() }, failure: { XCTFail() })
    }

    func testTonConnectOperationApprovalOmitsConnectionToast() {
        var events: [String] = []
        walletBeginTonConnectApproval(isProcessing: false, requiresAuthorization: true, setProcessing: { _ in events.append("processing") }, approve: { callback in events.append("approve"); callback(.success(())) }, finish: { events.append("finish") }, close: { events.append("close") }, connectionSucceeded: { XCTFail() }, failure: { XCTFail() })
        XCTAssertEqual(events, ["processing", "approve", "finish", "close"])
    }

    func testTonConnectErrorsAllowRetryAndSuppressCancellationAlert() {
        for error: WalletContext.WalletError in [.network, .authorizationCancelled] {
            var processing: [Bool] = []
            var alerts = 0
            walletBeginTonConnectApproval(isProcessing: false, requiresAuthorization: false, setProcessing: { processing.append($0) }, approve: { $0(.failure(error)) }, finish: { XCTFail() }, close: { XCTFail() }, connectionSucceeded: { XCTFail() }, failure: { alerts += 1 })
            XCTAssertEqual(processing, [true, false])
            XCTAssertEqual(alerts, error == .network ? 1 : 0)
        }
    }

    func testTonConnectRejectionRunsOnceAndStillClosesAfterSuccess() {
        let completion = WalletTonConnectCompletion()
        var events: [String] = []
        completion.rejectAndClose(cancelled: { events.append("reject"); completion.finish() }, close: { events.append("close") })
        completion.rejectAndClose(cancelled: { XCTFail() }, close: { events.append("close") })
        XCTAssertEqual(events, ["reject", "close", "close"])
    }

    func testTonConnectExternalDismissalClosesOnceWithoutRejecting() {
        let completion = WalletTonConnectCompletion()
        var closes = 0
        completion.dismiss {
            closes += 1
            completion.rejectAndClose(cancelled: { XCTFail() }, close: {})
        }
        completion.dismiss { XCTFail() }
        XCTAssertEqual(closes, 1)
        let approved = WalletTonConnectCompletion()
        approved.finish()
        approved.dismiss { XCTFail() }
    }
}
