import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

final class AccessEvents {
    var values: [Bool] = []
    var latest: Bool { values.last ?? false }
    func record(_ value: Bool) { values.append(value) }
}

func makeState(verified: Bool = true) -> (LockStateHarness, AccessEvents) {
    let events = AccessEvents()
    return (LockStateHarness(initialUnlockVerified: verified, catalogAccessUpdated: events.record), events)
}

func request(_ id: UUID, _ locked: Bool) -> PasscodeLockRequest {
    PasscodeLockRequest(id: id, shouldLock: locked)
}

func testUnverifiedStartup() {
    let (state, events) = makeState(verified: false)
    require(!events.latest, "Unverified startup must deny access")
    let id = state.beginPasscodeLockRequest()!
    require(state.receivePasscodeLockRequest(request(id, false)), "Current result must be consumed")
    require(!events.latest, "A false timeout or no-passcode result cannot authenticate startup")
    require(state.receivePasscodeLockRequest(request(id, true)), "Lock must be accepted")
    state.completePasscodeLockRequest(request(id, false))
    require(events.latest, "Authenticated unlock must grant access")
}

func testVerifiedStartup() {
    let (_, events) = makeState()
    require(events.values == [false, true], "Only explicit verified startup may grant access")
}

func testDelayedLockAndSettings() {
    let (state, events) = makeState()
    let id = state.beginPasscodeLockRequest()!
    require(!events.latest, "Pending lock must deny access before transaction result")
    require(state.receivePasscodeLockRequest(request(id, true)), "Current lock must be accepted")
    require(state._lockedValue.passcodeLock, "Lock must take effect before settings/UI completion")
    require(!events.latest, "Waiting for settings/UI must retain denial")
    require(state.beginPasscodeLockRequest() == nil, "An established lock cannot be replaced")
    state.completePasscodeLockRequest(request(id, false))
    require(events.latest, "Verified unlock should restore access")
}

func testNoPasscodeRequest() {
    let (state, events) = makeState()
    let id = state.beginPasscodeLockRequest()!
    require(!events.latest, "Even no-passcode requests deny while unresolved")
    require(state.receivePasscodeLockRequest(request(id, false)), "No-passcode result must be accepted")
    require(events.latest, "No-passcode resolution must not leave access permanently denied")
}

func testStaleRequestResults() {
    let (state, events) = makeState()
    let old = state.beginPasscodeLockRequest()!
    let current = state.beginPasscodeLockRequest()!
    require(!state.receivePasscodeLockRequest(request(old, false)), "Stale false must be discarded")
    require(!events.latest, "Stale false must not clear a newer pending denial")
    require(!state.receivePasscodeLockRequest(request(old, true)), "Stale true must also be discarded")
    state.completePasscodeLockRequest(request(old, false))
    require(!events.latest, "Stale unlock completion must be ignored")
    require(state.receivePasscodeLockRequest(request(current, true)), "Newest lock must be accepted")
    require(!state.receivePasscodeLockRequest(request(current, false)), "Queued timer false must not cancel the active unlock listener")
    require(!state.receivePasscodeLockRequest(request(current, true)), "Repeated true must not present another lock controller")
    require(!events.latest && state._lockedValue.passcodeLock, "Timer false cannot clear a real passcode lock")
}

func testScreenUnlockBeforePasscodeResolution() {
    let (state, events) = makeState()
    state.updateLocked { $0.withUpdatedScreenLock(true) }
    let id = state.beginPasscodeLockRequest()!
    state.updateLocked { $0.withUpdatedScreenLock(false) }
    require(!events.latest, "Screen unlock cannot bypass pending Telegram challenge")
    require(state.receivePasscodeLockRequest(request(id, true)), "Telegram lock must still apply")
    require(!events.latest, "Unlocked screen is insufficient for Telegram access")
    state.completePasscodeLockRequest(request(id, false))
    require(events.latest, "Both screen and Telegram unlock restore access")
}

func testScreenLockDuringAuthenticatedUnlock() {
    let (state, events) = makeState()
    let id = state.beginPasscodeLockRequest()!
    require(state.receivePasscodeLockRequest(request(id, true)), "Lock must be consumed")
    state.updateLocked { $0.withUpdatedScreenLock(true) }
    state.completePasscodeLockRequest(request(id, false))
    require(!events.latest, "Passcode success cannot override the screen lock")
    state.updateLocked { $0.withUpdatedScreenLock(false) }
    require(events.latest, "Screen unlock restores access after passcode success")
}

func testLogoutRevokesPendingCompletions() {
    let (state, events) = makeState()
    let id = state.beginPasscodeLockRequest()!
    require(state.receivePasscodeLockRequest(request(id, true)), "Lock must be accepted")
    state.revokeCatalogAccess()
    require(!events.latest, "Logout must revoke immediately")
    state.completePasscodeLockRequest(request(id, false))
    require(!events.latest, "Late authenticated completion cannot undo logout")
    require(!state.receivePasscodeLockRequest(request(id, false)), "Late transaction result must be ignored")
    state.updateLocked { $0.withUpdatedScreenLock(false) }
    require(!events.latest, "Screen updates cannot undo logout")
}

func testCallbackRevocationOrder() {
    let (state, events) = makeState()
    var observed: [Bool] = []
    state.didUpdateLocked = { _ in observed.append(events.latest) }
    let id = state.beginPasscodeLockRequest()!
    require(state.receivePasscodeLockRequest(request(id, true)), "Lock must be accepted")
    require(observed == [false], "Catalog access must revoke before existing UI callbacks")
}

let tests: [(String, () -> Void)] = [
    ("unverified startup", testUnverifiedStartup),
    ("verified startup", testVerifiedStartup),
    ("delayed lock and settings", testDelayedLockAndSettings),
    ("no-passcode request", testNoPasscodeRequest),
    ("stale request results", testStaleRequestResults),
    ("screen unlock before challenge", testScreenUnlockBeforePasscodeResolution),
    ("screen lock during verified unlock", testScreenLockDuringAuthenticatedUnlock),
    ("logout and late completion", testLogoutRevokesPendingCompletions),
    ("callback revocation order", testCallbackRevocationOrder),
]
for (name, test) in tests {
    test()
    print("PASS: \(name)")
}
print("All \(tests.count) Focus lock-state scenarios passed")
