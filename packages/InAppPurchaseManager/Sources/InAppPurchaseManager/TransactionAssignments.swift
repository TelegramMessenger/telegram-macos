import Foundation

struct TransactionAssignments {
    enum Status: Equatable {
        case new
        case inProgress
        case finished
    }

    private var inProgress = Set<String>()
    private var finished = Set<String>()

    func status(of transactionId: String?) -> Status {
        guard let transactionId else {
            return .new
        }
        if self.inProgress.contains(transactionId) {
            return .inProgress
        }
        if self.finished.contains(transactionId) {
            return .finished
        }
        return .new
    }

    mutating func begin(_ transactionIds: [String]) {
        self.inProgress.formUnion(transactionIds)
    }

    mutating func end(_ transactionIds: [String]) {
        self.inProgress.subtract(transactionIds)
        self.finished.formUnion(transactionIds)
    }
}
