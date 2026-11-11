import Foundation
import XCTest
import SwiftSignalKit

public struct PeerId: Hashable, ExpressibleByIntegerLiteral {
    let value: Int64
    var namespace: Int32 { value < 0 ? -1 : 1 }
    public init(integerLiteral value: Int64) { self.value = value }
    init(_ value: Int64) { self.value = value }
    func toInt64() -> Int64 { value }
}
struct MessageId: Hashable { let peerId: PeerId; let id: Int }
struct Message {
    let id: MessageId
    var attributes: [Any] = []
    var media: [Int] = []
    var isPublicPoll = false
    var containsSecretMedia = false
    var groupInfo: Bool?
    var anyMedia: GalleryMedia? { TelegramMediaImage() }
    var effectiveMedia: [GalleryMedia] { [] }
}
enum Namespaces { enum Peer { static let SecretChat: Int32 = -1 } }
struct StarsAmount { let value: Int64; let nanos: Int32 }
__POLICY__
__CONTEXT__
extension AnalyticsContext {
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(context: self) }
__PRESERVING__
}
__PRESENTATION__
extension AnalyticsPrivacy {
    init(peerId: PeerId) { self = peerId.value < 0 ? .excluded : peerId.value == 0 ? .unresolved : .ordinary }
}
final class Analytics {
    static var shared = Analytics()
    let policy = AnalyticsCollectionPolicy()
    let screens = GalleryScreenTracker()
    func privacyContext(peerId: PeerId) -> AnalyticsContext { AnalyticsContext(analytics: self, privacy: AnalyticsPrivacy(peerId: peerId), scope: nil) }
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(analytics: self, privacy: .unresolved, scope: nil) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext? = nil) -> AnalyticsContext {
        captureContext(owner: engine.account, privacy: AnalyticsPrivacy(peerId: peerId), inherited: inherited)
    }
__CAPTURE__
}
final class Account { let peerId: PeerId = 1; let postbox = Postbox() }
struct PreparedInlineMessage { let botId: PeerId; let result: Int }
struct EnginePeer { let id: PeerId; init(id: PeerId) { self.id = id }; init(_ peer: Peer) { id = peer.id } }
struct InlineBuildArguments { let peer: PeerId; let bot: PeerId; let thread: Int64?; let silent: Bool; let schedule: Int32?; let stars: StarsAmount?; let hideVia: Bool; let postpone: Bool }
final class EngineMessages {
    var preparedResult: Signal<PreparedInlineMessage?, NoError> = .single(nil)
    var lookups: [(PeerId, String)] = []
    var onLookup: (() -> Void)?
    func getPreparedInlineMessage(botId: PeerId, id: String) -> Signal<PreparedInlineMessage?, NoError> { onLookup?(); lookups.append((botId, id)); return preparedResult }

    func outgoingMessageWithChatContextResult(to peerId: PeerId, threadId: Int64?, botId: PeerId, result: Int, replyToMessageId: Int?, replyToStoryId: Int?, hideVia: Bool, silentPosting: Bool, scheduleTime: Int32?, sendPaidMessageStars: StarsAmount?, postpone: Bool, correlationId: Int64?) -> EnqueueMessage? {
        UI.onInlineBuild?(); UI.inlineBuilds.append(InlineBuildArguments(peer: peerId, bot: botId, thread: threadId, silent: silentPosting, schedule: scheduleTime, stars: sendPaidMessageStars, hideVia: hideVia, postpone: postpone))
        if UI.inlineFailures.contains(peerId) { return nil }
        return EnqueueMessage(text: "synthetic-inline", attributes: [], mediaReference: nil, threadId: threadId)
    }
}
final class Engine { let account = Account(); let messages = EngineMessages() }
final class Window {}
protocol AccountContextProtocol { var engine: Engine { get }; var account: Account { get }; var peerId: PeerId { get }; var bindings: Bindings { get }; var window: Window { get } }
extension AccountContextProtocol { var concrete: AccountContext { self as! AccountContext } }
struct StarsState { let balance: StarsAmount }
final class StarsContext { var state: Signal<StarsState?, NoError> = .single(nil) }
extension AccountContextProtocol {
    var starsContext: StarsContext { (self as! AccountContext).starState }
    var timestamp: Int32 { 100 }
}
final class AccountContext: AccountContextProtocol {
    let starState = StarsContext()
    let engine = Engine(); let bindings = Bindings(); let window = Window()
    let peerId: PeerId = 1
    var account: Account { engine.account }
}
class Peer {
    let id: PeerId
    var compactDisplayTitle: String { "synthetic" }
    var displayTitle: String { compactDisplayTitle }
    var isChannel = false, isCommunity = false, isMonoForum = false, canSend = true
    var bansInline = false
    func hasBannedRights(_ right: ComposerBannedRight) -> Bool { bansInline }
    init(_ id: PeerId) { self.id = id }
    func canSendMessage(media: Int? = nil) -> Bool { canSend }
}
struct PeerFlags: OptionSet { let rawValue: Int; static let slowModeEnabled = Self(rawValue: 1), isCreator = Self(rawValue: 2) }
struct GroupInfo { let flags: PeerFlags }
enum ChannelInfo { case group(GroupInfo), broadcast }
final class TelegramChannel: Peer {
    var info: ChannelInfo = .group(GroupInfo(flags: [])), flags: PeerFlags = []
    var adminRights: Int?, sendPaidMessageStars: StarsAmount?
}
final class CachedChannelData { var sendAsPeerId: PeerId?, slowModeValidUntilTimestamp: Int32? }
struct UnsentView { var ids: [MessageId] = [] }
final class Transaction {
    var peers: [PeerId: Peer] = [:], messages: [MessageId: Message] = [:], groups: [MessageId: [Message]] = [:]
    var cached: [PeerId: CachedChannelData] = [:]
    func getPeerCachedData(peerId: PeerId) -> AnyObject? { cached[peerId] }
    func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    func getMessage(_ id: MessageId) -> Message? { messages[id] }
    func getMessageGroup(_ id: MessageId) -> [Message]? { groups[id] }
}
final class Postbox {
    var composerMessages: Signal<[Message], NoError> = .single([])
    func messagesAtIds(_ ids: [MessageId]) -> Signal<[Message], NoError> { composerMessages }
    var contactResult: Signal<Peer?, NoError>?, onContactLookup: (() -> Void)?
    let value = Transaction()
    var delayed = false
    var pending: [() -> Void] = []
    var onSetup: (() -> Void)?, onSubscription: (() -> Void)?, onDispose: (() -> Void)?
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        onSetup?()
        return Signal { subscriber in
            self.onSubscription?()
            let deliver = { subscriber.putNext(f(self.value)); subscriber.putCompletion() }
            if self.delayed { self.pending.append(deliver) } else { deliver() }
            return ActionDisposable { self.onDispose?() }
        }
    }
    var unsent: Signal<UnsentView, NoError> = .single(UnsentView())
    func unsentMessageIdsView() -> Signal<UnsentView, NoError> { unsent }
    var loadedResults: [PeerId: Signal<Peer, NoError>] = [:]
    func loadedPeerWithId(_ id: PeerId) -> Signal<Peer, NoError> { loadedResults[id] ?? transaction { $0.getPeer(id)! } }
    func flush() { let jobs = pending; pending = []; jobs.forEach { $0() } }
}
func getCachedDataView(peerId: PeerId, postbox: Postbox) -> Signal<AnyObject?, NoError> { .single(nil) }
struct ChatTextInputState: Equatable { var hasExcludedAnalytics = false; var inputText = ""; var inlineMedia: [Int: Int] = [:]; func messageTextEntities(_ type: ParsingType) -> [Int] { [] } }
struct ParsingType: OptionSet { let rawValue: Int; static let Hashtags = Self(rawValue: 1), Links = Self(rawValue: 2) }
protocol MessageAttribute {}
struct TextEntitiesMessageAttribute: MessageAttribute { let entities: [Int] }
struct SendAsMessageAttribute: MessageAttribute { let peerId: PeerId }
struct NotificationInfoMessageAttribute: MessageAttribute {
    struct Flags: OptionSet { let rawValue: Int; static let muted = Self(rawValue: 1) }
    let flags: Flags
}
struct OutgoingScheduleInfoMessageAttribute: MessageAttribute { let scheduleTime: Int32; let repeatPeriod: Int32? }
struct PaidStarsMessageAttribute: MessageAttribute { let stars: StarsAmount; let postponeSending: Bool }
struct AnyMediaReference { let media: Int; static func standalone(media: Int) -> Self { Self(media: media) } }
struct EnqueueMessage {
    let text: String; let attributes: [MessageAttribute]; let mediaReference: AnyMediaReference?; let threadId: Int64?
    static func message(text: String, attributes: [MessageAttribute], inlineStickers: [Int: Int], mediaReference: AnyMediaReference?, threadId: Int64?, replyToMessageId: Int?, replyToStoryId: Int?, localGroupingKey: Int?, correlationId: Int?, bubbleUpEmojiOrStickersets: [Int]) -> Self { Self(text: text, attributes: attributes, mediaReference: mediaReference, threadId: threadId) }
}
func enqueueMessages(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
    UI.onSendSetup?(); UI.enqueued.append((peerId, messages))
    return UI.enqueueResults.isEmpty ? .complete() : UI.enqueueResults.removeFirst()
}
enum FastSettings { static func isChannelMessagesMuted(_ id: PeerId) -> Bool { false } }
enum Sender {
    static func enqueue(message: EnqueueMessage, context: any AccountContextProtocol, peerId: PeerId) -> Signal<[MessageId?], NoError> {
        UI.onSendSetup?(); UI.sentMessages.append((peerId, message)); UI.comments += 1; return UI.targetComments[peerId] ?? UI.commentResult ?? UI.sendResult
    }
    static func forwardMessages(messageIds: [MessageId], context: any AccountContextProtocol, peerId: PeerId, replyId: Int?, threadId: Int64?, hideNames: Bool = false, hideCaptions: Bool = false, silent: Bool = false, atDate: Date? = nil, sendAsPeerId: PeerId? = nil, sendPaidMessageStars: StarsAmount? = nil) -> Signal<[MessageId?], NoError> {
        UI.onSendSetup?(); UI.targets.append(peerId); UI.forwarded.append(messageIds); return UI.targetResults[peerId] ?? UI.sendResult
    }
}
enum Behavior { case automatic }
enum ChatInitialAction { case forward(messageIds: [MessageId], text: ChatTextInputState?, behavior: Behavior) }
enum ChatLocation: Equatable { case peer(PeerId); var peerId: PeerId { switch self { case let .peer(id): return id } } }
struct FixtureEditState { let message: Message }
struct ComposerReplySubject { let messageId: MessageId }
struct InterfaceState {
    var replyMessageId: ComposerReplySubject?
    var replyMessage: Message?
    var forwardMessageIds: [MessageId] { ids }
    var forwardMessages: [Message] = []
    var editState: FixtureEditState?
    var ids: [MessageId] = [], input = ChatTextInputState()
    var inputState: ChatTextInputState { input }
    func withUpdatedForwardMessageIds(_ ids: [MessageId]) -> Self { var value = self; value.ids = ids; return value }
    func withUpdatedInputState(_ input: ChatTextInputState) -> Self { var value = self; value.input = input; return value }
}
enum FixtureChatState { case normal, selecting }
struct ChatState {
    var state: FixtureChatState = .normal
    var reportMode: Int?
    var interface = InterfaceState()
    var effectiveInput: ChatTextInputState { interface.input }
    var interfaceState: InterfaceState { interface }
    func withoutSelectionState() -> Self { self }
    func updatedInterfaceState(_ f: (InterfaceState) -> InterfaceState) -> Self { var value = self; value.interface = f(interface); return value }
}
final class ChatInteraction {
    var richDraftEntry: (value: Int, origin: AnalyticsContext?)?
__RICH_RESTRICTION__
    let interactionContext: any AccountContextProtocol
    var peer: Peer?
__CHAT_CAPTURE__
    let chatLocation: ChatLocation
    var peerId: PeerId { chatLocation.peerId }
    var inheritedAnalyticsContext: AnalyticsContext?
    let quickForwardAction = ChatQuickForwardAction()
    let composerForwardPreparation = ChatForwardSendPreparation()
    private var deferredSendRevision = UUID()
    private let composerAnalyticsScopes = Atomic(value: ComposerAnalyticsScopeState())
__COMPOSER_INVALIDATE__
__COMPOSER_PREPARE__
    var composerPrivacyRevision: UInt64 { composerAnalyticsScopes.with { $0.revision } }
    var quickMenuCurrent = true
    var getMessages: ([MessageId], Bool) -> Signal<[Message], NoError> = { _, _ in .single([]) }
    var context: any AccountContextProtocol { interactionContext }
    func captureDeferredSendAction() -> ChatDeferredSendAction { let revision = deferredSendRevision; return ChatDeferredSendAction { [weak self] in self?.quickMenuCurrent == true && self?.deferredSendRevision == revision } }
__QUICK_FORWARD_DISPATCH__
__MENU_FORWARD_HANDOFF__
    var reportMessages: (Int, [MessageId]) -> Void = { _, _ in }
    private let _presentation = Atomic(value: ChatState())
    var state: ChatState {
        get { _presentation.with { $0 } }
        set { _ = _presentation.swap(newValue) }
    }
    var presentation: ChatState { state }
    func applyComposerPrivacyUpdate(_ f: (ChatState) -> ChatState, after: () -> Void = {}) {
__COMPOSER_LIVE_UPDATE__
        after()
    }
    init(chatLocation: ChatLocation, context: any AccountContextProtocol) { self.chatLocation = chatLocation; self.interactionContext = context }
    func update(_ f: (ChatState) -> ChatState) { UI.onUpdate?(); state = f(state) }
}
class Popover { func hide() {} }
class ViewController {
    var popover: Popover?
    var analyticsContext: AnalyticsContext?
    let ready = ValuePromise(false)
}
protocol ChatInterfaceController: ViewController {
    var chatInteraction: ChatInteraction { get }
    func inheritAnalyticsContext(_ inherited: AnalyticsContext)
}
func messageForForwarding(_ message: Message) -> Message { message }
final class ChatController: ViewController, ChatInterfaceController {
    let nextTransaction = ComposerTransaction()
    func installForwardingCallbacks() {
        let context = self.context
__FORWARD_CONTROLLER_BINDINGS__
    }
    let context: any AccountContextProtocol
    let chatInteraction: ChatInteraction
    var chatLocation: ChatLocation { chatInteraction.chatLocation }
    private var inheritedAnalyticsPresentation: AnalyticsPresentation?
    init(_ context: any AccountContextProtocol, _ location: ChatLocation) { self.context = context; chatInteraction = ChatInteraction(chatLocation: location, context: context); super.init() }
    func updateAnalyticsScreen(chatLocation: ChatLocation) { analyticsContext = chatInteraction.inheritedAnalyticsContext }
__INHERIT__
}
final class Navigation {
    var controllers: [ViewController] = []
    var controller: ViewController? { controllers.last }
    func push(_ controller: ViewController) { UI.onPush?(controller); controllers.append(controller) }
    func enumerateControllers(_ f: (ViewController, Int) -> Bool) { for (i, c) in controllers.enumerated() { if f(c, i) { break } } }
}
final class Bindings { let navigation = Navigation(); func rootNavigation() -> Navigation { navigation } }
struct Theme { struct Icons { let successModalProgress = 1, modalClose = 2 }; let icons = Icons() }
let theme = Theme()
func delay(_ value: Double, closure: @escaping () -> Void) { UI.delayed.append(closure) }
func showModalSuccess(for window: Window, icon: Int, delay: Double) -> Signal<Never, NoError> { UI.onSuccess?(); UI.successes += 1; return .complete() }
struct Strings {
    var messageContextForward: String { "forward" }
    var chatContextForwardMore: String { "more" }
    let galleryContextShareThisPhoto = "photo", galleryContextShareThisVideo = "video", galleryContextShareThisFile = "file"
    func galleryContextShareAllPhotosOther(_ count: Int) -> String { "photos" }
    func galleryContextShareAllVideosOther(_ count: Int) -> String { "videos" }
    func galleryContextShareAllItemsOther(_ count: Int) -> String { "items" }
    let peerSavedMessages = "saved"
    let webappShareMessageShare = "preview"
    let shareIncompleteDelivery = "incomplete"
    let pollForwardError = "poll", alertLearnMore = "learn", slowModeForwardCommentError = "comment", slowModeMultipleError = "unsent", chatPayStarsConfirmTitle = "pay"
    func peerInfoConfirmShareInfo(_ title: String) -> String { title }
    func peerForwardPremiumRequired(_ title: String) -> String { title }
    func starListItemCountOther(_ value: Int) -> String { "amount \(value)" }
    func chatPayStarsConfirmMessagesOther(_ value: Int) -> String { "messages \(value)" }
    func sharePayConfirmUserCountOther(_ value: Int) -> String { "users \(value)" }
    func sharePayConfirmText(_ users: String, _ amount: String, _ messages: String) -> String { "\(users) \(amount) \(messages)" }
    func chatPayStarsConfirmPayOther(_ value: Int) -> String { "pay \(value)" }
}
func slowModeTooltipText(_ value: Int32) -> String { "slow" }
func tooltip(for view: PickerView, text: String) { UI.blockers.append(text) }
func strings() -> Strings { Strings() }
enum ForumUI {
    static func openTopic(_ threadId: Int64, peerId: PeerId, context: any AccountContextProtocol, animated: Bool, addition: Bool, initialAction: ChatInitialAction, isMonoforum: Bool, analyticsContext: AnalyticsContext?) -> Signal<Bool, NoError> {
        UI.forumContext = analyticsContext; UI.onForum?(); return UI.forumResult
    }
}
struct TelegramPresentationTheme {}
class ShareObject {
    let context: any AccountContextProtocol
    var presentation: TelegramPresentationTheme?
    var excludePeerIds = Set<PeerId>(), threadIds: [PeerId: Int64] = [:]
    var scheduleDate: Date?, withoutSound = false
    let emptyPerformOnClose: Bool
    init(_ context: any AccountContextProtocol, emptyPerformOnClose: Bool = false) { self.context = context; self.emptyPerformOnClose = emptyPerformOnClose }
    var alwaysEnableDone: Bool { false }
    var messagesCount: Int { 0 }; var multipleSelection: Bool { true }; var searchPlaceholderKey: String { "" }
    func possibilityPerformTo(_ peer: Peer) -> Bool { true }
    func perform(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars: [PeerId: StarsAmount] = [:]) -> Signal<Never, String> { .complete() }
__ATTRIBUTES__
}
__FORWARD_OBJECT__
enum ModalAnimationCloseBehaviour { case common }
class ModalViewController: ViewController {
    func close(animationType: ModalAnimationCloseBehaviour = .common) { UI.closed += 1 }
    struct Bar { let height: Int }
    var bar = Bar(height: 0)
    var analyticsScreen: AnalyticsScreen?
    init(frame: NSRect = .zero) { super.init() }
}
enum AnalyticsScreen { case sharePeerPicker, appPeerPicker, botMiniAppShareMessage, botMiniApp, peerInfo, mediaViewer; var isAnalyticsExcluded: Bool { false } }
final class InputContextHelper { init(chatInteraction: ChatInteraction) { UI.inputOrigin = chatInteraction.inheritedAnalyticsContext } }
class ShareSelectCallbackObject: ShareObject {}
class ShareLinkObject: ShareObject, ShareDeliveryProviding {
    let link: String
    init(_ context: any AccountContextProtocol, link: String) { self.link = link; super.init(context) }
    override var messagesCount: Int { 1 }
__LINK_SHARE__
}
class ShareContactObject: ShareObject, ShareDeliveryProviding {
    let user: Peer
    let media: Int
    init(_ context: any AccountContextProtocol, user: Peer, media: Int = 42) { self.user = user; self.media = media; super.init(context) }
    override var messagesCount: Int { 1 }
__CONTACT_SHARE__
}
__DELIVERY__
class ShareMessageObject: ShareObject, ShareDeliveryProviding {
    let message: Message
    let messageIds: [MessageId]
    init(_ context: any AccountContextProtocol, _ message: Message, _ group: [Message] = []) {
        self.message = message; self.messageIds = group.isEmpty ? [message.id] : group.map { $0.id }; super.init(context)
    }
    override var messagesCount: Int { messageIds.count }
__MESSAGE_SHARE__
}
class ShareStoryObject: ShareObject {}
class ReplyForwardMessageObject: ShareObject {}
class ShareChatContextResult: ShareObject, ShareDeliveryProviding {
    let preparedMessage: PreparedInlineMessage
    init(_ context: any AccountContextProtocol, preparedMessage: PreparedInlineMessage) { self.preparedMessage = preparedMessage; super.init(context) }
__PREPARED_SHARE__
}
__PICKER_ACTION__
__CONFIRMATION__
enum KeyHandlerResult { case invoked, rejected }
enum Currency { case stars }
func verifyAlert(for window: Window, header: String, information: String, ok: String, successHandler: @escaping (Int) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    UI.onConfirmation?(); UI.confirmationTexts.append(information)
    UI.confirmations.append((successHandler, cancelHandler, onDeinit))
}
struct PickerSelection {
    var premiumRequired = Set<PeerId>(), selected = Set<PeerId>()
    var comment = ""
    var peers: [PeerId: Peer] = [:]
}
final class SelectPeerInteraction {
    var presentation = PickerSelection()
    var premiumRequiredAction: ((PeerId) -> Void)?
    var action: (PeerId, Int64?) -> Void = { _, _ in }
    func activateSelection(_ peer: Peer) { UI.toggled.append(peer.id) }
    func toggleSelection(_ peer: Peer) { UI.toggled.append(peer.id) }
}
class TableRowItem {}
final class ShortPeerRowItem: TableRowItem {
    enum InteractionType { case selectable, interactable }
    let peer: Peer
    let interactionType: InteractionType
    let action: () -> Void
    init(_ peer: Peer, interactionType: InteractionType = .interactable, action: @escaping () -> Void) { self.peer = peer; self.interactionType = interactionType; self.action = action }
}
class GeneralRowItem: TableRowItem {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
}
enum PickerControlEvent { case SingleClick }
final class PickerControl {
    var action: ((Int) -> Void)?
    func set(handler: @escaping (Int) -> Void, for event: PickerControlEvent) { action = handler }
}
extension FastSettings { static func checkSendingAbility(for event: Int) -> Bool { event != 0 } }
typealias TableView = PickerView
final class PickerView {
    var query = ""
    var items: [TableRowItem] = [], highlighted: TableRowItem?
    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    let sendButton = PickerControl()
    var sendWithoutSound: (() -> Void)?
    var tokenizedView: PickerView { self }; var textView: PickerView { self }; var bottomSeparator: PickerView { self }
    func item(at index: Int) -> TableRowItem { items[index] }
    func highlightedItem() -> TableRowItem? { highlighted }
    func select(item: TableRowItem) -> Bool { true }
    func removeAllFailed(animated: Bool) {}
    func markAsFailed(_ ids: [Int64], animated: Bool) { UI.failedTargets.append(contentsOf: ids) }
    func addTooltip(for id: Int64, text: String) { UI.blockers.append(text) }
    func shake() {}
    var activeTableView: PickerView { self }
    var basicSearchView: PickerView { self }
    func setString(_ value: String) { query = value }
    func popCommunity(animated: Bool) {}
    func popForum(animated: Bool) {}
    func cancelSelection() {}
}
struct PickerSearchState {
    private let value: String
    private let onRead: (() -> Void)?
    init(request: String, onRead: (() -> Void)? = nil) { value = request; self.onRead = onRead }
    var request: String { onRead?(); return value }
}
final class PickerSearch {
    private let promise = Promise<PickerSearchState>()
    private(set) var observers = 0
    func set(_ signal: Signal<PickerSearchState, NoError>) { promise.set(signal) }
    func get() -> Signal<PickerSearchState, NoError> {
        Signal { subscriber in
            self.observers += 1
            let disposable = self.promise.get().start(next: subscriber.putNext)
            return ActionDisposable { disposable.dispose(); self.observers -= 1 }
        }
    }
}
func alert(for window: Window, info: String, onDeinit: @escaping () -> Void) { UI.onAlert?(); UI.alerts += 1; UI.alertClosures.append(onDeinit) }
func showModalText(for window: Window, text: String, button: String, callback: @escaping (String) -> Void) { UI.onPremiumText?(); UI.premiumTextCallbacks.append(callback) }
final class FeatureNavigationHooks {
    static let shared = FeatureNavigationHooks()
    func showStarsPurchaseWithContext(_ context: any AccountContextProtocol, _ window: Window, _ currency: Currency, _ suffix: String?, _ amount: Int64?, _ analyticsContext: AnalyticsContext) { UI.onPurchase?(); UI.purchaseOrigin = analyticsContext; UI.purchaseAmounts.append(amount) }
    func showPremiumBoardingObserved(_ context: any AccountContextProtocol, _ window: Window, _ source: Int?, _ open: Bool, _ theme: Int?, analyticsContext: AnalyticsContext) { UI.premiumOrigin = analyticsContext; UI.premiumOpened += 1 }
}
final class ShareModalController: ModalViewController {
__DESTINATION_TYPE__
    let search = PickerSearch()
    let analyticsSearchDisposable = MetaDisposable()
    var destinationStack: [Destination] = []
    let destinationPeerId = ValuePromise<PeerId?>(nil, ignoreRepeated: true)
    let communityDisposable = MetaDisposable(), forumDisposable = MetaDisposable()
    var onNavigationLoad: (() -> Void)?
__DESTINATION_NAVIGATION__
    let recipientAction = SharePickerAction(), premiumAction = SharePickerAction()
    var pickerClosed = false, success = false
    var deliveryResult: SharePickerResult?
    var analyticsShareJourney: AnalyticsShareJourney?
    var analyticsForwardJourney: AnalyticsForwardPickerJourney?
    var recipientActivation: AnalyticsForwardPickerJourney.Spec.Activation?
    func bindPremiumCallback() {
        let selectInteraction = selectInteractions
__PREMIUM_BINDING__
__RECIPIENT_BINDING__
    }
    func bindActivationCallbacks() {
        let selectInteraction = selectInteractions
__SEND_BINDINGS__
    }
    var resultCompletion: ((SharePickerResult) -> Void)?
    let selectInteractions = SelectPeerInteraction(), genericView = PickerView()
    func popForum(peerId: PeerId, animated: Bool) { UI.popped.append(peerId) }
    func invalidate(_ value: PickerSelection, _ oldValue: PickerSelection) {
__INVALIDATION__
    }
__ACTIVATION_METHODS__
__KEY_BINDINGS__
    func showSuccess() { UI.successes += 1 }
__INVOKE__
__RECIPIENT_METHODS__
__PICKER_CLOSE__
    let share: ShareObject
    let completion: ((Bool) -> Void)?
    let presentation: TelegramPresentationTheme?
    let emoji: ViewController
    let contextChatInteraction: ChatInteraction
    let inputContextHelper: InputContextHelper
__MODAL_INIT__
    deinit { analyticsSearchDisposable.dispose() }
}
final class ShareUIHooks {
    static let shared = ShareUIHooks()
    func makeChatController(_ context: any AccountContextProtocol, _ location: ChatLocation, _ initialAction: ChatInitialAction) -> ChatInterfaceController { UI.onConstruct?(); UI.fullChats += 1; return ChatController(context, location) }
    func makeChatAdditionController(_ context: any AccountContextProtocol, _ location: ChatLocation, _ initialAction: ChatInitialAction) -> ChatInterfaceController { UI.onConstruct?(); UI.additionalChats += 1; return ChatController(context, location) }
    func makeEmojies(_ context: any AccountContextProtocol, _ presentation: TelegramPresentationTheme?) -> ViewController { UI.onEmoji?(); return ViewController() }
}
struct ChatUIHooks {
    static var shared = installedHooks()
__HOOK__
}
func installedHooks() -> ChatUIHooks {
    var hooks = ChatUIHooks(makeForwardMessagesShareModal: { _, _, _ in XCTFail("legacy fallback"); return ModalViewController() })
__INSTALL__
    return hooks
}
enum UI {
    static var onSendSetup: (() -> Void)?, onConstruct: (() -> Void)?, onUpdate: (() -> Void)?, onSuccess: (() -> Void)?, onForum: (() -> Void)?, onEmoji: (() -> Void)?
    static var onAlert: (() -> Void)?, onPremiumText: (() -> Void)?
    static var closed = 0, alerts = 0, premiumOpened = 0
    static var toggled: [PeerId] = [], popped: [PeerId] = [], premiumTextCallbacks: [(String) -> Void] = []
    static var onConfirmation: (() -> Void)?, onPurchase: (() -> Void)?
    static var confirmations: [((Int) -> Void, () -> Void, () -> Void)] = []
    static var confirmationTexts: [String] = [], blockers: [String] = []
    static var failedTargets: [Int64] = [], purchaseAmounts: [Int64?] = []
    static var purchaseOrigin: AnalyticsContext?
    static var alertClosures: [() -> Void] = []
    static var premiumOrigin: AnalyticsContext?
    static var onPush: ((ViewController) -> Void)?
    static var targets: [PeerId] = [], forwarded: [[MessageId]] = [], delayed: [() -> Void] = []
    static var comments = 0, successes = 0, fullChats = 0, additionalChats = 0
    static var forumContext: AnalyticsContext?, inputOrigin: AnalyticsContext?
    static var forumResult: Signal<Bool, NoError> = .single(true)
    static var targetResults: [PeerId: Signal<[MessageId?], NoError>] = [:], targetComments: [PeerId: Signal<[MessageId?], NoError>] = [:]
    static var enqueued: [(PeerId, [EnqueueMessage])] = []
    static var enqueueResults: [Signal<[MessageId?], NoError>] = []
    static var onInlineBuild: (() -> Void)?, onShow: (() -> Void)?, onProgress: (() -> Void)?
    static var inlineBuilds: [InlineBuildArguments] = [], inlineFailures = Set<PeerId>()
    static var presented: [ModalViewController] = []
    static var forwardPickerResults: [(entry: String?, steps: [String], result: String?, outcome: String, retryCount: String?, lastBlocker: String?, searchUsed: Bool?, activation: String?)] = []
    static var quickForwardStarts = 0
    static var quickForwardResults: [(entry: String?, steps: [String], result: String?, outcome: String)] = []
    static var shareJourneyStarts = 0
    static var galleryScreenContexts: [AnalyticsContext?] = []
    static var onGalleryChildren: (() -> Void)?
    static var cancellableProgress = false
    static var cancelProgress: [() -> Void] = []
    static var ownContactResults: [(steps: [String], result: String?, outcome: String)] = []
    static var ownContacts: [(String, String, String, PeerId)] = []
    static var sentMessages: [(PeerId, EnqueueMessage)] = []
    static var shareJourneyResults: [(entry: String?, steps: [String], result: String?, outcome: String, retryCount: String?, lastBlocker: String?, source: AnalyticsScreen?)] = []
    static var journeyResults: [(steps: [String], result: String?, outcome: String)] = []
    static var commentResult: Signal<[MessageId?], NoError>?
    static var sendResult: Signal<[MessageId?], NoError> = .complete()
    static func reset() {
        forwardPickerResults = []; quickForwardStarts = 0; quickForwardResults = []; viewer = nil; AppMenu.menu = nil; galleryScreenContexts = []; shareJourneyStarts = 0; onGalleryChildren = nil; cancellableProgress = false; cancelProgress = []; ownContactResults = []; ownContacts = []; sentMessages = []; onInlineBuild = nil; onShow = nil; onProgress = nil; journeyResults = []; shareJourneyResults = []; inlineBuilds = []; inlineFailures = []; presented = []
        ChatUIHooks.shared = installedHooks(); BrowserHooks.shared = installedPreparedHooks(); ChatHistoryUIHooks.shared = installedHistoryHooks()
        enqueued = []; enqueueResults = []
        targetResults = [:]; targetComments = [:]
        onConfirmation = nil; onPurchase = nil; confirmations = []; confirmationTexts = []; blockers = []; failedTargets = []; purchaseAmounts = []; purchaseOrigin = nil
        alertClosures = []; onAlert = nil; onPremiumText = nil; closed = 0; alerts = 0; premiumOpened = 0; toggled = []; popped = []; premiumTextCallbacks = []; premiumOrigin = nil
        onSendSetup = nil; onConstruct = nil; onUpdate = nil; onSuccess = nil; onForum = nil; onEmoji = nil; onPush = nil
        targets = []; forwarded = []; delayed = []; comments = 0; successes = 0; fullChats = 0; additionalChats = 0
        forumContext = nil; inputOrigin = nil; forumResult = .single(true); sendResult = .complete(); commentResult = nil
    }
}
final class ForwardObjectTests: XCTestCase {
    var account: AccountContext!
    let sourceId = MessageId(peerId: 2, id: 1)
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); UI.reset(); account = AccountContext()
        hub.policy.setOwner(account.account); hub.policy.isEnabled = true
        account.account.postbox.value.messages[sourceId] = Message(id: sourceId)
        for id: PeerId in [1, 2, 3, -1] { account.account.postbox.value.peers[id] = Peer(id) }
    }
    override func tearDown() { account = nil; UI.reset(); Analytics.shared = Analytics() }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: account.account, privacy: privacy) }
    func object(_ context: AnalyticsContext? = nil) -> ForwardMessagesObject { ForwardMessagesObject(account, messages: [Message(id: sourceId)], analyticsContext: context ?? origin()) }
    func assertPrivate() { XCTAssertTrue(hub.policy.hasExclusions) }
    func testInstalledBridgeBindsObjectModalEmojiAndInputBeforeConstruction() {
        UI.onEmoji = { self.assertPrivate() }
        let modal = installedHooks().makeForwardMessagesShareModalObserved(account, [Message(id: sourceId)], { _, _ in .single([Message(id: self.sourceId)]) }, analyticsContext: origin(.excluded)) as! ShareModalController
        XCTAssertTrue((modal.share as! ForwardMessagesObject).forwardingAnalyticsContext.isExcluded)
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true); XCTAssertTrue(modal.emoji.analyticsContext?.isExcluded == true)
        XCTAssertTrue(UI.inputOrigin?.isExcluded == true)
    }
    func testLegacyForwardObjectAndModalRemainUnresolved() {
        let object = ForwardMessagesObject(account, messages: [Message(id: sourceId)])
        UI.onEmoji = { self.assertPrivate() }
        let modal = ShareModalController(object)
        XCTAssertTrue(object.forwardingAnalyticsContext.isExcluded); XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
    }
    func testOrdinaryGrantReachesReusedChatBeforeDraftUpdate() {
        let source = origin(), controller = ChatController(account, .peer(3))
        account.bindings.navigation.controllers = [controller]
        UI.onUpdate = { XCTAssertTrue(controller.analyticsContext?.scope === source.scope) }
        let disposable = object(source).perform(to: [3], threadId: nil).start()
        XCTAssertEqual(controller.chatInteraction.state.interface.ids, [sourceId])
        XCTAssertTrue(UI.targets.isEmpty); disposable.dispose()
    }
    func testSecretOriginPersistsIntoNewChatReadinessAfterOperationOwnerRelease() {
        UI.onConstruct = { self.assertPrivate() }
        UI.onPush = { XCTAssertTrue($0.analyticsContext?.isExcluded == true); self.assertPrivate() }
        var value: ForwardMessagesObject? = object(origin(.excluded))
        var completed = false
        let disposable = value!.perform(to: [3], threadId: nil).start(completed: { completed = true; self.assertPrivate() })
        value = nil
        XCTAssertEqual(UI.additionalChats, 1); XCTAssertFalse(completed)
        account.bindings.navigation.controller?.ready.set(true)
        XCTAssertTrue(completed); disposable.dispose()
    }
    func testExistingTargetElsewhereUsesFullChatFactoryWithOrigin() {
        let source = origin()
        account.bindings.navigation.controllers = [ChatController(account, .peer(3)), ChatController(account, .peer(2))]
        let disposable = object(source).perform(to: [3], threadId: nil).start()
        XCTAssertEqual(UI.fullChats, 1); XCTAssertTrue(account.bindings.navigation.controller?.analyticsContext?.scope === source.scope)
        account.bindings.navigation.controller?.ready.set(true); disposable.dispose()
    }
    func testLateAlbumSourceTightensOrdinaryDestinationAndMetadataIsOneShot() {
        var subscriber: Subscriber<[Message], NoError>?
        let value = ForwardMessagesObject(account, messages: [Message(id: sourceId)], getMessages: { _, _ in Signal { subscriber = $0; return EmptyDisposable } }, analyticsContext: origin())
        let disposable = value.perform(to: [3], threadId: nil).start()
        let secret = Message(id: MessageId(peerId: -1, id: 9))
        subscriber?.putNext([secret]); subscriber?.putNext([Message(id: sourceId)]); subscriber = nil
        XCTAssertEqual(UI.additionalChats, 1); XCTAssertTrue(account.bindings.navigation.controller?.analyticsContext?.isExcluded == true)
        account.bindings.navigation.controller?.ready.set(true); disposable.dispose()
    }
    func testTopicNavigationReceivesOriginalPrivateContext() {
        UI.onForum = { self.assertPrivate() }
        let disposable = object(origin(.excluded)).perform(to: [3], threadId: 8).start()
        XCTAssertTrue(UI.forumContext?.isExcluded == true); XCTAssertEqual(UI.additionalChats, 0); disposable.dispose()
    }
    func testSavedMessagesOwnedRequestsCancelBeforeOuterCompletion() {
        var subscribers: [Subscriber<[MessageId?], NoError>] = [], disposed = 0
        UI.onSendSetup = { self.assertPrivate() }; UI.onSuccess = { self.assertPrivate() }
        UI.sendResult = Signal { subscriber in
            subscribers.append(subscriber); self.assertPrivate()
            return ActionDisposable { disposed += 1; self.assertPrivate() }
        }
        var value: ForwardMessagesObject? = object(origin(.excluded)), completed = false
        let disposable = value!.perform(to: [1], threadId: nil, comment: ChatTextInputState(inputText: "synthetic")).start(completed: { completed = true })
        value = nil; disposable.dispose()
        XCTAssertFalse(completed); XCTAssertEqual(UI.comments, 1); XCTAssertEqual(UI.targets, [1])
        XCTAssertTrue(UI.delayed.isEmpty)
        subscribers.forEach { $0.putNext([self.sourceId]); $0.putCompletion() }
        let delayed = UI.delayed; UI.delayed = []; delayed.forEach { $0() }
        XCTAssertEqual(UI.successes, 0)
        subscribers.forEach { $0.putCompletion() }; subscribers = []
        XCTAssertEqual(disposed, 2)
    }
    func testMixedSecretDestinationExcludesWholeMultiTargetTask() {
        UI.onSendSetup = { self.assertPrivate() }
        account.account.postbox.onSetup = { self.assertPrivate() }
        let disposable = object().perform(to: [3, -1], threadId: nil).start()
        XCTAssertEqual(Set(UI.targets), Set([3, -1])); disposable.dispose()
    }
    func testRevokedContextCannotRefreshBeforeDeferredPeerLookup() {
        let value = object(origin())
        account.account.postbox.delayed = true
        let disposable = value.perform(to: [3], threadId: nil).start()
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        UI.onConstruct = { self.assertPrivate() }
        account.account.postbox.flush()
        XCTAssertNil(account.bindings.navigation.controller?.analyticsContext?.scope)
        account.bindings.navigation.controller?.ready.set(true); disposable.dispose()
    }
    func testForeignContextAndSecretInitialMessageAreExcluded() {
        let foreign = hub.captureContext(owner: NSObject(), privacy: .ordinary)
        let a = object(foreign)
        let b = ForwardMessagesObject(account, messages: [Message(id: MessageId(peerId: -1, id: 4))], analyticsContext: origin())
        XCTAssertNil(a.forwardingAnalyticsContext.scope); XCTAssertTrue(b.forwardingAnalyticsContext.isExcluded)
    }
    func testPublicPollRestrictionDoesNotEnqueueOrNavigate() {
        account.account.postbox.value.peers[3]?.isChannel = true
        account.account.postbox.value.messages[sourceId] = Message(id: sourceId, isPublicPoll: true)
        var error: String?
        let disposable = object().perform(to: [3], threadId: nil).start(error: { error = $0 })
        XCTAssertEqual(error, "poll"); XCTAssertTrue(UI.targets.isEmpty); XCTAssertEqual(UI.additionalChats, 0); disposable.dispose()
    }
}

