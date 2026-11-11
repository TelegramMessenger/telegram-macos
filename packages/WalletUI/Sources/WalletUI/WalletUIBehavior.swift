import Foundation
import WalletContext

@available(macOS 10.15, *)
func walletVisibleTransactions(_ transactions: [WalletContext.Transaction]) -> [WalletContext.Transaction] {
    return transactions.filter { $0.isVisibleInWalletHistory && $0.kind != .deployContract }
}

let walletCommentMaximumBytes = 960

@available(macOS 10.15, *)
func walletDisableBackupRequiresTopUp(_ state: WalletContext.State) -> Bool {
    guard let balance = state.balance.currentValue else {
        return false
    }
    return balance < 500_000
}

func walletCommentInputFilter(_ text: String) -> String {
    guard text.utf8.count > walletCommentMaximumBytes else {
        return text
    }
    var result = ""
    var bytes = 0
    for character in text {
        let count = character.utf8.count
        if bytes + count > walletCommentMaximumBytes {
            break
        }
        result.append(character)
        bytes += count
    }
    return result
}

func walletRecoveryWords(_ value: String) -> [String] {
    let quotes = CharacterSet(charactersIn: "\"'“”‘’«»")
    let leadingFormatting = "•-–—*\"'“”‘’«»"
    func stripFormatting(_ token: String) -> String {
        return String(token.drop(while: { leadingFormatting.contains($0) })).trimmingCharacters(in: quotes)
    }

    var words: [(number: Int?, word: String)] = []
    var pendingNumber: Int?
    var hasExtraNumbers = false
    for sourceToken in value.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }) {
        var token = stripFormatting(String(sourceToken))
        guard !token.isEmpty else {
            continue
        }

        var numberToken = token[...]
        let closingBracket: Character?
        if numberToken.first == "(" {
            closingBracket = ")"
            numberToken = numberToken.dropFirst()
        } else if numberToken.first == "[" {
            closingBracket = "]"
            numberToken = numberToken.dropFirst()
        } else {
            closingBracket = nil
        }
        let digits = numberToken.prefix(while: { ("0" ... "9").contains($0) })
        if !digits.isEmpty {
            let suffix = numberToken.dropFirst(digits.count)
            var wordAfterNumber: Substring?
            if let closingBracket {
                if suffix.first == closingBracket {
                    wordAfterNumber = suffix.dropFirst()
                }
            } else if suffix.isEmpty {
                wordAfterNumber = suffix
            } else if suffix.first == "." || suffix.first == ")" || suffix.first == ":" {
                wordAfterNumber = suffix.dropFirst()
            }
            if let wordAfterNumber {
                if pendingNumber != nil {
                    hasExtraNumbers = true
                }
                pendingNumber = Int(digits) ?? 0
                token = stripFormatting(String(wordAfterNumber))
            }
        }

        if !token.isEmpty {
            words.append((number: pendingNumber, word: token.lowercased()))
            pendingNumber = nil
        }
    }

    if (words.count == 12 || words.count == 24) && !hasExtraNumbers && pendingNumber == nil {
        let numbers = Set(words.compactMap { $0.number })
        if numbers == Set(1 ... words.count) {
            words.sort { ($0.number ?? 0) < ($1.number ?? 0) }
        }
    }
    return words.map { $0.word }
}

func walletRecoveryPasteFilter(_ value: String) -> (Bool, String) {
    let words = walletRecoveryWords(value)
    return (words.count > 1, words.joined(separator: " "))
}

enum WalletRecoveryPasteResult: Equatable {
    case unchanged
    case invalidCount
    case inserted(Range<Int>)
}

func walletDistributeRecoveryWords(_ state: inout WalletImportState, index: Int, words: [String], verification: Bool) -> WalletRecoveryPasteResult {
    if verification {
        let inserted = Array(words.prefix(state.words.count - index))
        guard !inserted.isEmpty else { return .unchanged }
        for offset in inserted.indices {
            state.words[index + offset] = inserted[offset]
            state.mismatchedIndices.remove(index + offset)
        }
        state.suggestions = nil
        return .inserted(index ..< index + inserted.count)
    }
    guard words.count == 12 || words.count == 24 else {
        state.suggestions = nil
        return .invalidCount
    }
    state.words = words
    state.displayNumbers = Array(1 ... words.count)
    state.suggestions = nil
    return .inserted(0 ..< words.count)
}

final class WalletUICompletion<Value> {
    private var completion: ((Value) -> Void)?

    init(_ completion: @escaping (Value) -> Void) {
        self.completion = completion
    }

    func finish(_ value: Value) {
        guard let completion = self.completion else { return }
        self.completion = nil
        completion(value)
    }
}

struct WalletPasswordRetryState {
    private var retriedWithoutRemovedPassword = false

    mutating func consumeRemovedPasswordRetry() -> Bool {
        guard !retriedWithoutRemovedPassword else { return false }
        retriedWithoutRemovedPassword = true
        return true
    }
}

struct WalletDetachedSubmissionState {
    var submitCompleted = false
    var observationStopped = false
    var hasObservedTransfer = false
    var successPresented = false

    var shouldCleanUp: Bool { submitCompleted && observationStopped }

    mutating func beginPresentingSuccess() -> Bool {
        guard !successPresented else { return false }
        successPresented = true
        return true
    }

    enum Observation: Equatable {
        case none
        case stop
        case completed
    }

    @available(macOS 10.15, *)
    mutating func observe(matchesWallet: Bool, status: WalletContext.Transaction.Status?, hasTransfer: Bool) -> Observation {
        guard !observationStopped else { return .none }
        guard matchesWallet else { return .stop }
        if status == .completed {
            return .completed
        } else if status == .failed || (hasObservedTransfer && !hasTransfer) {
            return .stop
        } else if hasTransfer {
            hasObservedTransfer = true
        }
        return .none
    }
}

@available(macOS 10.15, *)
func walletBeginTonConnectApproval(isProcessing: Bool, requiresAuthorization: Bool, setProcessing: @escaping (Bool) -> Void, approve: @escaping (@escaping (Result<Void, WalletContext.WalletError>) -> Void) -> Void, finish: @escaping () -> Void, close: @escaping () -> Void, connectionSucceeded: @escaping () -> Void, failure: @escaping () -> Void) {
    guard !isProcessing else { return }
    setProcessing(true)
    let performApproval: () -> Void = {
        approve { result in
            switch result {
            case .success:
                finish()
                close()
                if !requiresAuthorization {
                    connectionSucceeded()
                }
            case let .failure(error):
                setProcessing(false)
                if error != .authorizationCancelled {
                    failure()
                }
            }
        }
    }
    performApproval()
}

final class WalletTonConnectCompletion {
    private var finished = false

    func finish() {
        finished = true
    }

    func dismiss(close: () -> Void) {
        guard !finished else {
            return
        }
        finished = true
        close()
    }

    func rejectAndClose(cancelled: () -> Void, close: () -> Void) {
        if !finished {
            finished = true
            cancelled()
        }
        close()
    }
}

struct WalletTonConnectInputGate {
    private(set) var acceptsInputAfter: TimeInterval = 0

    mutating func appear(now: TimeInterval, delay: TimeInterval) {
        acceptsInputAfter = now + max(0, delay)
    }

    func allowsInput(now: TimeInterval) -> Bool {
        now >= acceptsInputAfter
    }
}
