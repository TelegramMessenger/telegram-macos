import Foundation
import XCTest

__ACTION__

struct Signal<Value> {
    let subscribe: (@escaping (Value) -> Void) -> Void
    func start(next: @escaping (Value) -> Void) { subscribe(next) }
}
infix operator |> : AdditionPrecedence
func |> <A, B>(value: A, transform: (A) -> B) -> B { transform(value) }
func deliverOnMainQueue<A>(_ signal: Signal<A>) -> Signal<A> { signal }
final class NSImage {}
final class Window {}
final class AccountContext {}
final class Context {
    var wrappedSignals = 0
    func preservingPresentation<T>(_ signal: Signal<T>) -> Signal<T> { wrappedSignals += 1; return signal }
}
final class Analytics {
    static let shared = Analytics()
    func unresolvedContext() -> Context { Context() }
}
enum Entry { case attachFile, attachPhotoVideo, imagePicker }
enum Mode { case media, file }
enum Blocker: Equatable { case sizeLimit, fileUnavailable, emptySelection }
final class Journey {
    var blockers: [Blocker] = []
    var failures: [Blocker] = []
    var cancellations = 0
    var discards = 0
    var prepares = 0
    func blocked(_ blocker: Blocker) { blockers.append(blocker) }
    func fail(_ blocker: Blocker) { failures.append(blocker) }
    func cancel() { cancellations += 1 }
    func discard() { discards += 1 }
    func preparing() { prepares += 1 }
}
final class ChatInteraction {
    var revision = 0
    var admitted = true
    var tasks: [Journey] = []
    var previews: [[String]] = []
    var modes: [Bool] = []
    func makeMediaAnalyticsJourney(context: Context?, entry: Entry, mode: Mode, source: Int) -> Journey? {
        guard admitted else { return nil }
        let task = Journey(); tasks.append(task); return task
    }
    func captureDeferredSendAction() -> ChatDeferredSendAction {
        let captured = revision
        return ChatDeferredSendAction { [weak self] in self?.revision == captured }
    }
    func showPreviewSender(_ files: [URL], _ media: Bool, _ caption: String?, analyticsContext: Context?, journey: Journey?) {
        previews.append(files.map(\.path)); modes.append(media)
    }
}
struct FileCallbacks { let cancel: () -> Void; let complete: ([String]?) -> Void }
var panels: [FileCallbacks] = []
var pictures: [(NSImage?) -> Void] = []
var preparedImages: [(String) -> Void] = []
var sizeAlerts = 0
func filePanel(with: [String]? = nil, allowMultiple: Bool, canChooseDirectories: Bool, for: Window, analyticsContext: Context?, cancelled: @escaping () -> Void, completion: @escaping ([String]?) -> Void) {
    panels.append(FileCallbacks(cancel: cancelled, complete: completion))
}
func pickImage(for: Window, analyticsContext: Context?, completion: @escaping (NSImage?) -> Void) { pictures.append(completion) }
func putToTemp(image: NSImage) -> Signal<String> { Signal { preparedImages.append($0) } }
func fileSize(_ path: String) -> Int64? { path == "/missing" ? nil : path == "/large" ? 101 : 10 }
func fileSizeLimitExceed(context: AccountContext, fileSize: Int64) -> Bool { fileSize <= 100 }
func showFileLimit(context: AccountContext, fileSize: Int64?) { sizeAlerts += 1 }
final class Controller {
    let context = AccountContext()
    let analyticsContext: Context? = Context()
    let chatInteraction = ChatInteraction()
    let analyticsScreen = 1
    let window = Window()
    let exts: [String]? = nil
    func files(asMedia: Bool = false) {
        let context = self.context
        let analyticsContext = self.analyticsContext
__FILES__
    }
    func photos() {
        let context = self.context
        let analyticsContext = self.analyticsContext
__PHOTOS__
    }
    func picture() {
        let context = self.context
        let analyticsContext = self.analyticsContext
__IMAGE__
    }
}

