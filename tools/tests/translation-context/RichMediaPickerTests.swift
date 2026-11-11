enum PickerType { case image, movie; func conforms(to other: PickerType) -> Bool { self == other } }
struct PickerURL {
    enum Key { case contentTypeKey }
    struct Values { let contentType: PickerType? }
    let path: String
    var type: PickerType? = .image
    var isImage = true
    func resourceValues(forKeys: Set<Key>) throws -> Values { Probe.check?(); return Values(contentType: type) }
}
struct PickerImage {
    init?(contentsOf url: PickerURL) { Probe.check?(); if !url.isImage { return nil } }
}
final class PickerPanel {
    enum Response { case OK, cancel }
    var allowedContentTypes: [PickerType] = []
    var allowsMultipleSelection = false
    var canChooseDirectories = true
    var urls: [PickerURL] = []
    var url: PickerURL? { urls.first }
    var completion: ((Response) -> Void)?
    init() { Probe.check?(); PickerProbe.panel = self }
    func beginSheetModal(for window: Int, completionHandler: @escaping (Response) -> Void) { Probe.check?(); completion = completionHandler }
    func finish(_ response: Response) { let callback = completion; completion = nil; callback?(response) }
}
struct PickerScreens {
    enum Screen { case systemFilePicker }
    func showStandalone(_ screen: Screen, owner: PickerPanel, context: AnalyticsContext) { Probe.check?(); PickerProbe.origin = context; PickerProbe.shows += 1 }
    func hideStandalone(owner: PickerPanel) { Probe.check?(); PickerProbe.hides += 1 }
}
extension Analytics { var screens: PickerScreens { PickerScreens() } }
struct MediaSenderContainer { let path: String; let isFile: Bool }
struct PickerMedia: Equatable { let id: Int }
final class PickerCache { var media: [String: PickerMedia] = [:] }
final class PickerEditor {
    var window: Int? = 1
    var inserted: [(String, [String])] = []
    var focuses = 0
    func makeEditorFirstResponder() { Probe.check?(); focuses += 1 }
    func insertMediaBlock(kind: String, mediaID: String) { Probe.check?(); inserted.append((kind, [mediaID])) }
    func insertMediaGroup(kind: String, mediaIDs: [String]) { Probe.check?(); inserted.append((kind, mediaIDs)) }
}
enum PickerSender {
    static func generateMedia(for container: MediaSenderContainer, account: Account, isSecretRelated: Bool) -> Signal<(PickerMedia, Int), NoError> {
        Probe.check?(); PickerProbe.requests.append(container); XCTAssertFalse(isSecretRelated)
        return Signal { sink in
            Probe.check?(); PickerProbe.sinks.append(sink)
            return ActionDisposable { Probe.check?(); PickerProbe.disposals += 1 }
        }
    }
}
func filePanel(with types: [String], allowMultiple: Bool, for window: Int, analyticsContext: AnalyticsContext?, completion: @escaping ([String]?) -> Void) {
    Probe.check?(); XCTAssertFalse(allowMultiple); PickerProbe.audioTypes = types; PickerProbe.origin = analyticsContext; PickerProbe.audioCompletion = completion
}
enum PickerProbe {
    static var panel: PickerPanel?
    static var origin: AnalyticsContext?
    static var shows = 0, hides = 0, disposals = 0
    static var requests: [MediaSenderContainer] = []
    static var sinks: [Subscriber<(PickerMedia, Int), NoError>] = []
    static var audioTypes: [String] = []
    static var audioCompletion: (([String]?) -> Void)?
    static func reset() { panel = nil; origin = nil; shows = 0; hides = 0; disposals = 0; requests = []; sinks = []; audioTypes = []; audioCompletion = nil }
}
enum RichMediaPickers {
__RICH_MEDIA_PICKERS__
}

final class PickerCoordinatorHost {
    let context: Context
    let mediaInteraction: ChatInteraction
    let captured: AnalyticsContext
    init(context: Context, analyticsContext: AnalyticsContext? = nil) {
__PICKER_COORDINATOR_INIT__
        captured = analyticsContext
    }
}
func makePickerCoordinator(context: Context, analyticsContext: AnalyticsContext) -> PickerCoordinatorHost {
__PICKER_COORDINATOR_CALL__
    return coordinator
}

