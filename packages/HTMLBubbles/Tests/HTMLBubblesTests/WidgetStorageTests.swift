import XCTest
import Postbox
import WidgetSandbox
@testable import HTMLBubbles

final class WidgetStorageTests: XCTestCase {
    private func context(basePath: String, peer: Int64 = 1, message: Int32 = 1) -> HTMLWidgetContext {
        let peerId = PeerId(peer)
        return HTMLWidgetContext(accountPeerId: PeerId(100), basePath: basePath, messageId: MessageId(peerId: peerId, namespace: 0, id: message), locale: "en-US")
    }

    func testClearCannotReloadAFileAwaitingDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("widget-storage"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = context(basePath: directory.path)
        let file = directory.appendingPathComponent("widget-storage/\(context.messageId.peerId.toInt64())_0_1.json")
        try JSONSerialization.data(withJSONObject: ["value": "old"]).write(to: file)
        let queue = DispatchQueue(label: "WidgetStorageTests.clear")
        let storage = HTMLWidgetStorage(queue: queue)
        XCTAssertEqual(storage.storage(for: context).local, ["value": "old"])
        let blocked = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        queue.async {
            blocked.signal()
            release.wait()
        }
        blocked.wait()
        storage.removeAll(basePath: directory.path)
        let readStarted = DispatchSemaphore(value: 0)
        let readFinished = DispatchSemaphore(value: 0)
        let result = expectation(description: "cleared storage")
        DispatchQueue.global().async {
            readStarted.signal()
            XCTAssertEqual(storage.storage(for: context).local, [:])
            readFinished.signal()
            result.fulfill()
        }
        readStarted.wait()
        let finishedWhileDeletionWasBlocked = readFinished.wait(timeout: .now() + 0.1)
        release.signal()
        XCTAssertEqual(finishedWhileDeletionWasBlocked, .timedOut)
        wait(for: [result], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCommitAfterClearPersistsTheNewValue() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = DispatchQueue(label: "WidgetStorageTests.commit")
        let storage = HTMLWidgetStorage(queue: queue)
        let context = context(basePath: directory.path)
        storage.commit(.local, values: ["value": "old"], context: context)
        storage.flush(context)
        storage.removeAll(basePath: directory.path)
        storage.commit(.local, values: ["value": "new"], context: context)
        storage.flush(context)
        queue.sync {}
        let reloaded = HTMLWidgetStorage(queue: DispatchQueue(label: "WidgetStorageTests.reload"))
        XCTAssertEqual(reloaded.storage(for: context).local, ["value": "new"])
    }

    func testPeerClearPreservesOtherMessagesAndClearsSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = HTMLWidgetStorage(queue: DispatchQueue(label: "WidgetStorageTests.peers"))
        let first = context(basePath: directory.path)
        let second = context(basePath: directory.path, peer: 2)
        for context in [first, second] {
            storage.commit(.local, values: ["local": "value"], context: context)
            storage.commit(.session, values: ["session": "value"], context: context)
            storage.flush(context)
        }
        storage.removeAll(basePath: directory.path, peerId: first.messageId.peerId)
        XCTAssertEqual(storage.storage(for: first).local, [:])
        XCTAssertEqual(storage.storage(for: first).session, [:])
        XCTAssertEqual(storage.storage(for: second).local, ["local": "value"])
        XCTAssertEqual(storage.storage(for: second).session, ["session": "value"])
    }
}