extension ForwardObjectTests {
    func testOrdinaryInstalledBridgeRetainsGrantThroughAllConstructorBindings() {
        let source = origin()
        UI.onEmoji = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        let modal = installedHooks().makeForwardMessagesShareModalObserved(account, [Message(id: sourceId)], { _, _ in .single([Message(id: self.sourceId)]) }, analyticsContext: source) as! ShareModalController
        XCTAssertTrue((modal.share as! ForwardMessagesObject).forwardingAnalyticsContext.scope === source.scope)
        XCTAssertTrue(modal.analyticsContext?.scope === source.scope)
        XCTAssertTrue(modal.emoji.analyticsContext?.scope === source.scope); XCTAssertTrue(UI.inputOrigin?.scope === source.scope)
    }
    func testReusedPrivateChatCannotBeRelaxedByOrdinaryForwardOrigin() {
        let controller = ChatController(account, .peer(3))
        let source = origin(); controller.inheritAnalyticsContext(origin(.excluded))
        account.bindings.navigation.controllers = [controller]
        let disposable = object(source).perform(to: [3], threadId: nil).start()
        XCTAssertTrue(controller.analyticsContext?.isExcluded == true)
        XCTAssertEqual(controller.chatInteraction.state.interface.ids, [sourceId]); disposable.dispose()
    }
    func testDisposingMetadataPreventsLateNavigationAndSending() {
        account.account.postbox.delayed = true
        var disposed = 0
        account.account.postbox.onDispose = { disposed += 1; self.assertPrivate() }
        let disposable = object(origin(.excluded)).perform(to: [3], threadId: nil).start()
        disposable.dispose(); account.account.postbox.flush()
        XCTAssertGreaterThan(disposed, 0); XCTAssertEqual(UI.additionalChats, 0); XCTAssertTrue(UI.targets.isEmpty)
    }
    func testSavedMessagesDelayedFeedbackAndDisposalUseRevokedOriginalGrant() {
        var subscriber: Subscriber<[MessageId?], NoError>?
        UI.sendResult = Signal { subscriber = $0; return ActionDisposable { self.assertPrivate() } }
        let disposable = object().perform(to: [1], threadId: nil).start()
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        UI.onSuccess = { self.assertPrivate() }
        subscriber?.putNext([sourceId])
        let delayed = UI.delayed; UI.delayed = []; delayed.forEach { $0() }
        subscriber?.putCompletion(); subscriber = nil; disposable.dispose()
        XCTAssertEqual(UI.successes, 1)
    }
}


extension ForwardObjectTests {
    func testSavedMessagesWaitsForCommentAndForwardAcceptanceOnce() {
        var comment: Subscriber<[MessageId?], NoError>?, forward: Subscriber<[MessageId?], NoError>?
        UI.commentResult = Signal { comment = $0; return EmptyDisposable }
        UI.sendResult = Signal { forward = $0; return EmptyDisposable }
        let disposable = object().perform(to: [1], threadId: nil, comment: ChatTextInputState(inputText: "synthetic")).start()
        XCTAssertTrue(UI.delayed.isEmpty)
        forward?.putNext([sourceId]); forward?.putNext([sourceId])
        XCTAssertTrue(UI.delayed.isEmpty)
        comment?.putNext([sourceId]); comment?.putNext([sourceId])
        XCTAssertEqual(UI.delayed.count, 1)
        let delayed = UI.delayed; UI.delayed = []; delayed.forEach { $0() }
        XCTAssertEqual(UI.successes, 1)
        comment = nil; forward = nil; disposable.dispose()
    }
    func testSavedMessagesWithoutCommentNeedsOneCompleteForwardResult() {
        UI.sendResult = .single([sourceId])
        let disposable = object().perform(to: [1], threadId: nil).start()
        XCTAssertEqual(UI.comments, 0); XCTAssertEqual(UI.delayed.count, 1)
        let delayed = UI.delayed; UI.delayed = []; delayed.forEach { $0() }
        XCTAssertEqual(UI.successes, 1); disposable.dispose()
    }
    func testSavedMessagesRejectsPartialMissingAndOversizedResults() {
        for result: [MessageId?] in [[], [nil], [sourceId, nil], [sourceId, sourceId]] {
            for invalidComment in [false, true] {
                UI.reset()
                UI.commentResult = .single(invalidComment ? result : [sourceId])
                UI.sendResult = .single(invalidComment ? [sourceId] : result)
                let disposable = object().perform(to: [1], threadId: nil, comment: ChatTextInputState(inputText: "synthetic")).start()
                XCTAssertTrue(UI.delayed.isEmpty); XCTAssertEqual(UI.successes, 0)
                disposable.dispose()
            }
        }
    }
    func testSavedMessagesEmptyCompletionNeverInventsSuccess() {
        for emptyComment in [false, true] {
            UI.reset()
            UI.commentResult = emptyComment ? .complete() : .single([sourceId])
            UI.sendResult = emptyComment ? .single([sourceId]) : .complete()
            let disposable = object().perform(to: [1], threadId: nil, comment: ChatTextInputState(inputText: "synthetic")).start()
            XCTAssertEqual(UI.comments, 1); XCTAssertEqual(UI.targets, [1])
            XCTAssertTrue(UI.delayed.isEmpty); XCTAssertEqual(UI.successes, 0); disposable.dispose()
        }
    }
    func testEmptySourceLookupCannotSendCommentOrPrepareDraft() {
        account.account.postbox.value.messages = [:]
        for target: PeerId in [1, 3] {
            let disposable = object().perform(to: [target], threadId: nil, comment: ChatTextInputState(inputText: "synthetic")).start()
            XCTAssertTrue(UI.targets.isEmpty); XCTAssertEqual(UI.comments, 0); XCTAssertEqual(UI.additionalChats, 0)
            XCTAssertTrue(UI.delayed.isEmpty); disposable.dispose()
        }
    }
    func testSavedMessagesAlbumNeedsEveryForwardedItem() {
        let second = MessageId(peerId: 2, id: 2)
        for complete in [false, true] {
            UI.reset()
            UI.sendResult = .single(complete ? [sourceId, second] : [sourceId, nil])
            let value = ForwardMessagesObject(account, messages: [Message(id: sourceId)], album: true, getMessages: { _, _ in .single([Message(id: self.sourceId), Message(id: second)]) }, analyticsContext: origin())
            let disposable = value.perform(to: [1], threadId: nil).start()
            XCTAssertEqual(UI.forwarded, [[sourceId, second]])
            XCTAssertEqual(UI.delayed.count, complete ? 1 : 0); disposable.dispose()
        }
    }
}


extension ForwardObjectTests {
    func testExplicitOrdinaryModalContextCannotRelaxPrivateForwardSource() {
        let source = origin(), value = object(origin(.excluded))
        UI.onEmoji = { self.assertPrivate() }
        let modal = ShareModalController(value, analyticsContext: source)
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
        XCTAssertTrue(modal.emoji.analyticsContext?.isExcluded == true)
        XCTAssertTrue(UI.inputOrigin?.isExcluded == true)
    }
    func testExplicitFreshModalContextCannotReplaceRevokedForwardGrant() {
        let value = object()
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        let fresh = origin()
        XCTAssertNotNil(fresh.scope)
        UI.onEmoji = { self.assertPrivate() }
        let modal = ShareModalController(value, analyticsContext: fresh)
        XCTAssertNil(modal.analyticsContext?.scope); XCTAssertNil(modal.emoji.analyticsContext?.scope)
        XCTAssertNil(UI.inputOrigin?.scope)
    }
    func testExplicitPrivateModalContextStillTightensOrdinaryForwardSource() {
        let value = object(), excluded = origin(.excluded)
        UI.onEmoji = { self.assertPrivate() }
        let modal = ShareModalController(value, analyticsContext: excluded)
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
        XCTAssertTrue(modal.emoji.analyticsContext?.isExcluded == true)
    }
}

