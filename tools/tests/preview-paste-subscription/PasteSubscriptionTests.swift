import Foundation
import XCTest
import SwiftSignalKit

__ACTIONS__
__ATTACHMENT_EDITS__
__DEFERRED__

final class Lease {
    private var finish: (() -> Void)?
    init(_ finish: @escaping () -> Void) { self.finish = finish }
    func end() { let callback = finish; finish = nil; callback?() }
    deinit { end() }
}
final class Context {
    var depth = 0
    func beginPresentation() -> Lease { depth += 1; return Lease { self.depth -= 1 } }
__SIGNAL_CONTEXT__
}
final class Analytics {
    static let shared = Analytics()
    func unresolvedContext() -> Context { Context() }
}
final class ChatInteraction {
    var revision = 0
    func captureDeferredSendAction() -> ChatDeferredSendAction {
        let captured = revision
        return ChatDeferredSendAction { [weak self] in self?.revision == captured }
    }
}
final class NSPasteboard {
    enum Kind { case kFilenames }
    var types: [Kind]? = [.kFilenames]
    let files: [String]
    init(files: [String]) { self.files = files }
    func propertyList(forType: Kind) -> Any? { files }
}
struct DragItem { let title: String; let desc: String; let handler: () -> Void }
struct Labels { func previewDraggingAddItemsOther(_ count: Int) -> String { "add" } }
func strings() -> Labels { Labels() }
enum Route { case addDrop }
final class Controller {
    var insertAdditionUrls: (([URL], Route) -> Void)?
__DROP__
    let pendingActions = PreviewSenderPendingActions()
    let pasteActions = PreviewSenderPendingActions()
    let attachmentEdits = PreviewSenderAttachmentEdits()
    let editorDisposable = MetaDisposable()
    let pasteDisposable = MetaDisposable()
    let chatInteraction = ChatInteraction()
    var analyticsContext: Context? = Context()
    var sent = false
__RECEIVE__
    func close() {
__CLOSE__
    }
    deinit { pasteDisposable.dispose() }
}
final class Source {
    var observer: Subscriber<[URL], NoError>?
    var disposed = false
    var started = false
    var onDispose: (() -> Void)?
    func signal() -> Signal<[URL], NoError> {
        Signal { observer in
            self.started = true
            self.observer = observer
            return ActionDisposable { self.disposed = true; self.onDispose?() }
        }
    }
    func send(_ path: String) { observer?.putNext([URL(fileURLWithPath: path)]) }
}

