import Foundation
import XCTest
import SwiftSignalKit

__EDITS__
__PENDING__
__DEFERRED__

final class Lease { func end() {} }
final class Context {
    let window = 1
    func beginPresentation() -> Lease { Lease() }
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
final class Slot { var resets = 0; func set(_ value: Int?) { resets += 1 } }
struct EditedVideoData: Equatable { let value: Int }
final class Journey {
    enum Step: Equatable { case applyEditor, cancelEditor, openEditor, openCoverPicker, cancelCoverPicker, applyCover, removeCover }
    enum Blocker: Equatable { case emptySelection, preparation }
    var blockers: [Blocker] = []
    func blocked(_ value: Blocker) { blockers.append(value) }
    var steps: [Step] = []
    func step(_ step: Step) { steps.append(step) }
}
final class PendingVideoRenders {
    static let shared = PendingVideoRenders()
    var cancelled: [String] = []
    func cancel(path: String) { cancelled.append(path) }
}
final class EditVideoController {
    static var instances: [EditVideoController] = []
    let completion: (URL, EditedVideoData?) -> Void
    var analyticsContext: Context?
    var onCancelled: (() -> Void)?
    init(context: Context, url: URL, edited: EditedVideoData?, completion: @escaping (URL, EditedVideoData?) -> Void) {
        self.completion = completion
        Self.instances.append(self)
    }
}
enum Animation { case scaleCenter }
func showModal(with editor: EditVideoController, for window: Int, animationType: Animation) {
    XCTAssertNotNil(editor.analyticsContext)
}
struct TelegramMediaFile {
    struct Dimensions { let size: Int }
    var dimensions: Dimensions? = nil
}
enum EditControllerSettings: Equatable { case plain, disableSizes(dimensions: Int, circle: Bool) }
enum SelectionRectDimensions { static func bestDimension(for size: Int) -> Int { size } }
struct EditedImageData {}
let photoExts = ["jpg"]
struct FileCallbacks { let cancelled: () -> Void; let completion: ([String]?) -> Void }
var fileCallbacks: [FileCallbacks] = []
func filePanel(with: [String], allowMultiple: Bool, for window: Int, analyticsContext: Context, cancelled: @escaping () -> Void, completion: @escaping ([String]?) -> Void) {
    fileCallbacks.append(FileCallbacks(cancelled: cancelled, completion: completion))
}
final class EditImageModalController {
    static var instances: [EditImageModalController] = []
    static var failConstruction = false
    static var completeWithoutOutput = false
    let pipe = ValuePipe<(URL, EditedImageData?)>()
    var result: Signal<(URL, EditedImageData?), NoError> { Self.completeWithoutOutput ? .complete() : pipe.signal() }
    var analyticsContext: Context?
    var onCancelled: (() -> Void)?
    let settings: EditControllerSettings
    init?(_ url: URL, context: Context, settings: EditControllerSettings) {
        guard !Self.failConstruction else { return nil }
        self.settings = settings
        Self.instances.append(self)
    }
}
func showModal(with editor: EditImageModalController, for window: Int, animationType: Animation) { XCTAssertNotNil(editor.analyticsContext) }
final class Controller {
    let pendingActions = PreviewSenderPendingActions()
    let attachmentEdits = PreviewSenderAttachmentEdits()
    let chatInteraction = ChatInteraction()
    let editorDisposable = MetaDisposable()
    let context = Context()
    let analyticsContext: Context? = Context()
    var analyticsMediaJourney: Journey? = Journey()
    var sent = false
    var urls: [URL] { didSet { attachmentEdits.update(urls); if urls != oldValue { pendingActions.invalidate() } } }
    var editedVideos: [URL: EditedVideoData] = [:]
    var previews: [String: String] = [:] { didSet { if previews != oldValue { pendingActions.invalidate() } } }
    func updateCustomPreview(_ path: String, _ preview: String?) { previews[path] = preview }
    init(urls: [URL]) { self.urls = urls }
__VIDEO__
__COVER__
__CAPTURE__
}

final class EditorTests: XCTestCase {
    let a = URL(fileURLWithPath: "/first")
    let b = URL(fileURLWithPath: "/second")
    override func setUp() { EditVideoController.instances = []; PendingVideoRenders.shared.cancelled = [] }
    func testRemovedAndReaddedAttachmentDoesNotReviveEditor() {
        let owner = PreviewSenderAttachmentEdits()
        let edit = owner.begin(for: a, urls: [a])!
        owner.update([]); owner.update([a])
        XCTAssertFalse(edit.apply())
        XCTAssertFalse(edit.cancel())
    }
    func testReorderAndUnrelatedAdditionPreserveTargetIdentity() {
        let owner = PreviewSenderAttachmentEdits()
        let edit = owner.begin(for: a, urls: [a])!
        owner.update([b, a, a])
        XCTAssertTrue(edit.apply())
        XCTAssertFalse(edit.apply())
    }
    func testNewEditorSupersedesSameAttachmentAndOldRender() {
        let owner = PreviewSenderAttachmentEdits()
        let old = owner.begin(for: a, urls: [a])!
        XCTAssertTrue(old.commit()); XCTAssertTrue(old.startRendering())
        let current = owner.begin(for: a, urls: [a])!
        XCTAssertFalse(old.apply())
        XCTAssertTrue(current.apply())
    }
    func testPaintCancelAndUnknownClosureCannotRenderOrCommitLater() {
        for cancel in [true, false] {
            let owner = PreviewSenderAttachmentEdits()
            let edit = owner.begin(for: a, urls: [a])!
            if cancel { XCTAssertTrue(edit.cancel()) }
            XCTAssertFalse(edit.startRendering())
            XCTAssertFalse(edit.commit())
            XCTAssertFalse(edit.apply())
        }
    }
    func testPaintRenderingBeginsOnceAndDuplicateCloseKeepsPendingResult() {
        let owner = PreviewSenderAttachmentEdits()
        let edit = owner.begin(for: a, urls: [a])!
        XCTAssertTrue(edit.commit())
        XCTAssertFalse(edit.commit())
        XCTAssertFalse(edit.apply())
        XCTAssertTrue(edit.startRendering())
        XCTAssertFalse(edit.startRendering())
        XCTAssertFalse(edit.cancel())
        XCTAssertTrue(edit.apply())
        XCTAssertFalse(edit.apply())
    }
    func testClosedOrDestroyedOwnerRejectsAllPendingStages() {
        var owner: PreviewSenderAttachmentEdits? = PreviewSenderAttachmentEdits()
        let edit = owner!.begin(for: a, urls: [a])!
        XCTAssertTrue(edit.commit())
        owner?.close()
        XCTAssertFalse(edit.startRendering())
        XCTAssertNil(owner?.begin(for: a, urls: [a]))
        owner = nil
        XCTAssertFalse(edit.apply())
    }
    func testMissingTargetDoesNotStartAnEditor() {
        let controller = Controller(urls: [a])
        controller.runVideoEditor(b)
        XCTAssertTrue(EditVideoController.instances.isEmpty)
        XCTAssertTrue(controller.analyticsMediaJourney!.steps.isEmpty)
    }
    func testVideoUsesValueEqualURLAndTransfersMetadataOnce() {
        let controller = Controller(urls: [a])
        let data = EditedVideoData(value: 2)
        controller.editedVideos[a] = EditedVideoData(value: 1)
        controller.previews[a.path] = "/cover"
        controller.runVideoEditor(URL(fileURLWithPath: a.path))
        let editor = EditVideoController.instances[0]
        XCTAssertTrue(editor.analyticsContext === controller.analyticsContext)
        editor.completion(b, data)
        editor.completion(URL(fileURLWithPath: "/duplicate"), nil)
        editor.onCancelled?()
        XCTAssertEqual(controller.urls, [b])
        XCTAssertEqual(controller.editedVideos, [b: data])
        XCTAssertEqual(controller.previews, [b.path: "/cover"])
        XCTAssertEqual(PendingVideoRenders.shared.cancelled, [a.path])
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openEditor, .applyEditor])
    }
    func testVideoCancelPreventsLaterOutput() {
        let controller = Controller(urls: [a])
        controller.runVideoEditor(a)
        let editor = EditVideoController.instances[0]
        editor.onCancelled?(); editor.onCancelled?(); editor.completion(b, nil)
        XCTAssertEqual(controller.urls, [a])
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openEditor, .cancelEditor])
    }
    func testVideoRejectsRemovedReaddedOrChangedChatAndClosedPreview() {
        for invalidation in 0..<4 {
            let controller = Controller(urls: [a])
            controller.runVideoEditor(a)
            let editor = EditVideoController.instances.last!
            switch invalidation {
            case 0: controller.urls = []; controller.urls = [a]
            case 1: controller.chatInteraction.revision += 1
            case 2: controller.pendingActions.close()
            default: controller.sent = true
            }
            editor.completion(b, EditedVideoData(value: 3))
            XCTAssertEqual(controller.urls, [a])
            XCTAssertTrue(controller.editedVideos.isEmpty)
            XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openEditor])
        }
    }
    func testVideoOldCallbackCannotReplaceNewEditorOutput() {
        let controller = Controller(urls: [a])
        controller.runVideoEditor(a)
        let old = EditVideoController.instances.last!
        controller.runVideoEditor(a)
        let current = EditVideoController.instances.last!
        old.completion(b, nil)
        XCTAssertEqual(controller.urls, [a])
        current.completion(b, nil)
        XCTAssertEqual(controller.urls, [b])
    }
    func testEditorCallbacksDoNotRetainPreview() {
        var controller: Controller? = Controller(urls: [a])
        controller?.runVideoEditor(a)
        let editor = EditVideoController.instances.last!
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        editor.completion(b, nil)
        editor.onCancelled?()
    }
}


