struct MessageReaction {
    enum Reaction: Equatable { case builtin(String), custom(Int64) }
    let value: Reaction
}
typealias InputDataIdentifier = String
struct SavedTagInput { let stringValue: String? }
struct ModalHeaderData { let image: Int; let handler: () -> Void }
struct SavedTagIcons { let modalClose = 0; let successModalProgress = 1 }
extension CommonTheme { var icons: SavedTagIcons { SavedTagIcons() } }
extension CommonStrings {
    var chatReactionContextEditTag: String { "Edit tag" }
    var chatReactionContextAddLabel: String { "Add label" }
    var modalDone: String { "Done" }
}
__SAVED_TAG_TYPES__
func savedTagEntries(_ state: SavedTagState, arguments: SavedTagArguments) -> [CommonEntry] {
    SavedProbe.check?(); SavedProbe.values.append(state.value); return []
}
__SAVED_TAG_FACTORY__
func installSavedTagBridge() {
    var hooks = ChatNavigationHooks.shared
__SAVED_TAG_BRIDGE__
    ChatNavigationHooks.shared = hooks
}
final class SavedStickers {
    func setSavedMessageTagTitle(reaction: MessageReaction.Reaction, title: String?) -> Signal<Never, NoError> {
        SavedProbe.check?(); SavedProbe.saves.append((reaction, title))
        return Signal { sink in
            SavedProbe.check?(); SavedProbe.saveSink = sink
            return ActionDisposable { SavedProbe.check?(); SavedProbe.saveDisposals += 1 }
        }
    }
}
extension Engine { var stickers: SavedStickers { SavedProbe.stickers } }
func showModalSuccess(for window: Int, icon: Int, delay: Double) -> Signal<Never, NoError> {
    SavedProbe.check?(); SavedProbe.feedback += 1
    return Signal { sink in
        SavedProbe.check?(); SavedProbe.feedbackSink = sink
        return ActionDisposable { SavedProbe.check?(); SavedProbe.feedbackDisposals += 1 }
    }
}
final class SavedReaction {
    let analyticsContext: AnalyticsContext
    let message: Message
    let context: any AccountContextProtocol
    let value: MessageReaction
    let text: BadgeText?
    init(context: any AccountContextProtocol, message: Message, analyticsContext: AnalyticsContext? = nil) {
__REACTION_ORIGIN__
        self.context = context; self.message = message; self.value = MessageReaction(value: .builtin("tag"))
        self.text = BadgeText(attributedString: NSAttributedString(string: "original"))
    }
    func menuAction() -> () -> Void {
__REACTION_MENU_PREFIX__
        return {
__REACTION_MENU_ACTION__
        }
    }
}
final class SavedReactionLayout {
    typealias Reaction = SavedReaction
    let analyticsContext: AnalyticsContext
    let message: Message
    var reactions: [Reaction]
    init(context: any AccountContextProtocol, message: Message, analyticsContext: AnalyticsContext? = nil) {
__LAYOUT_ORIGIN__
        self.message = message
        self.reactions = [SavedReaction(context: context, message: message, analyticsContext: __LAYOUT_HANDOFF__)]
    }
__LAYOUT_TIGHTENING__
}
final class SavedReactionView {
    var reactions: [SavedReaction] = []
    func update(with layout: SavedReactionLayout) {
__LAYOUT_UPDATE_PREFIX__
        reactions = layout.reactions
    }
}
func makeSavedReaction(context: any AccountContextProtocol, message: Message, analyticsContext: AnalyticsContext? = nil) -> SavedReaction {
    SavedReactionLayout(context: context, message: message, analyticsContext: analyticsContext).reactions[0]
}
func makeSavedRowReaction(_ chatInteraction: ChatInteraction, message: Message) -> SavedReaction {
    let origin = __ROW_LAYOUT_ORIGIN__
    return makeSavedReaction(context: chatInteraction.interactionContext, message: message, analyticsContext: origin)
}
struct EmojiTag {
    struct Tag { let reaction: MessageReaction.Reaction; let title: String? }
    let tag: Tag
}
__SEARCH_TAG_ARGUMENTS__
final class NSAccessibilityCustomAction {
    let name: String
    let handler: () -> Bool
    init(name: String, handler: @escaping () -> Bool) { self.name = name; self.handler = handler }
}
final class SavedSearchItem {
    let arguments: SearchTagArguments
    let tag: EmojiTag
    var enabled = true
    init(_ arguments: SearchTagArguments, title: String? = "original") {
        self.arguments = arguments; self.tag = EmojiTag(tag: .init(reaction: .custom(44), title: title))
    }
__SEARCH_TAG_ACCESSIBILITY__
    func menuAction() -> () -> Void {
        let item = self; let context = arguments.context
        return {
__SEARCH_TAG_MENU_ACTION__
        }
    }
}
final class SavedSearchTags {
    var selected: [EmojiTag] = []
    var tags: [EmojiTag] = []
    var context: (any AccountContextProtocol)?
    var analyticsContext: AnalyticsContext?
    var callback: ((EmojiTag?) -> Void)?
    var arguments: SearchTagArguments?
    func set(tags: [EmojiTag], context: any AccountContextProtocol, analyticsContext: AnalyticsContext, animated: Bool, callback: @escaping (EmojiTag?) -> Void) {
__SEARCH_TAG_SET__
        self.arguments = arguments
    }
    func themeChanged() {
__SEARCH_TAG_THEME__
    }
}
final class SavedSearchHeader {
    let chatInteraction: ChatInteraction
    let parentInteractions: ChatInteraction
    init(_ chatInteraction: ChatInteraction) {
__SEARCH_HEADER_PREFIX__
        SavedProbe.check?()
        parentInteractions = chatInteraction
__SEARCH_HEADER_INTERACTION__
    }
    func tagsOrigin() -> AnalyticsContext { __SEARCH_HEADER_TAG_ORIGIN__ }
}
enum SavedProbe {
    static let stickers = SavedStickers()
    static var check: (() -> Void)?
    static var values: [String?] = []
    static var saves: [(MessageReaction.Reaction, String?)] = []
    static var saveSink: Subscriber<Never, NoError>?
    static var feedbackSink: Subscriber<Never, NoError>?
    static var feedback = 0
    static var saveDisposals = 0
    static var feedbackDisposals = 0
    static func reset() {
        check = nil; values = []; saves = []; saveSink = nil; feedbackSink = nil
        feedback = 0; saveDisposals = 0; feedbackDisposals = 0
    }
}
final class SavedTagContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        RecommendationProbe.events = []
        SavedProbe.reset(); TagProbe.reset(); MemberProbe.reset(); GroupProbe.reset(); MediaProbe.created = []; Probe.construction = nil
        Analytics.shared = Analytics(); context = AccountContext(); hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        installSavedTagBridge()
    }
    override func tearDown() { SavedProbe.reset(); TagProbe.reset(); MemberProbe.reset(); GroupProbe.reset(); MediaProbe.created = []; context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func message(secret: Bool = false) -> Message { Message(id: MessageId(peerId: 1, id: 1), containsSecretMedia: secret) }
    func expectExcluded() { SavedProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }; TagProbe.check = SavedProbe.check }
    func open(_ source: AnalyticsContext? = nil) {
        ChatNavigationHooks.shared.showEditTagLabelObserved(context, .builtin("tag"), "original", context.window, analyticsContext: source ?? origin())
    }
    func testEditorPreservesScopeAndPassesActualTypedValueOnlyToSave() {
        let source = origin(); open(source)
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.scope === source.scope)
        XCTAssertTrue(TagProbe.modal?.content.analyticsContext?.scope === source.scope)
        _ = TagProbe.modal?.content.updateDatas([_id_input: SavedTagInput(stringValue: "new label")])
        _ = TagProbe.modal?.content.validateData(0)
        XCTAssertEqual(SavedProbe.saves.last?.0, .builtin("tag")); XCTAssertEqual(SavedProbe.saves.last?.1, "new label")
        XCTAssertEqual(SavedProbe.feedback, 1); XCTAssertEqual(TagProbe.closes, 1)
        SavedProbe.saveSink?.putCompletion(); SavedProbe.feedbackSink?.putCompletion()
    }
    func testMessageReactionMenuRetainsPrivateOriginAfterLayoutRelease() {
        var layout: SavedReaction? = makeSavedReaction(context: context, message: message(), analyticsContext: origin(.excluded))
        let action = layout!.menuAction(); layout = nil
        expectExcluded(); action(); XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testSecretMediaCannotEnterThroughOrdinaryLayoutOrReaction() {
        let source = origin()
        for direct in [false, true] {
            let reaction = direct ? SavedReaction(context: context, message: message(secret: true), analyticsContext: source) : makeSavedReaction(context: context, message: message(secret: true), analyticsContext: source)
            expectExcluded(); reaction.menuAction()(); XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
            TagProbe.modal = nil
        }
    }
    func testRowSuppliesOwningInteractionScope() {
        let source = origin(); let interaction = ChatInteraction(context, location: .peer(1)); interaction.inheritedAnalyticsContext = source
        makeSavedRowReaction(interaction, message: message()).menuAction()()
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.scope === source.scope)
    }
    func testSearchMenuAndAccessibilityKeepOriginalScopeAndEnabledGuard() {
        let source = origin(); let arguments = SearchTagArguments(context: context, analyticsContext: source, callback: { _ in })
        let item = SavedSearchItem(arguments)
        item.menuAction()(); XCTAssertTrue(TagProbe.modal?.analyticsContext?.scope === source.scope)
        XCTAssertEqual(item.accessibilityCustomActions?.first?.name, "Edit tag")
        XCTAssertTrue(item.accessibilityCustomActions?.first?.handler() == true)
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.scope === source.scope)
        item.enabled = false; XCTAssertNil(item.accessibilityCustomActions)
    }
    func testSearchThemeRefreshRetainsPrivateSourceAndAccessibilityAction() {
        let tags = SavedSearchTags(); tags.set(tags: [], context: context, analyticsContext: origin(.excluded), animated: false, callback: { _ in })
        tags.themeChanged(); let item = SavedSearchItem(tags.arguments!, title: nil)
        let action = item.accessibilityCustomActions!.first!; expectExcluded()
        XCTAssertEqual(action.name, "Add label"); XCTAssertTrue(action.handler())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testSyntheticSearchInteractionInheritsParentAndTagsUseParentOrigin() {
        let parent = ChatInteraction(context, location: .peer(1)); parent.inheritedAnalyticsContext = origin(.excluded)
        expectExcluded(); let header = SavedSearchHeader(parent)
        XCTAssertTrue(header.chatInteraction.inheritedAnalyticsContext?.isExcluded == true)
        XCTAssertTrue(header.tagsOrigin().isExcluded)
    }
    func testPrivateSaveAndFeedbackRemainGuardedAfterEditorRelease() {
        open(origin(.excluded)); expectExcluded()
        _ = TagProbe.modal?.content.updateDatas([_id_input: SavedTagInput(stringValue: "new")])
        _ = TagProbe.modal?.content.validateData(0); TagProbe.modal = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        SavedProbe.saveSink?.putCompletion(); XCTAssertTrue(hub.policy.hasExclusions)
        SavedProbe.feedbackSink?.putCompletion(); XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertEqual(SavedProbe.saveDisposals, 1); XCTAssertEqual(SavedProbe.feedbackDisposals, 1)
    }
    func testHeaderCancelDoesNotSaveOrShowFeedback() {
        open(origin(.excluded)); expectExcluded(); TagProbe.modal?.content.leftModalHeader?.handler()
        XCTAssertEqual(TagProbe.closes, 1); XCTAssertTrue(SavedProbe.saves.isEmpty); XCTAssertEqual(SavedProbe.feedback, 0)
    }
    func testDeferredRenderingRetainsPrivateOriginAndCurrentInput() {
        TagProbe.deferRendering = true; open(origin(.excluded)); expectExcluded()
        _ = TagProbe.modal?.content.updateDatas([_id_input: SavedTagInput(stringValue: "changed")])
        XCTAssertTrue(SavedProbe.values.isEmpty)
        TagProbe.renderGate.set(true); XCTAssertEqual(SavedProbe.values, ["changed"])
    }
    func testAccountSwitchAfterMenuCreationCannotRefreshScope() {
        let action = makeSavedReaction(context: context, message: message(), analyticsContext: origin()).menuAction()
        let other = AccountContext(); hub.policy.setOwner(other.account); expectExcluded(); action()
        XCTAssertNil(TagProbe.modal?.analyticsContext?.scope)
    }
    func testExclusionDuringEditingRestrictsLaterInputAndSave() {
        let source = origin(); open(source); source.scope?.exclude(); expectExcluded()
        _ = TagProbe.modal?.content.updateDatas([:]); _ = TagProbe.modal?.content.validateData(0)
        XCTAssertEqual(SavedProbe.saves.count, 1); XCTAssertNil(SavedProbe.saves[0].1)
        SavedProbe.saveSink?.putCompletion(); SavedProbe.feedbackSink?.putCompletion()
    }
    func testRevokedOriginDoesNotRenewAtSubmit() {
        open(); hub.policy.isEnabled = false; hub.policy.isEnabled = true; expectExcluded()
        _ = TagProbe.modal?.content.validateData(0); XCTAssertFalse(TagProbe.modal?.analyticsContext?.scope?.isValid == true)
        SavedProbe.saveSink?.putCompletion(); SavedProbe.feedbackSink?.putCompletion()
    }
    func testLegacyAndDisabledFactoriesRemainFunctionalWithoutGrant() {
        hub.policy.isEnabled = false; expectExcluded(); ChatNavigationHooks.shared.showEditTagLabelWithContext = nil
        open(origin(.excluded)); XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
        _ = TagProbe.modal?.content.validateData(0); XCTAssertEqual(SavedProbe.saves.count, 1)
        SavedProbe.saveSink?.putCompletion(); SavedProbe.feedbackSink?.putCompletion()
    }
    func testPrivateLayoutRevokesMenuCapturedBeforeSameMessageBecomesSecret() {
        let source = origin(); let view = SavedReactionView()
        view.update(with: SavedReactionLayout(context: context, message: message(), analyticsContext: source))
        let oldMenu = view.reactions[0].menuAction()
        view.update(with: SavedReactionLayout(context: context, message: message(secret: true), analyticsContext: source))
        XCTAssertTrue(source.scope?.isExcluded == true)
        expectExcluded(); oldMenu(); XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testRemovedReactionsAreExcludedWithoutMarkingOtherMessagesPrivate() {
        let source = origin(); let otherSource = origin(); let view = SavedReactionView()
        let otherMessage = Message(id: MessageId(peerId: 1, id: 2))
        view.reactions = [makeSavedReaction(context: context, message: message(), analyticsContext: source), makeSavedReaction(context: context, message: otherMessage, analyticsContext: otherSource)]
        let privateLayout = SavedReactionLayout(context: context, message: message(secret: true), analyticsContext: origin(.excluded))
        privateLayout.reactions = []; view.update(with: privateLayout)
        XCTAssertTrue(source.scope?.isExcluded == true); XCTAssertFalse(otherSource.scope?.isExcluded == true)
        XCTAssertFalse(otherSource.scope?.isValid == true)
        XCTAssertTrue(view.reactions.isEmpty)
    }
    func testOrdinaryLayoutReplacementDoesNotRevokeOriginalScope() {
        let source = origin(); let view = SavedReactionView()
        view.reactions = [makeSavedReaction(context: context, message: message(), analyticsContext: source)]
        view.update(with: SavedReactionLayout(context: context, message: message(), analyticsContext: origin()))
        XCTAssertTrue(source.scope?.isValid == true); XCTAssertFalse(source.scope?.isExcluded == true)
    }
    func testPrivateSearchReplacementRevokesPreviouslyCapturedMenu() {
        let source = origin(); let tags = SavedSearchTags()
        tags.set(tags: [], context: context, analyticsContext: source, animated: false, callback: { _ in })
        let menu = SavedSearchItem(tags.arguments!).menuAction()
        tags.set(tags: [], context: context, analyticsContext: origin(.excluded), animated: false, callback: { _ in })
        XCTAssertTrue(source.scope?.isExcluded == true)
        expectExcluded(); menu(); XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testActualEditCallbacksRecordThreeDistinctEntryCategories() {
        let source = origin()
        makeSavedReaction(context: context, message: message(), analyticsContext: source).menuAction()()
        let item = SavedSearchItem(SearchTagArguments(context: context, analyticsContext: source, callback: { _ in }))
        item.menuAction()()
        XCTAssertTrue(item.accessibilityCustomActions?.first?.handler() == true)
        XCTAssertEqual(RecommendationProbe.events.map { $0.params }, [["entry": .string("reaction_menu")], ["entry": .string("search_tag_menu")], ["entry": .string("accessibility")]])
        XCTAssertTrue(RecommendationProbe.events.allSatisfy { $0.name == .chatSavedTagEditSelect })
    }
    func testMenuAndAccessibilityConstructionDoNotRecordSelection() {
        let source = origin()
        let action = makeSavedReaction(context: context, message: message(), analyticsContext: source).menuAction()
        let item = SavedSearchItem(SearchTagArguments(context: context, analyticsContext: source, callback: { _ in }))
        _ = item.menuAction(); _ = item.accessibilityCustomActions
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        action(); XCTAssertEqual(RecommendationProbe.events.count, 1)
    }
    func testTypingSavingAndFeedbackDoNotAddSelections() {
        makeSavedReaction(context: context, message: message(), analyticsContext: origin()).menuAction()()
        _ = TagProbe.modal?.content.updateDatas([_id_input: SavedTagInput(stringValue: "private label")])
        _ = TagProbe.modal?.content.validateData(0)
        SavedProbe.saveSink?.putCompletion(); SavedProbe.feedbackSink?.putCompletion()
        XCTAssertEqual(RecommendationProbe.events.map { $0.params }, [["entry": .string("reaction_menu")]])
    }
    func testRepeatedCommandInvocationsRemainSeparateIntentSelections() {
        let action = makeSavedReaction(context: context, message: message(), analyticsContext: origin()).menuAction()
        action(); action()
        XCTAssertEqual(RecommendationProbe.events.count, 2)
        XCTAssertTrue(RecommendationProbe.events.allSatisfy { $0.params == ["entry": .string("reaction_menu")] })
    }
    func testPrivateAndUnknownEntryCallbacksStaySilent() {
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            makeSavedReaction(context: context, message: message(), analyticsContext: origin(privacy)).menuAction()()
            XCTAssertNotNil(TagProbe.modal); TagProbe.modal = nil
        }
        makeSavedReaction(context: context, message: message()).menuAction()()
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
    }
    func testSecretMediaEditSelectionStaysSilent() {
        makeSavedReaction(context: context, message: message(secret: true), analyticsContext: origin()).menuAction()()
        XCTAssertTrue(RecommendationProbe.events.isEmpty); XCTAssertNotNil(TagProbe.modal)
    }
    func testAccountChangeBeforeSelectionStaysSilent() {
        let action = makeSavedReaction(context: context, message: message(), analyticsContext: origin()).menuAction()
        let other = AccountContext(); hub.policy.setOwner(other.account)
        action(); XCTAssertTrue(RecommendationProbe.events.isEmpty); XCTAssertNotNil(TagProbe.modal)
    }
    func testForeignContextCannotUseAnotherAccountsGrantForSelection() {
        let source = origin(); let other = AccountContext()
        ChatNavigationHooks.shared.showEditTagLabelObserved(other, .builtin("tag"), nil, other.window, analyticsContext: source, entry: .searchTagMenu)
        XCTAssertTrue(RecommendationProbe.events.isEmpty); XCTAssertNotNil(TagProbe.modal)
    }
    func testRevokedAccessibilitySelectionStaysSilent() {
        let source = origin(); let item = SavedSearchItem(SearchTagArguments(context: context, analyticsContext: source, callback: { _ in }))
        let action = item.accessibilityCustomActions!.first!
        source.scope?.exclude(); XCTAssertTrue(action.handler())
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
    }
    func testDisabledAndReenabledOldMenuCannotEmitSelection() {
        let action = makeSavedReaction(context: context, message: message(), analyticsContext: origin()).menuAction()
        hub.policy.isEnabled = false; action(); TagProbe.modal = nil
        hub.policy.isEnabled = true; action()
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
    }
    func testPrivateReplacementKeepsCapturedSelectionSilent() {
        let source = origin(); let view = SavedReactionView()
        view.update(with: SavedReactionLayout(context: context, message: message(), analyticsContext: source))
        let action = view.reactions[0].menuAction()
        view.update(with: SavedReactionLayout(context: context, message: message(secret: true), analyticsContext: source))
        action(); XCTAssertTrue(RecommendationProbe.events.isEmpty)
    }
    func testSourceLessHelperAndDirectFactoryDoNotInventSelectionEntry() {
        open()
        let controller = EditTagLabelController(context: context, reaction: .builtin("tag"), label: nil, analyticsContext: origin())
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        withExtendedLifetime(controller) {}
    }
    func testCompletionAddsNoSecondFeedbackOrSuccessOutcome() {
        open(); _ = TagProbe.modal?.content.validateData(0); XCTAssertEqual(SavedProbe.feedback, 1)
        SavedProbe.saveSink?.putCompletion(); XCTAssertEqual(SavedProbe.feedback, 1)
        SavedProbe.feedbackSink?.putCompletion()
    }
}