final class PasteSubscriptionTests: XCTestCase {
    func testSynchronousEmptyParseCannotDisposeNestedPreparation() {
        let controller = Controller()
        let preparation = Source()
        var paths: [String] = []
        controller.receivePasteURLs(.single([])) { urls in
            XCTAssertTrue(urls.isEmpty)
            controller.receivePasteURLs(preparation.signal()) { paths += $0.map(\.path) }
        }
        XCTAssertTrue(preparation.started)
        XCTAssertFalse(preparation.disposed)
        preparation.send("/prepared")
        XCTAssertEqual(paths, ["/prepared"])
        controller.close()
        XCTAssertTrue(preparation.disposed)
    }
    func testReentrantNewRequestRemainsSubscribedAfterOldDelivery() {
        let controller = Controller()
        let old = Source()
        let new = Source()
        var paths: [String] = []
        controller.receivePasteURLs(old.signal()) { urls in
            paths += urls.map(\.path)
            controller.receivePasteURLs(new.signal()) { paths += $0.map(\.path) }
        }
        old.send("/first")
        XCTAssertTrue(old.disposed)
        XCTAssertFalse(new.disposed)
        old.send("/stale")
        new.send("/second")
        XCTAssertEqual(paths, ["/first", "/second"])
    }
    func testDuplicateOutputIsConsumedOnce() {
        let controller = Controller()
        let source = Source()
        var paths: [String] = []
        controller.receivePasteURLs(source.signal()) { paths += $0.map(\.path) }
        source.send("/first"); source.send("/duplicate")
        XCTAssertEqual(paths, ["/first"])
    }
    func testNewRequestDisposesOldSourceAndOnlyNewOutputApplies() {
        let controller = Controller()
        let old = Source()
        let new = Source()
        var paths: [String] = []
        controller.receivePasteURLs(old.signal()) { paths += $0.map(\.path) }
        controller.receivePasteURLs(new.signal()) { paths += $0.map(\.path) }
        XCTAssertTrue(old.disposed)
        old.send("/old"); new.send("/new")
        XCTAssertEqual(paths, ["/new"])
    }
    func testChangedChatSuppressesDeliveryWithoutRebindingContext() {
        let controller = Controller()
        let origin = controller.analyticsContext!
        let source = Source()
        var count = 0
        controller.receivePasteURLs(source.signal()) { _ in count += 1 }
        controller.chatInteraction.revision += 1
        controller.analyticsContext = Context()
        source.send("/stale")
        XCTAssertEqual(count, 0)
        XCTAssertEqual(origin.depth, 1)
        controller.close()
        XCTAssertEqual(origin.depth, 0)
    }
    func testCommitAndCloseSuppressPendingAndNewRequests() {
        for closed in [false, true] {
            let controller = Controller()
            let source = Source()
            var count = 0
            controller.receivePasteURLs(source.signal()) { _ in count += 1 }
            if closed { controller.close() } else { controller.sent = true }
            source.send("/late")
            let next = Source()
            controller.receivePasteURLs(next.signal()) { _ in count += 1 }
            XCTAssertFalse(next.started)
            XCTAssertEqual(count, 0)
            if closed { XCTAssertTrue(source.disposed) }
        }
    }
    func testDeliveryLeaseSurvivesReentrantClosure() {
        let controller = Controller()
        let context = controller.analyticsContext!
        let source = Source()
        controller.receivePasteURLs(source.signal()) { _ in
            XCTAssertEqual(context.depth, 2)
            controller.close()
            XCTAssertEqual(context.depth, 1)
        }
        source.send("/result")
        XCTAssertEqual(context.depth, 0)
    }
    func testDestructionDisposesWithoutKeepingControllerAlive() {
        var controller: Controller? = Controller()
        let context = controller!.analyticsContext!
        let source = Source()
        var count = 0
        controller?.receivePasteURLs(source.signal()) { _ in count += 1 }
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        XCTAssertTrue(source.disposed)
        XCTAssertEqual(context.depth, 0)
        source.send("/late")
        XCTAssertEqual(count, 0)
    }
    func testUnrelatedPreviewActionDoesNotCancelPendingPaste() {
        let controller = Controller()
        let source = Source()
        var count = 0
        controller.receivePasteURLs(source.signal()) { _ in count += 1 }
        controller.pendingActions.invalidate()
        source.send("/result")
        XCTAssertEqual(count, 1)
    }
    func testEmptyOrCompletedOutputDoesNotInventAcceptedAttachments() {
        let controller = Controller()
        var results: [[URL]] = []
        controller.receivePasteURLs(.complete()) { results.append($0) }
        XCTAssertTrue(results.isEmpty)
        controller.receivePasteURLs(.single([])) { results.append($0) }
        XCTAssertEqual(results, [[]])
    }
    func testPreviewDropStartsOnlyOnOneAcceptedTargetInvocation() {
        let controller = Controller()
        var paths: [String] = []
        controller.insertAdditionUrls = { urls, _ in paths += urls.map(\.path) }
        let targets = controller.draggingItems(for: NSPasteboard(files: ["/drop"]))
        XCTAssertTrue(paths.isEmpty)
        targets[0].handler(); targets[0].handler()
        XCTAssertEqual(paths, ["/drop"])
    }
    func testPreviewDropRejectsOldChatAndClosedOrCommittedPreview() {
        for state in 0..<3 {
            let controller = Controller()
            var calls = 0
            controller.insertAdditionUrls = { _, _ in calls += 1 }
            let target = controller.draggingItems(for: NSPasteboard(files: ["/drop"]))[0]
            if state == 0 { controller.chatInteraction.revision += 1 }
            if state == 1 { controller.close() }
            if state == 2 { controller.sent = true }
            target.handler()
            XCTAssertEqual(calls, 0)
            if state != 0 { XCTAssertTrue(controller.draggingItems(for: NSPasteboard(files: ["/late"])).isEmpty) }
        }
    }
    func testCapturedDropDoesNotRetainPreview() {
        var controller: Controller? = Controller()
        var calls = 0
        controller?.insertAdditionUrls = { _, _ in calls += 1 }
        let target = controller!.draggingItems(for: NSPasteboard(files: ["/drop"]))[0]
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        target.handler()
        XCTAssertEqual(calls, 0)
    }
    func testDisposalStartingNewerPastePreventsSupersededConverterSubscription() {
        let controller = Controller()
        let old = Source(), superseded = Source(), newest = Source()
        var paths: [String] = []
        controller.receivePasteURLs(old.signal()) { paths += $0.map(\.path) }
        old.onDispose = {
            old.onDispose = nil
            controller.receivePasteURLs(newest.signal()) { paths += $0.map(\.path) }
        }
        controller.receivePasteURLs(superseded.signal()) { paths += $0.map(\.path) }
        XCTAssertFalse(superseded.started)
        XCTAssertTrue(newest.started); XCTAssertFalse(newest.disposed)
        superseded.send("/stale"); newest.send("/newest")
        XCTAssertEqual(paths, ["/newest"])
        controller.close()
        XCTAssertEqual(controller.analyticsContext?.depth, 0)
    }
    func testDisposalClosingCommittingOrChangingChatPreventsNextSubscription() {
        for state in 0..<3 {
            let controller = Controller()
            let old = Source(), next = Source()
            controller.receivePasteURLs(old.signal()) { _ in XCTFail("Old request must not deliver") }
            old.onDispose = {
                old.onDispose = nil
                if state == 0 { controller.close() }
                else if state == 1 { controller.sent = true }
                else { controller.chatInteraction.revision += 1 }
            }
            controller.receivePasteURLs(next.signal()) { _ in XCTFail("Invalidated request must not deliver") }
            XCTAssertFalse(next.started)
            controller.close()
            XCTAssertEqual(controller.analyticsContext?.depth, 0)
        }
    }

}
