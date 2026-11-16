__EDITOR_ERRORS__
typealias FixtureCloudStyle = CloudStyle
enum TelegramComposeAIMessageMode { typealias CloudStyle = FixtureCloudStyle }
extension CloudStyle {
    struct Custom { let id: Int64; let accessHash: Int64; let title: String; let prompt: String?; let authorId: PeerId?; let emojiFileId: Int64? }
    enum Content { case custom(Custom) }
    var content: Content { .custom(.init(id: id, accessHash: 91, title: "existing", prompt: "instructions", authorId: authorId, emojiFileId: 9)) }
}
typealias StickerPackReference = Int
enum EditorFileAttribute { case CustomEmoji(Int, Int, Int, StickerPackReference?) }
extension Int {
    struct FileId { let id: Int64 }
    var fileId: FileId { .init(id: Int64(self)) }
    var attributes: [EditorFileAttribute] { [.CustomEmoji(0, 0, 0, 10)] }
}
extension String { var length: Int { (self as NSString).length } }
extension NSAttributedString.Key { static var font: NSAttributedString.Key { .init("font") } }
enum NSFont { enum Size { case text }; static func normal(_ size: Size) -> Int { 1 } }
struct Updated_ChatTextInputState: Equatable { var inputText: NSAttributedString }
struct ChatTextInputState {
    let inputText: String
    var hasExcludedAnalytics = false
    init(inputText: String, selectionRange: Range<Int>, attributes: [Int]) { self.inputText = inputText }
    func textInputState() -> Updated_ChatTextInputState { .init(inputText: NSAttributedString(string: inputText)) }
}
struct TextEntitiesMessageAttribute { let entities: [Int] }
func chatTextAttributes(from value: TextEntitiesMessageAttribute, associatedMedia: [Int: Int]) -> [Int] { [] }
struct EditorConfiguration {
    func getGeneralValue(_ key: String, orElse: Int32) -> Int32 { Probe.check?(); return orElse }
}
extension Context { var appConfiguration: EditorConfiguration { EditorConfiguration() }; var isPremium: Bool { EditorProbe.premium } }
struct EditorState: Equatable {
    var name = ""
    var instructions = Updated_ChatTextInputState(inputText: NSAttributedString(string: ""))
    var displayAuthor = false
    var emojiFileId: Int64?
    var emojiFile: TelegramMediaFile?
    var emojiPackReference: StickerPackReference?
}
struct EditorArguments {
    let context: Context
    let titleMax: Int32
    let promptMax: Int32
    let updateName: (String) -> Void
    let updateInstructions: (Updated_ChatTextInputState) -> Void
    let toggleDisplayAuthor: () -> Void
    let pickEmoji: (Control) -> Void
    let deleteStyle: (() -> Void)?
}
func entries(_ state: EditorState, arguments: EditorArguments) -> [State] {
    Probe.check?(); EditorProbe.state = state; EditorProbe.arguments = arguments; return []
}
let _id_name = "name", _id_instructions = "instructions", _id_icon = "icon"
struct EditorValue { let stringValue: String? }
enum EditorValidation: Equatable { case none, fail(Failure); enum Failure: Equatable { case fields([String: Field]) }; enum Field { case shake } }
final class EditorController: Controller {
    enum Screen { case chatAiEditorStyle }
    var analyticsScreen: Screen?
    var updateDatas: (([String: EditorValue]) -> EditorValidation)?
    var validateData: (([String: EditorValue]) -> EditorValidation)?
    var leftModalHeader: ModalHeaderData?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) { Probe.check?(); super.init(dataSignal) }
    func returnKeyAction() -> Bool { Probe.check?(); _ = validateData?([:]); return true }
}
final class EditorModal {
    let controller: EditorController
    let interactions: ModalInteractions
    var analyticsContext: AnalyticsContext?
    var modal: EditorModal? { self }
    init(_ controller: EditorController, modalInteractions: ModalInteractions, size: NSSize) { Probe.check?(); self.controller = controller; interactions = modalInteractions }
    func close() { Probe.check?(); EditorProbe.closes += 1 }
}
func showModal(with modal: EditorModal, for window: Int) { Probe.check?(); EditorProbe.presented = modal }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Int) -> Signal<T, E> { Probe.check?(); EditorProbe.progress += 1; return signal }
func showModalText(for window: Int, text: String, button: String, callback: @escaping (Int) -> Void) { Probe.check?(); EditorProbe.limitAction = callback }
extension Strings {
    var aiStyleModalEditStyleTitle: String { "Edit" }; var aiStyleModalNewStyleTitle: String { "New" }
    var aiStyleModalSave: String { "Save" }; var aiStyleModalCreate: String { "Create" }
    var aiStyleModalDeleteStyleHeader: String { "delete-style" }; var aiStyleModalDeleteStyleConfirm: String { "confirm-delete" }; var aiStyleModalDeleteStyleForAll: String { "for-all" }
    var premiumLimitIncrease: String { "Increase" }
    func aiStyleModalSavedLimitReachedOther(_ count: Int) -> String { "limit" }
    func aiStyleModalSavedLimitPremiumOther(_ count: Int, _ max: Int) -> String { "limit" }
}
extension Messages {
    func createAITextStyle(displayAuthor: Bool, emojiFileId: Int64, title: String, prompt: String) -> Signal<CloudStyle, CreateAITextStyleError> {
        Probe.check?(); EditorProbe.requests.append(("create", emojiFileId, title, prompt))
        return Signal { sink in Probe.check?(); EditorProbe.createSinks.append(sink); return ActionDisposable { Probe.check?(); EditorProbe.disposals += 1 } }
    }
    func editAITextStyle(id: Int64, accessHash: Int64, displayAuthor: Bool, emojiFileId: Int64, title: String, prompt: String) -> Signal<CloudStyle, EditAITextStyleError> {
        Probe.check?(); EditorProbe.requests.append(("edit", emojiFileId, title, prompt))
        return Signal { sink in Probe.check?(); EditorProbe.editSinks.append(sink); return ActionDisposable { Probe.check?(); EditorProbe.disposals += 1 } }
    }
}
struct EditorSticker { struct File { let value: Int; func _parse() -> Int { Probe.check?(); return value } }; let file: File }
final class EntertainmentInteractions {
    enum Kind { case emoji }
    var sendAnimatedEmoji: (EditorSticker, Int, Int, Int, Int) -> Void = { _, _, _, _, _ in }
    init(_ kind: Kind, peerId: PeerId) { Probe.check?() }
}
extension ChatInteraction {
    convenience init(chatLocation: ChatLocation, context: Context) { self.init(context); switch chatLocation { case let .peer(id): peerId = id } }
}
final class EmojiesController {
    enum Mode { case status }; enum Screen { case appEmojiPicker }
    var analyticsScreen: Screen?
    var analyticsContext: AnalyticsContext? { didSet { presentation = analyticsContext?.beginPresentation() } }
    var presentation: AnalyticsPresentation?
    var showsGlassSurface = false
    var _frameRect = NSRect.zero
    var interactions: EntertainmentInteractions?
    var chatInteraction: ChatInteraction?
    init(_ context: Context, mode: Mode, ignorePremium: Bool) { Probe.check?(); XCTAssertTrue(ignorePremium) }
    func update(with interactions: EntertainmentInteractions, chatInteraction: ChatInteraction) { Probe.check?(); self.interactions = interactions; self.chatInteraction = chatInteraction }
}
func closeAllPopovers(for window: Int) { Probe.check?(); EditorProbe.picker = nil }
func showPopover(for control: Int, with picker: EmojiesController) { Probe.check?(); EditorProbe.picker = picker }
enum EditorProbe {
    static var arguments: EditorArguments?
    static var state = EditorState()
    static var premium = false
    static var requests: [(String, Int64, String, String)] = []
    static var createSinks: [Subscriber<CloudStyle, CreateAITextStyleError>] = []
    static var editSinks: [Subscriber<CloudStyle, EditAITextStyleError>] = []
    static var progress = 0
    static var disposals = 0
    static var closes = 0
    static var limitAction: ((Int) -> Void)?
    static var picker: EmojiesController?
    static var presented: EditorModal?
    static func reset() { arguments = nil; state = EditorState(); premium = false; requests = []; createSinks = []; editSinks = []; progress = 0; disposals = 0; closes = 0; limitAction = nil; picker = nil; presented = nil }
}
__EDITOR_FACTORY__
func installEditorEmojiBridge() {
    var hooks = styleShareHooks()
__EDITOR_EMOJI_BRIDGE__
    TranslateUIHooks.install(hooks)
}
func styleEditorEntry(_ context: Context, editing: Bool, getAnalyticsContext: @escaping () -> AnalyticsContext, completed: @escaping () -> Void) -> () -> Void {
    let pinnedNewStyleIds = Atomic<[Int64]>(value: [])
    let triggerReloadStyles = completed
    let cloudStyle = CloudStyle(id: 42, authorId: 1)
    if editing {
        return {
__EDITOR_EDIT_ENTRY__
        }
    } else {
        return {
__EDITOR_CREATE_ENTRY__
        }
    }
}
final class StyleEditorTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.check = nil; EditorProbe.reset(); StyleRemovalProbe.reset(); Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true; installEditorEmojiBridge()
        FeatureNavigationHooks.shared = FeatureNavigationHooks()
    }
    override func tearDown() {
        Probe.check = nil
        EditorProbe.createSinks.forEach { $0.putCompletion() }; EditorProbe.editSinks.forEach { $0.putCompletion() }; StyleRemovalProbe.sinks.forEach { $0.putCompletion() }
        EditorProbe.reset(); StyleRemovalProbe.reset(); TranslateUIHooks.install(.placeholder); FeatureNavigationHooks.shared = FeatureNavigationHooks()
        super.tearDown()
    }
    func origin(_ id: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: id) }
    func excluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func fill() { EditorProbe.arguments!.updateName(" name "); EditorProbe.arguments!.updateInstructions(.init(inputText: NSAttributedString(string: " prompt "))); EditorProbe.arguments!.pickEmoji(1); EditorProbe.picker!.interactions!.sendAnimatedEmoji(.init(file: .init(value: 9)), 0, 0, 0, 0) }
    func testCreateAndEditEntriesPassExactOrdinaryScope() {
        let source = origin(); Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        for editing in [false, true] {
            styleEditorEntry(context, editing: editing, getAnalyticsContext: { source }, completed: {})()
            XCTAssertTrue(EditorProbe.presented?.analyticsContext?.scope === source.scope)
            XCTAssertTrue(EditorProbe.presented?.controller.analyticsContext?.scope === source.scope)
            XCTAssertEqual(EditorProbe.arguments!.deleteStyle != nil, editing)
            EditorProbe.presented = nil
        }
    }
    func testPrivateCreateRetainsContextThroughLookupProviderAndCompletionAfterRelease() {
        excluded(); var ids: [Int64?] = []
        var modal: EditorModal? = AIStyleModalController(context: context, onCompleted: { Probe.check?(); ids.append($0) }, analyticsContext: origin(-1))
        fill(); XCTAssertEqual(modal!.controller.validateData?([:]), EditorValidation.none)
        modal = nil; EditorProbe.arguments = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        context.engine.messages.styleSinks.last!.putNext([])
        XCTAssertEqual(EditorProbe.requests.last?.0, "create"); XCTAssertEqual(EditorProbe.requests.last?.2, "name"); XCTAssertEqual(EditorProbe.requests.last?.3, "prompt")
        EditorProbe.createSinks.last!.putNext(.init(id: 55, authorId: 1)); EditorProbe.createSinks.last!.putCompletion()
        XCTAssertEqual(ids.count, 1); XCTAssertEqual(ids[0], 55); XCTAssertEqual(EditorProbe.disposals, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPrivateEditReturnsNilAndPreservesRequestAfterOwnerRelease() {
        excluded(); var completed = false
        var modal: EditorModal? = AIStyleModalController(context: context, editing: .init(id: 42, authorId: 1), onCompleted: { Probe.check?(); XCTAssertNil($0); completed = true }, analyticsContext: origin(-1))
        XCTAssertEqual(modal!.controller.validateData?([:]), EditorValidation.none)
        modal = nil; EditorProbe.arguments = nil
        XCTAssertEqual(EditorProbe.requests.last?.0, "edit")
        EditorProbe.editSinks.last!.putNext(.init(id: 42, authorId: 1)); EditorProbe.editSinks.last!.putCompletion()
        XCTAssertTrue(completed); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testEmptyFieldsKeepValidationAndAvoidRequests() {
        let modal = AIStyleModalController(context: context, analyticsContext: origin())
        XCTAssertEqual(modal.controller.validateData?([:]), .fail(.fields([_id_name: .shake])))
        EditorProbe.arguments!.updateName("name")
        XCTAssertEqual(modal.controller.validateData?([:]), .fail(.fields([_id_instructions: .shake])))
        EditorProbe.arguments!.updateInstructions(.init(inputText: NSAttributedString(string: "prompt")))
        XCTAssertEqual(modal.controller.validateData?([:]), .fail(.fields([_id_icon: .shake])))
        XCTAssertEqual(EditorProbe.progress, 0); XCTAssertTrue(EditorProbe.requests.isEmpty)
    }
    func testSavedLimitPremiumCallbackRetainsContextAfterRelease() {
        excluded()
        var modal: EditorModal? = AIStyleModalController(context: context, analyticsContext: origin(-1))
        fill(); _ = modal!.controller.validateData?([:]); modal = nil; EditorProbe.arguments = nil
        context.engine.messages.styleSinks.last!.putNext(Array(repeating: .init(id: 1, authorId: 1), count: 5))
        XCTAssertTrue(EditorProbe.requests.isEmpty); XCTAssertFalse(hub.policy.hasExclusions)
        var called = false
        FeatureNavigationHooks.shared.showPremiumBoardingWithContext = { _, _, _, _, _, origin in Probe.check?(); called = true; XCTAssertTrue(origin.isExcluded) }
        EditorProbe.limitAction?(0)
        XCTAssertTrue(called); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPrivateEditorDeleteConfirmationAndRequestOutliveEditor() {
        excluded(); var completed = false
        var modal: EditorModal? = AIStyleModalController(context: context, editing: .init(id: 42, authorId: 1), onCompleted: { _ in Probe.check?(); completed = true }, analyticsContext: origin(-1))
        EditorProbe.arguments!.deleteStyle?(); modal = nil; EditorProbe.arguments = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        StyleRemovalProbe.confirmation?.success(.thrid); StyleRemovalProbe.confirmation = nil
        XCTAssertTrue(completed); XCTAssertEqual(StyleRemovalProbe.calls.last?.0, "delete")
        XCTAssertTrue(hub.policy.hasExclusions); StyleRemovalProbe.sinks.last!.putCompletion(); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testEmojiCompletionRevalidatesAccountAfterPickerRelease() {
        var modal: EditorModal? = AIStyleModalController(context: context, analyticsContext: origin())
        EditorProbe.arguments!.pickEmoji(1)
        let callback = EditorProbe.picker!.interactions!.sendAnimatedEmoji
        modal = nil; EditorProbe.arguments = nil; EditorProbe.picker = nil
        hub.policy.setOwner(Account()); excluded()
        callback(.init(file: .init(value: 9)), 0, 0, 0, 0)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testProviderPremiumRequiredKeepsDeferredUpsellExcluded() {
        excluded()
        var modal: EditorModal? = AIStyleModalController(context: context, analyticsContext: origin(-1))
        fill(); _ = modal!.controller.validateData?([:]); modal = nil; EditorProbe.arguments = nil
        context.engine.messages.styleSinks.last!.putNext([])
        EditorProbe.createSinks.last!.putError(.premiumRequired)
        XCTAssertFalse(hub.policy.hasExclusions)
        var called = false
        FeatureNavigationHooks.shared.showPremiumBoardingWithContext = { _, _, _, _, _, context in Probe.check?(); called = true; XCTAssertTrue(context.isExcluded) }
        hub.policy.setOwner(Account()); EditorProbe.limitAction?(0)
        XCTAssertTrue(called); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testEditFailureDoesNotInvokeCompletionAndReleasesRequestGuard() {
        excluded(); var completed = false
        let toasts = ActionProbe.toasts
        var modal: EditorModal? = AIStyleModalController(context: context, editing: .init(id: 42, authorId: 1), onCompleted: { _ in completed = true }, analyticsContext: origin(-1))
        _ = modal!.controller.validateData?([:]); modal = nil; EditorProbe.arguments = nil
        EditorProbe.editSinks.last!.putError(.generic)
        XCTAssertFalse(completed); XCTAssertEqual(ActionProbe.toasts, toasts + 1)
        XCTAssertEqual(EditorProbe.closes, 0); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testLegacyEmojiCompletionRetainsExclusionAfterHookReturns() {
        var selected: ((TelegramMediaFile) -> Void)?
        var calls = 0
        TranslateUIHooks.install(TranslateUIHooks(showAboutCocoonModal: { _ in }, shareLink: { _, _ in }, followResolvedName: { _, _, _ in }, showStyleEmojiPicker: { _, _, callback in Probe.check?(); selected = callback }))
        excluded()
        TranslateUIHooks.shared.showStyleEmojiPickerObserved(context, 1, analyticsContext: origin(-1), selected: { value in Probe.check?(); XCTAssertEqual(value, 9); calls += 1 })
        XCTAssertFalse(hub.policy.hasExclusions); selected?(9)
        XCTAssertEqual(calls, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testLegacyAndDisabledEditorCannotAcquireEligibility() {
        for disabled in [false, true] {
            hub.policy.isEnabled = !disabled; excluded()
            var modal: EditorModal? = AIStyleModalController(context: context)
            XCTAssertTrue(modal!.analyticsContext!.isExcluded)
            fill(); _ = modal!.controller.validateData?([:]); modal = nil; EditorProbe.arguments = nil
            context.engine.messages.styleSinks.last!.putNext([])
            EditorProbe.createSinks.last!.putError(.generic)
            XCTAssertFalse(hub.policy.hasExclusions)
        }
    }
}
