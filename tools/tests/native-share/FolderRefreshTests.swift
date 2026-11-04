let context = AccountContext()
let stream = shareFolderPreferences(context: context)
var snapshots: [ChatListFolders] = []
let first = stream.start(next: { snapshots.append($0) })
assert(snapshots.last?.list.first?.title == "Old")
assert(context.engine.peers.requests == 1 && context.engine.peers.activeRequests == 1)

let renamed = [ChatListFilter(id: 2, title: "Renamed ⭐️"), ChatListFilter(id: 3, title: "New")]
context.engine.peers.remote.putNext(renamed)
assert(snapshots.last?.list == renamed)
let renamedCount = snapshots.count
context.engine.peers.remote.putNext(renamed)
assert(snapshots.count == renamedCount)

context.engine.cached.set(ChatListFolders(list: [ChatListFilter(id: 2, title: "Stale")], sidebar: true, showTags: true))
assert(snapshots.last?.list == renamed)
assert(snapshots.last?.sidebar == true && snapshots.last?.showTags == true)
first.dispose()
assert(context.engine.peers.activeRequests == 0)
let closedCount = snapshots.count
context.engine.peers.remote.putNext([])
assert(snapshots.count == closedCount)

let second = stream.start(next: { snapshots.append($0) })
assert(context.engine.peers.requests == 2 && context.engine.peers.activeRequests == 1)
context.engine.peers.remote.putNext([ChatListFilter(id: 2, title: "Latest")])
assert(snapshots.last?.list.first?.title == "Latest")
second.dispose()
assert(context.engine.peers.activeRequests == 0)
print("Native share folder refresh and subscription cleanup tests passed")
