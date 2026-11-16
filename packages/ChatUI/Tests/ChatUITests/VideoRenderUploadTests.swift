import Foundation
import XCTest
import SwiftSignalKit
import TelegramMediaResources
@testable import TelegramMediaUtils

final class VideoRenderUploadTests: XCTestCase {
    private func file(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("video-upload-test-" + UUID().uuidString)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func record(_ state: inout VideoRenderUploadState, event: PendingVideoRenderEvent, path: String, bytes: inout Data, completions: inout Int) throws {
        try state.update(event, finalPath: path) { chunk in
            switch chunk {
            case let .data(offset, data):
                XCTAssertEqual(Int(offset), bytes.count)
                bytes.append(data)
            case let .header(data):
                bytes.replaceSubrange(0 ..< data.count, with: data)
            case let .complete(size):
                XCTAssertEqual(Int(size), bytes.count)
                completions += 1
            case let .completeFile(path):
                bytes = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
                completions += 1
            }
        }
    }

    func testLargeVideoPublishesBodyBeforeCompletionAndReplacesEntireReservedHeader() throws {
        let header = 1024 * 1024 + 48
        var source = Data(repeating: 0x31, count: 12 * 1024 * 1024)
        let url = try file(source)
        var state = VideoRenderUploadState()
        var received = Data()
        var completions = 0
        try record(&state, event: .progress(path: url.path, size: Int64(source.count), headerSize: Int64(header)), path: url.path, bytes: &received, completions: &completions)
        XCTAssertGreaterThan(received.count, header)
        XCTAssertEqual(completions, 0)
        XCTAssertFalse(state.isComplete)
        let body = received.subdata(in: header ..< received.count)
        source.replaceSubrange(0 ..< header, with: Data(repeating: 0x72, count: header))
        source.append(Data(repeating: 0x53, count: 3 * 1024 * 1024 + 37))
        try source.write(to: url)
        try record(&state, event: .completed(true), path: url.path, bytes: &received, completions: &completions)
        XCTAssertEqual(received, source)
        XCTAssertEqual(body, source.subdata(in: header ..< 12 * 1024 * 1024))
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(state.isComplete)
        try record(&state, event: .completed(true), path: url.path, bytes: &received, completions: &completions)
        XCTAssertEqual(completions, 1)
    }

    func testSmallAndThresholdSizedChatVideosWaitForFinalSizeLikeUpstream() throws {
        for size in [32 * 1024, 1024 * 1024 + 47, 10 * 1024 * 1024] {
            let source = Data(repeating: 0x42, count: size)
            let url = try file(source)
            var state = VideoRenderUploadState()
            var received = Data()
            var completions = 0
            try record(&state, event: .progress(path: url.path, size: Int64(size), headerSize: 32 * 1024), path: url.path, bytes: &received, completions: &completions)
            XCTAssertTrue(received.isEmpty)
            try record(&state, event: .completed(true), path: url.path, bytes: &received, completions: &completions)
            XCTAssertEqual(received, source)
            XCTAssertEqual(completions, 1)
        }
    }

    func testAppendChunksAreBoundedAndCompletionCanUseRenamedFinalFile() throws {
        let source = Data(repeating: 0x55, count: 11 * 1024 * 1024 + 333)
        let initial = try file(source)
        let final = try file(source + Data([1, 2, 3]))
        var state = VideoRenderUploadState()
        var chunks: [(Int64, Int)] = []
        try state.update(.progress(path: initial.path, size: Int64(source.count), headerSize: 32 * 1024), finalPath: final.path) { chunk in
            if case let .data(offset, data) = chunk { chunks.append((offset, data.count)) }
        }
        XCTAssertGreaterThan(try XCTUnwrap(chunks.first).1, 10 * 1024 * 1024)
        XCTAssertLessThanOrEqual(try XCTUnwrap(chunks.first).1, 10 * 1024 * 1024 + 512 * 1024)
        XCTAssertTrue(chunks.dropFirst().allSatisfy { $0.1 <= 512 * 1024 })
        var complete = false
        try state.update(.completed(true), finalPath: final.path) { chunk in
            if case .complete = chunk { complete = true }
        }
        XCTAssertTrue(complete)
        XCTAssertEqual(state.offset, Int64(source.count + 3))
    }

    func testQueuedGrowthSurvivesFinalRenameWithOrWithoutEarlierBody() throws {
        for alreadyExposed in [false, true] {
            let header = 1024 * 1024 + 48
            var source = Data(repeating: 0x21, count: 12 * 1024 * 1024)
            let temporary = try file(source)
            let final = try file(Data())
            var state = VideoRenderUploadState()
            var received = Data()
            var completions = 0
            if alreadyExposed {
                try record(&state, event: .progress(path: temporary.path, size: Int64(source.count), headerSize: Int64(header)), path: final.path, bytes: &received, completions: &completions)
            }
            source.replaceSubrange(0 ..< header, with: Data(repeating: 0x75, count: header))
            source.append(Data(repeating: 0x64, count: 1024 * 1024 + 19))
            try source.write(to: temporary)
            try FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: temporary, to: final)
            try record(&state, event: .progress(path: temporary.path, size: Int64(source.count), headerSize: Int64(header)), path: final.path, bytes: &received, completions: &completions)
            try record(&state, event: .completed(true), path: final.path, bytes: &received, completions: &completions)
            XCTAssertEqual(received, source)
            XCTAssertEqual(completions, 1)
        }
    }

