import Foundation

final class BrowserFindRequestQueue {
    typealias Search = (String, Bool, @escaping (Bool) -> Void) -> Void

    private let search: Search
    var result: ((String, Bool) -> Void)?
    private var generation = 0
    private var inFlight = false
    private var pending: (query: String, backwards: Bool, generation: Int)?

    init(search: @escaping Search) {
        self.search = search
    }

    func enqueue(_ query: String, backwards: Bool) {
        generation += 1
        pending = (query, backwards, generation)
        performPending()
    }

    private func performPending() {
        guard !inFlight, let request = pending else { return }
        pending = nil
        inFlight = true
        search(request.query, request.backwards) { [self] found in
            inFlight = false
            if generation == request.generation {
                result?(request.query, found)
            }
            performPending()
        }
    }
}
