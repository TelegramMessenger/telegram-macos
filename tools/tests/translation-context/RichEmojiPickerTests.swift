struct RichEmojiFile: Equatable {
    struct ID: Equatable { let id: Int64 }
    let fileId: ID
    let customEmojiText: String?
    let stickerText: String?
}
struct RichEmojiSticker {
    struct File {
        let value: RichEmojiFile
        func _parse() -> RichEmojiFile { Probe.check?(); return value }
    }
    let file: File
}
struct RichEmojiGift: Equatable { let id: Int }
struct RichEmojiCollection: Equatable { let id: Int }
typealias RichAnimatedSelection = (RichEmojiSticker, RichEmojiGift?, RichEmojiCollection?, Int32?, NSRect?) -> Void
typealias RichPlainSelection = (String, CGRect?) -> Void
final class RichEmojiInteractions {
    enum Kind { case emoji }
    var sendAnimatedEmoji: RichAnimatedSelection = { _, _, _, _, _ in }
    var sendEmoji: RichPlainSelection = { _, _ in }
    let peerId: PeerId
    init(_ kind: Kind, peerId: PeerId) { Probe.check?(); self.peerId = peerId }
}
final class RichEmojiController {
    enum Screen { case appEmojiPicker }
    var analyticsScreen: Screen?
    var analyticsContext: AnalyticsContext? { didSet { presentation = analyticsContext?.beginPresentation() } }
    var presentation: AnalyticsPresentation?
    var showsGlassSurface = false
    var _frameRect = NSRect.zero
    var interactions: RichEmojiInteractions?
    var chatInteraction: ChatInteraction?
    init(_ context: Context, ignorePremium: Bool) { Probe.check?(); XCTAssertTrue(ignorePremium) }
    func update(with interactions: RichEmojiInteractions, chatInteraction: ChatInteraction) {
        Probe.check?(); self.interactions = interactions; self.chatInteraction = chatInteraction
    }
}
struct RichEmojiHooks {
    static var shared = RichEmojiHooks()
    var makeEmojiPicker: (Context, @escaping RichAnimatedSelection, @escaping RichPlainSelection) -> RichEmojiController = { context, animated, plain in
        let controller = RichEmojiController(context, ignorePremium: true)
        let interactions = RichEmojiInteractions(.emoji, peerId: context.peerId)
        interactions.sendAnimatedEmoji = animated; interactions.sendEmoji = plain; controller.interactions = interactions
        return controller
    }
__RICH_EMOJI_HOOK__
}
func installRichEmojiFixture() {
    var hooks = RichEmojiHooks()
__RICH_EMOJI_BRIDGE__
    RichEmojiHooks.shared = hooks
}
final class RichEmojiCache { var files: [String: RichEmojiFile] = [:] }
final class RichEmojiEditor {
    var selections: [(String, String?)] = []
    var text: [String] = []
    var focuses = 0
    func makeEditorFirstResponder() { Probe.check?(); focuses += 1 }
    func insertEmoji(id: String, altText: String?) { Probe.check?(); selections.append((id, altText)) }
    func insertText(_ string: String) { Probe.check?(); text.append(string) }
}
enum RichEmojiPicker {
__RICH_EMOJI_PICKER__
}
enum RichEmojiProbe { static var picker: RichEmojiController? }
func showPopover(for control: Int, with picker: RichEmojiController) { Probe.check?(); XCTAssertEqual(control, 1); RichEmojiProbe.picker = picker }

