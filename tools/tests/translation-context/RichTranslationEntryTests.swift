typealias Block = Int

enum RichEntryProbe {
    static var arguments: (String?, String, String, [Int], [Int])?
    static var origin: AnalyticsContext?
    static func reset() { arguments = nil; origin = nil }
}

extension ChatInputUIHooks {
    var makeRichTranslateModal: (Context, String?, String, String, [MessageTextEntity], [Block], @escaping ([Block]) -> Void) -> Modal {
        { context, _, _, _, _, _, use in
            Probe.check?()
            var state = State(); state.translatedRich = [7, 8]
            return makeTranslation(context, initialState: state, onUseRich: use)
        }
    }
}

func TranslateModalController(context: Context, from: String?, toLang: String, text: String, entities: [Int], richBlocks: [Int], onUseRich: @escaping ([Int]) -> Void, analyticsContext: AnalyticsContext) -> Modal {
    Probe.check?()
    RichEntryProbe.arguments = (from, toLang, text, entities, richBlocks)
    RichEntryProbe.origin = analyticsContext
    var state = State(); state.translatedRich = [7, 8]
    return makeTranslation(context, analyticsContext: analyticsContext, initialState: state, onUseRich: onUseRich)
}

func installRichTranslationBridge() {
    var hooks = ChatInputUIHooks()
__RICH_TRANSLATE_BRIDGE__
    ChatInputUIHooks.shared = hooks
}

final class RichEntryEditor {
    var withPasteContext: ((() -> Void) -> Void)?
    var blocks: [Block] = []
    var focuses = 0
    func replaceSelection(with blocks: [Block]) { Probe.check?(); self.blocks = blocks }
    func makeEditorFirstResponder() { Probe.check?(); focuses += 1 }
}

final class RichEntryCoordinator {
    let editor = RichEntryEditor()
}

func richEditorReceiver(context: Context, analyticsContext: AnalyticsContext, coordinator: RichEntryCoordinator) -> ([Block], AnalyticsContext) -> Void {
    return __RICH_EDITOR_RECEIVER__
}

final class RichTranslationEntryTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.check = nil; RichEntryProbe.reset(); installRichTranslationBridge()
    }
    override func tearDown() { Probe.check = nil; RichEntryProbe.reset() }

    func origin(_ peer: PeerId = 1) -> AnalyticsContext {
        hub.captureContext(engine: context.engine, peerId: peer)
    }

    func modal(_ source: AnalyticsContext, _ receive: @escaping ([Block], AnalyticsContext) -> Void) -> Modal {
        ChatInputUIHooks.shared.makeRichTranslateModalObserved(context, "en", "fr", "preview", [1, 2], [3, 4], analyticsContext: source, onUse: receive)
    }

    func testOrdinaryBridgePreservesScopeArgumentsAndRichApply() {
        let source = origin(), coordinator = RichEntryCoordinator()
        let value = modal(source, richEditorReceiver(context: context, analyticsContext: source, coordinator: coordinator))
        XCTAssertTrue(RichEntryProbe.origin?.scope === source.scope)
        XCTAssertEqual(RichEntryProbe.arguments?.0, "en")
        XCTAssertEqual(RichEntryProbe.arguments?.1, "fr")
        XCTAssertEqual(RichEntryProbe.arguments?.2, "preview")
        XCTAssertEqual(RichEntryProbe.arguments?.3, [1, 2])
        XCTAssertEqual(RichEntryProbe.arguments?.4, [3, 4])
        value.interactions?.accept()
        XCTAssertEqual(coordinator.editor.blocks, [7, 8]); XCTAssertEqual(coordinator.editor.focuses, 1)
        XCTAssertTrue(source.scope?.isValid == true)
    }

    func testPrivateApplyRemainsGuardedAfterModalRelease() {
        let source = origin(-1), coordinator = RichEntryCoordinator()
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var value: Modal? = modal(source, richEditorReceiver(context: context, analyticsContext: source, coordinator: coordinator))
        let apply = value!.interactions!.accept
        value = nil; RichEntryProbe.reset(); apply()
        XCTAssertEqual(coordinator.editor.blocks, [7, 8]); XCTAssertEqual(coordinator.editor.focuses, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testUnclassifiedChildPermanentlyExcludesReceivingEditorOrigin() {
        let source = origin(), coordinator = RichEntryCoordinator()
        let apply = richEditorReceiver(context: context, analyticsContext: source, coordinator: coordinator)
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        apply([9], hub.unresolvedContext())
        XCTAssertTrue(source.isExcluded)
        XCTAssertEqual(coordinator.editor.blocks, [9])
        Probe.check = nil
        XCTAssertTrue(origin().scope?.isValid == true)
        XCTAssertTrue(source.isExcluded)
        XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testChangedAccountAndRevokedOriginCannotBeReplacedByFreshGrant() {
        for changeAccount in [false, true] {
            let source = origin(), coordinator = RichEntryCoordinator()
            var returned: AnalyticsContext?
            let receiver = richEditorReceiver(context: context, analyticsContext: source, coordinator: coordinator)
            var value: Modal? = modal(source, { blocks, current in returned = current; receiver(blocks, current) })
            let apply = value!.interactions!.accept
            value = nil; RichEntryProbe.reset()
            if changeAccount { hub.policy.setOwner(Account()) } else { source.scope?.exclude() }
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            apply()
            XCTAssertFalse(returned?.scope?.isValid == true)
            XCTAssertTrue(source.isExcluded)
            XCTAssertEqual(coordinator.editor.blocks, [7, 8])
            Probe.check = nil; hub.policy.setOwner(context.engine.account)
        }
    }

    func testLegacyFactoryCannotClaimAnOrdinaryRichOutputOrigin() {
        ChatInputUIHooks.shared = ChatInputUIHooks()
        let source = origin(), coordinator = RichEntryCoordinator()
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let value = modal(source, richEditorReceiver(context: context, analyticsContext: source, coordinator: coordinator))
        value.interactions?.accept()
        XCTAssertTrue(source.isExcluded)
        XCTAssertEqual(coordinator.editor.blocks, [7, 8])
    }

    func testDisabledAnalyticsAndReleasedReceiverDoNotBreakTranslation() {
        hub.policy.isEnabled = false
        var coordinator: RichEntryCoordinator? = RichEntryCoordinator()
        weak var observed = coordinator
        var count = 0
        let source = origin()
        let receiver = richEditorReceiver(context: context, analyticsContext: source, coordinator: coordinator!)
        var value: Modal? = modal(source, { blocks, current in count += 1; receiver(blocks, current) })
        coordinator = nil
        XCTAssertNil(observed)
        value?.interactions?.accept()
        XCTAssertEqual(count, 1)
        value = nil
        XCTAssertFalse(hub.policy.hasExclusions)
    }
}
