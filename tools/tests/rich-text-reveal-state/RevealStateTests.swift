import Foundation

__DECLARATION__

final class Item {
    let stableId: AnyHashable
    let isStreaming = false
    init(_ id: Int) { stableId = id }

__GETTER__
}

func store(item: Item, seed: Int) {
__STORE__
}

func remove(item: Item) {
__REMOVE__
}

let iterations = 10000
DispatchQueue.concurrentPerform(iterations: 2) { worker in
    let item = Item(worker)
    for count in 0 ..< iterations {
        if worker % 2 == 0 {
            store(item: item, seed: count)
            precondition(item.isRevealAnimationActive)
            remove(item: item)
            precondition(!item.isRevealAnimationActive)
        } else {
            _ = Item(worker - 1).isRevealAnimationActive
        }
    }
    store(item: item, seed: iterations)
}
for worker in 0 ..< 2 {
    let item = Item(worker)
    precondition(item.isRevealAnimationActive)
    remove(item: item)
    precondition(!item.isRevealAnimationActive)
}
print("PASS 20000 concurrent iterations; all final cursors retained and removed")