final class RichMediaPickerTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.check = nil; PickerProbe.reset()
    }
    override func tearDown() { Probe.check = nil; PickerProbe.reset() }
    func origin(_ peer: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: peer) }
    func deliver(_ index: Int) { PickerProbe.sinks[index].putNext((PickerMedia(id: index), 0)); PickerProbe.sinks[index].putCompletion() }

    func testCoordinatorConstructionPassesParentOriginToMediaInteraction() {
        let source = origin()
        let coordinator = makePickerCoordinator(context: context, analyticsContext: source)
        XCTAssertTrue(coordinator.captured.scope === source.scope)
        XCTAssertTrue(coordinator.mediaInteraction.inheritedAnalyticsContext?.scope === source.scope)
        let legacy = PickerCoordinatorHost(context: context)
        XCTAssertTrue(legacy.captured.isExcluded)
        XCTAssertTrue(legacy.mediaInteraction.inheritedAnalyticsContext?.isExcluded == true)
    }

    func testSingleImageAndVideoPreserveScopeOptionsAndInsertionKind() {
        for video in [false, true] {
            PickerProbe.reset()
            let source = origin(), editor = PickerEditor(), cache = PickerCache(), disposable = MetaDisposable()
            RichMediaPickers.presentImagePicker(editor, context: context, cache: cache, disposable: disposable, analyticsContext: source)
            XCTAssertTrue(PickerProbe.origin?.scope === source.scope)
            XCTAssertEqual(PickerProbe.panel?.allowedContentTypes, [.image, .movie])
            XCTAssertEqual(PickerProbe.panel?.allowsMultipleSelection, true)
            XCTAssertEqual(PickerProbe.panel?.canChooseDirectories, false)
            PickerProbe.panel?.urls = [PickerURL(path: "synthetic", type: video ? .movie : .image, isImage: !video)]
            PickerProbe.panel?.finish(.OK)
            XCTAssertEqual(PickerProbe.requests.count, 1); XCTAssertFalse(PickerProbe.requests[0].isFile)
            XCTAssertTrue(editor.inserted.isEmpty)
            deliver(0)
            XCTAssertEqual(editor.inserted.first?.0, video ? "video" : "image")
            XCTAssertEqual(cache.media.count, 1); XCTAssertEqual(editor.focuses, 1)
            XCTAssertEqual(PickerProbe.hides, 1); disposable.dispose()
        }
    }

    func testCollageCapsAtTenAndWaitsForEveryMediaResult() {
        let editor = PickerEditor(), cache = PickerCache(), disposable = MetaDisposable()
        RichMediaPickers.presentImagePicker(editor, context: context, cache: cache, disposable: disposable, analyticsContext: origin())
        PickerProbe.panel?.urls = (0..<12).map { PickerURL(path: "item-\($0)") }
        PickerProbe.panel?.finish(.OK)
        XCTAssertEqual(PickerProbe.requests.count, 10)
        for index in 0..<9 { deliver(index) }
        XCTAssertTrue(editor.inserted.isEmpty)
        deliver(9)
        XCTAssertEqual(editor.inserted.count, 1); XCTAssertEqual(editor.inserted.first?.0, "collage")
        XCTAssertEqual(editor.inserted.first?.1.count, 10); XCTAssertEqual(cache.media.count, 10)
        disposable.dispose()
    }

    func testPrivateSheetAndGenerationStayExcludedUntilCompletion() {
        let source = origin(-1), editor = PickerEditor(), cache = PickerCache(), disposable = MetaDisposable()
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        RichMediaPickers.presentImagePicker(editor, context: context, cache: cache, disposable: disposable, analyticsContext: source)
        XCTAssertTrue(hub.policy.hasExclusions)
        PickerProbe.panel?.urls = [PickerURL(path: "private")]
        PickerProbe.panel?.finish(.OK)
        XCTAssertTrue(hub.policy.hasExclusions)
        deliver(0); disposable.dispose()
        XCTAssertEqual(editor.inserted.first?.0, "image")
        XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testCancelledEmptyAndUnreadableImageDoNotGenerateMedia() {
        for mode in 0..<3 {
            PickerProbe.reset()
            let editor = PickerEditor(), disposable = MetaDisposable()
            RichMediaPickers.presentImagePicker(editor, context: context, cache: PickerCache(), disposable: disposable, analyticsContext: origin(-1))
            if mode != 1 { PickerProbe.panel?.urls = [PickerURL(path: "invalid", type: nil, isImage: false)] }
            PickerProbe.panel?.finish(mode == 0 ? .cancel : .OK)
            XCTAssertEqual(PickerProbe.hides, 1); XCTAssertTrue(PickerProbe.requests.isEmpty)
            XCTAssertTrue(editor.inserted.isEmpty); XCTAssertFalse(hub.policy.hasExclusions)
            disposable.dispose()
        }
    }

    func testFilePickerChecksOriginalAfterAccountChangeAndPreservesFileMode() {
        let source = origin(), editor = PickerEditor(), cache = PickerCache(), disposable = MetaDisposable()
        RichMediaPickers.presentFilePicker(editor, context: context, cache: cache, disposable: disposable, analyticsContext: source)
        XCTAssertFalse(PickerProbe.panel!.allowsMultipleSelection)
        XCTAssertTrue(PickerProbe.origin?.scope === source.scope)
        hub.policy.setOwner(Account())
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        PickerProbe.panel?.urls = [PickerURL(path: "document")]
        PickerProbe.panel?.finish(.OK); XCTAssertTrue(PickerProbe.requests[0].isFile)
        deliver(0); disposable.dispose()
        XCTAssertEqual(editor.inserted.first?.0, "file"); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testRevokedOriginBeforeProviderDeliveryDoesNotAcquireFreshGrant() {
        let source = origin(), editor = PickerEditor(), disposable = MetaDisposable()
        RichMediaPickers.presentFilePicker(editor, context: context, cache: PickerCache(), disposable: disposable, analyticsContext: source)
        PickerProbe.panel?.urls = [PickerURL(path: "document")]; PickerProbe.panel?.finish(.OK)
        source.scope?.exclude()
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        deliver(0); disposable.dispose()
        XCTAssertEqual(editor.inserted.first?.0, "file"); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testAudioPanelPassesOriginAndGuardsRetainedCallback() {
        let source = origin(-1), editor = PickerEditor(), cache = PickerCache(), disposable = MetaDisposable()
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        RichMediaPickers.presentAudioPicker(editor, context: context, cache: cache, disposable: disposable, analyticsContext: source)
        XCTAssertTrue(PickerProbe.origin?.isExcluded == true)
        XCTAssertEqual(PickerProbe.audioTypes, ["mp3", "m4a", "aac", "flac", "ogg", "wav", "opus"])
        let callback = PickerProbe.audioCompletion; PickerProbe.audioCompletion = nil
        callback?(["track"])
        XCTAssertFalse(PickerProbe.requests[0].isFile)
        deliver(0); disposable.dispose()
        XCTAssertEqual(editor.inserted.first?.0, "audio"); XCTAssertEqual(cache.media.count, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testDisabledCollectionAndDisposedOrReleasedTargetsRemainFunctional() {
        hub.policy.isEnabled = false
        var editor: PickerEditor? = PickerEditor()
        let cache = PickerCache(), disposable = MetaDisposable()
        RichMediaPickers.presentAudioPicker(editor!, context: context, cache: cache, disposable: disposable, analyticsContext: origin())
        PickerProbe.audioCompletion?(["track"]); PickerProbe.audioCompletion = nil
        weak var observed = editor
        editor = nil
        XCTAssertNil(observed)
        deliver(0); disposable.dispose(); XCTAssertTrue(cache.media.isEmpty)
        XCTAssertFalse(hub.policy.hasExclusions)
        let next = PickerEditor(), pending = MetaDisposable()
        RichMediaPickers.presentAudioPicker(next, context: context, cache: cache, disposable: pending, analyticsContext: origin())
        PickerProbe.audioCompletion?(["track"]); PickerProbe.audioCompletion = nil
        pending.dispose(); deliver(1)
        XCTAssertTrue(next.inserted.isEmpty); XCTAssertTrue(cache.media.isEmpty)
        XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testMissingWindowAndAudioCancellationDoNotGenerateMedia() {
        let editor = PickerEditor(), cache = PickerCache(), disposable = MetaDisposable()
        editor.window = nil
        RichMediaPickers.presentFilePicker(editor, context: context, cache: cache, disposable: disposable, analyticsContext: origin())
        RichMediaPickers.presentImagePicker(editor, context: context, cache: cache, disposable: disposable, analyticsContext: origin())
        XCTAssertNil(PickerProbe.panel)
        RichMediaPickers.presentAudioPicker(editor, context: context, cache: cache, disposable: disposable, analyticsContext: origin())
        PickerProbe.audioCompletion?(nil); PickerProbe.audioCompletion = nil
        XCTAssertTrue(PickerProbe.requests.isEmpty); XCTAssertTrue(editor.inserted.isEmpty)
    }
}