final class PendingShareObject: ShareObject {
    var requests = 0, disposed = 0
    var recipients: [[PeerId]] = [], comments: [String?] = [], paid: [[PeerId: StarsAmount]] = []
    override var messagesCount: Int { 2 }
    var result: Signal<Never, String> = .never()
    var setup: (() -> Void)?
    override var multipleSelection: Bool { false }
    override func perform(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars: [PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        requests += 1; recipients.append(peerIds); comments.append(comment?.inputText); paid.append(sendPaidMessageStars); setup?(); return result
    }
}

extension ForwardObjectTests {
    func testRecipientDuplicateActivationCoalescesAndCompletionClosesOnce() {
        let share = PendingShareObject(account)
        var subscriber: Subscriber<Never, String>?, completions: [Bool] = []
        share.result = Signal { subscriber = $0; return EmptyDisposable }
        let modal = ShareModalController(share, completion: { completions.append($0) }, analyticsContext: origin())
        modal.selectRecipient(3, threadId: nil); modal.selectRecipient(3, threadId: nil)
        XCTAssertEqual(share.requests, 1); XCTAssertEqual(UI.closed, 0)
        subscriber?.putCompletion(); subscriber?.putCompletion(); modal.close()
        XCTAssertEqual(UI.closed, 1); XCTAssertEqual(completions, [true]); subscriber = nil
    }
    func testRecipientErrorAllowsRetryWithoutOldCompletionClosingPicker() {
        let share = PendingShareObject(account)
        var subscribers: [Subscriber<Never, String>] = []
        share.result = Signal { subscribers.append($0); return EmptyDisposable }
        let modal = ShareModalController(share, analyticsContext: origin(.excluded))
        UI.onAlert = { self.assertPrivate() }
        modal.selectRecipient(3, threadId: nil); subscribers[0].putError("synthetic")
        XCTAssertEqual(UI.alerts, 1); XCTAssertEqual(UI.closed, 0)
        modal.selectRecipient(3, threadId: nil); subscribers[0].putCompletion()
        XCTAssertEqual(share.requests, 2); XCTAssertEqual(UI.closed, 0)
        subscribers[1].putCompletion(); XCTAssertEqual(UI.closed, 1); subscribers = []
    }
    func testRecipientCloseCancelsAndSuppressesLateUIAndNewActions() {
        let share = PendingShareObject(account)
        var subscriber: Subscriber<Never, String>?, disposed = 0
        share.setup = { self.assertPrivate() }
        share.result = Signal { subscriber = $0; self.assertPrivate(); return ActionDisposable { disposed += 1; self.assertPrivate() } }
        let modal = ShareModalController(share, analyticsContext: origin(.excluded))
        modal.selectRecipient(3, threadId: nil); modal.close()
        subscriber?.putError("late"); modal.selectRecipient(3, threadId: nil); modal.showPremiumRequired(3)
        XCTAssertEqual(disposed, 1); XCTAssertEqual(share.requests, 1); XCTAssertEqual(UI.alerts, 0)
        XCTAssertEqual(UI.closed, 1); XCTAssertTrue(UI.premiumTextCallbacks.isEmpty); subscriber = nil
    }
    func testRecipientSelectionAndCommentChangesInvalidatePendingAttempt() {
        for commentChanged in [false, true] {
            UI.reset()
            let share = PendingShareObject(account)
            var subscriber: Subscriber<Never, String>?, disposed = 0
            share.result = Signal { subscriber = $0; return ActionDisposable { disposed += 1 } }
            let modal = ShareModalController(share, analyticsContext: origin())
            modal.selectRecipient(3, threadId: nil)
            let old = PickerSelection()
            modal.invalidate(old, old); XCTAssertEqual(disposed, 0)
            var updated = old
            if commentChanged { updated.comment = "changed" } else { updated.selected = [3] }
            modal.invalidate(updated, old); subscriber?.putCompletion()
            XCTAssertEqual(disposed, 1); XCTAssertEqual(UI.closed, 0)
            modal.selectRecipient(3, threadId: nil); XCTAssertEqual(share.requests, 2)
            modal.close(); subscriber = nil
        }
    }
    func testRecipientOwnerReleaseDisposesPendingWork() {
        let share = PendingShareObject(account)
        var subscriber: Subscriber<Never, String>?, disposed = 0
        share.result = Signal { subscriber = $0; return ActionDisposable { disposed += 1; self.assertPrivate() } }
        var modal: ShareModalController? = ShareModalController(share, analyticsContext: origin(.excluded))
        weak var weakModal = modal
        modal?.selectRecipient(3, threadId: nil); modal = nil
        XCTAssertNil(weakModal); XCTAssertEqual(disposed, 1)
        subscriber?.putError("late"); XCTAssertEqual(UI.alerts, 0); subscriber = nil
    }
    func testRecipientSetupClosureCannotSubscribeAfterReentrantClose() {
        let share = PendingShareObject(account)
        let modal = ShareModalController(share, analyticsContext: origin())
        share.setup = { [weak modal] in modal?.close() }
        var subscribed = false
        share.result = Signal { _ in subscribed = true; return EmptyDisposable }
        modal.selectRecipient(3, threadId: nil)
        XCTAssertFalse(subscribed); XCTAssertEqual(UI.closed, 1)
    }
    func testTopicSelectionWritesThreadOnlyAfterCurrentLookup() {
        let share = ShareObject(account)
        let modal = ShareModalController(share, analyticsContext: origin(.excluded))
        account.account.postbox.delayed = true
        modal.selectRecipient(3, threadId: 7); modal.selectRecipient(3, threadId: 7)
        XCTAssertNil(share.threadIds[3]); XCTAssertTrue(UI.toggled.isEmpty)
        account.account.postbox.flush()
        XCTAssertEqual(share.threadIds[3], 7); XCTAssertEqual(UI.toggled, [3]); XCTAssertEqual(UI.popped, [3]); modal.close()
    }
    func testTopicSelectionCloseCannotMutateThreadOrSelectionLater() {
        let share = ShareObject(account)
        let modal = ShareModalController(share, analyticsContext: origin())
        account.account.postbox.delayed = true
        modal.selectRecipient(3, threadId: 7); modal.close(); account.account.postbox.flush()
        XCTAssertNil(share.threadIds[3]); XCTAssertTrue(UI.toggled.isEmpty); XCTAssertTrue(UI.popped.isEmpty)
    }
    func testPremiumLookupCoalescesAndCloseSuppressesOverlay() {
        let modal = ShareModalController(ShareObject(account), analyticsContext: origin(.excluded))
        account.account.postbox.delayed = true
        var setups = 0
        account.account.postbox.onSetup = { setups += 1; self.assertPrivate() }
        modal.showPremiumRequired(3); modal.showPremiumRequired(3)
        XCTAssertEqual(setups, 1); modal.close(); account.account.postbox.flush()
        XCTAssertTrue(UI.premiumTextCallbacks.isEmpty)
    }
    func testPremiumOverlayRetainsPrivateOriginAfterPickerRelease() {
        var modal: ShareModalController? = ShareModalController(ShareObject(account), analyticsContext: origin(.excluded))
        UI.onPremiumText = { self.assertPrivate() }
        modal?.showPremiumRequired(3); modal = nil
        XCTAssertEqual(UI.premiumTextCallbacks.count, 1); self.assertPrivate()
        UI.premiumTextCallbacks[0]("")
        XCTAssertEqual(UI.premiumOpened, 0)
        UI.premiumTextCallbacks = []; XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPremiumCallbackUsesOriginalGrantAndOpensOnlyOnce() {
        let source = origin()
        let modal = ShareModalController(ShareObject(account), analyticsContext: source)
        modal.showPremiumRequired(3)
        modal.analyticsContext = origin(.excluded)
        UI.premiumTextCallbacks[0](""); UI.premiumTextCallbacks[0]("")
        XCTAssertEqual(UI.premiumOpened, 1); XCTAssertTrue(UI.premiumOrigin?.scope === source.scope)
        modal.close(); UI.premiumTextCallbacks = []
    }
    func testActionReentrantCompletionDoesNotConsumeNewAttempt() {
        let action = SharePickerAction(), context = origin()
        var requests = 0, values = 0
        let pending: () -> Signal<Int, NoError> = { requests += 1; return .never() }
        action.start(context: context, request: { Signal<Int, NoError>.single(1) }, next: { _ in
            values += 1
            action.start(context: context, request: pending, next: { _ in XCTFail() }, error: { _ in }, completed: { XCTFail() })
        }, error: { _ in }, completed: { XCTFail() })
        action.start(context: context, request: pending, next: { _ in XCTFail() }, error: { _ in }, completed: { XCTFail() })
        XCTAssertEqual(values, 1); XCTAssertEqual(requests, 1); action.close()
    }
    func testActionEmptyCompletionReleasesAdmissionWhenAnalyticsDisabled() {
        let action = SharePickerAction(), context = origin()
        hub.policy.isEnabled = false
        var completed = 0
        for _ in 0..<2 {
            action.start(context: context, request: { Signal<Int, NoError>.complete() }, next: { _ in XCTFail() }, error: { _ in }, completed: { completed += 1; self.assertPrivate() })
        }
        XCTAssertEqual(completed, 2); action.close()
    }
}


extension ForwardObjectTests {
    func testRecipientErrorOverlayRetainsPrivateLifetimeAfterPickerRelease() {
        let share = PendingShareObject(account)
        share.result = .fail("synthetic")
        var modal: ShareModalController? = ShareModalController(share, analyticsContext: origin(.excluded))
        modal?.selectRecipient(3, threadId: nil); modal = nil
        XCTAssertEqual(UI.alerts, 1); self.assertPrivate()
        UI.alertClosures.forEach { $0() }; UI.alertClosures = []
        XCTAssertFalse(hub.policy.hasExclusions)
    }
}


extension ForwardObjectTests {
    func testActionReplacementDisposalCannotConstructWorkAfterClosing() {
        let action = SharePickerAction(), context = origin()
        var subscriber: Subscriber<Int, NoError>?, replacementRequests = 0
        action.start(context: context, request: {
            Signal<Int, NoError> { subscriber = $0; return ActionDisposable { action.close() } }
        }, next: { _ in
            action.start(context: context, request: {
                replacementRequests += 1
                return Signal<Int, NoError>.never()
            }, next: { _ in XCTFail() }, error: { _ in }, completed: { XCTFail() })
        }, error: { _ in }, completed: { XCTFail() })
        subscriber?.putNext(1)
        XCTAssertEqual(replacementRequests, 0); subscriber = nil
    }
}

extension ForwardObjectTests {
    func multiPicker(_ source: AnalyticsContext? = nil, ids: Set<PeerId> = [3], comment: String = "") -> (PendingShareObject, ShareModalController) {
        let share = PendingShareObject(account)
        let modal = ShareModalController(share, analyticsContext: source ?? origin())
        modal.selectInteractions.presentation.selected = ids
        modal.selectInteractions.presentation.peers = Dictionary(uniqueKeysWithValues: ids.map { ($0, account.account.postbox.value.peers[$0]!) })
        modal.contextChatInteraction.state.interface.input.inputText = comment
        return (share, modal)
    }
    func paidPeer(balance: Int64 = 4, slow: Bool = false) {
        let peer = TelegramChannel(3)
        peer.sendPaidMessageStars = StarsAmount(value: 2, nanos: 0)
        peer.info = .group(GroupInfo(flags: slow ? [.slowModeEnabled] : []))
        account.account.postbox.value.peers[3] = peer
        account.starState.state = .single(StarsState(balance: StarsAmount(value: balance, nanos: 0)))
    }
    func drainMain() {
        let drained = expectation(description: "main callbacks")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }
    func testMultiRecipientWaitsForPerformCompletionAndCoalescesActivation() {
        let (share, modal) = multiPicker()
        var subscriber: Subscriber<Never, String>?
        share.result = Signal { subscriber = $0; return EmptyDisposable }
        _ = modal.invoke(); _ = modal.invoke(); drainMain()
        XCTAssertEqual(share.requests, 1); XCTAssertEqual(UI.closed, 0); XCTAssertEqual(UI.successes, 0)
        subscriber?.putCompletion(); drainMain()
        XCTAssertEqual(UI.closed, 1); XCTAssertEqual(UI.successes, 1); subscriber = nil
    }
    func testMultiRecipientCloseCancelsPreflightAndDoesNotSendLater() {
        paidPeer()
        let (share, modal) = multiPicker(origin(.excluded))
        account.account.postbox.delayed = true
        account.account.postbox.onDispose = { self.assertPrivate() }
        _ = modal.invoke(); modal.close(); account.account.postbox.flush(); drainMain()
        XCTAssertEqual(share.requests, 0); XCTAssertTrue(UI.confirmations.isEmpty); XCTAssertEqual(UI.successes, 0)
    }
    func testMultiRecipientRetainsCapturedTargetsAndInputDuringPreflight() {
        let (share, modal) = multiPicker(comment: "captured")
        account.account.postbox.delayed = true
        _ = modal.invoke()
        modal.contextChatInteraction.state.interface.input.inputText = "later"
        modal.selectInteractions.presentation.selected = [2]
        account.account.postbox.flush(); drainMain()
        XCTAssertEqual(share.recipients.map(Set.init), [Set([3])]); XCTAssertEqual(share.comments, ["captured"])
        modal.close()
    }
    func testMultiRecipientEmptyPreflightCompletionAllowsRetryWithoutSending() {
        let (share, modal) = multiPicker()
        account.starState.state = .complete()
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(share.requests, 0); XCTAssertEqual(UI.closed, 0)
        account.starState.state = .single(nil)
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(share.requests, 1); modal.close()
    }
    func testMultiRecipientEntireMixedDestinationAttemptIsPrivate() {
        let (share, modal) = multiPicker(ids: [3, -1])
        account.account.postbox.onSetup = { self.assertPrivate() }
        share.setup = { self.assertPrivate() }
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(share.requests, 1); modal.close()
    }
    func testPaidConfirmationExactBalanceSendsOnceAfterConsent() {
        paidPeer()
        let (share, modal) = multiPicker()
        _ = modal.invoke(); _ = modal.invoke(); drainMain()
        XCTAssertEqual(UI.confirmations.count, 1); XCTAssertEqual(share.requests, 0)
        UI.confirmations[0].0(0); UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(share.requests, 1); XCTAssertEqual(share.paid.first?[3]?.value, 2)
        XCTAssertTrue(UI.purchaseAmounts.isEmpty); XCTAssertEqual(UI.closed, 0); modal.close()
    }
    func testPaidConfirmationCancelReleasesAttemptAndIgnoresLateSuccess() {
        paidPeer()
        let (share, modal) = multiPicker()
        _ = modal.invoke(); drainMain()
        UI.confirmations[0].1(); UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(share.requests, 0); XCTAssertEqual(UI.closed, 0)
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(UI.confirmations.count, 2); modal.close()
    }
    func testPaidConfirmationDismissalAllowsRetryWithoutResult() {
        paidPeer()
        let (share, modal) = multiPicker()
        _ = modal.invoke(); drainMain()
        UI.confirmations[0].2(); drainMain()
        XCTAssertEqual(share.requests, 0)
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(UI.confirmations.count, 2); modal.close()
    }
    func testPaidConfirmationSelectionChangeCannotSendOldTargets() {
        paidPeer()
        let (share, modal) = multiPicker()
        _ = modal.invoke(); drainMain()
        let old = modal.selectInteractions.presentation
        var new = old; new.selected = [2]
        modal.invalidate(new, old)
        UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(share.requests, 0); XCTAssertEqual(UI.closed, 0); modal.close()
    }
    func testPaidConfirmationRetainsPrivateLifetimeAfterPickerRelease() {
        paidPeer()
        let share = PendingShareObject(account)
        var modal: ShareModalController? = ShareModalController(share, analyticsContext: origin(.excluded))
        modal?.selectInteractions.presentation.selected = [3]
        modal?.selectInteractions.presentation.peers = [3: account.account.postbox.value.peers[3]!]
        UI.onConfirmation = { self.assertPrivate() }
        _ = modal?.invoke(); drainMain(); modal = nil
        XCTAssertEqual(UI.confirmations.count, 1); self.assertPrivate()
        UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(share.requests, 0)
        UI.confirmations[0].2(); UI.confirmations = []; drainMain()
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPaidTopUpRetainsOriginalOriginAndDoesNotSendAutomatically() {
        paidPeer(balance: 3)
        let (share, modal) = multiPicker(origin(.excluded))
        UI.onPurchase = { self.assertPrivate() }
        _ = modal.invoke(); drainMain()
        UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(UI.purchaseAmounts, [4]); XCTAssertTrue(UI.purchaseOrigin?.isExcluded == true)
        XCTAssertEqual(share.requests, 0); XCTAssertEqual(UI.closed, 0)
        _ = modal.invoke(); drainMain(); XCTAssertEqual(UI.confirmations.count, 2); modal.close()
    }
    func testSlowModeBlockerPrecedesPaidConfirmation() {
        paidPeer(balance: 100, slow: true)
        let (share, modal) = multiPicker(comment: "captured")
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(share.requests, 0); XCTAssertTrue(UI.confirmations.isEmpty)
        XCTAssertEqual(UI.failedTargets, [3]); XCTAssertEqual(UI.blockers, ["comment"])
        modal.contextChatInteraction.state.interface.input.inputText = ""
        _ = modal.invoke(); drainMain(); XCTAssertEqual(UI.confirmations.count, 1); modal.close()
    }
    func testMultiRecipientPerformErrorKeepsPickerOpenForRetry() {
        let (share, modal) = multiPicker(origin(.excluded))
        share.result = .fail("synthetic")
        UI.onAlert = { self.assertPrivate() }
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(UI.alerts, 1); XCTAssertEqual(UI.closed, 0); XCTAssertEqual(UI.successes, 0)
        share.result = .complete()
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(share.requests, 2); XCTAssertEqual(UI.closed, 1)
    }
}


extension ForwardObjectTests {
    func testPaidTopUpDoesNotReplaceRevokedOriginAfterConfirmation() {
        paidPeer(balance: 3)
        let source = origin()
        let (share, modal) = multiPicker(source)
        _ = modal.invoke(); drainMain()
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        modal.analyticsContext = origin()
        UI.onPurchase = { self.assertPrivate() }
        UI.confirmations[0].0(0); drainMain()
        XCTAssertTrue(UI.purchaseOrigin?.scope === source.scope)
        XCTAssertFalse(hub.policy.accepts(UI.purchaseOrigin?.scope))
        XCTAssertEqual(share.requests, 0); modal.close()
    }
}


extension ForwardObjectTests {
    func messageShare(group: [Message]? = nil) -> ShareMessageObject {
        ShareMessageObject(account, Message(id: sourceId), group ?? [Message(id: sourceId), Message(id: MessageId(peerId: 2, id: 2))])
    }
    func testDeliveryPartClassifiesExactPartialRejectedAndUnknown() {
        let cases: [([MessageId?]?, ShareDeliveryStatus)] = [([sourceId, sourceId], .accepted), ([sourceId, nil], .partial), ([nil, nil], .rejected), (nil, .unknown), ([], .unknown), ([sourceId], .unknown), ([sourceId, sourceId, sourceId], .unknown)]
        for (ids, status) in cases {
            let result = ShareDeliveryPart(expectedCount: 2, result: ids)
            XCTAssertEqual(result.status, status)
            if status == .unknown { XCTAssertNil(result.acceptedCount) }
        }
        XCTAssertEqual(ShareDeliveryPart(expectedCount: 0, result: []).status, .notAttempted)
    }
    func testMessageShareRetainsCommentAndForwardResultsPerTarget() {
        UI.targetComments[2] = .single([sourceId]); UI.targetComments[3] = .single([nil])
        UI.targetResults[2] = .single([sourceId, sourceId]); UI.targetResults[3] = .single([sourceId, nil])
        var results: [ShareRecipientDelivery] = []
        let disposable = messageShare().performWithResults(to: [2, 3], threadId: nil, comment: ChatTextInputState(inputText: "synthetic"), sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { results = $0 })
        XCTAssertEqual(results.map { $0.peerId }, [2, 3]); XCTAssertEqual(results.map { $0.status }, [.accepted, .partial])
        XCTAssertEqual(results.last?.comment?.status, .rejected); XCTAssertEqual(results.last?.content.acceptedCount, 1)
        XCTAssertEqual(UI.comments, 2); disposable.dispose()
    }
    func testMessageShareEmptyCommentResultIsUnknownAndStillForwards() {
        UI.commentResult = .complete(); UI.sendResult = .single([sourceId, sourceId])
        var result: ShareRecipientDelivery?
        let disposable = messageShare().performWithResults(to: [3], threadId: nil, comment: ChatTextInputState(inputText: "synthetic"), sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { result = $0.first })
        XCTAssertEqual(result?.status, .unknown); XCTAssertEqual(result?.comment?.status, .unknown)
        XCTAssertEqual(result?.content.status, .accepted); XCTAssertEqual(UI.targets, [3]); disposable.dispose()
    }
    func testMessageShareUnavailableMetadataProducesUnknownWithoutEnqueue() {
        account.account.postbox.loadedResults[3] = .complete()
        var result: ShareRecipientDelivery?
        let disposable = messageShare().performWithResults(to: [3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { result = $0.first })
        XCTAssertEqual(result?.status, .unknown); XCTAssertTrue(UI.targets.isEmpty); disposable.dispose()
    }
    func testMessageShareEmptyForwardResultDoesNotBecomeAccepted() {
        UI.sendResult = .complete()
        var result: ShareRecipientDelivery?
        let disposable = messageShare().performWithResults(to: [3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { result = $0.first })
        XCTAssertEqual(result?.status, .unknown); disposable.dispose()
    }
    func testMessageShareDuplicateTargetsAndResultsCannotDuplicateForward() {
        var subscriber: Subscriber<[MessageId?], NoError>?, results: [[ShareRecipientDelivery]] = []
        UI.sendResult = Signal { subscriber = $0; return EmptyDisposable }
        let disposable = messageShare().performWithResults(to: [3, 3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { results.append($0) })
        subscriber?.putNext([sourceId, nil]); subscriber?.putNext([sourceId, sourceId])
        XCTAssertEqual(UI.targets, [3]); XCTAssertEqual(results.count, 1); XCTAssertEqual(results.first?.first?.status, .partial)
        subscriber = nil; disposable.dispose()
    }
    func testMessageShareForwardSubscriptionWaitsForCommentResult() {
        var comment: Subscriber<[MessageId?], NoError>?, forwardSubscriptions = 0
        UI.commentResult = Signal { comment = $0; return EmptyDisposable }
        UI.sendResult = Signal { subscriber in forwardSubscriptions += 1; subscriber.putNext([self.sourceId, self.sourceId]); subscriber.putCompletion(); return EmptyDisposable }
        let disposable = messageShare().performWithResults(to: [3], threadId: nil, comment: ChatTextInputState(inputText: "synthetic"), sendPaidMessageStars: [:], analyticsContext: origin()).start()
        XCTAssertEqual(forwardSubscriptions, 0)
        comment?.putNext([sourceId]); comment?.putNext([sourceId]); XCTAssertEqual(forwardSubscriptions, 1)
        comment = nil; disposable.dispose()
    }
    func testMessageSharePermissionSkippedCommentIsNotFullAcceptance() {
        account.account.postbox.value.peers[3]?.canSend = false
        UI.sendResult = .single([sourceId, sourceId])
        var result: ShareRecipientDelivery?
        let disposable = messageShare().performWithResults(to: [3], threadId: nil, comment: ChatTextInputState(inputText: "synthetic"), sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { result = $0.first })
        XCTAssertEqual(result?.status, .partial); XCTAssertEqual(result?.comment?.status, .rejected)
        XCTAssertEqual(UI.comments, 0); disposable.dispose()
    }
    func testMessageShareDisposalDoesNotInventTerminalOutcome() {
        var subscriber: Subscriber<[MessageId?], NoError>?, results = 0, disposed = 0
        UI.sendResult = Signal { subscriber = $0; return ActionDisposable { disposed += 1; self.assertPrivate() } }
        let disposable = messageShare().performWithResults(to: [3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin(.excluded)).start(next: { _ in results += 1 })
        disposable.dispose(); subscriber?.putCompletion(); subscriber = nil
        XCTAssertEqual(disposed, 1); XCTAssertEqual(results, 0)
    }
    func testMessageShareWholeTargetSetAndLegacyOriginRemainPrivate() {
        UI.onSendSetup = { self.assertPrivate() }
        let disposable = messageShare().performWithResults(to: [3, -1], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start()
        XCTAssertEqual(Set(UI.targets), [3, -1]); disposable.dispose()
        let legacy = messageShare().perform(to: [3], threadId: nil).start(); legacy.dispose()
    }
    func testMessageSharePrimarySecretSourceCannotBeHiddenByOrdinaryAlbum() {
        let value = ShareMessageObject(account, Message(id: MessageId(peerId: -1, id: 1)), [Message(id: sourceId)])
        UI.onEmoji = { self.assertPrivate() }
        let modal = ShareModalController(value, analyticsContext: origin())
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
    }
    func testMessageSharePickerIncompleteResultClosesWithoutSuccessOrReplay() {
        UI.sendResult = .single([sourceId, nil])
        var completed: [Bool] = []
        let modal = ShareModalController(messageShare(), completion: { completed.append($0) }, analyticsContext: origin(.excluded))
        modal.selectInteractions.presentation.selected = [3]
        modal.selectInteractions.presentation.peers = [3: account.account.postbox.value.peers[3]!]
        UI.onAlert = { self.assertPrivate() }
        _ = modal.invoke(); drainMain(); _ = modal.invoke(); drainMain()
        XCTAssertEqual(completed, [false]); XCTAssertEqual(UI.closed, 1); XCTAssertEqual(UI.successes, 0)
        XCTAssertEqual(UI.alerts, 1); XCTAssertEqual(UI.targets, [3])
    }
    func testMessageSharePickerFullAcceptanceClosesSuccessfully() {
        UI.sendResult = .single([sourceId, sourceId])
        var completed: [Bool] = []
        let modal = ShareModalController(messageShare(), completion: { completed.append($0) }, analyticsContext: origin())
        modal.selectInteractions.presentation.selected = [3]
        modal.selectInteractions.presentation.peers = [3: account.account.postbox.value.peers[3]!]
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(completed, [true]); XCTAssertEqual(UI.successes, 1); XCTAssertEqual(UI.alerts, 0)
    }
}


extension ForwardObjectTests {
    func testLinkDeliveryMergesCommentAndKeepsSeparateTargetOutcomes() {
        let link = ShareLinkObject(account, link: "synthetic-link")
        UI.enqueueResults = [.single([sourceId]), .single([nil])]
        var results: [ShareRecipientDelivery] = []
        let disposable = link.performWithResults(to: [2, 3, 3], threadId: 9, comment: ChatTextInputState(inputText: "synthetic-comment"), sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { results = $0 })
        XCTAssertEqual(UI.enqueued.map { $0.0 }, [2, 3]); XCTAssertEqual(UI.enqueued.map { $0.1.first?.text }, ["synthetic-link\nsynthetic-comment", "synthetic-link\nsynthetic-comment"])
        XCTAssertEqual(results.map { $0.status }, [.accepted, .rejected]); XCTAssertTrue(results.allSatisfy { $0.comment == nil && $0.content.expectedCount == 1 })
        XCTAssertEqual(link.outgoingMessageCount(comment: ChatTextInputState(inputText: "synthetic")), 1); disposable.dispose()
    }
    func testLinkDeliveryMissingOrMalformedResultStaysUnknown() {
        for result: [MessageId?]? in [nil, [], [sourceId, sourceId]] {
            UI.reset(); UI.enqueueResults = [result.map { .single($0) } ?? .complete()]
            var status: ShareDeliveryStatus?
            let disposable = ShareLinkObject(account, link: "synthetic").performWithResults(to: [3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { status = $0.first?.status })
            XCTAssertEqual(status, .unknown); disposable.dispose()
        }
    }
    func testContactDeliveryWaitsForBothCommentAndContactResults() {
        var subscribers: [Subscriber<[MessageId?], NoError>] = [], results: [ShareRecipientDelivery] = []
        let pending = Signal<[MessageId?], NoError> { subscribers.append($0); return EmptyDisposable }
        UI.enqueueResults = [pending, pending]
        let disposable = ShareContactObject(account, user: Peer(2)).performWithResults(to: [3], threadId: nil, comment: ChatTextInputState(inputText: "synthetic"), sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { results = $0 })
        XCTAssertEqual(subscribers.count, 2); XCTAssertTrue(results.isEmpty)
        subscribers[1].putNext([sourceId]); XCTAssertTrue(results.isEmpty)
        subscribers[0].putNext([nil])
        XCTAssertEqual(results.first?.status, .partial); XCTAssertEqual(results.first?.comment?.status, .rejected); XCTAssertEqual(results.first?.content.status, .accepted)
        subscribers = []; disposable.dispose()
    }
    func testContactDeliveryWithoutCommentHasOneExpectedMessage() {
        UI.enqueueResults = [.single([sourceId])]
        var result: ShareRecipientDelivery?
        let disposable = ShareContactObject(account, user: Peer(2), media: 84).performWithResults(to: [3], threadId: 7, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { result = $0.first })
        XCTAssertEqual(UI.enqueued.count, 1); XCTAssertEqual(UI.enqueued.first?.1.first?.mediaReference?.media, 84)
        XCTAssertEqual(UI.enqueued.first?.1.first?.threadId, 7); XCTAssertEqual(result?.status, .accepted); XCTAssertNil(result?.comment); disposable.dispose()
    }
    func testContactDeliveryAppliesSendOptionsToCommentAndContent() {
        let contact = ShareContactObject(account, user: Peer(2))
        contact.withoutSound = true; contact.scheduleDate = Date(timeIntervalSince1970: 1234); contact.threadIds[3] = 8
        UI.enqueueResults = [.single([sourceId]), .single([sourceId])]
        let disposable = contact.performWithResults(to: [3], threadId: 7, comment: ChatTextInputState(inputText: "synthetic"), sendPaidMessageStars: [3: StarsAmount(value: 2, nanos: 0)], analyticsContext: origin()).start()
        XCTAssertEqual(UI.enqueued.count, 2)
        for (_, messages) in UI.enqueued {
            XCTAssertEqual(messages.first?.threadId, 8)
            XCTAssertEqual(messages.first?.attributes.compactMap { $0 as? PaidStarsMessageAttribute }.first?.stars.value, 2)
            XCTAssertEqual(messages.first?.attributes.compactMap { $0 as? OutgoingScheduleInfoMessageAttribute }.first?.scheduleTime, 1234)
            XCTAssertTrue(messages.first?.attributes.compactMap { $0 as? NotificationInfoMessageAttribute }.first?.flags.contains(.muted) == true)
        }
        disposable.dispose()
    }
    func testLinkDeliveryUsesPerRecipientTopicAndFrozenAttributes() {
        let link = ShareLinkObject(account, link: "synthetic")
        link.threadIds[2] = 21; link.threadIds[3] = 31; link.withoutSound = true
        let signal = link.performWithResults(to: [2, 3], threadId: 7, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin())
        link.threadIds = [:]; link.withoutSound = false
        let disposable = signal.start()
        XCTAssertEqual(UI.enqueued.map { $0.1.first?.threadId }, [21, 31])
        XCTAssertTrue(UI.enqueued.allSatisfy { $0.1.first?.attributes.contains { $0 is NotificationInfoMessageAttribute } == true }); disposable.dispose()
    }
    func testLinkPaymentConfirmationCountsMergedCommentOnce() {
        paidPeer(balance: 2)
        UI.enqueueResults = [.single([sourceId])]
        let modal = ShareModalController(ShareLinkObject(account, link: "synthetic"), analyticsContext: origin())
        modal.selectInteractions.presentation.selected = [3]; modal.selectInteractions.presentation.peers = [3: account.account.postbox.value.peers[3]!]
        modal.contextChatInteraction.state.interface.input.inputText = "synthetic-comment"
        _ = modal.invoke(); drainMain()
        XCTAssertEqual(UI.confirmationTexts, ["users 1 amount 2 messages 1"])
        UI.confirmations.first?.0(0); drainMain()
        XCTAssertEqual(UI.enqueued.count, 1); XCTAssertEqual(UI.closed, 1); XCTAssertTrue(UI.purchaseAmounts.isEmpty)
    }
    func testContactSourceRestrictionBindsPickerBeforeChildren() {
        UI.onEmoji = { self.assertPrivate() }
        let modal = ShareModalController(ShareContactObject(account, user: Peer(-1)), analyticsContext: origin())
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true); XCTAssertTrue(modal.emoji.analyticsContext?.isExcluded == true)
    }
    func testLinkAndContactWholeDestinationSetsArePrivate() {
        for value: ShareDeliveryProviding in [ShareLinkObject(account, link: "synthetic"), ShareContactObject(account, user: Peer(2))] {
            UI.reset(); UI.onSendSetup = { self.assertPrivate() }
            let disposable = value.performWithResults(to: [3, -1], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start()
            XCTAssertEqual(UI.enqueued.count, 2); disposable.dispose()
        }
    }
    func testContactDisposalCancelsBothPartsWithoutInventingResults() {
        var subscribers: [Subscriber<[MessageId?], NoError>] = [], disposed = 0, results = 0
        let pending = Signal<[MessageId?], NoError> { subscribers.append($0); return ActionDisposable { disposed += 1; self.assertPrivate() } }
        UI.enqueueResults = [pending, pending]
        let disposable = ShareContactObject(account, user: Peer(2)).performWithResults(to: [3], threadId: nil, comment: ChatTextInputState(inputText: "synthetic"), sendPaidMessageStars: [:], analyticsContext: origin(.excluded)).start(next: { _ in results += 1 })
        disposable.dispose(); subscribers.forEach { $0.putCompletion() }; subscribers = []
        XCTAssertEqual(disposed, 2); XCTAssertEqual(results, 0)
    }
    func testLinkAndContactIncompletePickerResultsCannotReportSuccessOrReplay() {
        for share: ShareObject in [ShareLinkObject(account, link: "synthetic"), ShareContactObject(account, user: Peer(2))] {
            UI.reset(); UI.enqueueResults = [.single([nil])]
            var completed: [Bool] = []
            let modal = ShareModalController(share, completion: { completed.append($0) }, analyticsContext: origin())
            modal.selectRecipient(3, threadId: nil); modal.selectRecipient(3, threadId: nil)
            XCTAssertEqual(completed, [false]); XCTAssertEqual(UI.closed, 1); XCTAssertEqual(UI.alerts, 1); XCTAssertEqual(UI.successes, 0); XCTAssertEqual(UI.enqueued.count, 1)
        }
    }
    func testLinkAndContactLegacySignalsWaitForResultAndKeepUnknownOriginPrivate() {
        for share: ShareObject in [ShareLinkObject(account, link: "synthetic"), ShareContactObject(account, user: Peer(2))] {
            UI.reset(); var subscriber: Subscriber<[MessageId?], NoError>?, completed = false
            UI.onSendSetup = { self.assertPrivate() }
            UI.enqueueResults = [Signal { subscriber = $0; self.assertPrivate(); return EmptyDisposable }]
            let disposable = share.perform(to: [3], threadId: nil).start(completed: { completed = true; self.assertPrivate() })
            XCTAssertFalse(completed); subscriber?.putNext([sourceId]); XCTAssertTrue(completed)
            subscriber = nil; disposable.dispose()
        }
    }
    func testLinkAndContactEmptyDestinationStartsNoEnqueue() {
        for value: ShareDeliveryProviding in [ShareLinkObject(account, link: "synthetic"), ShareContactObject(account, user: Peer(2))] {
            var results: [ShareRecipientDelivery]?
            let disposable = value.performWithResults(to: [], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { results = $0 })
            XCTAssertEqual(results, []); XCTAssertTrue(UI.enqueued.isEmpty); disposable.dispose()
        }
    }
}


__PREVIEW_ACTION__
enum WebbotShareMessageStatus: Equatable { case success, failed }
enum PreviewValidation { case none }
final class InputDataController: ViewController {
    var analyticsScreen: AnalyticsScreen?
    var onDeinit: (() -> Void)?
    var validateData: ((Int) -> PreviewValidation)?
    var leftModalHeader: ModalHeaderData?
    let disposable: Disposable
    init(dataSignal: Signal<Int, NoError>, title: String) { disposable = dataSignal.start(); super.init() }
    func returnKeyAction() -> PreviewValidation { validateData?(0) ?? .none }
    deinit { disposable.dispose(); onDeinit?() }
}
struct ModalHeaderData { let image: Int; let handler: () -> Void }
struct ModalInteractions { let acceptTitle: String; let accept: () -> Void; let singleButton: Bool }
final class InputDataModalController: ModalViewController {
    let current: InputDataController
    let closeHandler: (@escaping () -> Void) -> Void
    var closeCount = 0
    init(_ controller: InputDataController, modalInteractions: ModalInteractions?, closeHandler: @escaping (@escaping () -> Void) -> Void) {
        self.current = controller; self.closeHandler = closeHandler; super.init()
    }
    override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        closeHandler { self.closeCount += 1 }
    }
}
func showModal(with controller: ModalViewController, for window: Window) { UI.onShow?(); UI.presented.append(controller) }
__PREPARED_RESULT__
struct BrowserHooks {
    static var shared = BrowserHooks(makeShareChatContextResultModal: { context, prepared, completion in
        ShareModalController(ShareChatContextResult(context, preparedMessage: prepared), completion: completion)
    })
__PREPARED_HOOK__
}
func installedPreparedHooks() -> BrowserHooks {
    var hooks = BrowserHooks(makeShareChatContextResultModal: { _, _, _ in XCTFail("legacy fallback"); return ModalViewController() })
__PREPARED_INSTALL__
    return hooks
}
func preparedPreview(context: any AccountContextProtocol, bot: EnginePeer, preparedMessage: PreparedInlineMessage, window: Window, analyticsContext: AnalyticsContext?, analyticsJourney: AnalyticsPreparedShareJourney? = nil, callback: @escaping (WebbotShareMessageStatus) -> Void) -> InputDataModalController {
__PREVIEW_ORIGIN__
    let signal = Signal<Int, NoError>.single(1)
__PREVIEW_BODY__
}

extension ForwardObjectTests {
    func preparedShare(_ bot: PeerId = 2) -> ShareChatContextResult {
        ShareChatContextResult(account, preparedMessage: PreparedInlineMessage(botId: bot, result: 1))
    }
    func preview(_ privacy: AnalyticsPrivacy = .ordinary, callback: @escaping (WebbotShareMessageStatus) -> Void) -> InputDataModalController {
        preparedPreview(context: account, bot: EnginePeer(id: 2), preparedMessage: PreparedInlineMessage(botId: 2, result: 1), window: account.window, analyticsContext: origin(privacy), callback: callback)
    }
    func testPreparedDeliveryWaitsForAcceptanceAndConsumesOneResult() {
        var subscriber: Subscriber<[MessageId?], NoError>?, results: [[ShareRecipientDelivery]] = []
        UI.enqueueResults = [Signal { subscriber = $0; return EmptyDisposable }]
        let disposable = preparedShare().performWithResults(to: [3, 3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { results.append($0) })
        XCTAssertEqual(UI.inlineBuilds.count, 1); XCTAssertEqual(UI.enqueued.count, 1); XCTAssertTrue(results.isEmpty)
        subscriber?.putNext([sourceId]); subscriber?.putNext([nil]); subscriber?.putCompletion()
        XCTAssertEqual(results.count, 1); XCTAssertEqual(results.first?.first?.status, .accepted)
        subscriber = nil; disposable.dispose()
    }
    func testPreparedFactoryFailureDoesNotEnqueueOrClaimAcceptance() {
        UI.inlineFailures = [3]
        var results: [ShareRecipientDelivery] = []
        let disposable = preparedShare().performWithResults(to: [3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { results = $0 })
        XCTAssertEqual(results.first?.status, .rejected); XCTAssertTrue(UI.enqueued.isEmpty); disposable.dispose()
    }
    func testPreparedMissingMalformedAndRejectedResultsStayDistinct() {
        for (result, expected): ([MessageId?]?, ShareDeliveryStatus) in [(nil, .unknown), ([], .unknown), ([sourceId, sourceId], .unknown), ([nil], .rejected)] {
            UI.reset(); UI.enqueueResults = [result.map { .single($0) } ?? .complete()]
            var status: ShareDeliveryStatus?
            let disposable = preparedShare().performWithResults(to: [3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { status = $0.first?.status })
            XCTAssertEqual(status, expected); disposable.dispose()
        }
    }
    func testPreparedFactoryKeepsSendOptionsAndCountsOnlyContent() {
        let share = preparedShare(); share.withoutSound = true; share.scheduleDate = Date(timeIntervalSince1970: 1234); share.threadIds[3] = 8
        UI.enqueueResults = [.single([sourceId])]
        let disposable = share.performWithResults(to: [3], threadId: 7, comment: ChatTextInputState(inputText: "ignored"), sendPaidMessageStars: [3: StarsAmount(value: 2, nanos: 0)], analyticsContext: origin()).start()
        let arguments = UI.inlineBuilds.first
        XCTAssertEqual(arguments?.thread, 8); XCTAssertEqual(arguments?.bot, 2); XCTAssertEqual(arguments?.silent, true); XCTAssertEqual(arguments?.schedule, 1234); XCTAssertEqual(arguments?.stars?.value, 2)
        XCTAssertEqual(arguments?.hideVia, false); XCTAssertEqual(arguments?.postpone, false)
        XCTAssertEqual(share.outgoingMessageCount(comment: ChatTextInputState(inputText: "ignored")), 1); XCTAssertEqual(UI.enqueued.count, 1); disposable.dispose()
    }
    func testPreparedWholeDestinationAndBotRestrictionsPrecedeConstruction() {
        for (bot, targets): (PeerId, [PeerId]) in [(2, [3, -1]), (-1, [3])] {
            UI.reset(); UI.onInlineBuild = { self.assertPrivate() }; UI.onSendSetup = { self.assertPrivate() }
            let disposable = preparedShare(bot).performWithResults(to: targets, threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { _ in self.assertPrivate() })
            XCTAssertEqual(UI.inlineBuilds.count, targets.count); disposable.dispose()
        }
    }
    func testPreparedLegacyOriginAndDisposedResultRemainExcluded() {
        var subscriber: Subscriber<[MessageId?], NoError>?, completions = 0, disposals = 0
        UI.onInlineBuild = { self.assertPrivate() }
        UI.enqueueResults = [Signal { subscriber = $0; self.assertPrivate(); return ActionDisposable { disposals += 1; self.assertPrivate() } }]
        let disposable = preparedShare().perform(to: [3], threadId: nil).start(completed: { completions += 1 })
        XCTAssertEqual(completions, 0); disposable.dispose(); subscriber?.putNext([sourceId]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertEqual(completions, 0); XCTAssertEqual(disposals, 1)
    }
    func testPreparedEmptyDestinationDoesNotConstructMessage() {
        var results: [ShareRecipientDelivery]?
        let disposable = preparedShare().performWithResults(to: [], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start(next: { results = $0 })
        XCTAssertEqual(results, []); XCTAssertTrue(UI.inlineBuilds.isEmpty); disposable.dispose()
    }
    func testPreparedPreviewCoalescesPickerAndWaitsForAcceptance() {
        var statuses: [WebbotShareMessageStatus] = [], subscriber: Subscriber<[MessageId?], NoError>?
        let modal = preview { statuses.append($0) }
        _ = modal.current.returnKeyAction(); _ = modal.current.returnKeyAction()
        XCTAssertEqual(UI.presented.count, 1)
        let picker = UI.presented.first as? ShareModalController
        UI.enqueueResults = [Signal { subscriber = $0; return EmptyDisposable }]
        picker?.selectRecipient(3, threadId: nil)
        XCTAssertTrue(statuses.isEmpty); XCTAssertEqual(modal.closeCount, 0)
        subscriber?.putNext([sourceId]); subscriber?.putNext([sourceId]); subscriber = nil
        XCTAssertEqual(statuses, [.success]); XCTAssertEqual(modal.closeCount, 1)
        _ = modal.current.returnKeyAction(); modal.close()
        XCTAssertEqual(UI.presented.count, 1); XCTAssertEqual(statuses, [.success]); XCTAssertEqual(modal.closeCount, 1)
    }
    func testPreparedPreviewIncompleteDeliveryReportsFailureOnce() {
        var statuses: [WebbotShareMessageStatus] = []
        let modal = preview { statuses.append($0) }
        _ = modal.current.returnKeyAction(); UI.enqueueResults = [.complete()]
        (UI.presented.first as? ShareModalController)?.selectRecipient(3, threadId: nil)
        XCTAssertEqual(statuses, [.failed]); XCTAssertEqual(modal.closeCount, 1); XCTAssertEqual(UI.successes, 0)
    }
    func testPreparedPreviewCloseCancelsPendingChildAndSuppressesLateSuccess() {
        var statuses: [WebbotShareMessageStatus] = [], subscriber: Subscriber<[MessageId?], NoError>?, disposed = 0
        let modal = preview(.excluded) { statuses.append($0); self.assertPrivate() }
        _ = modal.current.returnKeyAction()
        UI.enqueueResults = [Signal { subscriber = $0; return ActionDisposable { disposed += 1; self.assertPrivate() } }]
        (UI.presented.first as? ShareModalController)?.selectRecipient(3, threadId: nil)
        modal.close(); modal.close()
        XCTAssertEqual(disposed, 1); XCTAssertTrue((UI.presented.first as? ShareModalController)?.pickerClosed == true)
        subscriber?.putNext([sourceId]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertEqual(statuses, [.failed]); XCTAssertEqual(disposed, 1); XCTAssertEqual(modal.closeCount, 1); XCTAssertEqual(UI.successes, 0)
    }
    func testPreparedPreviewDeinitClosesOwnedPickerAndReportsOnce() {
        var statuses: [WebbotShareMessageStatus] = []
        var modal: InputDataModalController? = preview(.excluded) { statuses.append($0); self.assertPrivate() }
        _ = modal?.current.returnKeyAction(); weak var controller = modal?.current
        modal = nil
        XCTAssertNil(controller); XCTAssertEqual(statuses, [.failed]); XCTAssertTrue((UI.presented.first as? ShareModalController)?.pickerClosed == true)
        (UI.presented.first as? ShareModalController)?.resultCompletion?(.accepted)
        XCTAssertEqual(statuses, [.failed])
    }
    func testPreparedSynchronousFactoryCompletionCannotPresentStalePicker() {
        BrowserHooks.shared.makeShareChatContextResultModalWithResult = nil
        BrowserHooks.shared.makeShareChatContextResultModalWithContext = { _, _, _, completed in
            completed(true); completed(false); return ModalViewController()
        }
        var statuses: [WebbotShareMessageStatus] = []
        let modal = preview { statuses.append($0) }
        _ = modal.current.returnKeyAction()
        XCTAssertEqual(statuses, [.success]); XCTAssertTrue(UI.presented.isEmpty); XCTAssertEqual(modal.closeCount, 1)
    }
    func testPreparedObservedHookRetainsPrivateCallbackAfterControllerRelease() {
        var callback: ((Bool) -> Void)?, results: [Bool] = []
        BrowserHooks.shared.makeShareChatContextResultModalWithContext = { _, _, context, completed in
            self.assertPrivate(); XCTAssertTrue(context.isExcluded); callback = completed; return ModalViewController()
        }
        var controller: ModalViewController? = BrowserHooks.shared.makeShareChatContextResultModalObserved(account, PreparedInlineMessage(botId: 2, result: 1), analyticsContext: origin(.excluded), completion: { results.append($0); self.assertPrivate() })
        XCTAssertTrue(controller?.analyticsContext?.isExcluded == true); controller = nil
        callback?(true); callback?(false); XCTAssertEqual(results, [true]); callback = nil
    }
    func testPreparedInstalledHookBindsPrivateSourceBeforePickerChildren() {
        UI.onEmoji = { self.assertPrivate() }
        let picker = BrowserHooks.shared.makeShareChatContextResultModalObserved(account, PreparedInlineMessage(botId: -1, result: 1), analyticsContext: origin(), completion: { _ in }) as? ShareModalController
        XCTAssertTrue(picker?.analyticsContext?.isExcluded == true); XCTAssertTrue(picker?.emoji.analyticsContext?.isExcluded == true)
    }
}

extension ForwardObjectTests {
    func testPreparedPreviewWindowLossFinishesWithoutOpeningPicker() {
        var window: Window? = Window(), statuses: [WebbotShareMessageStatus] = []
        let modal = preparedPreview(context: account, bot: EnginePeer(id: 2), preparedMessage: PreparedInlineMessage(botId: 2, result: 1), window: window!, analyticsContext: origin(), callback: { statuses.append($0) })
        window = nil; _ = modal.current.returnKeyAction(); _ = modal.current.returnKeyAction()
        XCTAssertEqual(statuses, [.failed]); XCTAssertTrue(UI.presented.isEmpty); XCTAssertEqual(modal.closeCount, 1)
    }
    func testPreparedPreviewSourceUnknownForeignAndRevokedRemainExcluded() {
        let revoked = origin(); hub.policy.isEnabled = false; hub.policy.isEnabled = true
        let foreign = hub.captureContext(owner: NSObject(), privacy: .ordinary)
        for inherited: AnalyticsContext? in [nil, foreign, revoked] {
            UI.reset(); UI.onEmoji = { self.assertPrivate() }
            let modal = preparedPreview(context: account, bot: EnginePeer(id: 2), preparedMessage: PreparedInlineMessage(botId: 2, result: 1), window: account.window, analyticsContext: inherited, callback: { _ in self.assertPrivate() })
            XCTAssertFalse(hub.policy.accepts(modal.analyticsContext?.scope))
            _ = modal.current.returnKeyAction(); modal.close()
        }
    }
    func testPreparedPreviewOrdinaryGrantReachesPickerWithoutRefresh() {
        let inherited = origin()
        let modal = preparedPreview(context: account, bot: EnginePeer(id: 2), preparedMessage: PreparedInlineMessage(botId: 2, result: 1), window: account.window, analyticsContext: inherited, callback: { _ in })
        _ = modal.current.returnKeyAction()
        let picker = UI.presented.first as? ShareModalController
        XCTAssertFalse(modal.analyticsContext?.isExcluded ?? true); XCTAssertFalse(picker?.analyticsContext?.isExcluded ?? true)
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        UI.onInlineBuild = { self.assertPrivate() }
        UI.enqueueResults = [.single([sourceId])]; picker?.selectRecipient(3, threadId: nil)
        XCTAssertFalse(hub.policy.accepts(modal.analyticsContext?.scope)); XCTAssertFalse(hub.policy.accepts(picker?.analyticsContext?.scope))
    }
}

func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> {
    UI.onProgress?()
    guard UI.cancellableProgress else { return signal }
    return Signal { subscriber in
        let disposable = signal.start(next: { subscriber.putNext($0) }, error: { subscriber.putError($0) }, completed: { subscriber.putCompletion() })
        UI.cancelProgress.append { disposable.dispose() }
        return disposable
    }
}
func WebbotShareMessageModal(context: any AccountContextProtocol, bot: EnginePeer, preparedMessage: PreparedInlineMessage, window: Window, analyticsContext: AnalyticsContext?, analyticsJourney: AnalyticsPreparedShareJourney? = nil, callback: @escaping (WebbotShareMessageStatus) -> Void) -> InputDataModalController {
    preparedPreview(context: context, bot: bot, preparedMessage: preparedMessage, window: window, analyticsContext: analyticsContext, analyticsJourney: analyticsJourney, callback: callback)
}
__PREPARED_PAGE_ACTION__
final class WKWebView {}
final class WKNavigation {}
final class PageActionCancellation { var resets = 0; func reset() { resets += 1 } }
final class PageView { var _holder: PageView { self }; var reloads = 0; func reload() { reloads += 1 } }
final class PreparedPage {
    let context: AccountContext
    var window: Window?
    var lastTouchTimestamp: TimeInterval?
    var bot: Peer? = Peer(2)
    var analyticsContext: AnalyticsContext?
    let preparedShareAction = BrowserPreparedShareAction(), invoiceAction = PageActionCancellation(), locationAction = PageActionCancellation(), emojiPermissionAction = PageActionCancellation(), emojiStatusAction = PageActionCancellation()
    let genericView = PageView()
    var events: [String] = []
    var onEvent: (() -> Void)?
    init(_ context: AccountContext, origin: AnalyticsContext?) { self.context = context; self.window = context.window; self.analyticsContext = origin }
    func sendEvent(name: String, data: String?) { onEvent?(); events.append(name) }
    func updateLocalizationAndTheme(theme: Any) {}
    func receive(_ json: [String: Any]?) {
        guard let window else { return }
__PREPARED_PAGE_INGRESS__
    }
__PREPARED_PAGE_NAVIGATION__
}

extension ForwardObjectTests {
    func preparedPage(_ privacy: AnalyticsPrivacy = .ordinary) -> PreparedPage { PreparedPage(account, origin: origin(privacy)) }
    var preparedValue: PreparedInlineMessage { PreparedInlineMessage(botId: 2, result: 1) }
    func testPreparedPageCoalescesLookupAndWaitsForPickerAcceptance() {
        let page = preparedPage()
        var subscriber: Subscriber<PreparedInlineMessage?, NoError>?
        account.engine.messages.preparedResult = Signal { subscriber = $0; return EmptyDisposable }
        page.receive(["id": "first"]); page.receive(["id": "duplicate"])
        XCTAssertEqual(account.engine.messages.lookups.map { $0.1 }, ["first"]); XCTAssertTrue(UI.presented.isEmpty)
        subscriber?.putNext(preparedValue); subscriber?.putNext(preparedValue); drainMain()
        XCTAssertEqual(UI.presented.count, 1); XCTAssertTrue(page.events.isEmpty)
        let preview = UI.presented.first as? InputDataModalController
        _ = preview?.current.returnKeyAction(); UI.enqueueResults = [.single([sourceId])]
        (UI.presented.last as? ShareModalController)?.selectRecipient(3, threadId: nil)
        XCTAssertEqual(page.events, ["prepared_message_sent"]); XCTAssertEqual(preview?.closeCount, 1)
        subscriber = nil
    }
    func testPreparedPageReloadCancelsLookupBeforeLateResultAndAllowsNewAttempt() {
        let page = preparedPage(.excluded)
        var subscriber: Subscriber<PreparedInlineMessage?, NoError>?, disposed = 0
        account.engine.messages.preparedResult = Signal { subscriber = $0; return ActionDisposable { disposed += 1; self.assertPrivate() } }
        page.receive(["id": "old"]); page.reloadPage()
        XCTAssertEqual(disposed, 1); XCTAssertEqual(page.genericView.reloads, 1); XCTAssertEqual(page.invoiceAction.resets, 1)
        subscriber?.putNext(preparedValue); subscriber?.putCompletion(); drainMain()
        XCTAssertTrue(UI.presented.isEmpty); XCTAssertTrue(page.events.isEmpty)
        account.engine.messages.preparedResult = .single(preparedValue); page.receive(["id": "new"]); drainMain()
        XCTAssertEqual(UI.presented.count, 1); subscriber = nil
    }
    func testPreparedPageNavigationClosesPreviewAndPendingSendWithoutOldEvent() {
        let page = preparedPage(.excluded)
        account.engine.messages.preparedResult = .single(preparedValue)
        page.receive(["id": "old"]); drainMain()
        let preview = UI.presented.first as? InputDataModalController
        _ = preview?.current.returnKeyAction()
        var subscriber: Subscriber<[MessageId?], NoError>?, disposed = 0
        UI.enqueueResults = [Signal { subscriber = $0; return ActionDisposable { disposed += 1; self.assertPrivate() } }]
        let picker = UI.presented.last as? ShareModalController
        picker?.selectRecipient(3, threadId: nil)
        page.webView(WKWebView(), didStartProvisionalNavigation: WKNavigation())
        XCTAssertEqual(preview?.closeCount, 1); XCTAssertEqual(disposed, 1); XCTAssertTrue(picker?.pickerClosed == true)
        subscriber?.putNext([sourceId]); subscriber?.putCompletion(); picker?.resultCompletion?(.accepted); subscriber = nil
        XCTAssertTrue(page.events.isEmpty); XCTAssertEqual(page.invoiceAction.resets, 1)
    }
    func testPreparedPageMissingAndEmptyMetadataReportFailureAndReleaseAttempt() {
        for result: Signal<PreparedInlineMessage?, NoError> in [.single(nil), .complete()] {
            let page = preparedPage(); account.engine.messages.preparedResult = result
            page.receive(["id": "missing"]); drainMain()
            XCTAssertEqual(page.events, ["prepared_message_failed"]); XCTAssertTrue(UI.presented.isEmpty)
            page.receive(["id": "retry"]); drainMain()
            XCTAssertEqual(page.events, ["prepared_message_failed", "prepared_message_failed"])
        }
    }
    func testPreparedPagePreviewCancelReportsOneFailureAndAllowsRetry() {
        let page = preparedPage(); account.engine.messages.preparedResult = .single(preparedValue)
        page.receive(["id": "first"]); drainMain()
        let preview = UI.presented.first as? InputDataModalController
        preview?.close(); preview?.close()
        XCTAssertEqual(page.events, ["prepared_message_failed"])
        page.receive(["id": "second"]); drainMain()
        XCTAssertEqual(UI.presented.count, 2)
    }
    func testPreparedPageWindowLossSuppressesMetadataAndPreviewCallbacks() {
        let page = preparedPage()
        var subscriber: Subscriber<PreparedInlineMessage?, NoError>?
        account.engine.messages.preparedResult = Signal { subscriber = $0; return EmptyDisposable }
        page.receive(["id": "old"]); page.window = nil; subscriber?.putNext(preparedValue); drainMain()
        XCTAssertTrue(UI.presented.isEmpty); XCTAssertTrue(page.events.isEmpty)
        page.window = account.window; account.engine.messages.preparedResult = .single(preparedValue)
        page.receive(["id": "preview"]); drainMain(); page.window = nil
        (UI.presented.first as? InputDataModalController)?.close()
        XCTAssertTrue(page.events.isEmpty); subscriber = nil
    }
    func testPreparedPageResetDuringProgressConstructionDoesNotSubscribe() {
        let page = preparedPage(); var subscriptions = 0
        account.engine.messages.preparedResult = Signal { _ in subscriptions += 1; return EmptyDisposable }
        UI.onProgress = { page.cancelPendingPageActions() }
        page.receive(["id": "reset"])
        XCTAssertEqual(subscriptions, 0); XCTAssertTrue(UI.presented.isEmpty); XCTAssertTrue(page.events.isEmpty)
    }
    func testPreparedPageOwnerReleaseDisposesLookupAndClosesPreview() {
        var page: PreparedPage? = preparedPage(.excluded), subscriber: Subscriber<PreparedInlineMessage?, NoError>?, disposed = 0
        account.engine.messages.preparedResult = Signal { subscriber = $0; return ActionDisposable { disposed += 1; self.assertPrivate() } }
        page?.receive(["id": "pending"]); weak var oldPage = page; page = nil
        XCTAssertNil(oldPage); XCTAssertEqual(disposed, 1)
        subscriber?.putNext(preparedValue); drainMain(); XCTAssertTrue(UI.presented.isEmpty); subscriber = nil
        page = preparedPage(.excluded); account.engine.messages.preparedResult = .single(preparedValue)
        page?.receive(["id": "preview"]); drainMain()
        let preview = UI.presented.first as? InputDataModalController
        page = nil; XCTAssertEqual(preview?.closeCount, 1)
    }
    func testPreparedPageSecretAndUnknownOriginsCoverLookupPreviewAndEvent() {
        for inherited: AnalyticsContext? in [origin(.excluded), nil] {
            UI.reset(); let page = PreparedPage(account, origin: inherited)
            account.engine.messages.onLookup = { self.assertPrivate() }
            account.engine.messages.preparedResult = .single(preparedValue)
            UI.onShow = { self.assertPrivate() }; page.onEvent = { self.assertPrivate() }
            page.receive(["id": "private"]); drainMain()
            let preview = UI.presented.first as? InputDataModalController
            XCTAssertTrue(preview?.analyticsContext?.isExcluded == true); preview?.close()
            XCTAssertEqual(page.events, ["prepared_message_failed"])
        }
    }
    func testPreparedPageRevocationDuringMetadataCannotRefreshGrant() {
        let page = preparedPage(); var subscriber: Subscriber<PreparedInlineMessage?, NoError>?
        account.engine.messages.preparedResult = Signal { subscriber = $0; return EmptyDisposable }
        page.receive(["id": "old"]); hub.policy.isEnabled = false; hub.policy.isEnabled = true
        UI.onShow = { self.assertPrivate() }; page.onEvent = { self.assertPrivate() }
        subscriber?.putNext(preparedValue); drainMain()
        let preview = UI.presented.first as? InputDataModalController
        XCTAssertFalse(hub.policy.accepts(preview?.analyticsContext?.scope)); preview?.close()
        XCTAssertEqual(page.events, ["prepared_message_failed"]); subscriber = nil
    }
    func testPreparedPageReturnedPrivateBotRestrictsPreviewAndEvent() {
        let page = preparedPage(); account.engine.messages.preparedResult = .single(PreparedInlineMessage(botId: -1, result: 1))
        UI.onShow = { self.assertPrivate() }; page.onEvent = { self.assertPrivate() }
        page.receive(["id": "private-result"]); drainMain()
        (UI.presented.first as? InputDataModalController)?.close()
        XCTAssertEqual(page.events, ["prepared_message_failed"])
    }
    func testPreparedPageMalformedRequestsAndEmptyIdDoNotLookup() {
        let page = preparedPage(); page.receive(nil); page.receive(["id": 123]); page.receive(["id": ""])
        page.bot = nil; page.receive(["id": "no-bot"])
        XCTAssertTrue(account.engine.messages.lookups.isEmpty); XCTAssertTrue(UI.presented.isEmpty); XCTAssertTrue(page.events.isEmpty)
    }
    func testPreparedPageOldPickerCannotCompleteReplacementAttempt() {
        let page = preparedPage(); account.engine.messages.preparedResult = .single(preparedValue)
        page.receive(["id": "old"]); drainMain()
        _ = (UI.presented.first as? InputDataModalController)?.current.returnKeyAction()
        let oldPicker = UI.presented.last as? ShareModalController
        page.cancelPendingPageActions(); page.receive(["id": "new"]); drainMain()
        oldPicker?.resultCompletion?(.accepted); oldPicker?.resultCompletion?(.cancelled)
        XCTAssertTrue(page.events.isEmpty)
        (UI.presented.last as? InputDataModalController)?.close()
        XCTAssertEqual(page.events, ["prepared_message_failed"])
    }
}

extension ForwardObjectTests {
    func testPreparedPageOrdinaryOriginReachesPreviewAndPickerWithoutExclusion() {
        let page = preparedPage(); account.engine.messages.preparedResult = .single(preparedValue)
        account.engine.messages.onLookup = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        UI.onShow = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        page.receive(["id": "ordinary"]); drainMain()
        let preview = UI.presented.first as? InputDataModalController
        XCTAssertTrue(hub.policy.accepts(preview?.analyticsContext?.scope))
        _ = preview?.current.returnKeyAction()
        XCTAssertTrue(hub.policy.accepts(UI.presented.last?.analyticsContext?.scope))
        preview?.close(); XCTAssertEqual(page.events, ["prepared_message_failed"])
    }
    func testPreparedPageWindowLossDuringProgressSetupDoesNotSubscribe() {
        let page = preparedPage(); var subscriptions = 0
        account.engine.messages.preparedResult = Signal { _ in subscriptions += 1; return EmptyDisposable }
        UI.onProgress = { page.window = nil }
        page.receive(["id": "window-loss"])
        XCTAssertEqual(subscriptions, 0); XCTAssertTrue(UI.presented.isEmpty); XCTAssertTrue(page.events.isEmpty)
    }
    func testPreparedPageInvoiceOnlyCancellationPreservesPreparedLookup() {
        let page = preparedPage(); var subscriber: Subscriber<PreparedInlineMessage?, NoError>?, disposed = 0
        account.engine.messages.preparedResult = Signal { subscriber = $0; return ActionDisposable { disposed += 1 } }
        page.receive(["id": "prepared"]); page.cancelPendingInvoices()
        XCTAssertEqual(disposed, 0); XCTAssertEqual(page.invoiceAction.resets, 1)
        subscriber?.putNext(preparedValue); drainMain(); XCTAssertEqual(UI.presented.count, 1)
        subscriber = nil; page.cancelPendingPageActions()
    }
}

protocol FixtureFlowSpec {
    associatedtype EntryPoint: RawRepresentable where EntryPoint.RawValue == String
    associatedtype Result: RawRepresentable where Result.RawValue == String
    associatedtype Step: RawRepresentable where Step.RawValue == String
}
enum AnalyticsFlows {
__FORWARD_PICKER_SPEC__
    enum ChatShare: FixtureFlowSpec {
        enum EntryPoint: String { case messageAction = "message_action", albumAction = "album_action", profileContact = "profile_contact", gallerySelection = "gallery_selection", galleryGroup = "gallery_group" }
        enum Result: String { case accepted, partiallyAccepted = "partially_accepted", rejected, acceptanceUnknown = "acceptance_unknown", sourceUnavailable = "source_unavailable" }
        enum RetryCount: String { case _0 = "0", _1 = "1", _2_3 = "2_3", _4_plus = "4_plus" }
        enum LastBlocker: String { case premiumRequired = "premium_required", slowModeWait = "slow_mode_wait", slowModeComment = "slow_mode_comment", pendingMessages = "pending_messages", insufficientBalance = "insufficient_balance" }
        enum Step: String { case blocked, retry, openPaymentConfirmation = "open_payment_confirmation", confirmPayment = "confirm_payment", cancelPaymentConfirmation = "cancel_payment_confirmation", openTopUp = "open_top_up", request, sourceReady = "source_ready", sourceUnavailable = "source_unavailable", openPicker = "open_picker", submit, accepted, partiallyAccepted = "partially_accepted", rejected, acceptanceUnknown = "acceptance_unknown", cancel }
    }
    enum ChatQuickForward: FixtureFlowSpec {
        enum EntryPoint: String { case directTarget = "direct_target", topicTarget = "topic_target" }
        enum Result: String { case draftPrepared = "draft_prepared", destinationReady = "destination_ready", accepted, partiallyAccepted = "partially_accepted", rejected, acceptanceUnknown = "acceptance_unknown", sourceUnavailable = "source_unavailable", targetUnavailable = "target_unavailable", restricted, completionUnknown = "completion_unknown", operationFailed = "operation_failed" }
        enum Step: String { case request, draftPrepared = "draft_prepared", destinationReady = "destination_ready", accepted, partiallyAccepted = "partially_accepted", rejected, acceptanceUnknown = "acceptance_unknown", sourceUnavailable = "source_unavailable", targetUnavailable = "target_unavailable", restricted, completionUnknown = "completion_unknown", operationFailed = "operation_failed" }
    }
    enum PeerInfoShareOwnContact: FixtureFlowSpec {
        enum EntryPoint: String { case unused }
        enum Result: String { case targetUnavailable = "target_unavailable", sourceUnavailable = "source_unavailable", accepted, rejected, acceptanceUnknown = "acceptance_unknown" }
        enum Step: String { case request, targetReady = "target_ready", targetUnavailable = "target_unavailable", openConfirmation = "open_confirmation", confirm, cancel, sourceReady = "source_ready", sourceUnavailable = "source_unavailable", submit, accepted, rejected, acceptanceUnknown = "acceptance_unknown" }
    }
    enum BotPreparedShare: FixtureFlowSpec {
        enum EntryPoint: String { case miniAppRequest = "mini_app_request" }
        enum Result: String { case partiallyAccepted = "partially_accepted", rejected, acceptanceUnknown = "acceptance_unknown", accepted, notAccepted = "not_accepted", metadataUnavailable = "metadata_unavailable" }
        enum Step: String { case partiallyAccepted = "partially_accepted", rejected, acceptanceUnknown = "acceptance_unknown", cancelPicker = "cancel_picker", request, metadataReady = "metadata_ready", openPreview = "open_preview", openPicker = "open_picker", accepted, notAccepted = "not_accepted", metadataUnavailable = "metadata_unavailable", cancelPreview = "cancel_preview" }
    }
}
enum AnalyticsFlowOutcome: String { case success, fail, cancelled }
final class AnalyticsFlow<Spec: FixtureFlowSpec> {
    private let scope: AnalyticsScope?
    private var steps: [String] = [], result: String?, entry: String?, retryCount: String?, lastBlocker: String?
    private var searchUsed: Bool?
    private var activation: String?
    private let source: AnalyticsScreen?
    var storedStepCount: Int { steps.count }
    init(analytics: Analytics, scope: AnalyticsScope?, source: AnalyticsScreen? = nil) {
        self.scope = scope; self.source = source
        if Spec.self == AnalyticsFlows.ChatShare.self { UI.shareJourneyStarts += 1 }
        if Spec.self == AnalyticsFlows.ChatQuickForward.self { UI.quickForwardStarts += 1 }
    }
    func set(entryPoint: Spec.EntryPoint) { scope?.perform { entry = entryPoint.rawValue } }
    func set(destination: AnalyticsFlows.ChatForwardPicker.Destination) {}
    func set(result: Spec.Result) { scope?.perform { self.result = result.rawValue } }
    func step(_ step: Spec.Step) { scope?.perform { steps.append(step.rawValue) } }
    func finish(_ outcome: AnalyticsFlowOutcome) { scope?.perform {
        if Spec.self == AnalyticsFlows.ChatForwardPicker.self { UI.forwardPickerResults.append((entry, steps, result, outcome.rawValue, retryCount, lastBlocker, searchUsed, activation)) } else if Spec.self == AnalyticsFlows.ChatShare.self { UI.shareJourneyResults.append((entry, steps, result, outcome.rawValue, retryCount, lastBlocker, source)) } else if Spec.self == AnalyticsFlows.ChatQuickForward.self { UI.quickForwardResults.append((entry, steps, result, outcome.rawValue)) } else if Spec.self == AnalyticsFlows.PeerInfoShareOwnContact.self { UI.ownContactResults.append((steps, result, outcome.rawValue)) } else { UI.journeyResults.append((steps, result, outcome.rawValue)) }
        discard()
    } }
    func discard() { steps = []; result = nil; entry = nil; retryCount = nil; lastBlocker = nil; searchUsed = nil; activation = nil }
}
extension AnalyticsFlow where Spec == AnalyticsFlows.ChatShare {
    func set(retryCount: AnalyticsFlows.ChatShare.RetryCount) { scope?.perform { self.retryCount = retryCount.rawValue } }
    func set(lastBlocker: AnalyticsFlows.ChatShare.LastBlocker) { scope?.perform { self.lastBlocker = lastBlocker.rawValue } }
}
extension AnalyticsFlow where Spec == AnalyticsFlows.ChatForwardPicker {
    func set(sourceLookup: Bool) {}
    func set(sourceCoverage: AnalyticsFlows.ChatForwardPicker.SourceCoverage?) {}
    func set(activation: AnalyticsFlows.ChatForwardPicker.Activation?) { scope?.perform { self.activation = activation?.rawValue } }
    func set(searchUsed: Bool) { scope?.perform { self.searchUsed = searchUsed } }
    func set(retryCount: AnalyticsFlows.ChatForwardPicker.RetryCount) { scope?.perform { self.retryCount = retryCount.rawValue } }
    func set(lastBlocker: AnalyticsFlows.ChatForwardPicker.LastBlocker) { scope?.perform { self.lastBlocker = lastBlocker.rawValue } }
}
__PREPARED_JOURNEY__
__SHARE_JOURNEY__
__FORWARD_PICKER_JOURNEY__

extension ForwardObjectTests {
    func openPreparedPicker(_ page: PreparedPage) -> ShareModalController? {
        account.engine.messages.preparedResult = .single(preparedValue)
        page.receive(["id": "synthetic"]); drainMain()
        _ = (UI.presented.last as? InputDataModalController)?.current.returnKeyAction()
        return UI.presented.last as? ShareModalController
    }
    func testPreparedJourneyAcceptedRouteEmitsOneSummaryAfterEnqueue() {
        let page = preparedPage(); let picker = openPreparedPicker(page)
        XCTAssertTrue(UI.journeyResults.isEmpty)
        UI.enqueueResults = [.single([sourceId])]; picker?.selectRecipient(3, threadId: nil); picker?.resultCompletion?(.accepted)
        XCTAssertEqual(UI.journeyResults.count, 1); XCTAssertEqual(UI.journeyResults.first?.result, "accepted")
        XCTAssertEqual(UI.journeyResults.first?.outcome, "success")
        XCTAssertEqual(UI.journeyResults.first?.steps, ["request", "metadata_ready", "open_preview", "open_picker", "accepted"])
    }
    func testPreparedJourneyUnknownEnqueueHasExplicitUnknownOutcome() {
        let page = preparedPage(); let picker = openPreparedPicker(page)
        UI.enqueueResults = [.complete()]; picker?.selectRecipient(3, threadId: nil)
        XCTAssertEqual(UI.journeyResults.count, 1); XCTAssertEqual(UI.journeyResults.first?.result, "acceptance_unknown")
        XCTAssertEqual(UI.journeyResults.first?.outcome, "fail"); XCTAssertEqual(page.events, ["prepared_message_failed"])
    }
    func testPreparedJourneyPickerCancelDoesNotClaimEnqueueFailure() {
        let page = preparedPage(); let picker = openPreparedPicker(page); picker?.close()
        XCTAssertEqual(UI.journeyResults.count, 1); XCTAssertNil(UI.journeyResults.first?.result); XCTAssertEqual(UI.journeyResults.first?.outcome, "cancelled")
        XCTAssertEqual(UI.journeyResults.first?.steps.last, "cancel_picker"); XCTAssertTrue(UI.enqueued.isEmpty)
    }
    func testPreparedJourneyExplicitPreviewCancelDiffersFromPickerResult() {
        let page = preparedPage(); account.engine.messages.preparedResult = .single(preparedValue)
        page.receive(["id": "synthetic"]); drainMain(); (UI.presented.first as? InputDataModalController)?.close()
        XCTAssertEqual(UI.journeyResults.count, 1); XCTAssertNil(UI.journeyResults.first?.result)
        XCTAssertEqual(UI.journeyResults.first?.outcome, "cancelled")
        XCTAssertEqual(UI.journeyResults.first?.steps, ["request", "metadata_ready", "open_preview", "cancel_preview"])
    }
    func testPreparedJourneyMetadataUnavailableHasNoPreviewStep() {
        let page = preparedPage(); account.engine.messages.preparedResult = .single(nil)
        page.receive(["id": "missing"]); drainMain()
        XCTAssertEqual(UI.journeyResults.count, 1); XCTAssertEqual(UI.journeyResults.first?.result, "metadata_unavailable")
        XCTAssertEqual(UI.journeyResults.first?.steps, ["request", "metadata_unavailable"])
    }
    func testPreparedJourneyPageResetAndTeardownDiscardSilently() {
        var page: PreparedPage? = preparedPage()
        _ = openPreparedPicker(page!); page?.reloadPage(); XCTAssertTrue(UI.journeyResults.isEmpty)
        page?.receive(["id": "second"]); drainMain(); page = nil
        XCTAssertTrue(UI.journeyResults.isEmpty)
    }
    func testPreparedJourneySecretDestinationDiscardsEarlierOrdinarySteps() {
        let page = preparedPage(); let picker = openPreparedPicker(page)
        UI.enqueueResults = [.single([sourceId])]; picker?.selectRecipient(-1, threadId: nil)
        XCTAssertEqual(page.events, ["prepared_message_sent"]); XCTAssertTrue(UI.journeyResults.isEmpty)
    }
    func testPreparedJourneyPrivateUnknownAndReturnedPrivateOriginsHaveNoSummary() {
        for kind in 0..<3 {
            UI.reset()
            let page = kind == 0 ? preparedPage(.excluded) : kind == 1 ? PreparedPage(account, origin: nil) : preparedPage()
            account.engine.messages.preparedResult = .single(kind == 2 ? PreparedInlineMessage(botId: -1, result: 1) : preparedValue)
            page.receive(["id": "private"]); drainMain(); (UI.presented.first as? InputDataModalController)?.close()
            XCTAssertEqual(page.events, ["prepared_message_failed"]); XCTAssertTrue(UI.journeyResults.isEmpty)
        }
    }
    func testPreparedJourneyDisabledCollectionDoesNotChangeSuccessfulSharing() {
        hub.policy.isEnabled = false
        let page = preparedPage(); let picker = openPreparedPicker(page)
        UI.enqueueResults = [.single([sourceId])]; picker?.selectRecipient(3, threadId: nil)
        XCTAssertEqual(page.events, ["prepared_message_sent"]); XCTAssertTrue(UI.journeyResults.isEmpty)
    }
}

extension ForwardObjectTests {
    func testTypedShareResultAggregationKeepsUncertaintyDominant() {
        let accepted = ShareRecipientDelivery(peerId: 3, comment: nil, content: ShareDeliveryPart(expectedCount: 1, result: [sourceId]))
        let rejected = ShareRecipientDelivery(peerId: 2, comment: nil, content: ShareDeliveryPart(expectedCount: 1, result: [nil]))
        let unknown = ShareRecipientDelivery(peerId: 2, comment: nil, content: ShareDeliveryPart(expectedCount: 1, result: nil))
        let partial = ShareRecipientDelivery(peerId: 2, comment: nil, content: ShareDeliveryPart(expectedCount: 2, result: [sourceId, nil]))
        let empty = ShareRecipientDelivery(peerId: 2, comment: nil, content: ShareDeliveryPart(expectedCount: 0, result: []))
        XCTAssertEqual(SharePickerResult(deliveries: []), .unknown)
        XCTAssertEqual(SharePickerResult(deliveries: [accepted]), .accepted)
        XCTAssertEqual(SharePickerResult(deliveries: [rejected]), .rejected)
        XCTAssertEqual(SharePickerResult(deliveries: [accepted, rejected]), .partiallyAccepted)
        XCTAssertEqual(SharePickerResult(deliveries: [partial]), .partiallyAccepted)
        XCTAssertEqual(SharePickerResult(deliveries: [accepted, unknown]), .unknown)
        XCTAssertEqual(SharePickerResult(deliveries: [partial, unknown]), .unknown)
        XCTAssertEqual(SharePickerResult(deliveries: [empty]), .unknown)
    }
    func testTypedShareResultMatchesLegacyCompletionOnceForProvider() {
        for (ids, expected): ([MessageId?], SharePickerResult) in [([sourceId], .accepted), ([nil], .rejected), ([], .unknown)] {
            UI.reset(); UI.enqueueResults = [.single(ids)]
            var legacy: [Bool] = [], typed: [SharePickerResult] = []
            let modal = ShareModalController(preparedShare(), completion: { legacy.append($0) }, analyticsContext: origin())
            modal.resultCompletion = { typed.append($0) }
            modal.selectRecipient(3, threadId: nil); modal.close(); modal.close()
            XCTAssertEqual(typed, [expected]); XCTAssertEqual(legacy, [expected == .accepted])
        }
    }
    func testTypedShareMultiTargetPartialAndUnknownAreNotCancellation() {
        for (second, expected): ([MessageId?], SharePickerResult) in [([nil], .partiallyAccepted), ([], .unknown)] {
            UI.reset(); UI.enqueueResults = [.single([sourceId]), .single(second)]
            var typed: [SharePickerResult] = []
            let modal = ShareModalController(ShareLinkObject(account, link: "synthetic"), analyticsContext: origin())
            modal.resultCompletion = { typed.append($0) }
            let disposable = modal.performShare(to: [2, 3], threadId: nil, comment: nil, sendPaidMessageStars: [:], analyticsContext: origin()).start()
            XCTAssertEqual(typed, [expected]); XCTAssertEqual(UI.enqueued.count, 2); XCTAssertEqual(UI.alerts, 1); disposable.dispose()
        }
    }
    func testTypedShareDistinguishesUserCloseFromLegacyDispatch() {
        let cancelled = ShareModalController(preparedShare(), analyticsContext: origin())
        var typed: [SharePickerResult] = []
        cancelled.resultCompletion = { typed.append($0) }; cancelled.close(); cancelled.close()
        let share = PendingShareObject(account); share.result = .complete()
        let dispatched = ShareModalController(share, analyticsContext: origin())
        dispatched.resultCompletion = { typed.append($0) }; dispatched.selectRecipient(3, threadId: nil)
        XCTAssertEqual(typed, [.cancelled, .dispatched])
    }
    func testTypedPreparedBridgeMapsEveryOperationalOutcomeOnce() {
        for (value, expected): (SharePickerResult, BrowserPreparedShareResult) in [(.accepted, .accepted), (.partiallyAccepted, .partiallyAccepted), (.rejected, .rejected), (.unknown, .unknown), (.cancelled, .cancelled), (.dispatched, .unknown), (.draftPrepared, .unknown), (.destinationReady, .unknown), (.sourceUnavailable, .unknown), (.targetUnavailable, .unknown)] {
            var outcomes: [BrowserPreparedShareResult] = []
            let modal = BrowserHooks.shared.makeShareChatContextResultModalObservedResult(account, preparedValue, analyticsContext: origin(), completion: { outcomes.append($0) }) as? ShareModalController
            modal?.resultCompletion?(value); modal?.resultCompletion?(.accepted)
            XCTAssertEqual(outcomes, [expected])
        }
    }
    func testTypedPreparedHookRetainsPrivateLifetimeAfterOwnerRelease() {
        var callback: ((BrowserPreparedShareResult) -> Void)?, outcomes: [BrowserPreparedShareResult] = []
        BrowserHooks.shared.makeShareChatContextResultModalWithResult = { _, _, origin, completed in
            self.assertPrivate(); XCTAssertTrue(origin.isExcluded); callback = completed; return ModalViewController()
        }
        var modal: ModalViewController? = BrowserHooks.shared.makeShareChatContextResultModalObservedResult(account, preparedValue, analyticsContext: origin(.excluded), completion: { self.assertPrivate(); outcomes.append($0) })
        XCTAssertTrue(modal?.analyticsContext?.isExcluded == true); modal = nil; callback?(.rejected); callback?(.accepted)
        XCTAssertEqual(outcomes, [.rejected]); callback = nil
    }
    func testTypedPreparedLegacyFallbackKeepsFalseOutcomeAmbiguous() {
        BrowserHooks.shared.makeShareChatContextResultModalWithResult = nil
        BrowserHooks.shared.makeShareChatContextResultModalWithContext = { _, _, _, completed in completed(false); return ModalViewController() }
        let page = preparedPage(); _ = openPreparedPicker(page)
        XCTAssertEqual(UI.journeyResults.count, 1); XCTAssertEqual(UI.journeyResults.first?.result, "not_accepted")
        XCTAssertEqual(UI.journeyResults.first?.outcome, "fail"); XCTAssertEqual(page.events, ["prepared_message_failed"])
    }
    func testTypedPreparedRejectedEnqueueRecordsRejection() {
        let page = preparedPage(); let picker = openPreparedPicker(page)
        UI.enqueueResults = [.single([nil])]; picker?.selectRecipient(3, threadId: nil)
        XCTAssertEqual(UI.journeyResults.count, 1); XCTAssertEqual(UI.journeyResults.first?.result, "rejected")
        XCTAssertEqual(UI.journeyResults.first?.steps.last, "rejected"); XCTAssertEqual(page.events, ["prepared_message_failed"])
    }
    func testTypedPreparedSynchronousCompletionCannotPresentStalePicker() {
        BrowserHooks.shared.makeShareChatContextResultModalWithResult = { _, _, _, completed in
            completed(.cancelled); completed(.accepted); return ModalViewController()
        }
        let page = preparedPage(); _ = openPreparedPicker(page)
        XCTAssertEqual(UI.presented.count, 1); XCTAssertEqual(UI.journeyResults.count, 1)
        XCTAssertEqual(UI.journeyResults.first?.outcome, "cancelled"); XCTAssertEqual(page.events, ["prepared_message_failed"])
    }
}

extension ForwardObjectTests {
    func testTypedShareCloseScopesBothCallbacksWithoutBrowserWrapper() {
        for inherited: AnalyticsContext? in [origin(.excluded), nil] {
            var callbacks = 0
            let modal = ShareModalController(preparedShare(), completion: { _ in self.assertPrivate(); callbacks += 1 }, analyticsContext: inherited)
            modal.resultCompletion = { _ in self.assertPrivate(); callbacks += 1 }
            modal.close(); XCTAssertEqual(callbacks, 2)
        }
    }
    func testTypedShareCloseCannotRefreshRevokedOrdinaryScope() {
        var callbacks = 0
        let modal = ShareModalController(preparedShare(), completion: { _ in self.assertPrivate(); callbacks += 1 }, analyticsContext: origin())
        modal.resultCompletion = { _ in self.assertPrivate(); callbacks += 1 }
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        modal.close(); XCTAssertEqual(callbacks, 2)
    }
}

struct ChatHistoryUIHooks {
    static var shared = installedHistoryHooks()
__HISTORY_SHARE_HOOK__
__HISTORY_FORWARD_HOOK__
}
func installedHistoryHooks() -> ChatHistoryUIHooks {
    var hooks = ChatHistoryUIHooks(makeShareMessageModal: { context, message in ShareModalController(ShareMessageObject(context, message)) }, makeShareGroupedMessagesModal: { context, message, messages in ShareModalController(ShareMessageObject(context, message, messages)) }, makeForwardMessagesObject: { context, messages, album, lookup in ForwardMessagesObject(context, messages: messages, album: album, getMessages: lookup) })
__HISTORY_SHARE_INSTALL__
    return hooks
}
func canForwardMessage(_ message: Message, chatInteraction: ChatInteraction) -> Bool { true }
class MessageShareRow {
    let context: AccountContext, chatInteraction: ChatInteraction
    var message: Message?
    init(context: AccountContext, peerId: PeerId, message: Message?, origin: AnalyticsContext?) { self.context = context; self.message = message; chatInteraction = ChatInteraction(chatLocation: .peer(peerId), context: context); chatInteraction.inheritedAnalyticsContext = origin }
__MESSAGE_ROW_SHARE__
__ROW_FORWARD_ACTION__
}
final class GroupShareRow: MessageShareRow {
    struct Layout { var messages: [Message] = [] }
    var layout = Layout()
__GROUP_ROW_SHARE__
}
final class TelegramUser: Peer {
    var firstName: String? = "first", lastName: String? = "last", phone: String? = "phone"
}
func TelegramMediaContact(firstName: String, lastName: String, phoneNumber: String, peerId: PeerId, vCardData: String?) -> Int {
    UI.ownContacts.append((firstName, lastName, phoneNumber, peerId)); return 42
}
func verifyAlert_button(for window: Window, information: String, successHandler: @escaping (Int) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    UI.onConfirmation?(); UI.confirmations.append((successHandler, cancelHandler, onDeinit))
}
__PROFILE_OWN_ACTION__
func getPeerView(peerId: PeerId, postbox: Postbox) -> Signal<Peer?, NoError> {
    postbox.onContactLookup?(); return postbox.contactResult ?? .single(postbox.value.getPeer(peerId))
}
final class ProfileContactArguments {
    let context: AccountContext, peerId: PeerId
    var effectivePeerId: PeerId
    let shareDisposable = MetaDisposable()
    let ownContactShareAction = ProfileOwnContactShareAction()
    var getAnalyticsContext: () -> AnalyticsContext
    init(context: AccountContext, peerId: PeerId, effectivePeerId: PeerId? = nil, origin: AnalyticsContext?) { self.context = context; self.peerId = peerId; self.effectivePeerId = effectivePeerId ?? peerId; getAnalyticsContext = { origin ?? Analytics.shared.unresolvedContext() } }
__PROFILE_CAPTURE__
__PROFILE_CONTACT_SHARE__
__PROFILE_OWN_SHARE__
    deinit { shareDisposable.dispose() }
}

extension ForwardObjectTests {
    func testShareSourceMessageControlPreservesOrdinaryContextBeforeChildren() {
        let row = MessageShareRow(context: account, peerId: 3, message: Message(id: sourceId), origin: origin())
        UI.onEmoji = { XCTAssertFalse(self.hub.policy.hasExclusions) }; UI.onShow = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        row.share()
        let picker = UI.presented.first as? ShareModalController
        XCTAssertTrue(hub.policy.accepts(picker?.analyticsContext?.scope)); XCTAssertTrue(hub.policy.accepts(picker?.emoji.analyticsContext?.scope))
        XCTAssertEqual((picker?.share as? ShareMessageObject)?.messageIds, [sourceId])
    }
    func testShareSourceSecretChatOrPrimaryMessageExcludesConstruction() {
        for (chat, message): (PeerId, PeerId) in [(-1, 2), (3, -1)] {
            UI.reset(); UI.onEmoji = { self.assertPrivate() }; UI.onShow = { self.assertPrivate() }
            MessageShareRow(context: account, peerId: chat, message: Message(id: MessageId(peerId: message, id: 1)), origin: origin()).share()
            XCTAssertFalse(hub.policy.accepts(UI.presented.first?.analyticsContext?.scope))
        }
    }
    func testShareSourceAlbumPreservesWholeGroupAndPrivatePrimary() {
        for primaryPrivate in [false, true] {
            UI.reset(); UI.onEmoji = { self.assertPrivate() }; UI.onShow = { self.assertPrivate() }
            let row = GroupShareRow(context: account, peerId: 3, message: Message(id: MessageId(peerId: primaryPrivate ? -1 : 2, id: 1)), origin: origin())
            row.layout.messages = [Message(id: MessageId(peerId: primaryPrivate ? 2 : -1, id: 2)), Message(id: sourceId)]
            row.share()
            let picker = UI.presented.first as? ShareModalController
            XCTAssertFalse(hub.policy.accepts(picker?.analyticsContext?.scope))
            XCTAssertEqual((picker?.share as? ShareMessageObject)?.messageIds, row.layout.messages.map { $0.id })
        }
    }
    func testShareSourceAlbumOrdinaryRouteKeepsGroup() {
        let row = GroupShareRow(context: account, peerId: 3, message: Message(id: sourceId), origin: origin())
        row.layout.messages = [Message(id: sourceId), Message(id: MessageId(peerId: 2, id: 2))]; row.share()
        let picker = UI.presented.first as? ShareModalController
        XCTAssertTrue(hub.policy.accepts(picker?.analyticsContext?.scope)); XCTAssertEqual((picker?.share as? ShareMessageObject)?.messageIds.count, 2)
    }
    func testShareSourceCaptureRetainsDraftAndResolvedPeerRestrictions() {
        for kind in 0..<3 {
            UI.reset(); let row = MessageShareRow(context: account, peerId: 3, message: Message(id: sourceId), origin: origin())
            if kind == 0 { row.chatInteraction.peer = Peer(-1) }
            if kind == 1 { row.chatInteraction.state.interface.ids = [MessageId(peerId: -1, id: 1)] }
            if kind == 2 { row.chatInteraction.state.interface.editState = FixtureEditState(message: Message(id: MessageId(peerId: -1, id: 1))) }
            UI.onShow = { self.assertPrivate() }; row.share()
            XCTAssertFalse(hub.policy.accepts(UI.presented.first?.analyticsContext?.scope))
        }
    }
    func testPreviewOriginValidationPreservesExactEligibleScope() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        let original = origin()
        let checked = interaction.captureAnalyticsContext(inherited: original)
        XCTAssertTrue(checked.scope === original.scope)
        XCTAssertTrue(hub.policy.accepts(checked.scope))
        let lifetime = checked.beginPresentation()
        XCTAssertFalse(hub.policy.hasExclusions)
        lifetime.end()
    }
    func testPreviewOriginValidationTightensPrivateAndUnknownReceivingSources() {
        for kind in 0..<6 {
            let interaction = ChatInteraction(chatLocation: .peer(kind == 0 ? -1 : kind == 1 ? 0 : 3), context: account)
            let original = origin()
            switch kind {
            case 2: interaction.peer = Peer(-1)
            case 3: interaction.state.interface.ids = [MessageId(peerId: -1, id: 1)]
            case 4: interaction.state.interface.editState = FixtureEditState(message: Message(id: MessageId(peerId: -1, id: 1)))
            case 5: interaction.inheritedAnalyticsContext = origin(.excluded)
            default: break
            }
            let checked = interaction.captureAnalyticsContext(inherited: original)
            XCTAssertTrue(checked.isExcluded)
            XCTAssertNil(checked.scope)
            let lifetime = checked.beginPresentation()
            assertPrivate()
            XCTAssertFalse(original.scope?.isValid == true)
            lifetime.end()
        }
    }
    func testPreviewOriginValidationNeverRefreshesForeignRevokedOrOwnerlessGrant() {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        let revoked = origin()
        hub.policy.isEnabled = false
        hub.policy.isEnabled = true
        let otherHub = Analytics()
        otherHub.policy.setOwner(account.account)
        otherHub.policy.isEnabled = true
        let foreign = otherHub.captureContext(owner: account.account, privacy: .ordinary)
        for inherited in [revoked, foreign, origin(.excluded), hub.unresolvedContext()] {
            let checked = interaction.captureAnalyticsContext(inherited: inherited)
            XCTAssertFalse(hub.policy.accepts(checked.scope))
            XCTAssertNil(checked.scope)
        }
        let original = origin()
        hub.policy.setOwner(Account())
        let checked = interaction.captureAnalyticsContext(inherited: original)
        XCTAssertFalse(hub.policy.accepts(checked.scope))
        hub.policy.setOwner(account.account)
        XCTAssertFalse(hub.policy.accepts(interaction.captureAnalyticsContext(inherited: checked).scope))
    }
    func testShareSourceForeignAndRevokedGrantsCannotRefresh() {
        let revoked = origin(); hub.policy.isEnabled = false; hub.policy.isEnabled = true
        let foreign = hub.captureContext(owner: NSObject(), privacy: .ordinary)
        for inherited in [revoked, foreign] {
            UI.reset(); UI.onEmoji = { self.assertPrivate() }; UI.onShow = { self.assertPrivate() }
            MessageShareRow(context: account, peerId: 3, message: Message(id: sourceId), origin: inherited).share()
            XCTAssertFalse(hub.policy.accepts(UI.presented.first?.analyticsContext?.scope))
        }
    }
    func testShareSourceLegacyFactoryStillRunsUnderPrivateOrigin() {
        ChatHistoryUIHooks.shared.makeShareMessagesModalWithContext = nil
        UI.onEmoji = { self.assertPrivate() }; UI.onShow = { self.assertPrivate() }
        MessageShareRow(context: account, peerId: -1, message: Message(id: sourceId), origin: origin()).share()
        XCTAssertFalse(hub.policy.accepts(UI.presented.first?.analyticsContext?.scope))
    }
    func testShareSourceNoMessageDoesNotConstructPicker() {
        MessageShareRow(context: account, peerId: 3, message: nil, origin: origin()).share()
        GroupShareRow(context: account, peerId: 3, message: nil, origin: origin()).share()
        XCTAssertTrue(UI.presented.isEmpty)
    }
    func testShareSourceProfileContactOrdinaryContextPrecedesLookupAndChildren() {
        account.account.postbox.contactResult = .single(TelegramUser(2))
        account.account.postbox.onContactLookup = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        UI.onEmoji = { XCTAssertFalse(self.hub.policy.hasExclusions) }; UI.onShow = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        let arguments = ProfileContactArguments(context: account, peerId: 2, origin: origin())
        arguments.shareContact(); drainMain()
        let picker = UI.presented.first as? ShareModalController
        XCTAssertTrue(picker?.share is ShareContactObject); XCTAssertTrue(hub.policy.accepts(picker?.analyticsContext?.scope))
    }
    func testShareSourceSecretProfileAssociatedUserRemainsPrivate() {
        account.account.postbox.contactResult = .single(TelegramUser(2))
        account.account.postbox.onContactLookup = { self.assertPrivate() }; UI.onEmoji = { self.assertPrivate() }; UI.onShow = { self.assertPrivate() }
        let arguments = ProfileContactArguments(context: account, peerId: -1, effectivePeerId: 2, origin: origin())
        arguments.shareContact(); drainMain()
        XCTAssertFalse(hub.policy.accepts(UI.presented.first?.analyticsContext?.scope))
    }
    func testShareSourceProfileLookupRevocationAndReturnedPeerTightenOrigin() {
        for revoke in [true, false] {
            UI.reset(); var subscriber: Subscriber<Peer?, NoError>?
            account.account.postbox.contactResult = Signal { subscriber = $0; return EmptyDisposable }
            let arguments = ProfileContactArguments(context: account, peerId: 2, origin: origin())
            arguments.shareContact()
            if revoke { hub.policy.isEnabled = false; hub.policy.isEnabled = true }
            UI.onEmoji = { self.assertPrivate() }; UI.onShow = { self.assertPrivate() }
            subscriber?.putNext(TelegramUser(revoke ? 2 : -1)); drainMain()
            XCTAssertFalse(hub.policy.accepts(UI.presented.first?.analyticsContext?.scope)); subscriber = nil
        }
    }
    func testShareSourceProfileReplacementAndOwnerReleaseCancelOldLookup() {
        var subscribers: [Subscriber<Peer?, NoError>] = [], disposed = 0
        account.account.postbox.contactResult = Signal { subscribers.append($0); return ActionDisposable { disposed += 1; self.assertPrivate() } }
        var arguments: ProfileContactArguments? = ProfileContactArguments(context: account, peerId: -1, effectivePeerId: 2, origin: origin())
        arguments?.shareContact(); arguments?.shareContact(); XCTAssertEqual(disposed, 1)
        subscribers.first?.putNext(TelegramUser(2)); drainMain(); XCTAssertTrue(UI.presented.isEmpty)
        arguments = nil; XCTAssertEqual(disposed, 2)
        subscribers.last?.putNext(TelegramUser(2)); drainMain(); XCTAssertTrue(UI.presented.isEmpty); subscribers = []
    }
    func testShareSourceProfileMissingWrongTypeAndDuplicateMetadataDoNotInventPickers() {
        let arguments = ProfileContactArguments(context: account, peerId: 2, origin: origin())
        for peer: Peer? in [nil, Peer(2)] {
            account.account.postbox.contactResult = .single(peer); arguments.shareContact(); drainMain()
        }
        XCTAssertTrue(UI.presented.isEmpty)
        var subscriber: Subscriber<Peer?, NoError>?
        account.account.postbox.contactResult = Signal { subscriber = $0; return EmptyDisposable }
        arguments.shareContact(); subscriber?.putNext(TelegramUser(2)); subscriber?.putNext(TelegramUser(2)); drainMain()
        XCTAssertEqual(UI.presented.count, 1); subscriber = nil
    }
}

extension ForwardObjectTests {
    func testShareSourceDirectHookRestrictsWholeAlbumBeforeFactory() {
        UI.onEmoji = { self.assertPrivate() }
        let controller = ChatHistoryUIHooks.shared.makeShareMessagesModalObserved(account, Message(id: sourceId), groupedMessages: [Message(id: MessageId(peerId: -1, id: 2))], analyticsContext: origin())
        XCTAssertFalse(hub.policy.accepts(controller.analyticsContext?.scope))
    }
    func testShareSourceProfileMissingOriginNeverAssumesOrdinaryProfile() {
        account.account.postbox.contactResult = .single(TelegramUser(2))
        account.account.postbox.onContactLookup = { self.assertPrivate() }; UI.onEmoji = { self.assertPrivate() }; UI.onShow = { self.assertPrivate() }
        let arguments = ProfileContactArguments(context: account, peerId: 2, origin: nil)
        arguments.shareContact(); drainMain()
        XCTAssertFalse(hub.policy.accepts(UI.presented.first?.analyticsContext?.scope))
    }
}

extension ForwardObjectTests {
    func openMessageJourney(album: Bool = false, origin inherited: AnalyticsContext? = nil) -> ShareModalController? {
        if album {
            let row = GroupShareRow(context: account, peerId: 3, message: Message(id: sourceId), origin: inherited ?? origin())
            row.layout.messages = [Message(id: sourceId), Message(id: MessageId(peerId: 2, id: 2))]; row.share()
        } else {
            MessageShareRow(context: account, peerId: 3, message: Message(id: sourceId), origin: inherited ?? origin()).share()
        }
        return UI.presented.last as? ShareModalController
    }
    func testShareJourneyMessageAndAlbumRoutesSurvivePickerToAcceptance() {
        for album in [false, true] {
            UI.reset(); let picker = openMessageJourney(album: album)
            UI.sendResult = .single(album ? [sourceId, MessageId(peerId: 3, id: 2)] : [sourceId])
            XCTAssertTrue(UI.shareJourneyResults.isEmpty); picker?.selectRecipient(3, threadId: nil); picker?.close()
            XCTAssertEqual(UI.shareJourneyResults.count, 1); XCTAssertEqual(UI.shareJourneyResults.first?.entry, album ? "album_action" : "message_action")
            XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "submit", "accepted"])
            XCTAssertEqual(UI.shareJourneyResults.first?.outcome, "success")
        }
    }
    func testShareJourneyProfileSourceAndEnqueueRemainDistinct() {
        let arguments = ProfileContactArguments(context: account, peerId: 2, origin: origin())
        account.account.postbox.contactResult = .single(TelegramUser(2)); arguments.shareContact(); drainMain()
        let picker = UI.presented.first as? ShareModalController
        XCTAssertTrue(UI.shareJourneyResults.isEmpty); UI.enqueueResults = [.single([sourceId])]; picker?.selectRecipient(3, threadId: nil)
        XCTAssertEqual(UI.shareJourneyResults.count, 1); XCTAssertEqual(UI.shareJourneyResults.first?.entry, "profile_contact")
        XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "source_ready", "open_picker", "submit", "accepted"])
    }
    func testShareJourneyProfileMissingSourceFailsWithoutOpeningPicker() {
        let arguments = ProfileContactArguments(context: account, peerId: 2, origin: origin())
        account.account.postbox.contactResult = .single(nil); arguments.shareContact(); drainMain()
        XCTAssertTrue(UI.presented.isEmpty); XCTAssertEqual(UI.shareJourneyResults.count, 1)
        XCTAssertEqual(UI.shareJourneyResults.first?.result, "source_unavailable"); XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "source_unavailable"])
    }
    func testShareJourneyRejectedPartialAndUnknownEnqueueResultsKeepMeaning() {
        for (ids, value): ([MessageId?], String) in [([nil, nil], "rejected"), ([sourceId, nil], "partially_accepted"), ([], "acceptance_unknown")] {
            UI.reset(); let picker = openMessageJourney(album: true); UI.sendResult = .single(ids); picker?.selectRecipient(3, threadId: nil)
            XCTAssertEqual(UI.shareJourneyResults.count, 1); XCTAssertEqual(UI.shareJourneyResults.first?.result, value)
            XCTAssertEqual(UI.shareJourneyResults.first?.outcome, "fail"); XCTAssertEqual(UI.alerts, 1)
        }
    }
    func testShareJourneyExplicitPickerCloseHasNoDeliveryResult() {
        let picker = openMessageJourney(); picker?.close(); picker?.close()
        XCTAssertEqual(UI.shareJourneyResults.count, 1); XCTAssertEqual(UI.shareJourneyResults.first?.outcome, "cancelled"); XCTAssertNil(UI.shareJourneyResults.first?.result)
        XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "cancel"])
    }
    func testShareJourneyCloseDuringPendingSendIsCancellationRequestOnce() {
        let picker = openMessageJourney(); var subscriber: Subscriber<[MessageId?], NoError>?
        UI.sendResult = Signal { subscriber = $0; return EmptyDisposable }; picker?.selectRecipient(3, threadId: nil)
        XCTAssertTrue(UI.shareJourneyResults.isEmpty); picker?.close(); subscriber?.putNext([sourceId]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertEqual(UI.shareJourneyResults.count, 1); XCTAssertEqual(UI.shareJourneyResults.first?.outcome, "cancelled"); XCTAssertNil(UI.shareJourneyResults.first?.result)
        XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "submit", "cancel"])
    }
    func testShareJourneySupersededSubmissionCannotAttributeRetryResult() {
        let picker = openMessageJourney(); var subscriber: Subscriber<[MessageId?], NoError>?
        UI.sendResult = Signal { subscriber = $0; return EmptyDisposable }; picker?.selectRecipient(3, threadId: nil)
        picker?.recipientAction.reset(); XCTAssertEqual(picker?.analyticsShareJourney?.retainedStateCount, 0)
        UI.sendResult = .single([sourceId]); picker?.selectRecipient(3, threadId: nil); subscriber?.putNext([sourceId]); subscriber = nil
        XCTAssertTrue(UI.shareJourneyResults.isEmpty); XCTAssertTrue(picker?.success == true)
    }
    func testShareJourneyOwnerReleaseDoesNotInventAbandonment() {
        var picker = openMessageJourney(); UI.presented = []
        var subscriber: Subscriber<[MessageId?], NoError>?
        UI.sendResult = Signal { subscriber = $0; return EmptyDisposable }; picker?.selectRecipient(3, threadId: nil)
        weak var weakPicker = picker; picker = nil
        XCTAssertNil(weakPicker); subscriber?.putNext([sourceId]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertTrue(UI.shareJourneyResults.isEmpty)
    }
    func testShareJourneySecretDestinationErasesEarlierSourceSteps() {
        let picker = openMessageJourney(); UI.sendResult = .single([sourceId]); picker?.selectRecipient(-1, threadId: nil)
        XCTAssertTrue(UI.shareJourneyResults.isEmpty); XCTAssertEqual(picker?.analyticsShareJourney?.retainedStateCount, 0)
        XCTAssertTrue(picker?.success == true)
    }
    func testShareJourneyPrivateSourceAndMissingProfileOriginStayEmpty() {
        let picker = openMessageJourney(origin: origin(.excluded)); picker?.close(); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
        UI.reset(); let arguments = ProfileContactArguments(context: account, peerId: 2, origin: nil)
        account.account.postbox.contactResult = .single(nil); arguments.shareContact(); drainMain(); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
    }
    func testShareJourneyDisableDoesNotChangeFunctionalAcceptance() {
        let picker = openMessageJourney(); hub.policy.isEnabled = false; UI.sendResult = .single([sourceId]); picker?.selectRecipient(3, threadId: nil)
        XCTAssertTrue(picker?.success == true); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
    }
    func testShareJourneyLegacyDispatcherCannotClaimObservedOutcome() {
        let share = PendingShareObject(account); share.result = .complete()
        let picker = ShareModalController(share, analyticsContext: origin())
        let journey = AnalyticsShareJourney(context: origin(), entry: .messageAction)
        picker.setAnalyticsShareJourney(journey); picker.selectRecipient(3, threadId: nil)
        XCTAssertEqual(journey.retainedStateCount, 0); XCTAssertTrue(picker.success); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
    }
}

extension ForwardObjectTests {
    func recoveryPicker(ids: Set<PeerId> = [3], comment: String = "", inherited: AnalyticsContext? = nil) -> ShareModalController {
        let picker = openMessageJourney(origin: inherited)!
        picker.selectInteractions.presentation.selected = ids
        picker.selectInteractions.presentation.peers = Dictionary(uniqueKeysWithValues: ids.map { ($0, account.account.postbox.value.peers[$0]!) })
        picker.contextChatInteraction.state.interface.input.inputText = comment
        UI.sendResult = .single([sourceId])
        return picker
    }
    func testShareRecoveryRecordsDisplayedSlowModeReasonOnly() {
        for reason in ["slow_mode_wait", "slow_mode_comment", "pending_messages"] {
            UI.reset(); paidPeer(slow: true)
            let cached = CachedChannelData(); cached.slowModeValidUntilTimestamp = 200
            account.account.postbox.value.cached[3] = cached
            account.account.postbox.unsent = .single(UnsentView(ids: reason == "pending_messages" ? [MessageId(peerId: 3, id: 5)] : []))
            let picker = recoveryPicker(comment: reason == "slow_mode_wait" ? "" : "comment")
            _ = picker.invoke(); drainMain(); picker.close()
            XCTAssertTrue(UI.targets.isEmpty); XCTAssertTrue(UI.confirmations.isEmpty)
            XCTAssertEqual(UI.shareJourneyResults.first?.lastBlocker, reason)
            XCTAssertEqual(UI.shareJourneyResults.first?.retryCount, "0")
            XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "blocked", "cancel"])
        }
    }
    func testShareRecoverySlowModeToConfirmationToAcceptedCountsOneRetry() {
        paidPeer(slow: true); let picker = recoveryPicker(comment: "comment")
        _ = picker.invoke(); drainMain()
        picker.contextChatInteraction.state.interface.input.inputText = ""
        _ = picker.invoke(); _ = picker.invoke(); drainMain()
        XCTAssertEqual(UI.confirmations.count, 1); XCTAssertTrue(UI.targets.isEmpty)
        UI.confirmations[0].0(0); UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(UI.targets, [3]); XCTAssertEqual(UI.shareJourneyResults.count, 1)
        XCTAssertEqual(UI.shareJourneyResults.first?.lastBlocker, "slow_mode_comment"); XCTAssertEqual(UI.shareJourneyResults.first?.retryCount, "1")
        XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "blocked", "retry", "open_payment_confirmation", "confirm_payment", "submit", "accepted"])
    }
    func testShareRecoveryPaymentCancelThenExplicitRetryKeepsJourney() {
        paidPeer(); let picker = recoveryPicker()
        _ = picker.invoke(); drainMain(); UI.confirmations[0].1(); UI.confirmations[0].0(0); drainMain()
        XCTAssertTrue(UI.targets.isEmpty); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
        _ = picker.invoke(); drainMain(); UI.confirmations[1].0(0); drainMain()
        XCTAssertEqual(UI.shareJourneyResults.first?.retryCount, "1"); XCTAssertNil(UI.shareJourneyResults.first?.lastBlocker)
        XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "open_payment_confirmation", "cancel_payment_confirmation", "retry", "open_payment_confirmation", "confirm_payment", "submit", "accepted"])
    }
    func testShareRecoveryUnknownPaymentDismissalDiscardsObservationButAllowsSend() {
        paidPeer(); let picker = recoveryPicker()
        _ = picker.invoke(); drainMain(); UI.confirmations[0].2(); drainMain()
        XCTAssertEqual(picker.analyticsShareJourney?.retainedStateCount, 0)
        _ = picker.invoke(); drainMain(); UI.confirmations[1].0(0); drainMain()
        XCTAssertEqual(UI.targets, [3]); XCTAssertTrue(picker.success); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
    }
    func testShareRecoveryTopUpDoesNotSendUntilAnotherConfirmation() {
        paidPeer(balance: 1); let picker = recoveryPicker()
        _ = picker.invoke(); drainMain(); UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(UI.purchaseAmounts, [2]); XCTAssertTrue(UI.targets.isEmpty); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
        paidPeer(balance: 2)
        XCTAssertTrue(UI.targets.isEmpty)
        _ = picker.invoke(); drainMain(); UI.confirmations[1].0(0); drainMain()
        XCTAssertEqual(UI.targets, [3]); XCTAssertEqual(UI.shareJourneyResults.first?.retryCount, "1")
        XCTAssertEqual(UI.shareJourneyResults.first?.lastBlocker, "insufficient_balance")
        XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "open_payment_confirmation", "confirm_payment", "blocked", "open_top_up", "retry", "open_payment_confirmation", "confirm_payment", "submit", "accepted"])
    }
    func testShareRecoveryPremiumGateThenDirectRecipientCountsOneRetry() {
        let picker = recoveryPicker()
        account.account.postbox.delayed = true
        picker.showPremiumRequired(3); picker.showPremiumRequired(3)
        account.account.postbox.flush(); account.account.postbox.delayed = false
        picker.selectRecipient(3, threadId: nil)
        XCTAssertEqual(UI.shareJourneyResults.first?.lastBlocker, "premium_required")
        XCTAssertEqual(UI.shareJourneyResults.first?.retryCount, "1")
        XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "blocked", "retry", "submit", "accepted"])
    }
    func testShareRecoveryPrivateMixedTargetsEraseEarlierBlocker() {
        paidPeer(slow: true); let picker = recoveryPicker(comment: "comment")
        _ = picker.invoke(); drainMain()
        picker.selectInteractions.presentation.selected = [3, -1]
        picker.selectInteractions.presentation.peers[-1] = account.account.postbox.value.peers[-1]!
        UI.onConfirmation = { self.assertPrivate() }
        picker.contextChatInteraction.state.interface.input.inputText = ""
        _ = picker.invoke(); drainMain(); UI.confirmations[0].1(); drainMain(); picker.close()
        XCTAssertTrue(UI.targets.isEmpty); XCTAssertEqual(picker.analyticsShareJourney?.retainedStateCount, 0); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
    }
    func testShareRecoverySecretOriginHasNoPaymentOrRetryTelemetry() {
        paidPeer(); let picker = recoveryPicker(inherited: origin(.excluded))
        _ = picker.invoke(); drainMain(); UI.confirmations[0].1(); drainMain()
        _ = picker.invoke(); drainMain(); UI.confirmations[1].0(0); drainMain()
        XCTAssertEqual(UI.targets, [3]); XCTAssertTrue(UI.shareJourneyResults.isEmpty); XCTAssertEqual(picker.analyticsShareJourney?.retainedStateCount, 0)
    }
}