final class AttachmentTests: XCTestCase {
    override func setUp() { panels = []; pictures = []; preparedImages = []; sizeAlerts = 0 }
    private func open(_ controller: Controller, photo: Bool) -> FileCallbacks {
        if photo { controller.photos() } else { controller.files() }
        return panels.last!
    }
    func testExplicitCancelConsumesFollowingNilAndDuplicateCallbacks() {
        for photo in [false, true] {
            let controller = Controller()
            let callbacks = open(controller, photo: photo)
            callbacks.cancel(); callbacks.complete(nil); callbacks.cancel(); callbacks.complete(["/small"])
            let task = controller.chatInteraction.tasks[0]
            XCTAssertEqual(task.cancellations, 1)
            XCTAssertEqual(task.discards, 0)
            XCTAssertTrue(controller.chatInteraction.previews.isEmpty)
        }
    }
    func testUnknownExitDoesNotInventCancelOrLaterSelection() {
        for photo in [false, true] {
            let controller = Controller()
            let callbacks = open(controller, photo: photo)
            callbacks.complete(nil); callbacks.cancel(); callbacks.complete(["/small"])
            let task = controller.chatInteraction.tasks[0]
            XCTAssertEqual(task.cancellations, 0)
            XCTAssertEqual(task.discards, 1)
            XCTAssertTrue(controller.chatInteraction.previews.isEmpty)
        }
    }
    func testEmptyAcceptedSelectionFailsWithoutPreview() {
        for photo in [false, true] {
            let controller = Controller()
            open(controller, photo: photo).complete([])
            XCTAssertEqual(controller.chatInteraction.tasks[0].failures, [.emptySelection])
            XCTAssertTrue(controller.chatInteraction.previews.isEmpty)
        }
    }
    func testFullyRejectedAndPartiallyAcceptedSelections() {
        for photo in [false, true] {
            for accepted in [false, true] {
                let controller = Controller()
                open(controller, photo: photo).complete(accepted ? ["/small", "/large"] : ["/large"])
                let task = controller.chatInteraction.tasks[0]
                XCTAssertEqual(task.blockers, accepted ? [.sizeLimit] : [])
                XCTAssertEqual(task.failures, accepted ? [] : [.sizeLimit])
                XCTAssertEqual(controller.chatInteraction.previews, accepted ? [["/small"]] : [])
            }
        }
    }
    func testSelectionIsOneUseAndPreservesMode() {
        for photo in [false, true] {
            let controller = Controller()
            let callbacks = open(controller, photo: photo)
            callbacks.complete(["/small"]); callbacks.complete(["/other"]); callbacks.cancel()
            XCTAssertEqual(controller.chatInteraction.previews, [["/small"]])
            XCTAssertEqual(controller.chatInteraction.modes, [photo])
            XCTAssertEqual(controller.chatInteraction.tasks[0].cancellations, 0)
        }
    }
    func testStaleSelectionAndStaleCancelDiscardWithoutOutcome() {
        for photo in [false, true] {
            for cancelled in [false, true] {
                let controller = Controller()
                let callbacks = open(controller, photo: photo)
                controller.chatInteraction.revision += 1
                if cancelled { callbacks.cancel() } else { callbacks.complete(["/small"]) }
                XCTAssertEqual(controller.chatInteraction.tasks[0].discards, 1)
                XCTAssertEqual(controller.chatInteraction.tasks[0].cancellations, 0)
                XCTAssertTrue(controller.chatInteraction.previews.isEmpty)
            }
        }
    }
    func testPendingFileSelectionDoesNotRetainController() {
        for photo in [false, true] {
            var controller: Controller? = Controller()
            let callbacks = open(controller!, photo: photo)
            let task = controller?.chatInteraction.tasks[0]
            weak var weakController = controller
            controller = nil
            XCTAssertNil(weakController)
            callbacks.complete(["/small"])
            XCTAssertEqual(task?.discards, 1)
        }
    }
    func testPictureSelectionAndPreparationAreIndependentlyOneUse() {
        let controller = Controller()
        controller.picture()
        pictures.last?(NSImage()); pictures.last?(NSImage())
        XCTAssertEqual(preparedImages.count, 1)
        XCTAssertEqual(controller.analyticsContext?.wrappedSignals, 1)
        preparedImages.last?("/first"); preparedImages.last?("/duplicate")
        XCTAssertEqual(controller.chatInteraction.previews, [["/first"]])
        XCTAssertEqual(controller.chatInteraction.tasks[0].discards, 0)
    }
    func testPictureChangedBeforeSelectionOrDuringPreparation() {
        for beforeSelection in [false, true] {
            let controller = Controller()
            controller.picture()
            if beforeSelection { controller.chatInteraction.revision += 1 }
            pictures.last?(NSImage())
            if !beforeSelection {
                controller.chatInteraction.revision += 1
                preparedImages.last?("/stale")
            }
            XCTAssertTrue(controller.chatInteraction.previews.isEmpty)
            XCTAssertEqual(controller.chatInteraction.tasks[0].discards, 1)
        }
    }
    func testPictureUnknownAndDestroyedOwnerDiscard() {
        var controller: Controller? = Controller()
        controller?.picture()
        let unknownTask = controller?.chatInteraction.tasks[0]
        pictures.last?(nil)
        XCTAssertEqual(unknownTask?.discards, 1)
        controller?.picture()
        let destroyedTask = controller?.chatInteraction.tasks.last
        pictures.last?(NSImage())
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        preparedImages.last?("/late")
        XCTAssertEqual(destroyedTask?.discards, 1)
    }
    func testDeniedAnalyticsDoesNotDisableSelectionGuardsOrPreview() {
        let controller = Controller()
        controller.chatInteraction.admitted = false
        let first = open(controller, photo: false)
        first.complete(["/small"])
        let second = open(controller, photo: true)
        controller.chatInteraction.revision += 1
        second.complete(["/stale"])
        XCTAssertTrue(controller.chatInteraction.tasks.isEmpty)
        XCTAssertEqual(controller.chatInteraction.previews, [["/small"]])
    }
}