    func testOldGenerationCannotChangeReplacementHintOrTerminalState() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let registry = PendingVideoRenders()
        let info = PendingVideoRenderInfo(duration: 1, dimensions: .zero, hasAudio: false, frame: { nil })
        let old = ValuePipe<PendingVideoRenderEvent>()
        let current = ValuePipe<PendingVideoRenderEvent>()
        registry.add(path: path, info: info, rendering: old.signal())
        registry.add(path: path, info: info, rendering: current.signal())
        current.putNext(.progress(path: path + ".new", size: 2 * 1024 * 1024, headerSize: 65536))
        old.putNext(.progress(path: path + ".old", size: 2 * 1024 * 1024, headerSize: 131072))
        old.putNext(.completed(true))
        XCTAssertEqual(streamingVideoHeaderSize(path: path), 65536)
        var done: Bool?
        let disposable = try XCTUnwrap(registry.result(for: path)).start(next: { done = $0 })
        XCTAssertNil(done)
        current.putNext(.completed(true))
        XCTAssertEqual(done, true)
        disposable.dispose()
        registry.cancel(path: path)
    }

    func testFailureMissingFileAndTruncationNeverCompleteUpload() throws {
        let url = try file(Data(repeating: 0x22, count: 12 * 1024 * 1024))
        var state = VideoRenderUploadState()
        var completed = false
        let capture: (VideoRenderUploadChunk) -> Void = { chunk in if case .complete = chunk { completed = true } }
        XCTAssertThrowsError(try state.update(.completed(false), finalPath: url.path, emit: capture))
        XCTAssertThrowsError(try state.update(.completed(true), finalPath: url.path + ".missing", emit: capture))
        try state.update(.progress(path: url.path, size: 12 * 1024 * 1024, headerSize: 32 * 1024), finalPath: url.path, emit: capture)
        XCTAssertThrowsError(try state.update(.progress(path: url.path, size: 100, headerSize: 32 * 1024), finalPath: url.path, emit: capture))
        try Data([1, 2, 3]).write(to: url)
        XCTAssertThrowsError(try state.update(.completed(true), finalPath: url.path, emit: capture))
        XCTAssertFalse(completed)
    }

    func testHeaderGrowthAndSourceReplacementAfterBodyExposureAreRejected() throws {
        let url = try file(Data(repeating: 0x11, count: 12 * 1024 * 1024))
        var state = VideoRenderUploadState()
        try state.update(.progress(path: url.path, size: 12 * 1024 * 1024, headerSize: 32 * 1024), finalPath: url.path) { _ in }
        XCTAssertThrowsError(try state.update(.progress(path: url.path, size: 12 * 1024 * 1024, headerSize: 1024 * 1024), finalPath: url.path) { _ in })
        XCTAssertThrowsError(try state.update(.progress(path: url.path + ".other", size: 12 * 1024 * 1024, headerSize: 32 * 1024), finalPath: url.path) { _ in })
    }

    func testIncompleteOrUnsupportedHeaderReservationNeverPublishesData() throws {
        let url = try file(Data(repeating: 1, count: 12 * 1024 * 1024))
        let headers: [Int64] = [0, 13 * 1024 * 1024, Int64(Int32.max) + 1]
        for header in headers {
            var state = VideoRenderUploadState()
            var emitted = false
            XCTAssertThrowsError(try state.update(.progress(path: url.path, size: 12 * 1024 * 1024, headerSize: header), finalPath: url.path) { _ in emitted = true })
            XCTAssertFalse(emitted)
        }
        let registry = PendingVideoRenders()
        let info = PendingVideoRenderInfo(duration: 1, dimensions: .zero, hasAudio: false, frame: { nil })
        registry.add(path: url.path, info: info, rendering: .single(.progress(path: url.path, size: Int64.max, headerSize: Int64(Int32.max) + 1)))
        var result: Bool?
        let disposable = try XCTUnwrap(registry.result(for: url.path)).start(next: { result = $0 })
        XCTAssertEqual(result, false)
        XCTAssertEqual(streamingVideoHeaderSize(path: url.path), 32 * 1024)
        disposable.dispose()
        registry.cancel(path: url.path)
    }

    func testPendingHintPrecedesEventAndFinalResultIsReplayed() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let registry = PendingVideoRenders()
        let pipe = ValuePipe<PendingVideoRenderEvent>()
        let info = PendingVideoRenderInfo(duration: 1, dimensions: CGSize(width: 10, height: 10), hasAudio: true, frame: { nil })
        registry.add(path: path, info: info, rendering: pipe.signal())
        XCTAssertEqual(streamingVideoHeaderSize(path: path), 32 * 1024)
        var sawProgress = false
        let events = try XCTUnwrap(registry.events(for: path)).start(next: { event in
            if case .progress = event {
                XCTAssertEqual(streamingVideoHeaderSize(path: path), 1048624)
                sawProgress = true
            }
        })
        pipe.putNext(.progress(path: path + ".writing", size: 11 * 1024 * 1024, headerSize: 1048624))
        XCTAssertTrue(sawProgress)
        pipe.putNext(.completed(true))
        var result: Bool?
        let resultDisposable = try XCTUnwrap(registry.result(for: path)).start(next: { result = $0 })
        XCTAssertEqual(result, true)
        XCTAssertEqual(streamingVideoHeaderSize(path: path), 1048624)
        events.dispose()
        resultDisposable.dispose()
        registry.cancel(path: path)
    }

    func testCompletedWriterRetainsReservationWhileConsumerHasQueuedProgress() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let registry = PendingVideoRenders()
        let pipe = ValuePipe<PendingVideoRenderEvent>()
        let info = PendingVideoRenderInfo(duration: 1, dimensions: .zero, hasAudio: false, frame: { nil })
        registry.add(path: path, info: info, rendering: pipe.signal())
        let queue = Queue()
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        let received = expectation(description: "queued progress and completion")
        received.expectedFulfillmentCount = 2
        let disposable = (try XCTUnwrap(registry.events(for: path)) |> deliverOn(queue)).start(next: { _ in
            XCTAssertEqual(streamingVideoHeaderSize(path: path), 1048624)
            received.fulfill()
        })
        pipe.putNext(.progress(path: path + ".writing", size: 12 * 1024 * 1024, headerSize: 1048624))
        pipe.putNext(.completed(true))
        XCTAssertEqual(streamingVideoHeaderSize(path: path), 1048624)
        gate.signal()
        wait(for: [received], timeout: 4)
        disposable.dispose()
        registry.cancel(path: path)
        XCTAssertEqual(streamingVideoHeaderSize(path: path), 32 * 1024)
    }

    func testCancelDisposesRenderRemovesLogicalFileAndPublishesFailure() throws {
        let url = try file(Data([1, 2, 3]))
        let registry = PendingVideoRenders()
        var disposed = false
        let render = Signal<PendingVideoRenderEvent, NoError> { _ in ActionDisposable { disposed = true } }
        let info = PendingVideoRenderInfo(duration: 1, dimensions: CGSize(width: 10, height: 10), hasAudio: false, frame: { nil })
        registry.add(path: url.path, info: info, rendering: render)
        var result: Bool?
        let disposable = try XCTUnwrap(registry.result(for: url.path)).start(next: { result = $0 })
        registry.cancel(path: url.path)
        XCTAssertTrue(disposed)
        XCTAssertEqual(result, false)
        XCTAssertNil(registry.events(for: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        disposable.dispose()
    }

    func testReentrantReplacementKeepsNewestHintAndDoesNotStartSupersededRender() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let registry = PendingVideoRenders()
        let info = PendingVideoRenderInfo(duration: 1, dimensions: .zero, hasAudio: false, frame: { nil })
        let newest = ValuePipe<PendingVideoRenderEvent>()
        registry.add(path: path, info: info, rendering: .never())
        let previous = try XCTUnwrap(registry.result(for: path)).start(next: { result in
            if !result {
                registry.add(path: path, info: info, rendering: newest.signal())
                newest.putNext(.progress(path: path + ".newest", size: 2 * 1024 * 1024, headerSize: 65536))
            }
        })
        var started = false
        let superseded = Signal<PendingVideoRenderEvent, NoError> { _ in
            started = true
            return EmptyDisposable
        }
        registry.add(path: path, info: info, rendering: superseded)
        XCTAssertFalse(started)
        XCTAssertEqual(streamingVideoHeaderSize(path: path), 65536)
        previous.dispose()
        registry.cancel(path: path)
    }

    func testReentrantCancelRetryPreservesNewFileAndHint() throws {
        let url = try file(Data([1, 2, 3]))
        let registry = PendingVideoRenders()
        let info = PendingVideoRenderInfo(duration: 1, dimensions: .zero, hasAudio: false, frame: { nil })
        let retry = ValuePipe<PendingVideoRenderEvent>()
        registry.add(path: url.path, info: info, rendering: .never())
        let previous = try XCTUnwrap(registry.result(for: url.path)).start(next: { result in
            if !result {
                registry.add(path: url.path, info: info, rendering: retry.signal())
                try? Data([4, 5, 6]).write(to: url)
                retry.putNext(.progress(path: url.path + ".retry", size: 2 * 1024 * 1024, headerSize: 65536))
            }
        })
        registry.cancel(path: url.path)
        XCTAssertEqual(try Data(contentsOf: url), Data([4, 5, 6]))
        XCTAssertEqual(streamingVideoHeaderSize(path: url.path), 65536)
        previous.dispose()
        registry.cancel(path: url.path)
    }

    func testReplacingPendingRenderFailsOldSubscriberWithoutCompletingNewOne() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let registry = PendingVideoRenders()
        let info = PendingVideoRenderInfo(duration: 1, dimensions: .zero, hasAudio: false, frame: { nil })
        registry.add(path: path, info: info, rendering: .never())
        var old: Bool?
        let disposable = try XCTUnwrap(registry.result(for: path)).start(next: { old = $0 })
        registry.add(path: path, info: info, rendering: .never())
        XCTAssertEqual(old, false)
        var current: Bool?
        let next = try XCTUnwrap(registry.result(for: path)).start(next: { current = $0 })
        XCTAssertNil(current)
        registry.cancel(path: path)
        XCTAssertEqual(current, false)
        disposable.dispose()
        next.dispose()
    }
}
