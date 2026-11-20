import Foundation

final class BrowserFindRequestQueue {
    typealias Search = (String, Bool, @escaping (Bool) -> Void) -> Void

    private let search: Search
    var result: ((String, Bool) -> Void)?
    private var query = ""
    private var generation = 0
    private var inFlight = false
    private var isDraining = false
    private var pending: [(query: String, backwards: Bool, generation: Int)] = []
    private var nextIndex = 0

    init(search: @escaping Search) {
        self.search = search
    }

    func enqueue(_ query: String, backwards: Bool) {
        generation += 1
        self.query = query
        pending = [(query, backwards, generation)]
        nextIndex = 0
        performPending()
    }

    func navigate(backwards: Bool) {
        guard !query.isEmpty else { return }
        pending.append((query, backwards, generation))
        performPending()
    }

    private func performPending() {
        guard !inFlight, !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while !inFlight {
            guard nextIndex < pending.count else {
                pending.removeAll(keepingCapacity: true)
                nextIndex = 0
                return
            }
            let request = pending[nextIndex]
            nextIndex += 1
            inFlight = true
            search(request.query, request.backwards) { [self] found in
                inFlight = false
                if generation == request.generation, nextIndex == pending.count {
                    result?(request.query, found)
                }
                performPending()
            }
        }
    }
}