final class RichEmojiPickerTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.check = nil; RichEmojiProbe.picker = nil; Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true; installRichEmojiFixture()
    }
    override func tearDown() { Probe.check = nil; RichEmojiProbe.picker = nil; RichEmojiHooks.shared = RichEmojiHooks() }
    func origin(_ peer: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: peer) }
    func sticker(_ alt: String? = "custom") -> RichEmojiSticker { .init(file: .init(value: .init(fileId: .init(id: 42), customEmojiText: alt, stickerText: "fallback"))) }
    func present(_ editor: RichEmojiEditor, _ cache: RichEmojiCache, _ source: AnalyticsContext) {
        RichEmojiPicker.presentEmojiPicker(editor, context: context, cache: cache, from: 1, analyticsContext: source)
    }

    func testOrdinaryPickerKeepsExactOriginAndConfiguration() {
        let source = origin(), editor = RichEmojiEditor(), cache = RichEmojiCache()
        Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        present(editor, cache, source)
        let picker = RichEmojiProbe.picker!
        XCTAssertTrue(picker.analyticsContext?.scope === source.scope)
        XCTAssertTrue(picker.chatInteraction?.inheritedAnalyticsContext?.scope === source.scope)
        XCTAssertEqual(picker.analyticsScreen, .appEmojiPicker); XCTAssertTrue(picker.showsGlassSurface)
        XCTAssertEqual(picker._frameRect, NSMakeRect(0, 0, 350, 300)); XCTAssertEqual(picker.interactions?.peerId, context.peerId)
        picker.interactions?.sendAnimatedEmoji(sticker(), nil, nil, nil, nil)
        picker.interactions?.sendEmoji("🙂", nil)
        XCTAssertEqual(editor.selections.first?.0, "42"); XCTAssertEqual(editor.selections.first?.1, "custom")
        XCTAssertEqual(cache.files["42"], sticker().file.value); XCTAssertEqual(editor.text, ["🙂"]); XCTAssertEqual(editor.focuses, 2)
    }

    func testPrivateSelectionRemainsGuardedAfterPickerRelease() {
        let editor = RichEmojiEditor(), cache = RichEmojiCache()
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        present(editor, cache, origin(-1))
        let animated = RichEmojiProbe.picker!.interactions!.sendAnimatedEmoji
        let plain = RichEmojiProbe.picker!.interactions!.sendEmoji
        XCTAssertTrue(RichEmojiProbe.picker!.chatInteraction!.inheritedAnalyticsContext!.isExcluded)
        RichEmojiProbe.picker = nil; XCTAssertFalse(hub.policy.hasExclusions)
        animated(sticker(), nil, nil, nil, nil); plain("🙂", nil)
        XCTAssertEqual(editor.selections.count, 1); XCTAssertEqual(editor.text.count, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testChangedAccountAndRevokedOriginDoNotMintFreshSelectionScope() {
        for changedOwner in [false, true] {
            setUp()
            let source = origin(), editor = RichEmojiEditor(), cache = RichEmojiCache()
            present(editor, cache, source)
            let animated = RichEmojiProbe.picker!.interactions!.sendAnimatedEmoji
            let plain = RichEmojiProbe.picker!.interactions!.sendEmoji
            RichEmojiProbe.picker = nil
            if changedOwner { hub.policy.setOwner(Account()) } else { source.scope?.exclude() }
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            animated(sticker(), nil, nil, nil, nil); plain("🙂", nil)
            XCTAssertEqual(editor.focuses, 2)
            tearDown()
        }
    }

    func testLegacyFallbackExcludesOriginalEditorScope() {
        RichEmojiHooks.shared.makeEmojiPickerWithContext = nil
        let source = origin(), editor = RichEmojiEditor(), cache = RichEmojiCache()
        present(editor, cache, source)
        XCTAssertTrue(source.isExcluded); XCTAssertTrue(RichEmojiProbe.picker!.analyticsContext!.isExcluded)
        let plain = RichEmojiProbe.picker!.interactions!.sendEmoji
        RichEmojiProbe.picker = nil
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        plain("🙂", nil); XCTAssertEqual(editor.text, ["🙂"])
    }

    func testHookForwardsSelectionMetadataWithoutChangingIt() {
        let rect = NSRect(x: 1, y: 2, width: 3, height: 4)
        var animated = 0, plain = 0
        let picker = RichEmojiHooks.shared.makeEmojiPickerObserved(context, analyticsContext: origin(), sendAnimatedEmoji: { value, gift, collection, index, frame in
            animated += 1; XCTAssertEqual(value.file.value.fileId.id, 42)
            XCTAssertEqual(gift, .init(id: 3)); XCTAssertEqual(collection, .init(id: 4))
            XCTAssertEqual(index, 5); XCTAssertEqual(frame, rect)
        }, sendEmoji: { value, frame in plain += 1; XCTAssertEqual(value, "🙂"); XCTAssertEqual(frame, rect) })
        picker.interactions?.sendAnimatedEmoji(sticker(), .init(id: 3), .init(id: 4), 5, rect)
        picker.interactions?.sendEmoji("🙂", rect)
        XCTAssertEqual(animated, 1); XCTAssertEqual(plain, 1)
    }

    func testStickerAltFallbackAndRepeatedSelectionsRemainFunctional() {
        let editor = RichEmojiEditor(), cache = RichEmojiCache()
        present(editor, cache, origin())
        for _ in 0..<2 { RichEmojiProbe.picker?.interactions?.sendAnimatedEmoji(sticker(nil), nil, nil, nil, nil) }
        XCTAssertEqual(editor.selections.count, 2); XCTAssertEqual(editor.selections.first?.1, "fallback"); XCTAssertEqual(cache.files.count, 1)
    }

    func testReleasedEditorDoesNotRetainOrMutateCache() {
        var editor: RichEmojiEditor? = RichEmojiEditor(); weak var weakEditor = editor
        let cache = RichEmojiCache()
        present(editor!, cache, origin())
        editor = nil; XCTAssertNil(weakEditor)
        RichEmojiProbe.picker?.interactions?.sendAnimatedEmoji(sticker(), nil, nil, nil, nil)
        RichEmojiProbe.picker?.interactions?.sendEmoji("🙂", nil)
        XCTAssertTrue(cache.files.isEmpty)
    }

    func testUnknownAndDisabledOriginsStillAllowInsertion() {
        for disabled in [false, true] {
            hub.policy.isEnabled = !disabled
            let editor = RichEmojiEditor(), cache = RichEmojiCache()
            present(editor, cache, disabled ? origin() : hub.unresolvedContext())
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            RichEmojiProbe.picker?.interactions?.sendEmoji("🙂", nil)
            XCTAssertEqual(editor.text, ["🙂"])
            Probe.check = nil; RichEmojiProbe.picker = nil
        }
    }
}

struct PremiumBoardingController {
    let origin: AnalyticsContext
    init(context: Context, source: PremiumLogEventsSource, openFeatures: Bool, analyticsContext: AnalyticsContext) {
        Probe.check?(); XCTAssertEqual(source, .rich_formatting); XCTAssertTrue(openFeatures); origin = analyticsContext
    }
}
enum RichPremiumProbe { static var origin: AnalyticsContext?; static var presentations = 0 }
func prem(with controller: PremiumBoardingController, for window: Int) { Probe.check?(); XCTAssertEqual(window, 1); RichPremiumProbe.origin = controller.origin; RichPremiumProbe.presentations += 1 }
func makeRichPremiumAction(context: Context, analyticsContext: AnalyticsContext) -> () -> Void {
__RICH_PREMIUM_ACTION__
    return showPremiumFormatting
}
extension RichEmojiPickerTests {
    func testPremiumActionPreservesOrdinaryAndExcludedAncestry() {
        for privateOrigin in [false, true] {
            let source = origin(privateOrigin ? -1 : 1)
            RichPremiumProbe.origin = nil; RichPremiumProbe.presentations = 0
            Probe.check = { XCTAssertEqual(self.hub.policy.hasExclusions, privateOrigin) }
            let action = makeRichPremiumAction(context: context, analyticsContext: source)
            action()
            XCTAssertEqual(RichPremiumProbe.presentations, 1)
            if privateOrigin { XCTAssertTrue(RichPremiumProbe.origin!.isExcluded) }
            else { XCTAssertTrue(RichPremiumProbe.origin?.scope === source.scope) }
        }
        Probe.check = nil; RichPremiumProbe.origin = nil
    }

    func testRetainedPremiumActionRechecksAccountAndRevocation() {
        for changedOwner in [false, true] {
            setUp()
            let source = origin(), action = makeRichPremiumAction(context: context, analyticsContext: origin())
            let revokedAction = makeRichPremiumAction(context: context, analyticsContext: source)
            if changedOwner { hub.policy.setOwner(Account()) } else { source.scope?.exclude() }
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            if changedOwner { action() } else { revokedAction() }
            let presentation = RichPremiumProbe.origin!.beginPresentation()
            XCTAssertTrue(hub.policy.hasExclusions); presentation.end()
            RichPremiumProbe.origin = nil; tearDown()
        }
    }
}