final class CoverTests: XCTestCase {
    let video = URL(fileURLWithPath: "/video")
    let cover = URL(fileURLWithPath: "/cover")
    override func setUp() { fileCallbacks = []; EditImageModalController.instances = []; EditImageModalController.failConstruction = false; EditImageModalController.completeWithoutOutput = false }
    private func open(_ controller: Controller) -> FileCallbacks {
        controller.editVideoCover(for: video, media: TelegramMediaFile(dimensions: .init(size: 16)))
        return fileCallbacks.last!
    }
    func testExplicitPickerCancelAndSubsequentNilAreOneOutcome() {
        let controller = Controller(urls: [video])
        let callbacks = open(controller)
        callbacks.cancelled(); callbacks.completion(nil); callbacks.completion(["/image"])
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openCoverPicker, .cancelCoverPicker])
        XCTAssertTrue(EditImageModalController.instances.isEmpty)
    }
    func testUnknownAndEmptyPickerResultsAreDistinct() {
        let unknown = Controller(urls: [video])
        open(unknown).completion(nil)
        XCTAssertEqual(unknown.analyticsMediaJourney?.steps, [.openCoverPicker])
        XCTAssertTrue(unknown.analyticsMediaJourney!.blockers.isEmpty)
        let empty = Controller(urls: [video])
        open(empty).completion([])
        XCTAssertEqual(empty.analyticsMediaJourney?.blockers, [.emptySelection])
        XCTAssertTrue(EditImageModalController.instances.isEmpty)
    }
    func testCoverApplicationKeepsContextAndConsumesResultOnce() {
        let controller = Controller(urls: [video])
        let callbacks = open(controller)
        callbacks.completion(["/image"]); callbacks.completion(["/duplicate"])
        XCTAssertEqual(EditImageModalController.instances.count, 1)
        let editor = EditImageModalController.instances[0]
        XCTAssertTrue(editor.analyticsContext === controller.analyticsContext)
        XCTAssertEqual(editor.settings, .disableSizes(dimensions: 16, circle: false))
        editor.pipe.putNext((cover, nil)); editor.pipe.putNext((URL(fileURLWithPath: "/late"), nil))
        XCTAssertEqual(controller.previews, [video.path: cover.path])
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openCoverPicker, .openEditor, .applyCover])
    }
    func testEditorCancelPreventsCoverApplication() {
        let controller = Controller(urls: [video])
        open(controller).completion(["/image"])
        let editor = EditImageModalController.instances[0]
        editor.onCancelled?(); editor.onCancelled?(); editor.pipe.putNext((cover, nil))
        XCTAssertTrue(controller.previews.isEmpty)
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openCoverPicker, .openEditor, .cancelEditor])
    }
    func testRemovingCoverInvalidatesPendingSelectionEvenWhenAlreadyEmpty() {
        let controller = Controller(urls: [video])
        let callbacks = open(controller)
        controller.removeVideoCover(for: video)
        callbacks.completion(["/late"])
        XCTAssertTrue(EditImageModalController.instances.isEmpty)
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openCoverPicker])
    }
    func testRemovalRecordsOnlyActualChangeAndRejectsOldEditor() {
        let controller = Controller(urls: [video])
        controller.previews[video.path] = "/old"
        open(controller).completion(["/image"])
        let editor = EditImageModalController.instances[0]
        controller.removeVideoCover(for: video); controller.removeVideoCover(for: video)
        editor.pipe.putNext((cover, nil))
        XCTAssertTrue(controller.previews.isEmpty)
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openCoverPicker, .openEditor, .removeCover])
    }
    func testStaleAttachmentChatAndClosedPreviewRejectEditorOutput() {
        for state in 0..<3 {
            let controller = Controller(urls: [video])
            open(controller).completion(["/image"])
            let editor = EditImageModalController.instances.last!
            if state == 0 { controller.urls = []; controller.urls = [video] }
            if state == 1 { controller.chatInteraction.revision += 1 }
            if state == 2 { controller.pendingActions.close() }
            editor.pipe.putNext((cover, nil))
            XCTAssertTrue(controller.previews.isEmpty)
            XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openCoverPicker, .openEditor])
        }
    }
    func testConstructorFailureIsPreparationBlocker() {
        EditImageModalController.failConstruction = true
        let controller = Controller(urls: [video])
        open(controller).completion(["/image"])
        XCTAssertEqual(controller.analyticsMediaJourney?.blockers, [.preparation])
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openCoverPicker])
    }
    func testEditorCompletionWithoutOutputDoesNotInventCancellationOrApply() {
        EditImageModalController.completeWithoutOutput = true
        let controller = Controller(urls: [video])
        open(controller).completion(["/image"])
        let editor = EditImageModalController.instances[0]
        editor.onCancelled?(); editor.pipe.putNext((cover, nil))
        XCTAssertTrue(controller.previews.isEmpty)
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [.openCoverPicker, .openEditor])
    }
    func testMissingAttachmentAndCommittedPreviewDoNotOpenPicker() {
        let controller = Controller(urls: [])
        controller.editVideoCover(for: video, media: TelegramMediaFile())
        controller.urls = [video]
        controller.sent = true
        controller.editVideoCover(for: video, media: TelegramMediaFile())
        XCTAssertTrue(fileCallbacks.isEmpty)
        XCTAssertTrue(controller.analyticsMediaJourney!.steps.isEmpty)
    }
}
