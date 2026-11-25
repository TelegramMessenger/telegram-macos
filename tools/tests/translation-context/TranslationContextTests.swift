import Foundation
import XCTest
import SwiftSignalKit

__TEXT_HELPER__
typealias CGImage = Int
struct Theme { struct Icons { let send_message_large = 1 }; let icons = Icons() }
let theme = Theme()
func richTextOutgoing(from page: [Int]) -> ([Int], Int) { Probe.check?(); return (page, 0) }
func coreBlocks(fromOutgoing blocks: [Int]) -> [Int] { Probe.check?(); return blocks }
final class ModalInteractions {
    let accept: () -> Void
    let extraAction: (() -> Void)?
    init(acceptTitle: String, accept: @escaping () -> Void, singleButton: Bool, extraActionImage: CGImage? = nil, extraAction: (() -> Void)? = nil) {
        self.accept = accept; self.extraAction = extraAction
    }
}
__PREMIUM_SOURCE__
enum StarGift { struct Gift: Equatable {} }
__PREMIUM_LOG_SOURCE__
__PREMIUM_SOURCE_MAPPING__
struct FeatureNavigationHooks {
    static var shared = FeatureNavigationHooks()
    var showPremiumBoarding: (Context, Int, PremiumBoardingSource?, Bool, Int?) -> Void = { _, _, _, _, _ in }
    var showPremiumBoardingWithContext: ((Context, Int, PremiumBoardingSource?, Bool, Int?, AnalyticsContext) -> Void)?
__PREMIUM_HOOK__
}
struct LinkHooks {
    static var shared = LinkHooks()
    func globalLinkExecutor() -> LinkExecutor { Probe.check?(); return LinkExecutor() }
}
struct LinkExecutor {
    func copyAttributedString(_ text: NSAttributedString) -> Bool { Probe.check?(); ActionProbe.copied.append(text); return true }
}
func showModalText(for window: Int, text: String) { Probe.check?(); ActionProbe.toasts += 1 }
enum ActionProbe {
    static var copied: [NSAttributedString] = []
    static var toasts = 0
}
typealias PeerId = Int64
struct MessageId { let peerId: PeerId }
__POLICY__
__CONTEXT__
extension AnalyticsPrivacy {
    init(peerId: PeerId) { self = peerId < 0 ? .excluded : peerId == 0 ? .unresolved : .ordinary }
}
final class Analytics {
    static var shared = Analytics()
    let policy = AnalyticsCollectionPolicy()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(analytics: self, privacy: .unresolved, scope: nil) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext? = nil) -> AnalyticsContext {
        captureContext(owner: engine.account, privacy: AnalyticsPrivacy(peerId: peerId), inherited: inherited)
    }
