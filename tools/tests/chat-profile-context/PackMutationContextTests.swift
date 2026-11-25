enum StickerPackPreviewModalSource { case install, installGroupEmojiPack, removeGroupEmojiPack }
enum PackStickerReference { case stickerPack(stickerPack: StickerPackReference, media: TelegramMediaFile), standalone(media: TelegramMediaFile) }
extension CommonStrings {
    var messageContextDelete: String { "Delete" }
    var stickerPackAddedTitle: String { "Added" }
    var emojiPackAddedTitle: String { "Added emoji" }
    var stickerPackRemovedTitle: String { "Removed" }
    var emojiPackRemovedTitle: String { "Removed emoji" }
    func stickerPackAddedInfo(_ title: String) -> String { title }
    func emojiPackAddedInfo(_ title: String) -> String { title }
    func stickerPackRemovedInfo(_ title: String) -> String { title }
    func emojiPackRemovedInfo(_ title: String) -> String { title }
}
extension SavedStickers {
    enum Removal { case archive }
    func addStickerPackInteractively(info: PackInfo, items: [StickerPackItem]) -> Signal<Void, NoError> { PackMutationProbe.operation("install", id: info.id.id) }
    func removeStickerPackInteractively(id: PackCollectionId, option: Removal) -> Signal<Void, NoError> { PackMutationProbe.operation("remove", id: id.id) }
    func deleteStickerSet(packReference: StickerPackReference) -> Signal<Void, NoError> {
        guard case let .id(id, _) = packReference else { return .complete() }
        return PackMutationProbe.operation("delete_pack", id: id)
    }
    func deleteStickerFromStickerSet(sticker: PackStickerReference) -> Signal<Void, NoError> {
        guard case let .stickerPack(_, media) = sticker else { return .complete() }
        return PackMutationProbe.operation("delete_sticker", id: media.fileId)
    }
    func reorderSticker(sticker: PackStickerReference, position: Int) -> Signal<Void, NoError> {
        guard case let .standalone(media) = sticker else { return .complete() }
        PackMutationProbe.positions.append(position)
        return PackMutationProbe.operation("reorder", id: media.fileId)
    }
}
func showModalText(for window: Int, text: String, title: String) { PackMutationProbe.check?(); PackMutationProbe.feedback.append((title, text)) }
func verifyAlert(for window: Int, header: String, information: String, ok: String, successHandler: @escaping (Int) -> Void, onDeinit: @escaping () -> Void) {
    PackMutationProbe.check?(); PackMutationProbe.confirm = successHandler; PackMutationProbe.dismiss = onDeinit
}
struct PackActions {
    let deleteSticker: (PreviewState.Collection, TelegramMediaFile) -> Void
    let deletePack: (PreviewState.Collection) -> Void
    let install: (PreviewState.Source, PreviewState.Collection, Bool) -> Void
    let installAll: (PreviewState.Source, [PreviewState.Collection], Bool) -> Void
    let reorder: (PreviewState.Collection, TelegramMediaFile, Int) -> Void
    let state: () -> PackState
}
func makePackActions(context: any AccountContextProtocol, controllerSource: StickerPackPreviewModalSource = .install, collections: [PreviewState.Collection], getAnalyticsContext: @escaping () -> AnalyticsContext) -> PackActions {
    let stateValue = Atomic(value: PackState(preview: PreviewStateEquatable(.loaded(source: .stickers, collections: collections)), installed: Set(), premiumFile: nil))
    let updateState: ((PackState) -> PackState) -> Void = { f in PackMutationProbe.check?(); _ = stateValue.modify(f) }
    let close: (() -> Void)? = { PackMutationProbe.check?(); PackMutationProbe.closes += 1 }
    let onAdd: (() -> Void)? = { PackMutationProbe.check?(); PackMutationProbe.addCallbacks += 1 }
__PACK_ITEM_HELPERS__
__PACK_DELETE_STICKER__
__PACK_DELETE_SET__
    let addpack: (PreviewState.Source, PreviewState.Collection, Bool) -> Void = __PACK_INSTALL__
    let addAll: (PreviewState.Source, [PreviewState.Collection], Bool) -> Void = __PACK_INSTALL_ALL__
    let reorderSticker: (PreviewState.Collection, TelegramMediaFile, Int) -> Void = __PACK_REORDER__
    return PackActions(deleteSticker: deleteSticker, deletePack: deletePack, install: addpack, installAll: addAll, reorder: reorderSticker, state: { stateValue.with { $0 } })
}
enum PackMutationProbe {
    static var check: (() -> Void)?
    static var calls: [(String, Int64)] = []
    static var positions: [Int] = []
    static var sinks: [Subscriber<Void, NoError>] = []
    static var disposals = 0
    static var closes = 0
    static var addCallbacks = 0
    static var feedback: [(String, String)] = []
    static var confirm: ((Int) -> Void)?
    static var dismiss: (() -> Void)?
    static func operation(_ name: String, id: Int64) -> Signal<Void, NoError> {
        check?(); calls.append((name, id))
        return Signal { sink in check?(); sinks.append(sink); return ActionDisposable { check?(); disposals += 1 } }
    }
    static func finish() { for sink in sinks { sink.putNext(()); sink.putCompletion() }; sinks = [] }
    static func reset() {
        check = nil; finish(); confirm = nil; dismiss?(); dismiss = nil
        calls = []; positions = []; disposals = 0; closes = 0; addCallbacks = 0; feedback = []
    }
}
final class PackMutationContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        PackMutationProbe.reset(); PackProbe.reset(); TagProbe.reset()
        Analytics.shared = Analytics(); context = AccountContext(); hub.policy.setOwner(context.account); hub.policy.isEnabled = true
    }
    override func tearDown() { PackMutationProbe.reset(); PackProbe.reset(); TagProbe.reset(); context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func collection(_ id: Int64 = 42, installed: Bool = false, items: [StickerPackItem] = [1, 2]) -> PreviewState.Collection { .init(info: PackInfo(id: id), items: items, installed: installed) }
    func actions(_ source: AnalyticsContext, collections: [PreviewState.Collection]? = nil, mode: StickerPackPreviewModalSource = .install) -> PackActions {
        var modal: ReactionStickerModal? = StickerPackPreviewModalController(context, peerId: nil, references: [.stickers(42)], analyticsContext: source)
        let getOrigin = modal!.getOrigin; modal = nil
        return makePackActions(context: context, controllerSource: mode, collections: collections ?? [collection()], getAnalyticsContext: getOrigin)
    }
    func expectExcluded() { PackMutationProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testOrdinaryInstallationPreservesRequestFeedbackAndImmediateCallbackSemantics() {
        let actions = actions(origin()); actions.install(.stickers, collection(), true)
        XCTAssertEqual(PackMutationProbe.calls.map(\.0), ["install"]); XCTAssertEqual(PackMutationProbe.calls.first?.1, 42)
        XCTAssertEqual(PackMutationProbe.closes, 1); XCTAssertEqual(PackMutationProbe.addCallbacks, 1)
        XCTAssertEqual(PackMutationProbe.feedback.first?.0, "Added"); XCTAssertEqual(PackMutationProbe.disposals, 0)
        PackMutationProbe.finish(); XCTAssertEqual(PackMutationProbe.disposals, 1); XCTAssertEqual(PackMutationProbe.addCallbacks, 1)
    }
    func testPrivateInstallAndRemoveRemainGuardedAfterPreviewRelease() {
        let actions = actions(origin(.excluded)); expectExcluded()
        actions.install(.emoji, collection(), false); actions.install(.stickers, collection(installed: true), true)
        XCTAssertEqual(PackMutationProbe.calls.map(\.0), ["install", "remove"])
        XCTAssertTrue(actions.state().installed.contains(.emoji(.name("42"))))
        XCTAssertTrue(hub.policy.hasExclusions); PackMutationProbe.finish(); XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertEqual(PackMutationProbe.disposals, 2)
    }
    func testBulkInstallKeepsEveryProviderAndDisposalPrivate() {
        let actions = actions(origin(.excluded)); expectExcluded()
        actions.installAll(.stickers, [collection(), collection(43)], false)
        XCTAssertEqual(PackMutationProbe.calls.map(\.1), [42, 43]); XCTAssertEqual(actions.state().installed.count, 2)
        XCTAssertEqual(PackMutationProbe.addCallbacks, 1); PackMutationProbe.finish(); XCTAssertEqual(PackMutationProbe.disposals, 2)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testDeleteStickerDistinguishesRemainingItemFromLastItem() {
        let actions = actions(origin(.excluded)); expectExcluded()
        actions.deleteSticker(collection(), TelegramMediaFile(fileId: 1))
        actions.deleteSticker(collection(), TelegramMediaFile(fileId: 2))
        XCTAssertEqual(PackMutationProbe.calls.map(\.0), ["delete_sticker", "delete_pack"])
        XCTAssertEqual(PackMutationProbe.calls.map(\.1), [1, 42]); XCTAssertEqual(PackMutationProbe.closes, 1)
        PackMutationProbe.finish(); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPackDeletionConfirmationSurvivesActionsReleaseAndGuardsLateCommit() {
        var actions: PackActions? = actions(origin(.excluded)); expectExcluded()
        actions?.deletePack(collection()); actions = nil
        XCTAssertTrue(PackMutationProbe.calls.isEmpty); XCTAssertTrue(hub.policy.hasExclusions)
        PackMutationProbe.confirm?(0); PackMutationProbe.dismiss?(); PackMutationProbe.dismiss = nil
        XCTAssertEqual(PackMutationProbe.calls.map(\.0), ["delete_pack"]); XCTAssertEqual(PackMutationProbe.closes, 1)
        PackMutationProbe.finish(); PackMutationProbe.confirm = nil; XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testCancelledDeleteConfirmationDoesNotStartRequest() {
        let actions = actions(origin(.excluded)); expectExcluded(); actions.deletePack(collection())
        PackMutationProbe.dismiss?(); PackMutationProbe.dismiss = nil; PackMutationProbe.confirm = nil
        XCTAssertTrue(PackMutationProbe.calls.isEmpty); XCTAssertEqual(PackMutationProbe.closes, 0); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRevocationBetweenConfirmationAndCallbackCannotRenewScope() {
        let source = origin(); let actions = actions(source); actions.deletePack(collection())
        source.scope?.exclude(); expectExcluded(); PackMutationProbe.confirm?(0)
        PackMutationProbe.dismiss?(); PackMutationProbe.dismiss = nil; PackMutationProbe.finish(); PackMutationProbe.confirm = nil
        XCTAssertEqual(PackMutationProbe.calls.count, 1); XCTAssertFalse(source.scope?.isValid == true)
    }
    func testReorderPreservesLocalItemOrderAndSubmittedPosition() {
        let actions = actions(origin(.excluded)); expectExcluded(); actions.reorder(collection(), TelegramMediaFile(fileId: 1), 1)
        if case let .loaded(_, collections) = actions.state().preview.value {
            XCTAssertEqual(collections.first?.items.map { $0.file.fileId }, [2, 1])
        } else { XCTFail("Missing loaded preview") }
        XCTAssertEqual(PackMutationProbe.positions, [1]); XCTAssertEqual(PackMutationProbe.calls.map(\.0), ["reorder"])
        PackMutationProbe.finish(); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testAccountChangeAndDisabledCollectionDoNotGrantRetainedActions() {
        let actions = actions(origin()); let other = AccountContext(); hub.policy.setOwner(other.account); expectExcluded()
        actions.install(.stickers, collection(), true); PackMutationProbe.finish()
        hub.policy.isEnabled = false; actions.deleteSticker(collection(), TelegramMediaFile(fileId: 1)); PackMutationProbe.finish()
        XCTAssertEqual(PackMutationProbe.calls.count, 2)
    }
    func testGroupSelectionModeKeepsCallbackWithoutInstallingLocally() {
        let actions = actions(origin(.excluded), mode: .installGroupEmojiPack); expectExcluded()
        actions.install(.emoji, collection(), false)
        XCTAssertTrue(PackMutationProbe.calls.isEmpty); XCTAssertEqual(PackMutationProbe.closes, 1); XCTAssertEqual(PackMutationProbe.addCallbacks, 1)
    }
}