extension ForwardObjectTests {
    func ownContactArguments(peerId: PeerId = 3, inherited: AnalyticsContext? = nil) -> ProfileContactArguments {
        account.account.postbox.value.peers[1] = TelegramUser(1)
        return ProfileContactArguments(context: account, peerId: peerId, origin: inherited ?? origin())
    }
    func testOwnContactExplicitConfirmationProducesOneAcceptedSend() {
        let arguments = ownContactArguments(); UI.sendResult = .single([sourceId])
        arguments.shareMyInfo(); arguments.shareMyInfo(); drainMain()
        XCTAssertEqual(UI.confirmations.count, 1); XCTAssertTrue(UI.sentMessages.isEmpty)
        UI.confirmations[0].0(0); UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(UI.sentMessages.count, 1); XCTAssertEqual(UI.sentMessages.first?.0, 3)
        XCTAssertEqual(UI.ownContacts.first?.0, "first"); XCTAssertEqual(UI.ownContacts.first?.1, "last"); XCTAssertEqual(UI.ownContacts.first?.2, "phone"); XCTAssertEqual(UI.ownContacts.first?.3, 1)
        XCTAssertEqual(UI.ownContactResults.count, 1); XCTAssertEqual(UI.ownContactResults.first?.outcome, "success")
        XCTAssertEqual(UI.ownContactResults.first?.steps, ["request", "target_ready", "open_confirmation", "confirm", "source_ready", "submit", "accepted"])
    }
    func testOwnContactExplicitCancelIgnoresLateSuccessAndAllowsNewTask() {
        let arguments = ownContactArguments(); arguments.shareMyInfo(); drainMain()
        UI.confirmations[0].1(); UI.confirmations[0].0(0); drainMain()
        XCTAssertTrue(UI.sentMessages.isEmpty); XCTAssertEqual(UI.ownContactResults.first?.outcome, "cancelled"); XCTAssertNil(UI.ownContactResults.first?.result)
        XCTAssertEqual(UI.ownContactResults.first?.steps, ["request", "target_ready", "open_confirmation", "cancel"])
        arguments.shareMyInfo(); drainMain(); XCTAssertEqual(UI.confirmations.count, 2)
        UI.confirmations[0].2(); drainMain(); UI.sendResult = .single([sourceId]); UI.confirmations[1].0(0); drainMain()
        XCTAssertEqual(UI.sentMessages.count, 1); XCTAssertEqual(UI.ownContactResults.count, 2)
    }
    func testOwnContactUnknownDismissalDoesNotBecomeCancellation() {
        let arguments = ownContactArguments(); arguments.shareMyInfo(); drainMain()
        UI.confirmations[0].2(); drainMain(); UI.confirmations[0].0(0); drainMain()
        XCTAssertTrue(UI.sentMessages.isEmpty); XCTAssertTrue(UI.ownContactResults.isEmpty)
        arguments.shareMyInfo(); drainMain(); XCTAssertEqual(UI.confirmations.count, 2)
    }
    func testOwnContactOwnerReleaseCancelsMetadataAndConfirmation() {
        for phase in 0..<3 {
            UI.reset(); account.account.postbox.delayed = phase == 0
            var arguments: ProfileContactArguments? = ownContactArguments()
            arguments?.shareMyInfo(); drainMain()
            if phase == 2 { account.account.postbox.delayed = true; UI.confirmations[0].0(0); drainMain() }
            weak var weakArguments = arguments; arguments = nil
            XCTAssertNil(weakArguments)
            account.account.postbox.flush(); UI.confirmations.first?.0(0); drainMain()
            XCTAssertTrue(UI.sentMessages.isEmpty); XCTAssertTrue(UI.ownContactResults.isEmpty)
            account.account.postbox.delayed = false
        }
    }
    func testOwnContactSwitchingToContactPickerInvalidatesConfirmation() {
        let arguments = ownContactArguments(); arguments.shareMyInfo(); drainMain()
        account.account.postbox.contactResult = .single(TelegramUser(3)); arguments.shareContact(); drainMain()
        UI.confirmations[0].0(0); drainMain()
        XCTAssertTrue(UI.sentMessages.isEmpty); XCTAssertTrue(UI.ownContactResults.isEmpty); XCTAssertEqual(UI.presented.count, 1)
    }
    func testOwnContactMissingTargetAndInvalidOwnMetadataAreDistinct() {
        let arguments = ownContactArguments(); account.account.postbox.value.peers[3] = nil
        arguments.shareMyInfo(); drainMain()
        XCTAssertTrue(UI.confirmations.isEmpty); XCTAssertEqual(UI.ownContactResults.first?.result, "target_unavailable")
        for peer: Peer? in [nil, Peer(1), TelegramUser(2)] {
            UI.reset(); account.account.postbox.value.peers[3] = Peer(3); account.account.postbox.value.peers[1] = peer
            arguments.shareMyInfo(); drainMain(); UI.confirmations[0].0(0); drainMain()
            XCTAssertTrue(UI.sentMessages.isEmpty); XCTAssertEqual(UI.ownContactResults.first?.result, "source_unavailable")
        }
    }
    func testOwnContactRejectedMalformedAndEmptyResultsAreConservative() {
        for (result, expected): (Signal<[MessageId?], NoError>, String) in [(.single([nil]), "rejected"), (.single([]), "acceptance_unknown"), (.single([sourceId, sourceId]), "acceptance_unknown"), (.complete(), "acceptance_unknown")] {
            UI.reset(); let arguments = ownContactArguments(); UI.sendResult = result
            arguments.shareMyInfo(); drainMain(); UI.confirmations[0].0(0); drainMain()
            XCTAssertEqual(UI.ownContactResults.count, 1); XCTAssertEqual(UI.ownContactResults.first?.result, expected); XCTAssertEqual(UI.ownContactResults.first?.outcome, "fail")
        }
    }
    func testOwnContactOwnerReleaseDisposesSendAndDropsLateResult() {
        var arguments: ProfileContactArguments? = ownContactArguments(), subscriber: Subscriber<[MessageId?], NoError>?
        var disposed = 0
        UI.sendResult = Signal { subscriber = $0; return ActionDisposable { disposed += 1 } }
        arguments?.shareMyInfo(); drainMain(); UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(UI.sentMessages.count, 1); XCTAssertTrue(UI.ownContactResults.isEmpty)
        arguments = nil; XCTAssertEqual(disposed, 1); subscriber?.putNext([sourceId]); subscriber?.putCompletion(); drainMain(); subscriber = nil
        XCTAssertTrue(UI.ownContactResults.isEmpty)
    }
    func testOwnContactPrivateSourceTargetAndReturnedPeerStayExcluded() {
        for phase in 0..<3 {
            UI.reset()
            let arguments = ownContactArguments(peerId: phase == 1 ? -1 : 3, inherited: phase == 0 ? origin(.excluded) : origin())
            if phase == 2 { account.account.postbox.value.peers[3] = Peer(-1) }
            if phase < 2 { account.account.postbox.onSetup = { self.assertPrivate() } }
            UI.onConfirmation = { self.assertPrivate() }; UI.onSendSetup = { self.assertPrivate() }; UI.onProgress = { self.assertPrivate() }
            UI.sendResult = .single([sourceId]); arguments.shareMyInfo(); drainMain(); UI.confirmations[0].0(0); drainMain()
            XCTAssertEqual(UI.sentMessages.count, 1); XCTAssertTrue(UI.ownContactResults.isEmpty)
            UI.confirmations = []; drainMain(); account.account.postbox.onSetup = nil; account.account.postbox.value.peers[3] = Peer(3)
        }
    }
    func testOwnContactUnknownAndRevokedOriginsDoNotRefreshAtConfirmation() {
        for phase in 0..<3 {
            UI.reset(); let arguments = ownContactArguments(inherited: phase == 0 ? hub.unresolvedContext() : origin())
            arguments.shareMyInfo(); drainMain()
            if phase == 1 { hub.policy.isEnabled = false; hub.policy.isEnabled = true }
            if phase == 2 { hub.policy.setOwner(NSObject()) }
            UI.sendResult = .single([sourceId]); UI.onSendSetup = { self.assertPrivate() }; UI.confirmations[0].0(0); drainMain()
            XCTAssertEqual(UI.sentMessages.count, 1); XCTAssertTrue(UI.ownContactResults.isEmpty)
            UI.confirmations = []; drainMain()
        }
    }
    func testOwnContactResetDuringRequestConstructionPreventsSubscription() {
        let arguments = ownContactArguments(); var subscriptions = 0
        account.account.postbox.onSetup = { arguments.ownContactShareAction.reset() }
        account.account.postbox.onSubscription = { subscriptions += 1 }
        arguments.shareMyInfo(); drainMain()
        XCTAssertEqual(subscriptions, 0); XCTAssertTrue(UI.confirmations.isEmpty); XCTAssertTrue(UI.ownContactResults.isEmpty)
    }
    func testOwnContactResetDuringProgressConstructionPreventsSendSubscription() {
        let arguments = ownContactArguments(); var subscriptions = 0
        UI.sendResult = Signal { _ in subscriptions += 1; return EmptyDisposable }
        UI.onProgress = { arguments.ownContactShareAction.reset() }
        arguments.shareMyInfo(); drainMain(); UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(subscriptions, 0); XCTAssertTrue(UI.ownContactResults.isEmpty)
    }
}


