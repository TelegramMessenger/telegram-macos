struct GroupControlsContext { let blockID: String }
final class GroupCache { var media: [String: Any] = [:] }
extension PickerEditor {
    func mediaID(forBlock blockID: String, tileIndex: Int?) -> String? {
        Probe.check?(); guard let values = GroupProbe.targets[blockID], values.indices.contains(tileIndex ?? 0) else { return nil }; return values[tileIndex ?? 0]
    }
    func addMediaToGroup(groupID: String, mediaIDs: [String]) { Probe.check?(); GroupProbe.targets[groupID, default: []].append(contentsOf: mediaIDs) }
    func convertMediaToGroup(blockID: String, kind: String, addingMediaIDs: [String]) { Probe.check?(); XCTAssertEqual(kind, "collage"); GroupProbe.converted = true; GroupProbe.targets[blockID, default: []].append(contentsOf: addingMediaIDs) }
    func replaceGroupMedia(groupID: String, index: Int, newMediaID: String) { Probe.check?(); guard var values = GroupProbe.targets[groupID], values.indices.contains(index) else { return }; values[index] = newMediaID; GroupProbe.targets[groupID] = values }
    func replaceMedia(blockID: String, newMediaID: String) { Probe.check?(); guard GroupProbe.targets[blockID] != nil else { return }; GroupProbe.targets[blockID] = [newMediaID] }
}
struct PixelDimensions { init(_ width: Int, _ height: Int) { XCTAssertEqual(width, 1280); XCTAssertEqual(height, 1280) } }
struct GroupResource {}
final class GroupImage {
    struct Representation { let resource = GroupResource() }
    func representationForDisplayAtSize(_ size: PixelDimensions) -> Representation? { Probe.check?(); return Representation() }
}
struct GroupData { let complete: Bool; let path: String }
struct GroupMediaBox {
    func resourceData(_ resource: GroupResource) -> Signal<GroupData, NoError> {
        Probe.check?()
        if let immediate = GroupProbe.immediateData { return .single(immediate) }
        return Signal { sink in Probe.check?(); GroupProbe.dataSink = sink; return ActionDisposable { Probe.check?(); GroupProbe.dataDisposals += 1 } }
    }
}
struct GroupPostbox { let mediaBox = GroupMediaBox() }
extension Account { var postbox: GroupPostbox { GroupPostbox() } }
enum GroupUserLocation { case other }
enum GroupContent { case image }
enum GroupReference { case standalone(resource: GroupResource) }
func fetchedMediaResource(mediaBox: GroupMediaBox, userLocation: GroupUserLocation, userContentType: GroupContent, reference: GroupReference) -> Signal<Void, NoError> {
    Probe.check?(); return Signal { sink in Probe.check?(); GroupProbe.fetches += 1; return ActionDisposable { Probe.check?(); GroupProbe.fetchDisposals += 1 } }
}
let kMediaImageExt = "jpg"
func link(path: String, ext: String) -> String? { Probe.check?(); return GroupProbe.linkAvailable ? path : nil }
struct GroupNavigationHooks {
    static var shared = GroupNavigationHooks()
    func editImageObserved(_ context: Context, _ url: URL, _ data: Int?, analyticsContext: AnalyticsContext) -> Signal<(URL, Int?), NoError> {
        Probe.check?(); GroupProbe.editOrigin = analyticsContext; GroupProbe.editURL = url
        if let immediate = GroupProbe.immediateEdit { return .single((immediate, nil)) }
        return Signal { sink in Probe.check?(); GroupProbe.editSink = sink; return ActionDisposable { Probe.check?(); GroupProbe.editDisposals += 1 } }
    }
}
enum GroupProbe {
    static var targets: [String: [String]] = [:]
    static var converted = false, linkAvailable = true
    static var immediateData: GroupData?
    static var immediateEdit: URL?
    static var dataSink: Subscriber<GroupData, NoError>?
    static var editSink: Subscriber<(URL, Int?), NoError>?
    static var editOrigin: AnalyticsContext?
    static var editURL: URL?
    static var fetches = 0, fetchDisposals = 0, dataDisposals = 0, editDisposals = 0
    static func reset() { targets = ["block": ["old", "other"]]; converted = false; linkAvailable = true; immediateData = nil; immediateEdit = nil; dataSink = nil; editSink = nil; editOrigin = nil; editURL = nil; fetches = 0; fetchDisposals = 0; dataDisposals = 0; editDisposals = 0 }
}
enum RichGroupMedia {
__GROUP_HELPERS__
}
final class RichGroupMediaTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() { Probe.check = nil; PickerProbe.reset(); GroupProbe.reset(); Analytics.shared = Analytics(); context = Context(); hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true }
    override func tearDown() { Probe.check = nil; PickerProbe.reset(); GroupProbe.reset() }
    func origin(_ peer: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: peer) }
    func generated(_ index: Int) { PickerProbe.sinks[index].putNext((PickerMedia(id: index), 0)); PickerProbe.sinks[index].putCompletion() }
    func edit(_ editor: PickerEditor, _ cache: GroupCache, _ disposable: MetaDisposable, _ source: AnalyticsContext) {
        cache.media["old"] = GroupImage()
        RichGroupMedia.presentMediaEditor(editor, ctx: .init(blockID: "block"), tileIndex: 0, isGroup: true, mediaID: "old", accountContext: context, cache: cache, disposable: disposable, analyticsContext: source)
    }

    func testGroupAdditionAndSingleConversionKeepPanelOptionsAndCap() {
        for convert in [false, true] {
            setUp()
            let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable(), source = origin()
            RichGroupMedia.presentAddToGroupPicker(editor, context: context, cache: cache, disposable: disposable, groupID: convert ? nil : "block", convertBlockID: convert ? "block" : nil, analyticsContext: source)
            XCTAssertTrue(PickerProbe.origin?.scope === source.scope); XCTAssertTrue(PickerProbe.panel!.allowsMultipleSelection); XCTAssertFalse(PickerProbe.panel!.canChooseDirectories)
            PickerProbe.panel!.urls = (0..<12).map { PickerURL(path: "image-\($0)") }; PickerProbe.panel!.finish(.OK)
            XCTAssertEqual(PickerProbe.requests.count, 10); XCTAssertTrue(PickerProbe.requests.allSatisfy { !$0.isFile })
            for i in 0..<9 { generated(i) }; XCTAssertEqual(cache.media.count, 0)
            generated(9); XCTAssertEqual(cache.media.count, 10); XCTAssertEqual(GroupProbe.targets["block"]?.count, 12); XCTAssertEqual(GroupProbe.converted, convert)
            disposable.dispose(); tearDown()
        }
    }

    func testPrivateAdditionAndReplacementGuardSheetAndDelayedGeneration() {
        for replace in [false, true] {
            setUp(); let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable(), source = origin(-1)
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            if replace { RichGroupMedia.presentReplacePicker(editor, ctx: .init(blockID: "block"), tileIndex: 1, isGroup: true, accountContext: context, cache: cache, disposable: disposable, analyticsContext: source) }
            else { RichGroupMedia.presentAddToGroupPicker(editor, context: context, cache: cache, disposable: disposable, groupID: "block", convertBlockID: nil, analyticsContext: source) }
            XCTAssertTrue(hub.policy.hasExclusions); PickerProbe.panel!.urls = [PickerURL(path: "image")]; PickerProbe.panel!.finish(.OK)
            generated(0); disposable.dispose(); XCTAssertEqual(cache.media.count, 1); XCTAssertFalse(hub.policy.hasExclusions); tearDown()
        }
    }

    func testCancelledEmptyOrMissingTargetDoesNotGenerate() {
        for mode in 0..<3 {
            setUp(); let disposable = MetaDisposable()
            if mode == 2 { GroupProbe.targets = [:] }
            RichGroupMedia.presentAddToGroupPicker(PickerEditor(), context: context, cache: GroupCache(), disposable: disposable, groupID: "block", convertBlockID: nil, analyticsContext: origin())
            PickerProbe.panel?.finish(mode == 0 ? .cancel : .OK)
            XCTAssertTrue(PickerProbe.requests.isEmpty); disposable.dispose(); tearDown()
        }
    }

    func testReplacedOrRemovedTargetIsNotOverwrittenByPickerResult() {
        for mode in 0..<2 {
            setUp(); let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable()
            RichGroupMedia.presentReplacePicker(editor, ctx: .init(blockID: "block"), tileIndex: 0, isGroup: mode == 0, accountContext: context, cache: cache, disposable: disposable, analyticsContext: origin())
            PickerProbe.panel!.urls = [PickerURL(path: "image")]; PickerProbe.panel!.finish(.OK)
            GroupProbe.targets["block"] = mode == 0 ? ["changed", "other"] : nil
            generated(0); XCTAssertTrue(cache.media.isEmpty); XCTAssertEqual(editor.focuses, 0); disposable.dispose(); tearDown()
        }
    }

    func testEditWaitsForCompleteResourceAndPreservesOriginalThroughSave() {
        let source = origin(), editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable()
        edit(editor, cache, disposable, source)
        GroupProbe.dataSink?.putNext(.init(complete: false, path: "/partial")); XCTAssertNil(GroupProbe.editOrigin)
        GroupProbe.dataSink?.putNext(.init(complete: true, path: "/original"))
        XCTAssertTrue(GroupProbe.editOrigin?.scope === source.scope)
        GroupProbe.editSink?.putNext((URL(fileURLWithPath: "/edited"), nil)); generated(0)
        XCTAssertNotEqual(GroupProbe.targets["block"]?.first, "old"); XCTAssertEqual(editor.focuses, 1); disposable.dispose()
        XCTAssertEqual(GroupProbe.fetchDisposals, 1)
    }

    func testSynchronousResourceAndEditorDoNotDisposePendingGeneration() {
        GroupProbe.immediateData = .init(complete: true, path: "/original"); GroupProbe.immediateEdit = URL(fileURLWithPath: "/edited")
        let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable()
        edit(editor, cache, disposable, origin())
        XCTAssertEqual(PickerProbe.disposals, 0); XCTAssertEqual(PickerProbe.requests.count, 1)
        generated(0); XCTAssertEqual(editor.focuses, 1); disposable.dispose()
    }

    func testEditAccountChangeAndPrivateOriginGuardEveryDelayedStage() {
        for changed in [false, true] {
            setUp(); let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable()
            edit(editor, cache, disposable, origin(changed ? 1 : -1))
            if changed { hub.policy.setOwner(Account()) }
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            GroupProbe.dataSink?.putNext(.init(complete: true, path: "/original"))
            GroupProbe.editSink?.putNext((URL(fileURLWithPath: "/edited"), nil)); generated(0); disposable.dispose()
            XCTAssertEqual(editor.focuses, 1); XCTAssertFalse(hub.policy.hasExclusions); tearDown()
        }
    }

    func testEditStaleAtResourceSaveOrGenerationDoesNotReplace() {
        for stage in 0..<3 {
            setUp(); let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable()
            edit(editor, cache, disposable, origin())
            if stage == 0 { GroupProbe.targets = [:] }
            GroupProbe.dataSink?.putNext(.init(complete: true, path: "/original"))
            if stage == 1 { GroupProbe.targets = [:] }
            GroupProbe.editSink?.putNext((URL(fileURLWithPath: "/edited"), nil))
            if stage == 2 { GroupProbe.targets = [:]; generated(0) }
            XCTAssertEqual(cache.media.count, 1); XCTAssertEqual(editor.focuses, 0); disposable.dispose(); tearDown()
        }
    }

    func testCancelledUnchangedOrUnlinkableEditDoesNotGenerate() {
        for mode in 0..<3 {
            setUp(); let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable()
            edit(editor, cache, disposable, origin())
            GroupProbe.linkAvailable = mode != 2
            GroupProbe.dataSink?.putNext(.init(complete: true, path: "/original"))
            if mode == 0 { GroupProbe.editSink?.putCompletion() }
            if mode == 1 { GroupProbe.editSink?.putNext((URL(fileURLWithPath: "/original"), nil)) }
            XCTAssertTrue(PickerProbe.requests.isEmpty); XCTAssertEqual(editor.focuses, 0); disposable.dispose(); tearDown()
        }
    }

    func testRemovedGroupDoesNotPopulateCacheAndDisabledReplacementStillWorks() {
        let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable()
        RichGroupMedia.presentAddToGroupPicker(editor, context: context, cache: cache, disposable: disposable, groupID: "block", convertBlockID: nil, analyticsContext: origin())
        PickerProbe.panel!.urls = [PickerURL(path: "image")]; PickerProbe.panel!.finish(.OK)
        GroupProbe.targets = [:]; generated(0); XCTAssertTrue(cache.media.isEmpty)
        disposable.set(nil); PickerProbe.reset(); GroupProbe.reset(); hub.policy.isEnabled = false
        RichGroupMedia.presentReplacePicker(editor, ctx: .init(blockID: "block"), tileIndex: 0, isGroup: false, accountContext: context, cache: cache, disposable: disposable, analyticsContext: origin())
        XCTAssertFalse(PickerProbe.panel!.allowsMultipleSelection)
        PickerProbe.panel!.urls = [PickerURL(path: "replacement")]; PickerProbe.panel!.finish(.OK)
        generated(0); XCTAssertEqual(cache.media.count, 1); XCTAssertEqual(GroupProbe.targets["block"]?.count, 1)
        disposable.dispose()
    }

    func testDisposalCancelsFetchResourceAndEditorWithNoLateMutation() {
        let editor = PickerEditor(), cache = GroupCache(), disposable = MetaDisposable()
        edit(editor, cache, disposable, origin(-1))
        GroupProbe.dataSink?.putNext(.init(complete: true, path: "/original")); disposable.dispose()
        XCTAssertEqual(GroupProbe.fetchDisposals, 1); XCTAssertEqual(GroupProbe.editDisposals, 1)
        GroupProbe.editSink?.putNext((URL(fileURLWithPath: "/edited"), nil))
        XCTAssertTrue(PickerProbe.requests.isEmpty); XCTAssertFalse(hub.policy.hasExclusions)
    }
}
