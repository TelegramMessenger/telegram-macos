enum SavedLocationTag: Equatable { case customTag(MessageReaction.Reaction, Int?) }
enum ReactionsMessageAttribute {
    static func messageTag(reaction: MessageReaction.Reaction) -> MessageReaction.Reaction { reaction }
}
extension AccountContextProtocol { var isPremium: Bool { concrete.isPremium } }
enum SavedPremiumProbe {
    static var morph: (() -> AnyObject?)?
    static var check: (() -> Void)?
    static var sink: Subscriber<Int, NoError>?
    static var disposals = 0
    static func reset() { morph = nil; check = nil; sink = nil; disposals = 0 }
}
func savedPremiumInput() -> Signal<Int, NoError> {
    SavedPremiumProbe.check?()
    return Signal { sink in
        SavedPremiumProbe.check?(); SavedPremiumProbe.sink = sink
        return ActionDisposable { SavedPremiumProbe.check?(); SavedPremiumProbe.disposals += 1 }
    }
}
struct SavedPremiumMenu {
    let link: (Int) -> Void
    let reveal: () -> Void
    let add: () -> Void
}
func savedPremiumMenu(_ chatInteraction: ChatInteraction, message: Message, peer: Peer) -> Signal<SavedPremiumMenu, NoError> {
    let context = chatInteraction.interactionContext
    let isTags = context.peerId == chatInteraction.peerId
__PREMIUM_MENU_ORIGIN__
    let signal = savedPremiumInput()
    return __PREMIUM_MENU_SIGNAL__ |> map { _ in
        SavedPremiumProbe.check?()
        let link: (Int) -> Void = __PREMIUM_MENU_LINK__
        return SavedPremiumMenu(link: link, reveal: {
__PREMIUM_MENU_REVEAL__
        }, add: {
__PREMIUM_MENU_ADD__
        })
    }
}
func savedPremiumEffects(_ chatInteraction: ChatInteraction) -> Signal<(Int) -> Void, NoError> {
    let context = chatInteraction.interactionContext
__PREMIUM_EFFECTS_ORIGIN__
    let reactions = savedPremiumInput()
    return __PREMIUM_EFFECTS_SIGNAL__ |> map { _ in
        SavedPremiumProbe.check?()
        let link: (Int) -> Void = __PREMIUM_EFFECTS_LINK__
        return link
    }
}
final class SavedPremiumView {
    var context: (any AccountContextProtocol)?
    var analyticsContext: AnalyticsContext?
    func clickAction() -> (Int) -> Void {
        return __PREMIUM_VIEW_CALLBACK__
    }
    func set(context: any AccountContextProtocol, analyticsContext: AnalyticsContext) {
__PREMIUM_VIEW_SET__
    }
}
func setSavedPremiumView(_ current: SavedPremiumView, context: any AccountContextProtocol, analyticsContext: AnalyticsContext) {
__PREMIUM_VIEW_HANDOFF__
}
func savedPremiumRowAction(_ chatInteraction: ChatInteraction, message: Message) -> (SavedReactionLayout, (MessageReaction.Reaction) -> Void) {
    let context = chatInteraction.interactionContext
__PREMIUM_ROW_ORIGIN__
    let layout = SavedReactionLayout(context: context, message: message, analyticsContext: origin)
    let action: (MessageReaction.Reaction) -> Void = __PREMIUM_ROW_CALLBACK__
    return (layout, action)
}
final class SavedPremiumHeader {
    let parentInteractions: ChatInteraction
    var tagsView: SavedSearchTags?
    init(_ parent: ChatInteraction) { parentInteractions = parent; tagsView = SavedSearchTags() }
    func update() -> (EmojiTag?) -> Void {
__PREMIUM_HEADER_ORIGIN__
        let action: (EmojiTag?) -> Void = __PREMIUM_HEADER_CALLBACK__
        tagsView?.set(tags: [], context: context, analyticsContext: origin, animated: false, callback: action)
        return action
    }
}
final class SavedTagPremiumTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        RecommendationProbe.premium = []; RecommendationProbe.events = []
        Probe.construction = nil; SavedPremiumProbe.reset()
    }
    override func tearDown() {
        Probe.construction = nil; SavedPremiumProbe.reset()
        RecommendationProbe.premium = []; RecommendationProbe.events = []; context = nil
    }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func parent(_ source: AnalyticsContext, peer: PeerId = 1) -> ChatInteraction {
        let interaction = ChatInteraction(context, location: .peer(peer)); interaction.inheritedAnalyticsContext = source; return interaction
    }
    func message(_ peer: PeerId = 1, secret: Bool = false) -> Message { Message(id: MessageId(peerId: peer, id: 1), containsSecretMedia: secret) }
    func expectExcluded() { Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testAllThreeUnlockRoutesPreserveScopeAndPremiumOptionsWithoutEditEvent() {
        let source = origin(); let interaction = parent(source)
        let row = savedPremiumRowAction(interaction, message: message())
        let header = SavedPremiumHeader(interaction); let action = header.update()
        let view = SavedPremiumView(); setSavedPremiumView(view, context: context, analyticsContext: source)
        XCTAssertTrue(RecommendationProbe.premium.isEmpty)
        row.1(.builtin("tag")); action(nil); view.clickAction()(0)
        XCTAssertEqual(RecommendationProbe.premium.count, 3)
        for controller in RecommendationProbe.premium {
            XCTAssertTrue(controller.analyticsContext?.scope === source.scope)
            XCTAssertEqual(controller.source, .saved_tags); XCTAssertTrue(controller.openFeatures)
        }
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        XCTAssertTrue(SavedPremiumProbe.morph?() === view)
    }
    func testSecretAndUnknownMessagesGuardFactoryAndPresentation() {
        for message in [message(secret: true), message(-1), message(0)] {
            let interaction = parent(origin()); let action = savedPremiumRowAction(interaction, message: message).1
            expectExcluded(); action(.builtin("tag"))
            XCTAssertTrue(RecommendationProbe.premium.last?.analyticsContext?.isExcluded == true)
            XCTAssertFalse(hub.policy.hasExclusions)
        }
    }
    func testPrivateParentSurvivesOrdinarySavedMessageDestination() {
        let source = origin(.excluded); let interaction = parent(source)
        let header = SavedPremiumHeader(interaction); let action = header.update()
        let view = SavedPremiumView(); view.set(context: context, analyticsContext: source)
        expectExcluded()
        savedPremiumRowAction(interaction, message: message()).1(.builtin("tag"))
        action(nil); view.clickAction()(0)
        XCTAssertEqual(RecommendationProbe.premium.count, 3)
        XCTAssertTrue(RecommendationProbe.premium.allSatisfy { $0.analyticsContext?.isExcluded == true })
    }
    func testRowCallbackRemainsPrivateAfterOwnerRelease() {
        var interaction: ChatInteraction? = parent(origin(.excluded))
        let action = savedPremiumRowAction(interaction!, message: message()).1
        weak var weakInteraction = interaction; interaction = nil
        XCTAssertNil(weakInteraction); expectExcluded(); action(.builtin("tag"))
        XCTAssertEqual(RecommendationProbe.premium.count, 1)
    }
    func testRetainedRowCallbackIsRevokedBeforePrivateLayoutReplacement() {
        let interaction = parent(origin()); let row = savedPremiumRowAction(interaction, message: message())
        let view = SavedReactionView(); view.update(with: row.0)
        view.update(with: savedPremiumRowAction(interaction, message: message(secret: true)).0)
        expectExcluded(); row.1(.builtin("tag"))
        XCTAssertFalse(RecommendationProbe.premium.last?.analyticsContext?.scope?.isValid == true)
    }
    func testCachedHeaderCallbackCannotRenewAfterPrivateReplacement() {
        let interaction = parent(origin()); let header = SavedPremiumHeader(interaction); let old = header.update()
        interaction.inheritedAnalyticsContext = origin(.excluded); _ = header.update()
        expectExcluded(); old(nil)
        XCTAssertFalse(RecommendationProbe.premium.last?.analyticsContext?.scope?.isValid == true)
    }
    func testEmptyViewRebindingExcludesPreviousScopeAndUsesPrivateOrigin() {
        let view = SavedPremiumView(); let source = origin(); view.set(context: context, analyticsContext: source)
        let action = view.clickAction(); view.set(context: context, analyticsContext: origin(.excluded))
        XCTAssertTrue(source.scope?.isExcluded == true)
        expectExcluded(); action(0)
        XCTAssertTrue(RecommendationProbe.premium.last?.analyticsContext?.isExcluded == true)
    }
    func testForeignAccountCannotUseCapturedSourceAtAnyEntry() {
        let source = origin(); let interaction = parent(source)
        let row = savedPremiumRowAction(interaction, message: message()).1
        let header = SavedPremiumHeader(interaction); let action = header.update()
        let view = SavedPremiumView(); view.set(context: context, analyticsContext: source)
        let other = AccountContext(); hub.policy.setOwner(other.account)
        expectExcluded(); row(.builtin("tag")); action(nil); view.clickAction()(0)
        XCTAssertEqual(RecommendationProbe.premium.count, 3)
        XCTAssertTrue(RecommendationProbe.premium.allSatisfy { $0.analyticsContext?.scope == nil })
    }
    func testRevokedAndDisabledSourcesRemainFunctionalWithoutRenewal() {
        let interaction = parent(origin()); let header = SavedPremiumHeader(interaction); let action = header.update()
        hub.policy.isEnabled = false; expectExcluded(); action(nil)
        hub.policy.isEnabled = true; action(nil)
        XCTAssertEqual(RecommendationProbe.premium.count, 2)
        XCTAssertTrue(RecommendationProbe.premium.allSatisfy { $0.analyticsContext?.scope == nil })
    }
    func testPremiumAndSearchTagSelectionKeepFunctionalBehaviorWithoutOpeningPremium() {
        context.isPremium = true; let interaction = parent(origin())
        savedPremiumRowAction(interaction, message: message()).1(.builtin("tag"))
        XCTAssertEqual(interaction.selectedTag, .customTag(.builtin("tag"), nil))
        let header = SavedPremiumHeader(interaction); let action = header.update()
        let tag = EmojiTag(tag: .init(reaction: .custom(4), title: nil))
        action(tag); XCTAssertEqual(interaction.selectedTag, .customTag(.custom(4), nil))
        header.tagsView?.selected = [tag]; action(tag); XCTAssertNil(interaction.selectedTag)
        XCTAssertTrue(RecommendationProbe.premium.isEmpty); XCTAssertTrue(RecommendationProbe.events.isEmpty)
    }
    func testReleasedSearchControlsDoNotOpenOrRetainMorphSource() {
        var header: SavedPremiumHeader? = SavedPremiumHeader(parent(origin()))
        let action = header!.update(); weak var weakHeader = header; header = nil
        XCTAssertNil(weakHeader); action(nil); XCTAssertTrue(RecommendationProbe.premium.isEmpty)
        var view: SavedPremiumView? = SavedPremiumView(); view!.set(context: context, analyticsContext: origin())
        let click = view!.clickAction(); click(0); weak var weakView = view; view = nil
        XCTAssertNil(weakView); XCTAssertNil(SavedPremiumProbe.morph?()); click(0)
        XCTAssertEqual(RecommendationProbe.premium.count, 1)
    }
    func testViewWithoutOriginDoesNotInventGrant() {
        let view = SavedPremiumView(); view.context = context
        expectExcluded(); view.clickAction()(0)
        XCTAssertTrue(RecommendationProbe.premium.last?.analyticsContext?.isExcluded == true)
    }
    func testDelayedReactionMenuRetainsPrivateSourceAtAllThreeUnlockCallbacks() {
        let interaction = parent(origin(.excluded))
        expectExcluded(); SavedPremiumProbe.check = Probe.construction
        var menu: SavedPremiumMenu?
        let disposable = savedPremiumMenu(interaction, message: message(), peer: Peer(1)).start(next: { menu = $0 })
        XCTAssertNil(menu); SavedPremiumProbe.sink?.putNext(0)
        SavedPremiumProbe.sink?.putCompletion(); XCTAssertFalse(hub.policy.hasExclusions)
        menu?.link(0); menu?.reveal(); menu?.add()
        XCTAssertEqual(RecommendationProbe.premium.count, 3)
        XCTAssertTrue(RecommendationProbe.premium.allSatisfy { $0.analyticsContext?.isExcluded == true })
        disposable.dispose(); XCTAssertEqual(SavedPremiumProbe.disposals, 1)
    }
    func testReactionMenuClassifiesSecretMediaAndRepresentedPrivatePeer() {
        for (message, peer) in [(message(secret: true), Peer(1)), (message(), Peer(-1))] {
            expectExcluded(); SavedPremiumProbe.check = Probe.construction
            var menu: SavedPremiumMenu?
            let disposable = savedPremiumMenu(parent(origin()), message: message, peer: peer).start(next: { menu = $0 })
            SavedPremiumProbe.sink?.putNext(0); SavedPremiumProbe.sink?.putCompletion()
            menu?.link(0); menu?.reveal(); menu?.add()
            disposable.dispose()
        }
        XCTAssertEqual(RecommendationProbe.premium.count, 6)
        XCTAssertTrue(RecommendationProbe.premium.allSatisfy { $0.analyticsContext?.isExcluded == true })
    }
    func testReactionMenuCompletionDoesNotLoseOrdinaryScopeOrInventSelection() {
        let source = origin(); var menu: SavedPremiumMenu?
        let disposable = savedPremiumMenu(parent(source), message: message(), peer: Peer(1)).start(next: { menu = $0 })
        SavedPremiumProbe.sink?.putNext(0); SavedPremiumProbe.sink?.putCompletion()
        XCTAssertTrue(RecommendationProbe.premium.isEmpty); XCTAssertTrue(RecommendationProbe.events.isEmpty)
        menu?.link(0); menu?.reveal(); menu?.add()
        XCTAssertEqual(RecommendationProbe.premium.count, 3)
        XCTAssertTrue(RecommendationProbe.premium.allSatisfy { $0.analyticsContext?.scope === source.scope })
        disposable.dispose()
    }
    func testReactionMenuRevokedWhileLoadingCannotRefreshAtClick() {
        let source = origin(); var menu: SavedPremiumMenu?
        let disposable = savedPremiumMenu(parent(source), message: message(), peer: Peer(1)).start(next: { menu = $0 })
        source.scope?.exclude(); expectExcluded(); SavedPremiumProbe.check = Probe.construction
        SavedPremiumProbe.sink?.putNext(0); SavedPremiumProbe.sink?.putCompletion()
        menu?.link(0); menu?.reveal(); menu?.add()
        XCTAssertEqual(RecommendationProbe.premium.count, 3)
        XCTAssertTrue(RecommendationProbe.premium.allSatisfy { $0.analyticsContext?.isExcluded == true })
        disposable.dispose()
    }
    func testDelayedMessageEffectsLinkUsesCorrectSourceAndPrivateOrigin() {
        expectExcluded(); SavedPremiumProbe.check = Probe.construction
        var action: ((Int) -> Void)?
        let disposable = savedPremiumEffects(parent(origin(.excluded))).start(next: { action = $0 })
        SavedPremiumProbe.sink?.putNext(0); SavedPremiumProbe.sink?.putCompletion(); action?(0)
        XCTAssertEqual(RecommendationProbe.premium.last?.source, .message_effects)
        XCTAssertTrue(RecommendationProbe.premium.last?.analyticsContext?.isExcluded == true)
        XCTAssertTrue(RecommendationProbe.events.isEmpty); disposable.dispose()
    }
    func testMessageEffectsLinkRevalidatesAccountAfterMenuCompletion() {
        let source = origin(); var action: ((Int) -> Void)?
        let disposable = savedPremiumEffects(parent(source)).start(next: { action = $0 })
        SavedPremiumProbe.sink?.putNext(0); SavedPremiumProbe.sink?.putCompletion()
        let other = AccountContext(); hub.policy.setOwner(other.account); expectExcluded(); action?(0)
        XCTAssertEqual(RecommendationProbe.premium.last?.source, .message_effects)
        XCTAssertNil(RecommendationProbe.premium.last?.analyticsContext?.scope)
        disposable.dispose()
    }
    func testPrivateMenuCancellationProtectsDisposalWithoutOpening() {
        expectExcluded(); SavedPremiumProbe.check = Probe.construction
        let disposable = savedPremiumMenu(parent(origin(.excluded)), message: message(), peer: Peer(1)).start()
        disposable.dispose(); XCTAssertEqual(SavedPremiumProbe.disposals, 1)
        XCTAssertFalse(hub.policy.hasExclusions); XCTAssertTrue(RecommendationProbe.premium.isEmpty)
    }

}