extension ForwardObjectTests {
    func testOwnContactProgressDismissalDiscardsAndReleasesAdmission() {
        let arguments = ownContactArguments(); UI.cancellableProgress = true
        var subscriber: Subscriber<[MessageId?], NoError>?, disposed = 0
        UI.sendResult = Signal { subscriber = $0; return ActionDisposable { disposed += 1 } }
        arguments.shareMyInfo(); drainMain(); UI.confirmations[0].0(0); drainMain()
        XCTAssertEqual(UI.cancelProgress.count, 1); UI.cancelProgress[0](); drainMain()
        XCTAssertEqual(disposed, 1); subscriber?.putNext([sourceId]); subscriber?.putCompletion(); subscriber = nil; drainMain()
        XCTAssertTrue(UI.ownContactResults.isEmpty)
        arguments.shareMyInfo(); drainMain(); XCTAssertEqual(UI.confirmations.count, 2)
        UI.sendResult = .single([sourceId]); UI.confirmations[1].0(0); drainMain()
        XCTAssertEqual(UI.ownContactResults.count, 1); XCTAssertEqual(UI.ownContactResults.first?.result, "accepted")
    }
}


class GalleryMedia { var isVideoFile: Bool { false }; var isGraphicFile: Bool { false } }
final class TelegramMediaImage: GalleryMedia {}
final class Control {}
enum MenuAnimation { case menu_share, menu_forward, menu_more; var value: Int { 1 } }
let darkPalette = 1
enum GalleryMenuPresentation { case current(Int) }
class ContextMenuItem {
    let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void, itemImage: Int) { self.handler = handler }
}
final class ContextMenu {
    var items: [ContextMenuItem] = []
    init(presentation: GalleryMenuPresentation = .current(1), betterInside: Bool = false) {}
    func addItem(_ item: ContextMenuItem) { items.append(item) }
}
enum AppMenu { static var menu: ContextMenu?; static func show(menu: ContextMenu, event: Int, for control: Control) { self.menu = menu } }
final class GalleryApplication { var currentEvent: Int? = 1 }
let NSApp = GalleryApplication()
struct GalleryEntry { var message: Message? }
final class GalleryItem { var entry: GalleryEntry; init(_ message: Message?) { entry = GalleryEntry(message: message) } }
final class GalleryThumbs { var items: [GalleryItem] = [] }
final class GalleryPager { var selectedItem: GalleryItem?; let thumbsControl = GalleryThumbs() }
enum GalleryAppearType { case alone, history, profile(PeerId), secret, recentDownloaded, messages([Message]) }
enum ChatGalleryAppearType { case alone, history, profile(PeerId), secret, recentDownloaded, messages([Message]) }
enum ChatMode { case history }
protocol InteractionContentViewProtocol {}
protocol GalleryContentInteractions {}
final class ChatMediaLayoutParameters: GalleryContentInteractions {}
final class CachedPeerData {}
final class ChatLocationContextHolder {}
__GALLERY_TYPE__
__GALLERY_ORIGIN__
var viewer: GalleryViewer?
final class GalleryViewer {
    let context: any AccountContextProtocol
    let analyticsOrigin: GalleryAnalyticsContext
    var presentationGeneration = 0
    let pager = GalleryPager()
    let window = Window()
    init(context: any AccountContextProtocol, message: Message, _ delegate: InteractionContentViewProtocol? = nil, _ contentInteractions: (any GalleryContentInteractions)? = nil, type: GalleryAppearType = .history, reversed: Bool = false, chatMode: ChatMode?, chatLocation: ChatLocation?, contextHolder: Atomic<ChatLocationContextHolder?> = Atomic(value: nil), cachedPeerData: CachedPeerData? = nil, analyticsContext: AnalyticsContext? = nil) {
        let analyticsMessages = [message]
__GALLERY_INIT_ORIGIN__
        self.context = context
        UI.onGalleryChildren?()
        pager.selectedItem = GalleryItem(message)
    }
__GALLERY_SHOW__
__GALLERY_SHARE__
__GALLERY_SELECTION_SCOPE__
    func updateMessageSelection(_ current: GalleryEntry) {
__GALLERY_MESSAGE_SCOPE__
    }
    func clean() { analyticsOrigin.end() }
    func close() { analyticsOrigin.end(); if viewer === self { viewer = nil } }
}
__GALLERY_OPEN__
struct GalleryHooks {
__GALLERY_SHARE_HOOK__
    static var shared = GalleryHooks(showShare: { _, _, _, _ in })
}
struct ChatNavigationHooks {
    var makeDateSelector: (any AccountContextProtocol, Date?, Int32?, ChatDateSelectorMode, @escaping (Date, Int32?) -> Void, TextViewLayout?) -> ModalViewController = { _, _, _, _, _, _ in ModalViewController() }
__CHAT_GALLERY_HOOK__
    static var shared = ChatNavigationHooks()
}
__CHAT_GALLERY_OPEN__
func installGalleryShare() {
    var hooks = GalleryHooks(showShare: { _, _, _, _ in })
__GALLERY_SHARE_INSTALL__
    GalleryHooks.shared = hooks
}
func installChatGallery() {
    var hooks = ChatNavigationHooks()
__CHAT_GALLERY_INSTALL__
    ChatNavigationHooks.shared = hooks
}