__CAPTURE__
}
final class Account {}
final class Context {
    let engine = Engine()
    let peerId: PeerId = 1
    let window = 1
}
final class Engine {
    let account = Account()
    let messages = Messages()
    let data = DataProvider()
}
struct CloudStyle { let id: Int64; var authorId: PeerId? }
struct TranslationStyleItem: Equatable { let id: String; let authorId: PeerId? }
func makeStyleItem(from style: CloudStyle) -> TranslationStyleItem { Probe.check?(); return .init(id: "custom_\(style.id)", authorId: style.authorId) }
struct PeerRequest { let id: PeerId }
struct EngineDataMap { let requests: [PeerRequest]; init(_ requests: [PeerRequest]) { self.requests = requests } }
struct Peer { let addressName: String? }
struct ComposeResult: Equatable { let text: String; let entities: [Int] }
enum Translate { enum Error: Swift.Error { case generic, limitExceeded } }
typealias TranslationResult = (detect: String?, result: String, entities: [Int])
final class Messages {
    var styleSinks: [Subscriber<[CloudStyle], NoError>] = []
    var resultSinks: [Subscriber<TranslationResult, Translate.Error>] = []
    var disposals = 0
    func composeAIMessageStyles() -> Signal<[CloudStyle], NoError> {
        Probe.check?()
        return Signal { sink in
            Probe.check?(); self.styleSinks.append(sink)
            return ActionDisposable { Probe.check?(); self.disposals += 1 }
        }
    }
    func translate() -> Signal<TranslationResult, Translate.Error> {
        Probe.check?()
        return Signal { sink in
            Probe.check?(); self.resultSinks.append(sink)
            return ActionDisposable { Probe.check?(); self.disposals += 1 }
        }
    }
}
final class DataProvider {
    var sinks: [Subscriber<[PeerId: Peer?], NoError>] = []
    var requests: [[PeerId]] = []
    func get(_ map: EngineDataMap) -> Signal<[PeerId: Peer?], NoError> {
        Probe.check?(); requests.append(map.requests.map(\.id))
        return Signal { sink in
            Probe.check?(); self.sinks.append(sink)
            return ActionDisposable { Probe.check?() }
        }
    }
}
enum TranslationTone: String { case neutral, formal }
struct State: Equatable {
    var styleId = ""
    var toneId = "neutral"
    var tone = TranslationTone.neutral
    var translatedRich: [Int]?
    func translatedAttr(context: Context) -> NSAttributedString? {
        Probe.check?()
        return translated.map { NSAttributedString(string: $0, attributes: [NSAttributedString.Key("testFormatting"): true]) }
    }
    var styles: [TranslationStyleItem] = []
    var authorNames: [PeerId: String] = [:]
    var translated: String?
    var text = "input"
    var textEntities: [Int] = [1]
    var translatedEntities: [Int] = []
    var isTranslating = true
    var limitExceeded = false
    var from: String?
    var cache: [String: ComposeResult] = [:]
}
struct InputDataSignalValue { let entries: [State] }
func entries(_ state: State, arguments: Int) -> [State] { Probe.check?(); Probe.states.append(state); return [state] }
func deliverOnPrepareQueue<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> { signal }
struct Strings {
    let translateModalDeleteStyleHeader = "delete-style", translateModalDeleteStyleConfirm = "confirm-delete", modalDelete = "Delete", translateModalDeleteStyleForAll = "for-all"
    let unknownError = "error", translateApply = "Apply", modalOK = "OK", contextCopy = "Copy", shareLinkCopied = "Copied"
}
func strings() -> Strings { Strings() }
enum Probe {
    static var check: (() -> Void)?
    static var states: [State] = []
    static var closes = 0
}
class Controller {
    var analyticsContext: AnalyticsContext?
    var onDeinit: (() -> Void)?
    let subscription = MetaDisposable()
    init(_ signal: Signal<InputDataSignalValue, NoError>) { Probe.check?(); subscription.set(signal.start()) }
    deinit { subscription.dispose(); onDeinit?() }
}
final class Modal {
    let controller: Controller
    var analyticsContext: AnalyticsContext?
    var interactions: ModalInteractions?
    var changeTone: (String) -> Void = { _ in }
    var copyTranslation: () -> Void = {}
    var entireChat: (() -> Void)?
    var modal: Modal? { self }
    var reload: () -> Void = {}
    var request: () -> Void = {}
    var dismiss: () -> Void = {}
    var getOrigin: () -> AnalyticsContext = { Analytics.shared.unresolvedContext() }
    var state: () -> State = { State() }
    init(_ controller: Controller) { Probe.check?(); self.controller = controller }
    func close() { Probe.check?(); Probe.closes += 1 }
}
func makeTranslation(_ context: Context, messageId: MessageId? = nil, analyticsContext: AnalyticsContext? = nil, initialState: State = State(), onUse: ((NSAttributedString) -> Void)? = nil, onSend: ((NSAttributedString) -> Void)? = nil, onUseRich: (([Int]) -> Void)? = nil, dismissOnly: Bool = false, onToneChanged: ((TranslationTone) -> Void)? = nil, translateEntireChat: (() -> Void)? = nil) -> Modal {
__ADMISSION__
    let actionsDisposable = DisposableSet()
    let disposable = MetaDisposable()
    actionsDisposable.add(disposable)
    let isInputMode = onUse != nil || onUseRich != nil
    var close: (() -> Void)?
__STATE__
__LOADING__
__REQUEST_GUARD__
        let signal = context.engine.messages.translate()
        let key = "key"
__REQUEST_RESULT__
    let arguments = 0
__RENDER__
    let controller = Controller(signal)
__CONTENT__
__CLEANUP__
__ACTIONS__
    let changeTone: (String) -> Void = { tone in
__TONE__
    }
    let copyTranslation: () -> Void = {
__COPY__
    }
    let entireChat: (() -> Void)? = translateEntireChat != nil ? {
__ENTIRE_CHAT__
    } : nil
    let modalController = Modal(controller)
__MODAL__
__CLOSE__
    modalController.interactions = modalInteractions
    modalController.changeTone = changeTone
    modalController.copyTranslation = copyTranslation
    modalController.entireChat = entireChat
    modalController.reload = triggerReloadStyles
    modalController.request = request
    modalController.dismiss = { close?() }
    modalController.getOrigin = getAnalyticsContext
    modalController.state = { stateValue.with { $0 } }
    return modalController
}
final class TranslationContextTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.check = nil; Probe.states = []; Probe.closes = 0
    }
    override func tearDown() { Probe.check = nil; super.tearDown() }
    func origin(_ id: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: id) }
    func expectExcluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testOrdinaryExplicitOriginIsRetainedAndLoadsStylesAndAuthors() {
        let origin = origin()
        Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        let modal = makeTranslation(context, analyticsContext: origin)
        XCTAssertTrue(modal.analyticsContext?.scope === origin.scope)
        XCTAssertTrue(modal.controller.analyticsContext?.scope === origin.scope)
        context.engine.messages.styleSinks[0].putNext([CloudStyle(id: 5, authorId: 2)])
        XCTAssertEqual(context.engine.data.requests, [[2]])
        context.engine.data.sinks[0].putNext([2: Peer(addressName: "author")])
        XCTAssertEqual(modal.state().authorNames[2], "author")
        XCTAssertEqual(modal.state().styles.map(\.id), ["custom_5"])
    }
    func testPrivateAndUnknownOriginsGuardDelayedProvidersDeliveryAndCleanup() {
        for id: PeerId in [-1, 0] {
            let source = origin(id); expectExcluded()
            var modal: Modal? = makeTranslation(context, analyticsContext: source)
            XCTAssertTrue(modal!.analyticsContext!.isExcluded)
            context.engine.messages.styleSinks.last!.putNext([CloudStyle(id: 7, authorId: 2)])
            context.engine.data.sinks.last!.putNext([2: Peer(addressName: "name")])
            modal!.request()
            context.engine.messages.resultSinks.last!.putNext((nil, "result", [2]))
            XCTAssertEqual(modal!.state().translated, "result")
            modal!.dismiss(); modal = nil
            XCTAssertFalse(hub.policy.hasExclusions)
        }
    }
    func testLegacyMissingContextCannotMintOrdinaryGrant() {
        expectExcluded()
        let modal = makeTranslation(context)
        XCTAssertTrue(modal.analyticsContext!.isExcluded)
        XCTAssertNil(modal.analyticsContext!.scope)
        modal.request(); modal.dismiss()
    }
    func testSecretMessageRestrictsOrdinaryInheritedScope() {
        let source = origin(); expectExcluded()
        let modal = makeTranslation(context, messageId: MessageId(peerId: -9), analyticsContext: source)
        XCTAssertTrue(modal.analyticsContext!.isExcluded)
        modal.request()
        context.engine.messages.resultSinks.last!.putNext((nil, "translated", []))
    }
    func testAccountSwitchAndScopeRevocationRejectCapturedOrigin() {
        for switchAccount in [false, true] {
            let source = origin()
            var modal: Modal? = makeTranslation(context, analyticsContext: source)
            let retainedGetter = modal!.getOrigin
            if switchAccount { hub.policy.setOwner(Account()) } else { source.scope!.exclude() }
            expectExcluded()
            context.engine.messages.styleSinks.last!.putNext([CloudStyle(id: 9, authorId: 2)])
            context.engine.data.sinks.last!.putNext([2: Peer(addressName: "late")])
            modal!.reload(); modal!.request(); modal!.dismiss()
            XCTAssertTrue(retainedGetter().scope?.isValid != true)
            modal = nil
            let guardValue = retainedGetter().beginPresentation()
            XCTAssertTrue(hub.policy.hasExclusions); guardValue.end()
            Probe.check = nil; hub.policy.setOwner(context.engine.account)
        }
    }
    func testDisabledCollectionKeepsFunctionalLoadingAndTranslation() {
        let source = origin(); hub.policy.isEnabled = false; expectExcluded()
        let modal = makeTranslation(context, analyticsContext: source)
        modal.request()
        context.engine.messages.resultSinks.last!.putNext(("detected", "translated", [3]))
        XCTAssertEqual(modal.state().translated, "translated")
        XCTAssertEqual(modal.state().from, "detected")
    }
    func testReloadAndRequestReplacementDisposePreviousSubscriptions() {
        let modal = makeTranslation(context, analyticsContext: origin())
        modal.reload(); XCTAssertEqual(context.engine.messages.styleSinks.count, 2)
        XCTAssertEqual(context.engine.messages.disposals, 1)
        modal.request(); modal.request()
        XCTAssertEqual(context.engine.messages.disposals, 2)
    }
    func testErrorEmptyResultCacheAndRenderKeepOriginalBehaviorUnderExclusion() {
        let source = origin(-1); expectExcluded()
        let modal = makeTranslation(context, analyticsContext: source)
        modal.request(); context.engine.messages.resultSinks.last!.putNext(("en", "", []))
        XCTAssertEqual(modal.state().translated, "input")
        XCTAssertEqual(modal.state().translatedEntities, [1])
        XCTAssertEqual(modal.state().cache["key"]?.text, "input")
        modal.request(); context.engine.messages.resultSinks.last!.putError(.limitExceeded)
        XCTAssertTrue(modal.state().limitExceeded)
        XCTAssertEqual(modal.state().translated, "input")
        modal.request(); context.engine.messages.resultSinks.last!.putError(.generic)
        XCTAssertEqual(modal.state().translated, "error")
        XCTAssertFalse(Probe.states.isEmpty)
    }
    func testReleasedModalDisposesWithoutKeepingControllerAlive() {
        expectExcluded()
        var modal: Modal? = makeTranslation(context)
        weak var content = modal?.controller
        modal!.request()
        let request = modal!.request
        modal = nil
        XCTAssertNil(content)
        XCTAssertFalse(hub.policy.hasExclusions)
        request()
        XCTAssertFalse(hub.policy.hasExclusions)
    }
}

final class TranslationActionTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.check = nil; Probe.closes = 0; Probe.states = []
        ActionProbe.copied = []; ActionProbe.toasts = 0
        FeatureNavigationHooks.shared = FeatureNavigationHooks()
    }
    override func tearDown() { Probe.check = nil; FeatureNavigationHooks.shared = FeatureNavigationHooks(); super.tearDown() }
    func origin(_ id: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: id) }
    func translated(_ text: String? = "result😀") -> State { var state = State(); state.translated = text; return state }
    func marked(_ text: NSAttributedString) -> Bool { text.length > 0 && text.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) != nil }
    func testOrdinaryApplyAndSendPreserveTextFormattingAndClose() {
        Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        var uses: [NSAttributedString] = []; var sends: [NSAttributedString] = []
        let modal = makeTranslation(context, analyticsContext: origin(), initialState: translated(), onUse: { uses.append($0) }, onSend: { sends.append($0) })
        modal.interactions!.accept(); modal.interactions!.extraAction?()
        XCTAssertEqual(uses.map(\.string), ["result😀"]); XCTAssertEqual(sends.map(\.string), ["result😀"])
        XCTAssertFalse(marked(uses[0])); XCTAssertFalse(marked(sends[0]))
        XCTAssertNotNil(uses[0].attribute(NSAttributedString.Key("testFormatting"), at: 0, effectiveRange: nil))
        XCTAssertEqual(Probe.closes, 2)
    }
    func testPrivateApplyAndSendRetainExclusionAfterModalRelease() {
        var results: [NSAttributedString] = []
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var modal: Modal? = makeTranslation(context, analyticsContext: origin(-1), initialState: translated(), onUse: { Probe.check?(); results.append($0) }, onSend: { Probe.check?(); results.append($0) })
        let actions = modal!.interactions!
        weak var content = modal?.controller
        modal = nil; XCTAssertNil(content); XCTAssertFalse(hub.policy.hasExclusions)
        actions.accept(); actions.extraAction?()
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy(marked))
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRevocationAccountChangeAndDisabledCollectionMarkResultsWithoutBlockingUse() {
        for mode in 0..<3 {
            let source = origin()
            var results: [NSAttributedString] = []
            var modal: Modal? = makeTranslation(context, analyticsContext: source, initialState: translated(), onUse: { Probe.check?(); results.append($0) })
            let accept = modal!.interactions!.accept
            if mode == 0 { source.scope!.exclude() }
            else if mode == 1 { hub.policy.setOwner(Account()) }
            else { hub.policy.isEnabled = false }
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            modal = nil; accept()
            XCTAssertEqual(results.count, 1); XCTAssertTrue(marked(results[0]))
            XCTAssertFalse(hub.policy.hasExclusions)
            Probe.check = nil; hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        }
    }
    func testLimitPremiumHandoffUsesExplicitContextAfterClose() {
        for id: PeerId in [1, -1] {
            let source = origin(id)
            var state = translated(); state.limitExceeded = true
            var premiumContext: AnalyticsContext?
            var applied = false
            FeatureNavigationHooks.shared.showPremiumBoardingWithContext = { _, window, kind, openFeatures, _, origin in
                Probe.check?(); XCTAssertEqual(window, 1); XCTAssertEqual(kind, .aiCompose); XCTAssertFalse(openFeatures)
                XCTAssertGreaterThan(Probe.closes, 0); premiumContext = origin
            }
            Probe.check = { XCTAssertEqual(self.hub.policy.hasExclusions, id < 0) }
            var modal: Modal? = makeTranslation(context, analyticsContext: source, initialState: state, onUse: { _ in applied = true })
            let accept = modal!.interactions!.accept
            accept()
            XCTAssertFalse(applied)
            XCTAssertEqual(premiumContext?.isExcluded, id < 0)
            if id > 0 { XCTAssertTrue(premiumContext?.scope === source.scope) }
            modal = nil
            accept()
            XCTAssertEqual(premiumContext?.isExcluded, id < 0)
            XCTAssertFalse(hub.policy.hasExclusions)
            Probe.check = nil
        }
    }
    func testCopyActionsHoldOriginAfterReleaseWithoutChangingClipboardText() {
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var modal: Modal? = makeTranslation(context, analyticsContext: origin(-1), initialState: translated())
        let primary = modal!.interactions!.accept; let secondary = modal!.copyTranslation
        modal = nil; primary(); secondary()
        XCTAssertEqual(ActionProbe.copied.map(\.string), ["result😀", "result😀"])
        XCTAssertEqual(ActionProbe.toasts, 2); XCTAssertEqual(Probe.closes, 0)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRichUsePreservesBlocksAndHoldsOriginAfterRelease() {
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var state = translated(); state.translatedRich = [1, 2, 3]
        var result: [Int] = []
        var modal: Modal? = makeTranslation(context, analyticsContext: origin(-1), initialState: state, onUseRich: { Probe.check?(); result = $0 })
        let accept = modal!.interactions!.accept
        modal = nil; accept()
        XCTAssertEqual(result, [1, 2, 3]); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testToneAndEntireChatCallbacksRetainOriginAfterRelease() {
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var tones: [TranslationTone] = []; var wholeChat = 0
        var modal: Modal? = makeTranslation(context, analyticsContext: origin(-1), initialState: translated(), onToneChanged: { Probe.check?(); tones.append($0) }, translateEntireChat: { Probe.check?(); wholeChat += 1 })
        let tone = modal!.changeTone; let entire = modal!.entireChat
        modal = nil
        tone("formal"); tone("unknown"); entire?()
        XCTAssertEqual(tones, [.formal, .neutral]); XCTAssertEqual(wholeChat, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testNilEmptyAndDismissOnlyKeepExistingActionSemantics() {
        let source = origin()
        var results: [NSAttributedString] = []
        var modal: Modal? = makeTranslation(context, analyticsContext: source, initialState: translated(nil), onUse: { results.append($0) })
        modal!.interactions!.accept(); XCTAssertTrue(results.isEmpty); XCTAssertEqual(Probe.closes, 0)
        modal = makeTranslation(context, analyticsContext: source, initialState: translated(""), onUse: { results.append($0) })
        modal!.interactions!.accept(); XCTAssertEqual(results.map(\.string), [""]); XCTAssertEqual(Probe.closes, 1)
        modal = makeTranslation(context, analyticsContext: source, dismissOnly: true)
        modal!.interactions!.accept(); XCTAssertEqual(Probe.closes, 2); XCTAssertTrue(ActionProbe.copied.isEmpty)
        modal = nil
    }
}