final class GalleryScreenTracker {
    func showStandalone(_ screen: AnalyticsScreen, owner: AnyObject, context: AnalyticsContext?) { UI.galleryScreenContexts.append(context) }
}

extension ForwardObjectTests {
    @discardableResult
    func chatGallery(_ message: Message? = nil, origin inherited: AnalyticsContext? = nil, type: ChatGalleryAppearType = .history, location: ChatLocation? = .peer(3)) -> GalleryViewer {
        installGalleryShare(); installChatGallery()
        openChatGallery(context: account, message: message ?? Message(id: sourceId), type: type, chatMode: .history, chatLocation: location, analyticsContext: inherited ?? origin())
        return viewer!
    }
    func testGalleryShareChatOriginReachesConstructionPickerAndOutcome() {
        let captured = origin()
        UI.onGalleryChildren = { XCTAssertFalse(self.hub.policy.hasExclusions); XCTAssertTrue(self.hub.policy.accepts(captured.scope)) }
        let gallery = chatGallery(origin: captured)
        XCTAssertTrue(gallery.analyticsOrigin.context.scope === captured.scope)
        UI.onEmoji = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        gallery.share(Control()); let picker = UI.presented.last as? ShareModalController
        XCTAssertTrue(picker?.analyticsContext?.scope === captured.scope)
        UI.sendResult = .single([sourceId]); picker?.selectRecipient(3, threadId: nil)
        XCTAssertEqual(UI.shareJourneyResults.first?.entry, "gallery_selection"); XCTAssertEqual(UI.shareJourneyResults.first?.source, .mediaViewer)
        XCTAssertEqual(UI.shareJourneyResults.first?.steps, ["request", "open_picker", "submit", "accepted"])
        gallery.close()
    }
    func testGalleryShareMenuConstructionIsNotIntentAndChoicesStayDistinct() {
        for all in [false, true] {
            UI.reset(); var message = Message(id: sourceId); message.groupInfo = true
            let gallery = chatGallery(message); gallery.pager.thumbsControl.items = [GalleryItem(message), GalleryItem(Message(id: MessageId(peerId: 2, id: 2)))]
            gallery.share(Control())
            XCTAssertEqual(UI.shareJourneyStarts, 0); XCTAssertTrue(UI.presented.isEmpty); XCTAssertEqual(AppMenu.menu?.items.count, 2)
            AppMenu.menu?.items[all ? 1 : 0].handler()
            UI.sendResult = .single(all ? [sourceId, MessageId(peerId: 3, id: 2)] : [sourceId])
            (UI.presented.last as? ShareModalController)?.selectRecipient(3, threadId: nil)
            XCTAssertEqual(UI.shareJourneyResults.count, 1); XCTAssertEqual(UI.shareJourneyResults.first?.entry, all ? "gallery_group" : "gallery_selection")
            XCTAssertEqual(UI.forwarded.first?.count, all ? 2 : 1)
            gallery.close()
        }
    }
    func testGalleryShareLegacyEntryNeverInfersOriginFromMessage() {
        installGalleryShare(); UI.onGalleryChildren = { self.assertPrivate() }
        openGallery(context: account, message: Message(id: sourceId), chatMode: nil, chatLocation: .peer(3))
        let gallery = viewer!; UI.onEmoji = { self.assertPrivate() }; gallery.share(Control())
        UI.sendResult = .single([sourceId]); (UI.presented.last as? ShareModalController)?.selectRecipient(3, threadId: nil)
        XCTAssertEqual(UI.forwarded.count, 1); XCTAssertTrue(UI.shareJourneyResults.isEmpty); gallery.close()
    }
    func testGalleryShareSensitiveInputsExcludeBeforeChildConstruction() {
        for phase in 0..<6 {
            UI.reset(); var message = Message(id: sourceId)
            if phase == 0 { message.containsSecretMedia = true }
            let type: ChatGalleryAppearType = phase == 1 ? .secret : phase == 2 ? .messages([Message(id: MessageId(peerId: -1, id: 4))]) : phase == 3 ? .profile(-1) : .history
            UI.onGalleryChildren = { self.assertPrivate() }
            let gallery = chatGallery(message, origin: phase == 5 ? origin(.excluded) : origin(), type: type, location: phase == 4 ? .peer(-1) : .peer(3))
            UI.onEmoji = { self.assertPrivate() }; gallery.share(Control()); (UI.presented.last as? ShareModalController)?.close()
            XCTAssertTrue(UI.shareJourneyResults.isEmpty); gallery.close(); UI.presented = []; drainMain()
        }
    }
    func testGalleryShareReturnedPrivateSelectionIsStickyUntilGalleryEnds() {
        let gallery = chatGallery()
        gallery.updateMessageSelection(GalleryEntry(message: Message(id: MessageId(peerId: -1, id: 4))))
        assertPrivate(); gallery.updateMessageSelection(GalleryEntry(message: Message(id: sourceId))); assertPrivate()
        XCTAssertTrue(UI.galleryScreenContexts.last??.isExcluded == true)
        gallery.share(Control()); (UI.presented.last as? ShareModalController)?.close()
        XCTAssertTrue(UI.shareJourneyResults.isEmpty); UI.presented = []; gallery.close(); drainMain()
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testGalleryShareSelectedSecretMediaRevokesExistingOrigin() {
        let captured = origin(), gallery = chatGallery()
        var message = Message(id: sourceId); message.containsSecretMedia = true
        gallery.updateMessageSelection(GalleryEntry(message: message)); assertPrivate()
        XCTAssertFalse(hub.policy.accepts(captured.scope)); gallery.close()
    }
    func testGalleryShareWholeGroupIsRestrictedAtChoiceBeforePicker() {
        var message = Message(id: sourceId); message.groupInfo = true
        let gallery = chatGallery(message)
        gallery.pager.thumbsControl.items = [GalleryItem(message), GalleryItem(Message(id: MessageId(peerId: -1, id: 4)))]
        gallery.share(Control()); UI.onEmoji = { self.assertPrivate() }; AppMenu.menu?.items[1].handler()
        (UI.presented.last as? ShareModalController)?.close()
        assertPrivate()
        XCTAssertTrue(gallery.analyticsOrigin.context.isExcluded)
        XCTAssertTrue(UI.shareJourneyResults.isEmpty); gallery.close()
    }
    func testGalleryShareClosedOrReplacedMenuCannotOpenPicker() {
        var message = Message(id: sourceId); message.groupInfo = true
        let gallery = chatGallery(message); gallery.pager.thumbsControl.items = [GalleryItem(message)]; gallery.share(Control())
        let item = AppMenu.menu?.items.first; gallery.close(); _ = chatGallery()
        item?.handler(); gallery.share(Control())
        XCTAssertTrue(UI.presented.isEmpty); XCTAssertEqual(UI.shareJourneyStarts, 0); viewer?.close()
    }
    func testGalleryShareReopenedSameOwnerRejectsEarlierMenuGeneration() {
        var message = Message(id: sourceId); message.groupInfo = true
        let gallery = chatGallery(message); gallery.pager.thumbsControl.items = [GalleryItem(message)]; gallery.share(Control())
        let item = AppMenu.menu?.items.first; gallery.close(); gallery.show(); item?.handler()
        XCTAssertTrue(UI.presented.isEmpty); XCTAssertEqual(UI.shareJourneyStarts, 0); gallery.close()
    }
    func testGalleryShareRevokedMenuDoesNotCreateFreshGrant() {
        var message = Message(id: sourceId); message.groupInfo = true
        let gallery = chatGallery(message); gallery.pager.thumbsControl.items = [GalleryItem(message)]; gallery.share(Control())
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        UI.onEmoji = { self.assertPrivate() }; AppMenu.menu?.items[0].handler()
        (UI.presented.last as? ShareModalController)?.close(); XCTAssertTrue(UI.shareJourneyResults.isEmpty); gallery.close()
    }
    func testGalleryShareForeignOriginRemainsExcluded() {
        let foreign = Analytics(); foreign.policy.setOwner(account.engine.account); foreign.policy.isEnabled = true
        let captured = foreign.captureContext(engine: account.engine, peerId: 3)
        UI.onGalleryChildren = { self.assertPrivate() }; let gallery = chatGallery(origin: captured)
        gallery.share(Control()); (UI.presented.last as? ShareModalController)?.close()
        XCTAssertTrue(UI.shareJourneyResults.isEmpty); gallery.close()
    }
    func testGalleryShareLegacyHookRunsUnderRestrictedWholeGroup() {
        var calls = 0
        GalleryHooks.shared = GalleryHooks(showShare: { _, _, _, _ in calls += 1; self.assertPrivate() })
        GalleryHooks.shared.showShareObserved(account, Message(id: sourceId), [Message(id: MessageId(peerId: -1, id: 4))], account.window, analyticsContext: origin())
        XCTAssertEqual(calls, 1)
    }
    func testGalleryShareLegacyChatHookReceivesPrivateProfileRestriction() {
        var calls = 0; var hooks = ChatNavigationHooks()
        hooks.showChatGallery = { _, _, _, _, _, _, _, _, _, _ in calls += 1; self.assertPrivate() }
        ChatNavigationHooks.shared = hooks
        openChatGallery(context: account, message: Message(id: sourceId), type: .profile(-1), chatMode: nil, chatLocation: nil, analyticsContext: origin())
        XCTAssertEqual(calls, 1)
    }
    func testGalleryShareWithoutSelectedMessageDoesNotStartTask() {
        let gallery = chatGallery(); gallery.pager.selectedItem = nil; gallery.share(Control())
        XCTAssertEqual(UI.shareJourneyStarts, 0); XCTAssertTrue(UI.presented.isEmpty); gallery.close()
    }
}


__QUICK_FORWARD_PROTOCOL__
__QUICK_FORWARD_BRIDGE__
__QUICK_FORWARD_ACTION__
__FORWARD_MENU_ACTION__
__QUICK_FORWARD_TOKEN__
struct QuickMenuData { let message: Message; let chatInteraction: ChatInteraction }
extension String { func prefixWithDots(_ count: Int) -> String { String(prefix(count)) } }
enum QuickForwardDestination {
    case forward(callback: (PeerId, Int64?) -> Void, canSelect: (Peer) -> Bool)
    func select(_ peerId: PeerId, threadId: Int64?) { if case let .forward(callback, _) = self { callback(peerId, threadId) } }
    func permits(_ peer: Peer) -> Bool { switch self { case let .forward(_, canSelect): return canSelect(peer) } }
}
final class ReactionPeerMenu: ContextMenuItem {
    let destination: QuickForwardDestination
    init(title: String, handler: @escaping () -> Void, peer: Peer, context: any AccountContextProtocol, reaction: Int?, message: Message, destination: QuickForwardDestination) {
        self.destination = destination; super.init(title, handler: handler, itemImage: 0)
    }
}
func forwardingMenuItems(interaction chatInteraction: ChatInteraction, message: Message, group: [Message]? = nil, target: Peer) -> (main: ContextMenuItem, more: ContextMenuItem, quick: ReactionPeerMenu) {
    let data = QuickMenuData(message: message, chatInteraction: chatInteraction), context = chatInteraction.interactionContext
    let msgs = group ?? [message], useGroupIfNeeded = group != nil
__QUICK_FORWARD_MENU_SETUP__
__QUICK_FORWARD_MENU_ITEM__
__MENU_FORWARD_MORE__
    return (forwardItem, more, makeItem(target) as! ReactionPeerMenu)
}
func quickForwardMenuItem(interaction: ChatInteraction, message: Message, group: [Message]? = nil, target: Peer) -> ReactionPeerMenu {
    forwardingMenuItems(interaction: interaction, message: message, group: group, target: target).quick
}
func replacementForwardMenuItem(interaction chatInteraction: ChatInteraction, source: Message, replacementMessage: Message) -> ContextMenuItem {
    let data = QuickMenuData(message: source, chatInteraction: chatInteraction)
    var items: [ContextMenuItem] = []
__MENU_FORWARD_REPLACEMENT__
    return items[0]
}

final class LegacyQuickForward: ChatHistoryForwardMessagesObject {
    var calls = 0
    func chatHistoryPerform(to peerIds: [PeerId], threadId: Int64?) -> Signal<Never, String> { calls += 1; return .complete() }
    func possibilityPerformTo(_ peer: Peer) -> Bool { true }
}
extension ForwardObjectTests {
    func quickInteraction(_ inherited: AnalyticsContext? = nil, messages: [Message]? = nil) -> ChatInteraction {
        let interaction = ChatInteraction(chatLocation: .peer(3), context: account)
        interaction.inheritedAnalyticsContext = inherited ?? origin()
        let values = messages ?? [Message(id: sourceId)]
        interaction.getMessages = { _, _ in .single(values) }
        return interaction
    }
    func quickItem(_ interaction: ChatInteraction, target: PeerId = 3, group: [Message]? = nil) -> ReactionPeerMenu {
        quickForwardMenuItem(interaction: interaction, message: Message(id: sourceId), group: group, target: account.account.postbox.value.peers[target]!)
    }
    func testQuickForwardAppBridgePreservesTheExactOriginBeforeDispatch() {
        let hooks = installedHistoryHooks()
        XCTAssertNotNil(hooks.makeForwardMessagesObjectWithContext)
        let source = origin()
        let object = hooks.makeForwardMessagesObjectObserved(account, [Message(id: sourceId)], false, nil, analyticsContext: source) as? ForwardMessagesObject
        XCTAssertNotNil(object)
        XCTAssertTrue(object?.forwardingAnalyticsContext.scope === source.scope)
        XCTAssertTrue(hub.policy.accepts(object?.forwardingAnalyticsContext.scope))
        XCTAssertEqual(UI.quickForwardStarts, 0)
        XCTAssertTrue(UI.targets.isEmpty)
    }
    func testQuickForwardMenuAndPermissionChecksDoNotStartJourney() {
        let interaction = quickInteraction(), item = quickItem(interaction)
        XCTAssertTrue(item.destination.permits(Peer(3))); let community = Peer(4); community.isCommunity = true
        XCTAssertFalse(item.destination.permits(community)); XCTAssertEqual(UI.quickForwardStarts, 0); XCTAssertTrue(UI.targets.isEmpty)
        XCTAssertTrue(UI.quickForwardResults.isEmpty); interaction.quickForwardAction.reset()
    }
    func testQuickForwardExistingChatReportsDraftPreparedWithoutSending() {
        let interaction = quickInteraction(), destination = ChatController(account, .peer(3))
        account.bindings.navigation.controllers = [destination]
        let item = quickItem(interaction); item.handler(); item.handler(); drainMain()
        XCTAssertEqual(destination.chatInteraction.state.interface.ids, [sourceId]); XCTAssertTrue(UI.targets.isEmpty)
        XCTAssertEqual(UI.quickForwardStarts, 1); XCTAssertEqual(UI.quickForwardResults.count, 1)
        XCTAssertEqual(UI.quickForwardResults.first?.entry, "direct_target"); XCTAssertEqual(UI.quickForwardResults.first?.result, "draft_prepared")
        XCTAssertEqual(UI.quickForwardResults.first?.steps, ["request", "draft_prepared"])
    }
    func testQuickForwardNewChatWaitsForReadinessAndCoalescesPendingTargets() {
        let interaction = quickInteraction(); let first = quickItem(interaction), second = quickItem(interaction, target: 2)
        first.handler(); second.handler(); drainMain()
        XCTAssertEqual(UI.additionalChats, 1); XCTAssertTrue(UI.quickForwardResults.isEmpty); XCTAssertEqual(UI.quickForwardStarts, 1)
        account.bindings.navigation.controller?.ready.set(true); drainMain()
        XCTAssertEqual(UI.quickForwardResults.first?.result, "destination_ready"); XCTAssertTrue(UI.targets.isEmpty)
    }
    func testQuickForwardTopicChoiceUsesTopicRouteAfterReady() {
        let interaction = quickInteraction(); var ready: Subscriber<Bool, NoError>?
        UI.forumResult = Signal { ready = $0; return EmptyDisposable }
        let parent = Peer(4); parent.isCommunity = true
        let item = quickForwardMenuItem(interaction: interaction, message: Message(id: sourceId), target: parent)
        item.handler(); XCTAssertEqual(UI.quickForwardStarts, 0)
        item.destination.select(3, threadId: 42); ready?.putNext(false); drainMain()
        XCTAssertTrue(UI.quickForwardResults.isEmpty); ready?.putNext(true); ready?.putNext(true); ready = nil; drainMain()
        XCTAssertEqual(UI.quickForwardResults.count, 1); XCTAssertEqual(UI.quickForwardResults.first?.entry, "topic_target"); XCTAssertEqual(UI.quickForwardResults.first?.result, "destination_ready")
        XCTAssertTrue(UI.targets.isEmpty)
    }
    func testQuickForwardSavedMessagesWaitsForActualAcceptance() {
        let interaction = quickInteraction(); var subscriber: Subscriber<[MessageId?], NoError>?
        UI.sendResult = Signal { subscriber = $0; return EmptyDisposable }
        quickItem(interaction, target: 1).handler(); drainMain()
        XCTAssertEqual(UI.targets, [1]); XCTAssertTrue(UI.quickForwardResults.isEmpty); XCTAssertTrue(UI.delayed.isEmpty)
        subscriber?.putNext([sourceId]); subscriber?.putNext([sourceId]); subscriber = nil; drainMain()
        XCTAssertEqual(UI.quickForwardResults.count, 1); XCTAssertEqual(UI.quickForwardResults.first?.result, "accepted"); XCTAssertEqual(UI.delayed.count, 1)
    }
    func testQuickForwardSavedPartialRejectedAndUnknownStayDistinct() {
        let group = [Message(id: sourceId), Message(id: MessageId(peerId: 2, id: 2))]
        for (signal, result): (Signal<[MessageId?], NoError>, String) in [(.single([sourceId, nil]), "partially_accepted"), (.single([nil, nil]), "rejected"), (.single([sourceId]), "acceptance_unknown"), (.complete(), "acceptance_unknown")] {
            UI.reset(); let interaction = quickInteraction(messages: group); UI.sendResult = signal
            quickItem(interaction, target: 1, group: group).handler(); drainMain()
            XCTAssertEqual(UI.quickForwardResults.count, 1); XCTAssertEqual(UI.quickForwardResults.first?.result, result); XCTAssertEqual(UI.quickForwardResults.first?.outcome, "fail")
            XCTAssertTrue(UI.delayed.isEmpty)
        }
    }
    func testQuickForwardSourceTargetAndPollFailuresAreSeparate() {
        for result in ["source_unavailable", "target_unavailable", "restricted"] {
            UI.reset(); account.account.postbox.value.peers[3] = Peer(3)
            let interaction = quickInteraction(messages: result == "source_unavailable" ? [] : [Message(id: sourceId, isPublicPoll: result == "restricted")])
            let item = quickItem(interaction)
            if result == "target_unavailable" { account.account.postbox.value.peers[3] = nil }
            if result == "restricted" { account.account.postbox.value.peers[3]?.isChannel = true }
            item.handler(); drainMain()
            XCTAssertEqual(UI.quickForwardResults.first?.result, result); XCTAssertTrue(UI.targets.isEmpty); XCTAssertEqual(UI.additionalChats, 0)
        }
    }
    func testQuickForwardResetCancelsMetadataAndSuppressesLateNavigation() {
        let interaction = quickInteraction(); account.account.postbox.delayed = true
        var disposed = 0; account.account.postbox.onDispose = { disposed += 1 }
        quickItem(interaction).handler(); interaction.quickForwardAction.reset(); account.account.postbox.flush(); drainMain()
        XCTAssertGreaterThan(disposed, 0); XCTAssertEqual(UI.additionalChats, 0); XCTAssertTrue(UI.quickForwardResults.isEmpty)
    }
    func testQuickForwardResetCancelsSavedEnqueueWithoutInventingResult() {
        let interaction = quickInteraction(); var subscriber: Subscriber<[MessageId?], NoError>?, disposed = 0
        UI.sendResult = Signal { subscriber = $0; return ActionDisposable { disposed += 1 } }
        quickItem(interaction, target: 1).handler(); drainMain(); interaction.quickForwardAction.reset()
        XCTAssertEqual(disposed, 1); subscriber?.putNext([sourceId]); subscriber?.putCompletion(); subscriber = nil; drainMain()
        XCTAssertTrue(UI.quickForwardResults.isEmpty); XCTAssertTrue(UI.delayed.isEmpty)
    }
    func testQuickForwardOwnerReleaseCancelsPendingAction() {
        var interaction: ChatInteraction? = quickInteraction(); var disposed = 0
        UI.sendResult = Signal { _ in ActionDisposable { disposed += 1 } }
        quickItem(interaction!, target: 1).handler(); drainMain()
        weak var weakInteraction = interaction; interaction = nil
        XCTAssertNil(weakInteraction); XCTAssertEqual(disposed, 1); XCTAssertTrue(UI.quickForwardResults.isEmpty)
    }
    func testQuickForwardStaleMenuTokenDoesNotSendOrStartFlow() {
        let interaction = quickInteraction(), stale = quickItem(interaction)
        interaction.quickMenuCurrent = false
        stale.handler()
        XCTAssertEqual(UI.quickForwardStarts, 0); XCTAssertTrue(UI.targets.isEmpty)
    }
    func testQuickForwardPrivateSourceTargetAndResolvedMessagesStayExcluded() {
        for phase in 0..<4 {
            UI.reset(); let messages = [Message(id: MessageId(peerId: phase == 2 ? -1 : 2, id: 1), containsSecretMedia: phase == 3)]
            let interaction = quickInteraction(phase == 0 ? origin(.excluded) : origin(), messages: messages)
            UI.onConstruct = { self.assertPrivate() }; UI.onPush = { _ in self.assertPrivate() }
            quickItem(interaction, target: phase == 1 ? -1 : 3).handler(); drainMain(); account.bindings.navigation.controller?.ready.set(true); drainMain()
            XCTAssertTrue(UI.quickForwardResults.isEmpty); interaction.quickForwardAction.reset(); account.bindings.navigation.controllers = []
        }
    }
    func testQuickForwardGroupProvenanceProtectsLookupBeforeResolution() {
        let interaction = quickInteraction(); interaction.getMessages = { _, _ in self.assertPrivate(); return .single([Message(id: self.sourceId)]) }
        UI.onConstruct = { self.assertPrivate() }
        quickItem(interaction, group: [Message(id: sourceId), Message(id: MessageId(peerId: -1, id: 4))]).handler(); drainMain()
        account.bindings.navigation.controller?.ready.set(true); drainMain(); XCTAssertTrue(UI.quickForwardResults.isEmpty)
    }
    func testQuickForwardRevokedContextNeverRefreshesOnMenuClick() {
        let interaction = quickInteraction()
        let clicked = quickItem(interaction, target: 1); hub.policy.isEnabled = false; hub.policy.isEnabled = true
        UI.onSendSetup = { self.assertPrivate() }; UI.sendResult = .single([sourceId]); clicked.handler(); drainMain()
        XCTAssertEqual(UI.targets, [1]); XCTAssertTrue(UI.quickForwardResults.isEmpty)
    }
    func testQuickForwardLegacyCompletionIsNotDraftOrSendAcceptance() {
        let legacy = LegacyQuickForward(), action = ChatQuickForwardAction()
        action.start(context: account, peerId: 3, threadId: nil, analyticsContext: origin(), isCurrent: { true }, request: { legacy.chatHistoryPerformObserved(to: 3, threadId: nil) })
        XCTAssertEqual(legacy.calls, 1); XCTAssertEqual(UI.quickForwardResults.first?.result, "completion_unknown")
    }
    func testQuickForwardResetDuringConstructionPreventsSubscription() {
        let action = ChatQuickForwardAction(); var subscriptions = 0
        action.start(context: account, peerId: 3, threadId: nil, analyticsContext: origin(), isCurrent: { true }, request: {
            action.reset(); return Signal { _ in subscriptions += 1; return EmptyDisposable }
        })
        XCTAssertEqual(subscriptions, 0); XCTAssertTrue(UI.quickForwardResults.isEmpty)
    }
    func testQuickForwardUnclassifiedErrorHasNoRawTextInResult() {
        let action = ChatQuickForwardAction()
        action.start(context: account, peerId: 3, threadId: nil, analyticsContext: origin(), isCurrent: { true }, request: { .fail("synthetic diagnostic") })
        XCTAssertEqual(UI.quickForwardResults.first?.result, "operation_failed")
        XCTAssertEqual(UI.quickForwardResults.first?.steps, ["request", "operation_failed"])
    }
}

extension ForwardObjectTests {
    func testQuickForwardDisabledAnalyticsStillPreparesDraft() {
        hub.policy.isEnabled = false
        let interaction = quickInteraction(), destination = ChatController(account, .peer(3))
        account.bindings.navigation.controllers = [destination]
        quickItem(interaction).handler(); drainMain()
        XCTAssertEqual(destination.chatInteraction.state.interface.ids, [sourceId]); XCTAssertTrue(UI.quickForwardResults.isEmpty); XCTAssertTrue(UI.targets.isEmpty)
    }
    func testQuickForwardLegacyFactoryStaysUnresolvedWithoutBreakingDraft() {
        ChatHistoryUIHooks.shared.makeForwardMessagesObjectWithContext = nil
        let interaction = quickInteraction(), destination = ChatController(account, .peer(3))
        account.bindings.navigation.controllers = [destination]; UI.onUpdate = { self.assertPrivate() }
        quickItem(interaction).handler(); drainMain()
        XCTAssertEqual(destination.chatInteraction.state.interface.ids, [sourceId]); XCTAssertTrue(UI.quickForwardResults.isEmpty)
    }
}

extension ForwardObjectTests {
    func testQuickForwardTopicChoiceDoesNotOverwriteOpenParentChatDraft() {
        let interaction = quickInteraction(), parent = ChatController(account, .peer(3))
        parent.chatInteraction.state.interface.ids = [MessageId(peerId: 3, id: 9)]
        account.bindings.navigation.controllers = [parent]
        var topics = 0; UI.onForum = { topics += 1 }
        quickItem(interaction).destination.select(3, threadId: 42); drainMain()
        XCTAssertEqual(topics, 1); XCTAssertEqual(parent.chatInteraction.state.interface.ids, [MessageId(peerId: 3, id: 9)])
        XCTAssertEqual(UI.quickForwardResults.first?.entry, "topic_target"); XCTAssertEqual(UI.quickForwardResults.first?.result, "destination_ready")
        XCTAssertTrue(UI.targets.isEmpty)
    }
}

extension ForwardObjectTests {
    func testForwardObjectKnownSecretMediaExcludesPickerBeforeLookup() {
        let messages = [Message(id: sourceId), Message(id: MessageId(peerId: 2, id: 2), containsSecretMedia: true)]
        let object = ForwardMessagesObject(account, messages: messages, analyticsContext: origin())
        XCTAssertTrue(object.forwardingAnalyticsContext.isExcluded)
        UI.onEmoji = { self.assertPrivate() }
        let modal = ShareModalController(object, analyticsContext: origin())
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
        XCTAssertTrue(modal.emoji.analyticsContext?.isExcluded == true)
        XCTAssertTrue(UI.inputOrigin?.isExcluded == true)
    }
}


extension ForwardObjectTests {
    func testInstalledSelectedForwardFactoryCannotRestoreSecretMediaPickerContext() {
        UI.onEmoji = { self.assertPrivate() }
        let modal = installedHooks().makeForwardMessagesShareModalObserved(account, [Message(id: sourceId, containsSecretMedia: true)], { _, _ in .complete() }, analyticsContext: origin()) as! ShareModalController
        XCTAssertTrue((modal.share as! ForwardMessagesObject).forwardingAnalyticsContext.isExcluded)
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
        XCTAssertTrue(modal.emoji.analyticsContext?.isExcluded == true)
        XCTAssertTrue(UI.inputOrigin?.isExcluded == true)
    }
}


extension ForwardObjectTests {
    func pickerMenuActions(_ interaction: ChatInteraction, source: Message? = nil) -> [ContextMenuItem] {
        let message = source ?? Message(id: sourceId)
        let menu = forwardingMenuItems(interaction: interaction, message: message, target: Peer(3))
        let replacement = replacementForwardMenuItem(interaction: interaction, source: message, replacementMessage: Message(id: sourceId))
        return [menu.main, menu.more, replacement]
    }
    func bindPickerMenu(_ interaction: ChatInteraction, callback: @escaping ([Message], AnalyticsContext) -> Void) {
        interaction.forwardMessages = { [weak interaction] messages in
            guard let interaction else { return }
            interaction.forwardMessagesObserved(messages, analyticsContext: interaction.captureAnalyticsContext())
        }
        interaction.forwardMessagesWithContext = callback
    }
    func testPickerMenuRetainsOriginalPrivateSourceAfterContextChanges() {
        for index in 0..<3 {
            let interaction = quickInteraction(origin(.excluded)); var calls = 0
            bindPickerMenu(interaction) { _, context in calls += 1; XCTAssertTrue(context.isExcluded); self.assertPrivate() }
            let item = pickerMenuActions(interaction)[index]
            interaction.inheritedAnalyticsContext = origin()
            item.handler(); XCTAssertEqual(calls, 1)
        }
    }
    func testPickerMenuStaleAndDuplicateCallbacksCannotOpenAnotherPicker() {
        for index in 0..<3 {
            let interaction = quickInteraction(); var calls = 0
            bindPickerMenu(interaction) { _, _ in calls += 1 }
            let stale = pickerMenuActions(interaction)[index]; interaction.quickMenuCurrent = false
            stale.handler(); XCTAssertEqual(calls, 0)
            interaction.quickMenuCurrent = true; stale.handler(); XCTAssertEqual(calls, 0)
            let fresh = pickerMenuActions(interaction)[index]; fresh.handler(); fresh.handler()
            XCTAssertEqual(calls, 1)
        }
    }
    func testPickerMenuMainMoreAndQuickTargetShareOneConsumedAction() {
        for quickFirst in [false, true] {
            let interaction = quickInteraction(); var calls = 0
            bindPickerMenu(interaction) { _, _ in calls += 1 }
            let destination = ChatController(account, .peer(3)); account.bindings.navigation.controllers = [destination]
            let menu = forwardingMenuItems(interaction: interaction, message: Message(id: sourceId), target: Peer(3))
            if quickFirst { menu.quick.handler() } else { menu.main.handler() }
            menu.more.handler(); menu.main.handler(); menu.quick.handler(); drainMain()
            XCTAssertEqual(calls, quickFirst ? 0 : 1)
            XCTAssertEqual(destination.chatInteraction.state.interface.ids, quickFirst ? [sourceId] : [])
        }
    }
    func testPickerReplacementRetainsSecretMediaSourceBeforeNormalization() {
        let interaction = quickInteraction(); var calls = 0
        bindPickerMenu(interaction) { messages, context in
            calls += 1; XCTAssertFalse(messages[0].containsSecretMedia); XCTAssertTrue(context.isExcluded); self.assertPrivate()
        }
        let item = replacementForwardMenuItem(interaction: interaction, source: Message(id: sourceId, containsSecretMedia: true), replacementMessage: Message(id: sourceId))
        item.handler(); XCTAssertEqual(calls, 1)
    }
}


extension ForwardObjectTests {
    func testPickerMenuOwnerReleaseLeavesCallbacksInert() {
        var interaction: ChatInteraction? = quickInteraction()
        var calls = 0
        bindPickerMenu(interaction!) { _, _ in calls += 1 }
        let items = pickerMenuActions(interaction!)
        weak var weakInteraction = interaction
        interaction = nil
        XCTAssertNil(weakInteraction)
        for item in items { item.handler() }
        XCTAssertEqual(calls, 0)
    }
    func testPickerMenuOrdinarySourceKeepsGrantAndOriginalMessages() {
        let source = origin(), interaction = quickInteraction()
        interaction.inheritedAnalyticsContext = source
        let messages = [Message(id: sourceId), Message(id: MessageId(peerId: 2, id: 8))]
        var received: [MessageId] = []
        bindPickerMenu(interaction) { values, context in received = values.map { $0.id }; XCTAssertTrue(context.scope === source.scope) }
        let menu = forwardingMenuItems(interaction: interaction, message: messages[0], group: messages, target: Peer(3))
        XCTAssertTrue(received.isEmpty); XCTAssertEqual(UI.quickForwardStarts, 0)
        menu.main.handler(); XCTAssertEqual(received, messages.map { $0.id }); XCTAssertEqual(UI.quickForwardStarts, 0)
    }
    func testPickerMenuPrivateGroupRestrictsMainAndMore() {
        for more in [false, true] {
            let interaction = quickInteraction(); var calls = 0
            bindPickerMenu(interaction) { _, context in calls += 1; XCTAssertTrue(context.isExcluded); self.assertPrivate() }
            let menu = forwardingMenuItems(interaction: interaction, message: Message(id: sourceId), group: [Message(id: sourceId), Message(id: MessageId(peerId: -1, id: 8))], target: Peer(3))
            (more ? menu.more : menu.main).handler(); XCTAssertEqual(calls, 1)
        }
    }
    func testPickerMenuRevokedContextAndDisabledAnalyticsKeepFunctionalAction() {
        for disable in [false, true] {
            let interaction = quickInteraction(); var calls = 0
            bindPickerMenu(interaction) { _, context in calls += 1; XCTAssertNil(context.scope); self.assertPrivate() }
            let item = pickerMenuActions(interaction)[0]
            hub.policy.isEnabled = false
            if !disable { hub.policy.isEnabled = true }
            item.handler(); XCTAssertEqual(calls, 1)
        }
    }
}

extension ForwardObjectTests {
    func testForwardPickerCurrentDraftHasPreparationResultAndPreservesComment() {
        let destination = ChatController(account, .peer(3)); account.bindings.navigation.controllers = [destination]
        var legacy: [Bool] = [], results: [String] = []
        let modal = ShareModalController(object(), completion: { legacy.append($0) })
        modal.contextChatInteraction.state.interface.input = ChatTextInputState(inputText: "synthetic comment")
        modal.resultCompletion = { results.append(String(describing: $0)) }
        modal.selectRecipient(3, threadId: nil); modal.close()
        XCTAssertEqual(results, ["draftPrepared"]); XCTAssertEqual(legacy, [true])
        XCTAssertEqual(destination.chatInteraction.state.interface.ids, [sourceId])
        XCTAssertEqual(destination.chatInteraction.state.interface.input.inputText, "synthetic comment")
        XCTAssertTrue(UI.targets.isEmpty); XCTAssertEqual(UI.alerts, 0)
    }
    func testForwardPickerChatAndTopicReadinessAreNotEnqueueAcceptance() {
        for topic in [false, true] {
            UI.reset(); account.bindings.navigation.controllers = []
            var ready: Subscriber<Bool, NoError>?, results: [String] = []
            if topic { UI.forumResult = Signal { ready = $0; return EmptyDisposable } }
            let modal = ShareModalController(object())
            modal.resultCompletion = { results.append(String(describing: $0)) }
            modal.selectRecipient(3, threadId: topic ? 42 : nil)
            XCTAssertTrue(results.isEmpty)
            if topic { ready?.putNext(false); XCTAssertTrue(results.isEmpty); ready?.putNext(true) }
            else { account.bindings.navigation.controller?.ready.set(true) }
            XCTAssertEqual(results, ["destinationReady"]); XCTAssertTrue(UI.targets.isEmpty)
            modal.close(); ready = nil
        }
    }
    func testForwardPickerSavedResultsDistinguishAcceptedRejectedAndUnknown() {
        let cases: [(Signal<[MessageId?], NoError>, String, Bool)] = [(.single([sourceId]), "accepted", true), (.single([nil]), "rejected", false), (.single([]), "unknown", false), (.complete(), "unknown", false)]
        for (signal, expected, successful) in cases {
            UI.reset(); UI.sendResult = signal
            var legacy: [Bool] = [], results: [String] = []
            let modal = ShareModalController(object(), completion: { legacy.append($0) })
            modal.resultCompletion = { results.append(String(describing: $0)) }
            modal.selectRecipient(1, threadId: nil); modal.close()
            XCTAssertEqual(results, [expected]); XCTAssertEqual(legacy, [successful])
            XCTAssertEqual(UI.alerts, successful ? 0 : 1)
        }
    }
    func testForwardPickerSavedCommentPartialAcceptanceIsNotSuccess() {
        UI.sendResult = .single([sourceId]); UI.commentResult = .single([nil])
        var legacy: [Bool] = [], results: [String] = []
        let modal = ShareModalController(object(), completion: { legacy.append($0) })
        modal.contextChatInteraction.state.interface.input = ChatTextInputState(inputText: "synthetic comment")
        modal.resultCompletion = { results.append(String(describing: $0)) }
        modal.selectRecipient(1, threadId: nil)
        XCTAssertEqual(results, ["partiallyAccepted"]); XCTAssertEqual(legacy, [false]); XCTAssertEqual(UI.comments, 1)
        XCTAssertEqual(UI.targets, [1]); XCTAssertTrue(UI.delayed.isEmpty); XCTAssertEqual(UI.alerts, 1)
    }
    func testForwardPickerMissingSourceOrTargetNeverReportsSuccess() {
        for missingSource in [true, false] {
            UI.reset(); account.account.postbox.value.messages[sourceId] = missingSource ? nil : Message(id: sourceId)
            account.account.postbox.value.peers[3] = missingSource ? Peer(3) : nil
            var legacy: [Bool] = [], results: [String] = []
            let modal = ShareModalController(object(), completion: { legacy.append($0) })
            modal.resultCompletion = { results.append(String(describing: $0)) }
            modal.selectRecipient(3, threadId: nil)
            XCTAssertEqual(results, [missingSource ? "sourceUnavailable" : "targetUnavailable"])
            XCTAssertEqual(legacy, [false]); XCTAssertTrue(UI.targets.isEmpty); XCTAssertEqual(UI.alerts, 1)
        }
    }
    func testForwardPickerPollErrorKeepsRetryAndDoesNotBecomeFirstValueSuccess() {
        account.account.postbox.value.peers[3]?.isChannel = true
        account.account.postbox.value.messages[sourceId] = Message(id: sourceId, isPublicPoll: true)
        var results: [String] = []
        let modal = ShareModalController(object()); modal.resultCompletion = { results.append(String(describing: $0)) }
        modal.selectRecipient(3, threadId: nil)
        XCTAssertFalse(modal.pickerClosed); XCTAssertEqual(UI.alerts, 1); XCTAssertTrue(results.isEmpty)
        account.account.postbox.value.messages[sourceId] = Message(id: sourceId)
        let destination = ChatController(account, .peer(3)); account.bindings.navigation.controllers = [destination]
        modal.selectRecipient(3, threadId: nil)
        XCTAssertEqual(results, ["draftPrepared"]); XCTAssertEqual(UI.alerts, 1)
    }
    func testForwardPickerCloseDisposesPendingSavedSendAndReportsCancellationOnce() {
        var subscriber: Subscriber<[MessageId?], NoError>?, disposed = 0, results: [String] = []
        UI.sendResult = Signal { subscriber = $0; return ActionDisposable { disposed += 1 } }
        let modal = ShareModalController(object()); modal.resultCompletion = { results.append(String(describing: $0)) }
        modal.selectRecipient(1, threadId: nil); XCTAssertTrue(results.isEmpty)
        modal.close(); modal.close(); subscriber?.putNext([sourceId]); subscriber = nil
        XCTAssertEqual(results, ["cancelled"]); XCTAssertEqual(disposed, 1); XCTAssertTrue(UI.delayed.isEmpty)
    }
    func testForwardPickerPrivateUnknownOutcomeAndAlertStayExcluded() {
        var results: [String] = []
        UI.sendResult = .complete(); UI.onAlert = { self.assertPrivate() }
        let modal = ShareModalController(object(origin(.excluded)))
        modal.resultCompletion = { self.assertPrivate(); results.append(String(describing: $0)) }
        modal.selectRecipient(1, threadId: nil)
        XCTAssertEqual(results, ["unknown"]); XCTAssertEqual(UI.alerts, 1)
        XCTAssertTrue(UI.quickForwardResults.isEmpty); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
    }
}

extension ForwardObjectTests {
    func testForwardPickerFailureAlertKeepsPrivateLifetimeAfterPickerRelease() {
        UI.sendResult = .complete()
        var modal: ShareModalController? = ShareModalController(object(origin(.excluded)))
        modal?.selectRecipient(1, threadId: nil); modal = nil
        XCTAssertEqual(UI.alerts, 1); XCTAssertTrue(hub.policy.hasExclusions)
        UI.alertClosures.removeAll(); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testForwardPickerDisabledAnalyticsStillPreparesDraftWithTypedResult() {
        hub.policy.isEnabled = false
        let destination = ChatController(account, .peer(3)); account.bindings.navigation.controllers = [destination]
        var results: [SharePickerResult] = []
        let modal = ShareModalController(object()); modal.resultCompletion = { results.append($0) }
        modal.selectRecipient(3, threadId: nil)
        XCTAssertEqual(results, [.draftPrepared]); XCTAssertEqual(destination.chatInteraction.state.interface.ids, [sourceId])
        XCTAssertTrue(UI.quickForwardResults.isEmpty); XCTAssertTrue(UI.shareJourneyResults.isEmpty)
    }
    func testForwardPickerCloseDuringMetadataDoesNotNavigateOrReplaceCancellation() {
        account.account.postbox.delayed = true
        var results: [SharePickerResult] = []
        let modal = ShareModalController(object()); modal.resultCompletion = { results.append($0) }
        modal.selectRecipient(3, threadId: nil); modal.close(); account.account.postbox.flush()
        XCTAssertEqual(results, [.cancelled]); XCTAssertEqual(UI.additionalChats, 0); XCTAssertEqual(UI.alerts, 0)
    }
}


extension ForwardObjectTests {
    func routePicker(_ entry: AnalyticsFlows.ChatForwardPicker.EntryPoint, source: AnalyticsContext? = nil, messages: [Message]? = nil) -> ShareModalController {
        let values = messages ?? [Message(id: sourceId)]
        let modal = installedHooks().makeForwardMessagesShareModalObserved(account, values, { _, _ in .single(values) }, analyticsContext: source ?? origin(), entry: entry) as! ShareModalController
        modal.bindPremiumCallback()
        modal.bindActivationCallbacks()
        return modal
    }
    func testForwardJourneyMenuRoutesReachInstalledPickerAndOneSummary() {
        for (index, expected) in ["message_menu", "more_menu", "replacement_menu"].enumerated() {
            UI.reset(); let interaction = quickInteraction(); var modal: ShareModalController?
            interaction.forwardMessagesWithSource = { messages, source, entry in
                modal = installedHooks().makeForwardMessagesShareModalObserved(self.account, messages, interaction.getMessages, analyticsContext: source, entry: entry) as? ShareModalController
            }
            let items = pickerMenuActions(interaction)
            XCTAssertTrue(UI.forwardPickerResults.isEmpty); items[index].handler()
            let destination = ChatController(account, .peer(3)); account.bindings.navigation.controllers = [destination]
            modal?.selectRecipient(3, threadId: nil); modal?.close()
            XCTAssertEqual(UI.forwardPickerResults.count, 1); XCTAssertEqual(UI.forwardPickerResults.first?.entry, expected)
            XCTAssertEqual(UI.forwardPickerResults.first?.result, "draft_prepared")
            XCTAssertEqual(UI.forwardPickerResults.first?.steps, ["open_picker", "choose_chat", "draft_prepared"])
            interaction.forwardMessagesWithSource = nil
        }
    }
    func testForwardJourneyRowActionCarriesExplicitRouteAndSelectingDoesNotOpen() {
        let row = MessageShareRow(context: account, peerId: 3, message: Message(id: sourceId), origin: origin())
        var entry: AnalyticsFlows.ChatForwardPicker.EntryPoint?
        row.chatInteraction.forwardMessagesWithSource = { _, _, value in entry = value }
        row.chatInteraction.state.state = .selecting
        XCTAssertFalse(row.forwardAction()); XCTAssertNil(entry)
        row.chatInteraction.state.state = .normal
        XCTAssertTrue(row.forwardAction()); XCTAssertEqual(entry, .rowAction)
    }
    func testForwardJourneyTopicAndSavedAcceptanceStayDifferent() {
        for saved in [false, true] {
            UI.reset(); UI.sendResult = .single([sourceId])
            let modal = routePicker(.messageSelection)
            modal.selectRecipient(saved ? 1 : 3, threadId: saved ? nil : 42)
            XCTAssertEqual(UI.forwardPickerResults.first?.entry, "message_selection")
            XCTAssertEqual(UI.forwardPickerResults.first?.result, saved ? "accepted" : "destination_ready")
            XCTAssertEqual(UI.forwardPickerResults.first?.steps, ["open_picker", saved ? "choose_chat" : "choose_topic", saved ? "accepted" : "destination_ready"])
        }
    }
    func testForwardJourneyPollBlockerRetainsRouteAcrossRetry() {
        let message = Message(id: sourceId, isPublicPoll: true)
        account.account.postbox.value.peers[3]?.isChannel = true
        let modal = routePicker(.moreMenu, messages: [message])
        modal.selectRecipient(3, threadId: nil)
        XCTAssertTrue(UI.forwardPickerResults.isEmpty); XCTAssertFalse(modal.pickerClosed)
        account.account.postbox.value.peers[3]?.isChannel = false
        account.bindings.navigation.controllers = [ChatController(account, .peer(3))]
        modal.selectRecipient(3, threadId: nil)
        XCTAssertEqual(UI.forwardPickerResults.first?.retryCount, "1")
        XCTAssertEqual(UI.forwardPickerResults.first?.lastBlocker, "poll_restriction")
        XCTAssertEqual(UI.forwardPickerResults.first?.steps, ["open_picker", "choose_chat", "blocked", "retry", "choose_chat", "draft_prepared"])
    }
    func testForwardJourneyPremiumBlockerThenCancellationIsNotDelivery() {
        let modal = routePicker(.messageMenu)
        modal.selectInteractions.presentation.premiumRequired = [3]
        modal.selectRecipient(3, threadId: nil); modal.close()
        XCTAssertEqual(UI.forwardPickerResults.first?.lastBlocker, "premium_required")
        XCTAssertEqual(UI.forwardPickerResults.first?.outcome, "cancelled"); XCTAssertNil(UI.forwardPickerResults.first?.result)
    }
    func testForwardJourneyPreviousDisposalCannotEraseReentrantRetry() {
        let message = Message(id: sourceId, isPublicPoll: true)
        account.account.postbox.value.peers[3]?.isChannel = true
        var result: Subscriber<[MessageId?], NoError>?
        UI.sendResult = Signal { result = $0; return EmptyDisposable }
        let modal = routePicker(.moreMenu, messages: [message])
        UI.onAlert = {
            UI.onAlert = nil
            modal.selectRecipient(1, threadId: nil)
        }
        modal.selectRecipient(3, threadId: nil)
        XCTAssertNotNil(result)
        XCTAssertTrue(UI.forwardPickerResults.isEmpty)
        result?.putNext([sourceId]); result?.putCompletion()
        XCTAssertEqual(UI.forwardPickerResults.count, 1)
        XCTAssertEqual(UI.forwardPickerResults.first?.result, "accepted")
        XCTAssertEqual(UI.forwardPickerResults.first?.lastBlocker, "poll_restriction")
        XCTAssertEqual(UI.forwardPickerResults.first?.retryCount, "1")
        XCTAssertTrue(modal.success)
    }
    func testForwardJourneyUnknownPartialAndMissingAreNotAccepted() {
        for (result, expected): ([MessageId?], String) in [([], "acceptance_unknown"), ([nil], "rejected")] {
            UI.reset(); UI.sendResult = .single(result)
            routePicker(.messageMenu).selectRecipient(1, threadId: nil)
            XCTAssertEqual(UI.forwardPickerResults.first?.result, expected); XCTAssertEqual(UI.forwardPickerResults.first?.outcome, "fail")
        }
        UI.reset(); UI.sendResult = .single([sourceId]); UI.commentResult = .single([nil])
        let partial = routePicker(.messageMenu)
        partial.contextChatInteraction.state.interface.input = ChatTextInputState(inputText: "synthetic")
        partial.selectRecipient(1, threadId: nil)
        XCTAssertEqual(UI.forwardPickerResults.first?.result, "partially_accepted")
        UI.reset(); routePicker(.messageMenu, messages: []).selectRecipient(3, threadId: nil)
        XCTAssertEqual(UI.forwardPickerResults.first?.result, "source_unavailable")
    }
    func testForwardJourneyPrivateSourceTargetAndLateRevocationEmitNothing() {
        for phase in 0..<3 {
            UI.reset(); let modal = routePicker(.replacementMenu, source: phase == 0 ? origin(.excluded) : origin())
            if phase == 2 { hub.policy.isEnabled = false; hub.policy.isEnabled = true }
            modal.selectRecipient(phase == 1 ? -1 : 3, threadId: nil)
            account.bindings.navigation.controller?.ready.set(true); modal.close()
            XCTAssertTrue(UI.forwardPickerResults.isEmpty)
        }
    }
    func testForwardJourneyUnexplainedPendingResetDiscardsInsteadOfCancelling() {
        UI.sendResult = .never()
        let modal = routePicker(.moreMenu); modal.selectRecipient(1, threadId: nil)
        modal.recipientAction.reset(); modal.close()
        XCTAssertTrue(UI.forwardPickerResults.isEmpty)
    }
    func testForwardJourneyLegacyFactoryAndUnknownEntryDoNotGuessRoute() {
        var hooks = installedHooks(); hooks.makeForwardMessagesShareModalWithSource = nil
        let modal = hooks.makeForwardMessagesShareModalObserved(account, [Message(id: sourceId)], { _, _ in .single([Message(id: self.sourceId)]) }, analyticsContext: origin(), entry: .messageSelection) as! ShareModalController
        modal.close()
        let legacy = installedHooks().makeForwardMessagesShareModalObserved(account, [Message(id: sourceId)], { _, _ in .complete() }, analyticsContext: origin()) as! ShareModalController
        legacy.close(); XCTAssertTrue(UI.forwardPickerResults.isEmpty)
    }
    func testForwardDiscoverySearchIsOnceAcrossTypingClearingAndNavigation() {
        let modal = routePicker(.moreMenu)
        for query in ["", "s", "synthetic-private-query", "", "another"] { modal.search.set(.single(PickerSearchState(request: query))) }
        modal.openCommunity(3, animated: true)
        modal.openCommunity(3, animated: true)
        modal.openForum(4, isMonoforum: false, animated: true)
        modal.openForum(4, isMonoforum: false, animated: true)
        modal.popDestination(animated: true); modal.popDestination(animated: true); modal.popDestination(animated: true)
        modal.close()
        XCTAssertEqual(UI.forwardPickerResults.count, 1)
        XCTAssertEqual(UI.forwardPickerResults.first?.entry, "more_menu")
        XCTAssertEqual(UI.forwardPickerResults.first?.searchUsed, true)
        XCTAssertEqual(UI.forwardPickerResults.first?.steps, ["open_picker", "search", "open_community", "open_forum", "back", "back", "cancel"])
        XCTAssertFalse(String(describing: UI.forwardPickerResults).contains("synthetic-private-query"))
        XCTAssertTrue(modal.destinationStack.isEmpty)
    }
    func testForwardDiscoverySearchThenSelectionKeepsTypedOutcome() {
        let modal = routePicker(.messageSelection)
        modal.search.set(.single(PickerSearchState(request: "synthetic")))
        UI.sendResult = .single([sourceId]); modal.selectRecipient(1, threadId: nil)
        XCTAssertEqual(UI.forwardPickerResults.first?.steps, ["open_picker", "search", "choose_chat", "accepted"])
    }
    func testForwardDiscoveryPrivateNavigationExcludesLoadAndEarlierSearch() {
        for community in [false, true] {
            UI.reset(); let modal = routePicker(.rowAction)
            modal.search.set(.single(PickerSearchState(request: "synthetic")))
            var loaded = 0
            modal.onNavigationLoad = { loaded += 1; self.assertPrivate() }
            if community { modal.openCommunity(-1, animated: true) } else { modal.openForum(-1, isMonoforum: false, animated: true) }
            XCTAssertEqual(loaded, 1)
            modal.popDestination(animated: true); modal.search.set(.single(PickerSearchState(request: "later"))); modal.close()
            XCTAssertTrue(UI.forwardPickerResults.isEmpty)
        }
    }
    func testForwardDiscoveryPrivateUnknownRevokedAndDisabledOriginsRemainSilent() {
        for phase in 0..<4 {
            UI.reset()
            if phase == 3 { hub.policy.isEnabled = false }
            let modal = routePicker(.messageMenu, source: phase == 0 ? origin(.excluded) : phase == 1 ? hub.unresolvedContext() : origin())
            if phase == 2 { hub.policy.isEnabled = false; hub.policy.isEnabled = true }
            var reads = 0
            modal.search.set(.single(PickerSearchState(request: "synthetic", onRead: { reads += 1 })))
            XCTAssertEqual(reads, 0)
            modal.openForum(3, isMonoforum: true, animated: true)
            XCTAssertEqual(modal.destinationStack.count, 1)
            modal.popDestination(animated: true); modal.close()
            XCTAssertTrue(UI.forwardPickerResults.isEmpty)
        }
    }
    func testForwardDiscoverySearchObservationEndsWithPicker() {
        var reads = 0
        var updates: Subscriber<PickerSearchState, NoError>?
        let modal = routePicker(.moreMenu)
        modal.search.set(Signal { subscriber in
            updates = subscriber
            return EmptyDisposable
        })
        updates?.putNext(PickerSearchState(request: "synthetic", onRead: { reads += 1 }))
        XCTAssertEqual(reads, 1); XCTAssertEqual(modal.search.observers, 1)
        modal.close(); XCTAssertEqual(modal.search.observers, 0)
        updates?.putNext(PickerSearchState(request: "later", onRead: { reads += 1 }))
        XCTAssertEqual(reads, 1)
        modal.openForum(3, isMonoforum: false, animated: true); modal.openCommunity(4, animated: true)
        XCTAssertTrue(modal.destinationStack.isEmpty)
        XCTAssertEqual(UI.forwardPickerResults.first?.steps, ["open_picker", "search", "cancel"])
    }
    func activationRow(_ modal: ShareModalController, peerId: PeerId = 1, topic: Int64? = nil) -> TableRowItem {
        let action = { [weak modal] in modal?.selectInteractions.action(peerId, topic) }
        if topic != nil { return GeneralRowItem { action() } }
        return ShortPeerRowItem(Peer(peerId)) { action() }
    }
    func testForwardActivationRoutesReachTheAdmittedSubmission() {
        for (index, expected) in ["row_action", "return_key", "number_shortcut", "saved_messages_shortcut", "send_button", "send_menu"].enumerated() {
            UI.reset(); UI.sendResult = .single([sourceId])
            let modal = routePicker(.moreMenu)
            let row = activationRow(modal)
            modal.genericView.items = [row]; modal.genericView.highlighted = row
            switch index {
            case 0: (row as! ShortPeerRowItem).action()
            case 1: _ = modal.triggerReturn()
            case 2: modal.invokeShortCut(0)
            case 3: _ = modal.triggerSavedShortcut()
            default:
                modal.selectInteractions.presentation.selected = [1]
                modal.selectInteractions.presentation.peers = [1: Peer(1)]
                if index == 4 { modal.genericView.sendButton.action?(0) } else { modal.genericView.sendWithoutSound?() }
            }
            XCTAssertEqual(UI.forwardPickerResults.count, 1, expected)
            XCTAssertEqual(UI.forwardPickerResults.first?.activation, expected)
            XCTAssertEqual(UI.forwardPickerResults.first?.entry, "more_menu")
            XCTAssertEqual(UI.forwardPickerResults.first?.result, "accepted")
            XCTAssertNil(modal.recipientActivation)
        }
    }
    func testForwardActivationTopicKeyboardAndReturnFallback() {
        for shortcut in [false, true] {
            UI.reset(); let modal = routePicker(.messageMenu)
            modal.genericView.items = [activationRow(modal, peerId: 3, topic: 42)]
            if shortcut { modal.invokeShortCut(0) } else { _ = modal.returnKeyAction() }
            XCTAssertEqual(UI.forwardPickerResults.first?.activation, shortcut ? "number_shortcut" : "return_key")
            XCTAssertEqual(UI.forwardPickerResults.first?.result, "destination_ready")
        }
    }
    func testForwardActivationEmptyAndRejectedKeyboardActionsAreNotSubmissions() {
        let modal = routePicker(.rowAction)
        modal.invokeShortCut(0); _ = modal.triggerReturn()
        modal.genericView.items = [activationRow(modal)]
        NSApp.currentEvent = 0
        defer { NSApp.currentEvent = 1 }
        XCTAssertEqual(modal.returnKeyAction(), .rejected)
        modal.close()
        XCTAssertNil(UI.forwardPickerResults.first?.activation)
        XCTAssertNil(UI.forwardPickerResults.first?.result)
    }
    func testForwardActivationPendingDuplicateCannotReplaceOriginalRoute() {
        var pending: Subscriber<[MessageId?], NoError>?
        UI.sendResult = Signal { pending = $0; return EmptyDisposable }
        let modal = routePicker(.messageMenu)
        let row = activationRow(modal); modal.genericView.items = [row]
        (row as! ShortPeerRowItem).action(); modal.invokeShortCut(0)
        pending?.putNext([sourceId]); pending?.putCompletion()
        XCTAssertEqual(UI.forwardPickerResults.count, 1)
        XCTAssertEqual(UI.forwardPickerResults.first?.activation, "row_action")
    }
    func testForwardActivationReentrantRowRetryDoesNotInheritOldKeyboardRoute() {
        let message = Message(id: sourceId, isPublicPoll: true)
        account.account.postbox.value.peers[3]?.isChannel = true
        UI.sendResult = .single([sourceId])
        let modal = routePicker(.messageMenu, messages: [message])
        modal.genericView.highlighted = activationRow(modal, peerId: 3)
        UI.onAlert = { UI.onAlert = nil; modal.selectInteractions.action(1, nil) }
        _ = modal.triggerReturn()
        XCTAssertEqual(UI.forwardPickerResults.first?.activation, "row_action")
        XCTAssertEqual(UI.forwardPickerResults.first?.retryCount, "1")
        XCTAssertNil(modal.recipientActivation)
    }
    func testForwardActivationUnknownAndPrivateDoNotManufactureRoutes() {
        UI.sendResult = .single([sourceId])
        let unknown = routePicker(.messageMenu); unknown.selectRecipient(1, threadId: nil)
        XCTAssertNil(UI.forwardPickerResults.first?.activation)
        UI.reset(); UI.sendResult = .single([sourceId])
        let excluded = routePicker(.messageMenu, source: origin(.excluded))
        _ = excluded.triggerSavedShortcut()
        XCTAssertTrue(excluded.success); XCTAssertTrue(UI.forwardPickerResults.isEmpty)
    }
    func testForwardActivationSendButtonSurvivesDeferredPreflightAndDuplicateShortcut() {
        UI.sendResult = .single([sourceId]); account.account.postbox.delayed = true
        let modal = routePicker(.messageSelection)
        modal.selectInteractions.presentation.selected = [1]
        modal.selectInteractions.presentation.peers = [1: Peer(1)]
        modal.genericView.sendButton.action?(0)
        XCTAssertNil(modal.recipientActivation); XCTAssertTrue(UI.forwardPickerResults.isEmpty)
        _ = modal.triggerSavedShortcut()
        account.account.postbox.delayed = false; account.account.postbox.flush()
        XCTAssertEqual(UI.forwardPickerResults.count, 1)
        XCTAssertEqual(UI.forwardPickerResults.first?.activation, "send_button")
        XCTAssertEqual(UI.forwardPickerResults.first?.result, "accepted")
    }
    func testForwardActivationNavigationDoesNotLeakKeyboardRouteToNestedSelection() {
        UI.sendResult = .single([sourceId])
        let modal = routePicker(.messageMenu)
        modal.genericView.highlighted = GeneralRowItem { [weak modal] in modal?.openForum(3, isMonoforum: false, animated: true) }
        modal.onNavigationLoad = { [weak modal] in
            XCTAssertNil(modal?.recipientActivation)
            modal?.selectInteractions.action(1, nil)
        }
        _ = modal.triggerReturn()
        XCTAssertEqual(UI.forwardPickerResults.first?.activation, "row_action")
        XCTAssertEqual(UI.forwardPickerResults.first?.result, "accepted")
    }
    func testForwardSourceJourneySurvivesControllerFactoryAndTypedPicker() {
        let controller = ChatController(account, .peer(3)); controller.installForwardingCallbacks()
        controller.chatInteraction.getMessages = { _, _ in .single([Message(id: self.sourceId)]) }
        let source = origin()
        let journey = AnalyticsForwardPickerJourney(context: source, entry: .messageSelection, sourceLookup: true)
        journey.sourceReady()
        controller.chatInteraction.forwardMessagesObserved([Message(id: sourceId)], analyticsContext: source, entry: .messageSelection, journey: journey)
        let modal = UI.presented.last as? ShareModalController
        XCTAssertTrue(modal?.analyticsForwardJourney === journey)
        UI.sendResult = .single([sourceId]); modal?.selectRecipient(1, threadId: nil)
        XCTAssertEqual(UI.forwardPickerResults.count, 1)
        XCTAssertEqual(UI.forwardPickerResults.first?.entry, "message_selection")
        XCTAssertEqual(UI.forwardPickerResults.first?.steps, ["lookup_source", "source_ready", "open_picker", "choose_chat", "accepted"])
    }
    func testForwardSourceJourneyIsDiscardedByReportController() {
        let controller = ChatController(account, .peer(3)); controller.installForwardingCallbacks()
        controller.chatInteraction.state.reportMode = 1
        let source = origin()
        let journey = AnalyticsForwardPickerJourney(context: source, entry: .messageSelection, sourceLookup: true)
        journey.sourceReady()
        var calls = 0; controller.chatInteraction.reportMessages = { _, _ in calls += 1 }
        controller.chatInteraction.forwardMessagesObserved([Message(id: sourceId)], analyticsContext: source, entry: .messageSelection, journey: journey)
        XCTAssertEqual(calls, 1); XCTAssertEqual(journey.retainedStateCount, 0)
        XCTAssertTrue(UI.presented.isEmpty); XCTAssertTrue(UI.forwardPickerResults.isEmpty)
    }
    func testForwardSourceForeignJourneyCannotObservePrivatePicker() {
        let foreignHub = Analytics(), foreignOwner = NSObject()
        foreignHub.policy.setOwner(foreignOwner); foreignHub.policy.isEnabled = true
        let foreign = foreignHub.captureContext(owner: foreignOwner, privacy: .ordinary)
        let journey = AnalyticsForwardPickerJourney(context: foreign, entry: .messageSelection, sourceLookup: true)
        journey.sourceReady()
        let modal = routePicker(.messageMenu, source: origin(.excluded))
        modal.setAnalyticsForwardJourney(journey)
        UI.sendResult = .single([sourceId]); modal.selectRecipient(1, threadId: nil)
        XCTAssertTrue(modal.success); XCTAssertEqual(journey.retainedStateCount, 0)
        XCTAssertTrue(UI.forwardPickerResults.isEmpty)
    }
}


extension ForwardObjectTests {
    func testForwardJourneyInstalledControllerPassesRouteThroughNormalizationAndFactory() {
        let controller = ChatController(account, .peer(3)); controller.installForwardingCallbacks()
        controller.chatInteraction.getMessages = { _, _ in .single([Message(id: self.sourceId)]) }
        controller.chatInteraction.forwardMessagesObserved([Message(id: sourceId)], analyticsContext: origin(), entry: .messageSelection)
        let modal = UI.presented.last as? ShareModalController
        XCTAssertNotNil(modal); modal?.close()
        XCTAssertEqual(UI.forwardPickerResults.first?.entry, "message_selection")
        XCTAssertEqual(UI.forwardPickerResults.first?.outcome, "cancelled")
    }
    func testForwardJourneyReportModeDoesNotOpenOrAttributeForwardingPicker() {
        let controller = ChatController(account, .peer(3)); controller.installForwardingCallbacks()
        controller.chatInteraction.state.reportMode = 1
        var reported: [MessageId] = []; controller.chatInteraction.reportMessages = { _, ids in reported = ids }
        controller.chatInteraction.forwardMessagesObserved([Message(id: sourceId)], analyticsContext: origin(), entry: .messageSelection)
        XCTAssertEqual(reported, [sourceId]); XCTAssertTrue(UI.presented.isEmpty); XCTAssertTrue(UI.forwardPickerResults.isEmpty)
    }
}
