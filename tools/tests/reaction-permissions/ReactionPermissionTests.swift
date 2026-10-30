import Foundation
infix operator |> : AdditionPrecedence
func |> <T,U>(value:T, transform:(T)->U)->U { transform(value) }
struct Signal<T> {
 let provider: ()->T
 var value:T { provider() }
 init(value:T) { provider={ value } }
 init(provider:@escaping ()->T) { self.provider=provider }
 func startStandalone(next: (T)->Void) { next(value) }
}
func take<T>(_ count:Int) -> (Signal<T>)->Signal<T> { { $0 } }
func deliverOnMainQueue<T>(_ signal:Signal<T>)->Signal<T> { signal }

struct Namespace: Hashable { let rawValue: Int }
enum Namespaces {
    enum Message { static let Cloud = Namespace(rawValue: 0) }
    enum Peer { static let SecretChat = Namespace(rawValue: 1) }
}
struct PeerId: Hashable {
    let value: Int
    var namespace: Namespace { Namespace(rawValue: 0) }
}
struct Peer {
    let id: PeerId
    let allowsReactions: Bool
    var personalBan = false
}
struct EnginePeer { let peer: Peer; init(_ peer: Peer) { self.peer = peer } }
func canSendReactionsToPeer(_ peer: EnginePeer, ignoreDefault: Bool = false) -> Bool { !peer.peer.personalBan && (peer.peer.allowsReactions || ignoreDefault) }
struct MessageId: Hashable { let peerId: PeerId; var namespace = Namespaces.Message.Cloud }
struct MessageFlags: OptionSet {
    let rawValue: Int
    static let Unsent = MessageFlags(rawValue: 2)
    static let Failed = MessageFlags(rawValue: 4)
    static let ReactionsArePossible = MessageFlags(rawValue: 1)
    func contains(_ flag: MessageFlags) -> Bool { rawValue & flag.rawValue != 0 }
}
protocol Media {}
struct TelegramMediaAction: Media {}
struct TelegramMediaStory: Media { var isMention = false }
struct Message {
    var id = MessageId(peerId: PeerId(value: 2))
    var peers: [PeerId: Peer] = [:]
    var activeEphemeralReplacementMessage: Int?
    var adAttribute: Int?
    var containsSecretMedia = false
    var extendedMedia: Media?
    var flags: MessageFlags = []
    var selectedReactions: [Int] = []
}
enum PeerAllowedReactions { case all, limited([Reaction]), empty }
struct CachedChannelData { var boostsToUnrestrict: Int32?; var appliedBoosts: Int32? }
struct Presentation { var allowedReactions: PeerAllowedReactions? = .all; var cachedData: Any?; var peer: Peer?; func canSendReactions(to peer: Peer) -> Bool { __PRESENTATION_PERMISSION__ } }
enum Toaster { case banned }
final class Interaction {
    func showAnimatedToaster(_ type:Toaster,_ text:String) {}
    var latestMessage: Message?
    func getMessages(_ ids: [MessageId], _ album: Bool) -> Signal<[Message]> { Signal(value: latestMessage.map { [$0] } ?? []) }
    var peer: Peer? { didSet { presentation.peer = peer } }; var isPeerSavedMessages = false; var presentation = Presentation(); init(peer: Peer?) { self.peer = peer; presentation.peer = peer } }
final class PendingUpdateMessageManager { var media: [MessageId: Int] = [:]; var updatingMessageMedia: Signal<[MessageId:Int]> { Signal(provider:{ self.media }) } }
struct Account { let pendingUpdateMessageManager=PendingUpdateMessageManager() }
func combineLatest<A,B>(_ a:Signal<A>,_ b:Signal<B>)->Signal<(A,B)> { Signal(provider:{ (a.value,b.value) }) }
typealias ChatRowItem=Row
typealias NSRect=CGRect
struct Available { var enabledValues: [Reaction] = [.builtin] }
struct AdditionalData { var reactions: Available? = Available() }
struct Entry { var isFakeMessage = false; var additionalData = AdditionalData() }
final class Row {
    var firstMessage: Message?
    var chatInteraction: Interaction
    var entry = Entry()
    var isUnsent = false
    var isFailed = false
    var unsupported = false
    let context = Context(peerId: PeerId(value: 1))
    var message: Message? { firstMessage }
    func reactAction() -> Bool { __QUICK_ACTION__ }
    init(firstMessage: Message?, chatInteraction: Interaction) {
        self.firstMessage = firstMessage
        self.chatInteraction = chatInteraction
        chatInteraction.latestMessage = firstMessage
    }
    var reactionPermissionPeer: Peer? { __REACTION_PEER__ }
    var canSendReactions: Bool { __CAN_SEND_REACTIONS__ }
    var reactionPermission: () -> Bool { __REACTION_PERMISSION__ }
    func chipPermission() -> () -> Bool {
        let reactionPermission = self.reactionPermission
        return __LAYOUT_PERMISSION__
    }
    var reactionMessageIsEligible: Bool { __MESSAGE_ELIGIBILITY__ }
    var reactionApplicationPermission: () -> Bool { __APPLICATION_PERMISSION__ }
    static func isUnsupported(_ message:Message?) -> Bool { false }
    var reactionMessageAction: (@escaping (Message)->Void)->Void { __MESSAGE_ACTION__ }
    var isReactionRestricted: Bool { !canSendReactions && reactionMessageIsEligible }
    var isReactable: Bool { __BASELINE_ELIGIBILITY__ }
    var canSendReactionsHere: Bool { __BASELINE_PERMISSION__ }
    var canReact: Bool { __CAN_REACT__ }
    func pickerActions(message: Message, context: Context, isTags: Bool) -> [(Reaction) -> Void] {
        let chatInteraction = self.chatInteraction
        let messageId = message.id
        let reactionMessageAction = self.reactionMessageAction
        let applyStarsReaction: (CGRect?)->Void = { __PAID_ACTION__ }
        __CAN_APPLY_REACTION__
        let applyReaction: (UpdateMessageReaction, CGRect?, Bool) -> Void = { __LATEST_REACTION__ }

        let openSavedTagsPremium = { }
        let reactions: [RecentReactionItem] = []
        let fromRect: CGRect? = nil
        let isLarge = false
        let normal: (Reaction) -> Void = { value in __PICKER_ACTION__ }
        let large: (Reaction) -> Void = { value in __LARGE_ACTION__ }
        let expanded: (Reaction) -> Void = { _ in
            let sticker = StickerPackItem()
            __EXPANDED_ACTION__
        }
        return [normal, large, expanded]
    }
    func openStars(message: Message, context: Context) {
        let reactionPermission = self.reactionPermission
        let canApplyReaction = self.reactionApplicationPermission
        let reactionMessageAction = self.reactionMessageAction
        let action = {__STAR_CAPTURE__ __STAR_ACTION__ }
        action()
    }
}
enum Reaction: Equatable {
    case builtin, custom, stars
    func toUpdate(_ file: Int? = nil) -> UpdateMessageReaction { .builtin("👍") }
}
typealias FixtureReaction = Reaction
enum MessageReaction { typealias Reaction = FixtureReaction }
struct Source { var file: Int? }
struct Context { let account=Account(); let peerId: PeerId; let window = 0; let reactions = Engine(); var isPremium = true; var isFrozen = false }
struct EngineMessage {
    let message: Message
    init(_ message: Message) { self.message = message }
}
enum StarSource { case message(EngineMessage) }
struct Star_ReactionsController {
    init(context: Context, source: StarSource) {}
}
var starPickers = 0
func showModal(with controller: Star_ReactionsController, for window: Int) { starPickers += 1 }
enum Mode { case tag, full }
final class Engine {
    var calls = 0
    var values: [Int] = []
    func sendStarsReaction(_ messageId: MessageId, count: Int, fromRect: CGRect? = nil) { calls += 1 }
    func react(_ messageId: MessageId, values: [Int], fromRect: CGRect? = nil, storeAsRecentlyUsed: Bool = false, isLarge: Bool = false) { calls += 1; self.values = values }
}
struct ReactionSettings { var quickReaction: Reaction = .builtin }
struct ChatInterfaceHooks { static let shared = ChatInterfaceHooks(); func freezeAlert(_ context: Context) {} }
struct ChatHistoryUIHooks {
    static let shared = ChatHistoryUIHooks()
    func reactionSettings(_ context: Context) -> ReactionSettings { ReactionSettings() }
    func messageNewReactions(_ message: Message, _ update: Int, _ tags: Bool) -> [Int] { [update] }
    func messageNewReactions(_ message: Message, _ update: UpdateMessageReaction, _ tags: Bool) -> [Int] { message.selectedReactions + [1] }
}
func tap(message: Message, context: Context, mode: Mode, engine: Engine, value: Reaction = .builtin, isFilterTag: Bool = false, reactionPeer: (() -> Peer?)? = nil, canSend: (() -> Bool)? = nil, tagAction: (Reaction) -> Void = { _ in }) {
    let reactionsDisabled: ()->Void = {}
    let source = Source()
    let reactionPeer = reactionPeer ?? { message.peers[message.id.peerId] }
    let canSendReactions = canSend ?? { reactionPeer().map { canSendReactionsToPeer(EnginePeer($0)) } ?? false }
    __CHIP_ACTION__
}
struct ParsedFile {
    let stickerText: String? = "👍"
    let fileId = FileId()
    let isPremiumEmoji = false
    func _parse() -> ParsedFile { self }
}
struct FileId: Equatable { let id = 1 }
struct StickerPackItem { let file = ParsedFile() }
enum UpdateMessageReaction { case builtin(String), custom(fileId: Int, file: ParsedFile) }
enum RecentContent { case custom(ParsedFile), builtin }
struct RecentReactionItem { let content: RecentContent }
enum PremiumSource { case premium_stickers }
struct PremiumBoardingController { init(context: Context, source: PremiumSource) { } }
func prem(with controller: PremiumBoardingController, for window: Int) { }
func strings() -> (customReactionPremiumAlert: String, unused: Int) { ("Premium", 0) }
func showModalText(for window: Int, text: String, callback: (Int) -> Void) { }

var checks = 0
var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(name)") }
}
let chatId = PeerId(value: 2)
let restricted = Peer(id: chatId, allowsReactions: false)
let allowed = Peer(id: chatId, allowsReactions: true)
var message = Message(peers: [chatId: restricted])
let row = Row(firstMessage: message, chatInteraction: Interaction(peer: restricted))
expect(!row.canReact, "restricted chat does not offer reaction picker or quick reaction")
row.chatInteraction.peer = allowed
expect(row.canReact, "current allowed rights supersede stale restricted message peer")
message.peers[chatId] = allowed
row.firstMessage = message
row.chatInteraction.peer = restricted
expect(!row.canReact, "current restriction supersedes stale allowed message peer")
row.chatInteraction.peer = nil
expect(row.canReact, "search history falls back to actual message peer")
row.chatInteraction.peer = Peer(id: PeerId(value: 3), allowsReactions: false)
expect(row.canReact, "unrelated presentation peer does not restrict message chat")
row.firstMessage?.peers = [:]
expect(!row.canReact, "unresolved chat permissions do not offer reactions")
row.chatInteraction.peer = allowed
row.firstMessage = message
row.isUnsent = true
expect(!row.canReact, "unsent message stays unavailable")
row.isUnsent = false
row.firstMessage?.containsSecretMedia = true
expect(!row.canReact, "secret media stays unavailable")
row.firstMessage = message
row.chatInteraction.peer = restricted
row.openStars(message: message, context: Context(peerId: PeerId(value: 1)))
expect(starPickers == 0, "restricted chat does not open paid-reaction picker")
starPickers = 0
row.chatInteraction.peer = allowed
row.openStars(message: message, context: Context(peerId: PeerId(value: 1)))
expect(starPickers == 1, "allowed chat opens paid-reaction picker")
row.chatInteraction.peer = restricted
row.openStars(message: message, context: Context(peerId: PeerId(value: 1)))
expect(starPickers == 1, "paid-reaction picker observes changed rights")
for value in [Reaction.builtin, .stars] {
    let engine = Engine()
    var restrictedMessage = message
    restrictedMessage.peers[chatId] = restricted
    tap(message: restrictedMessage, context: Context(peerId: PeerId(value: 1)), mode: .full, engine: engine, value: value)
    expect(engine.calls == 0, "existing restricted reaction chip never submits \(value)")
    engine.calls = 0
    tap(message: message, context: Context(peerId: PeerId(value: 1)), mode: .full, engine: engine, value: value)
    expect(engine.calls == 1, "allowed reaction chip submits \(value)")
    engine.calls = 0
    row.firstMessage = message
    row.chatInteraction.peer = restricted
    tap(message: message, context: Context(peerId: PeerId(value: 1)), mode: .full, engine: engine, value: value, reactionPeer: { row.reactionPermissionPeer })
    expect(engine.calls == 0, "existing chip observes a live restriction despite stale allowed message peer \(value)")
    engine.calls = 0
    row.firstMessage = restrictedMessage
    row.chatInteraction.peer = allowed
    tap(message: restrictedMessage, context: Context(peerId: PeerId(value: 1)), mode: .full, engine: engine, value: value, reactionPeer: { row.reactionPermissionPeer })
    expect(engine.calls == 1, "existing chip observes permission restoration despite stale restricted message peer \(value)")

}
let engine = Engine()
var filtered = false
tap(message: message, context: Context(peerId: chatId), mode: .tag, engine: engine, reactionPeer: { nil }, tagAction: { _ in filtered = true })
expect(filtered && engine.calls == 0, "saved-message tags still filter without submitting")
row.firstMessage = message
row.chatInteraction.peer = allowed
row.chatInteraction.isPeerSavedMessages = true
let savedEngine = Engine()
tap(message: message, context: Context(peerId: chatId), mode: .tag, engine: savedEngine, isFilterTag: true, reactionPeer: { row.reactionPermissionPeer })
expect(savedEngine.calls == 1, "saved-peer media tags retain their existing update action when picker eligibility is false")
row.chatInteraction.isPeerSavedMessages = false
row.chatInteraction.peer = allowed
row.firstMessage = message
for index in 0..<3 {
    let context = Context(peerId: PeerId(value: 1))
    let current = row.pickerActions(message: message, context: context, isTags: false)[index]
    row.chatInteraction.peer = restricted
    current(.builtin)
    current(.stars)
    expect(context.reactions.calls == 0, "open picker action \(index) rejects a live restriction")
    context.reactions.calls = 0
    row.chatInteraction.peer = allowed
    current(.builtin)
    expect(context.reactions.calls == 1, "open picker action \(index) accepts restored rights")
}
row.chatInteraction.peer = restricted
_ = row.reactAction()
expect(row.context.reactions.calls == 0, "quick-reaction gesture does not send when restricted")
row.chatInteraction.peer = allowed
_ = row.reactAction()
expect(row.context.reactions.calls == 1, "quick-reaction gesture still sends when allowed")
row.chatInteraction.peer = restricted
_ = row.reactAction()
expect(row.context.reactions.calls == 1, "quick-reaction gesture observes revoked rights")
let tagContext = Context(peerId: chatId)
row.chatInteraction.peer = restricted
for action in row.pickerActions(message: message, context: tagContext, isTags: true) { action(.builtin) }
expect(tagContext.reactions.calls == 3, "open saved-tag actions preserve their update route")
let boosted = Row(firstMessage: message, chatInteraction: Interaction(peer: restricted))
func boosts(_ required: Int32?, _ applied: Int32?) {
    boosted.chatInteraction.presentation.cachedData = CachedChannelData(boostsToUnrestrict: required, appliedBoosts: applied)
}
for (required, applied, permitted): (Int32?, Int32?, Bool) in [(nil, nil, false), (0, 0, false), (2, nil, false), (2, 1, false), (2, 2, true), (2, 3, true)] {
    boosts(required, applied)
    expect(boosted.canReact == permitted, "default restriction uses boost threshold \(String(describing: required))/\(String(describing: applied))")
}
boosts(2, 2)
boosted.context.reactions.calls = 0
_ = boosted.reactAction()
expect(boosted.context.reactions.calls == 1, "boost exemption permits the common quick-reaction send path")
let boostedActions = boosted.pickerActions(message: message, context: boosted.context, isTags: false)
for (index, action) in boostedActions.enumerated() {
    boosted.context.reactions.calls = 0
    action(.builtin)
    expect(boosted.context.reactions.calls == 1, "boost exemption permits open picker callback \(index)")
}
let beforeBoostedStars = starPickers
boosted.openStars(message: message, context: boosted.context)
expect(starPickers == beforeBoostedStars + 1, "boost exemption permits paid-reaction entry point")
for value in [Reaction.builtin, .stars] {
    let send = Engine()
    tap(message: message, context: boosted.context, mode: .full, engine: send, value: value, reactionPeer: { boosted.reactionPermissionPeer }, canSend: { boosted.canSendReactions })
    expect(send.calls == 1, "boost exemption permits existing reaction chip \(value)")
}
boosts(2, 1)
for (index, action) in boostedActions.enumerated() {
    boosted.context.reactions.calls = 0
    action(.builtin)
    expect(boosted.context.reactions.calls == 0, "open picker observes lost boost exemption \(index)")
}
boosts(2, 2)
boosted.chatInteraction.peer = Peer(id: chatId, allowsReactions: false, personalBan: true)
expect(!boosted.canReact, "boosts never bypass a personal reaction ban")
boosted.context.reactions.calls = 0
_ = boosted.reactAction()
expect(boosted.context.reactions.calls == 0, "personally banned boosted member cannot quick-react")
for value in [Reaction.builtin, .stars] {
    let send = Engine()
    tap(message: message, context: boosted.context, mode: .full, engine: send, value: value, reactionPeer: { boosted.reactionPermissionPeer }, canSend: { boosted.canSendReactions })
    expect(send.calls == 0, "boosts do not bypass personal ban through existing chips \(value)")
}
var restrictedHistory = message
restrictedHistory.peers[chatId] = restricted
boosted.firstMessage = restrictedHistory
boosted.chatInteraction.peer = Peer(id: PeerId(value: 3), allowsReactions: true)
expect(!boosted.canReact, "another chat's boosts never unlock fallback message permissions")
boosted.chatInteraction.peer = restricted
boosted.chatInteraction.presentation.cachedData = nil
expect(!boosted.canReact, "missing cached boost data does not bypass defaults")
let refreshedContext = Context(peerId: PeerId(value: 1))
let refreshedInteraction = Interaction(peer: allowed)
var refreshedRow: Row? = Row(firstMessage: message, chatInteraction: refreshedInteraction)
weak var originalRow = refreshedRow
var openPickerActions = refreshedRow!.pickerActions(message: message, context: refreshedContext, isTags: false)
let retiredChipPermission = originalRow!.chipPermission()
refreshedRow = nil
expect(originalRow == nil, "reaction callbacks do not retain a retired table row")
expect(retiredChipPermission(), "existing reaction chip remains usable after its row is replaced")
for action in openPickerActions { action(.builtin) }
expect(refreshedContext.reactions.calls == 3, "normal, large and expanded picker actions survive a row refresh without boosts")
refreshedInteraction.peer = restricted
expect(!retiredChipPermission(), "retired chip observes a new live restriction")
for action in openPickerActions { action(.builtin) }
expect(refreshedContext.reactions.calls == 3, "row-independent picker still observes a live restriction")
for value in [Reaction.builtin, .stars] {
    let retiredChipEngine = Engine()
    refreshedInteraction.peer = allowed
    tap(message: message, context: refreshedContext, mode: .full, engine: retiredChipEngine, value: value, reactionPeer: { retiredChipPermission() ? allowed : nil }, canSend: retiredChipPermission)
    expect(retiredChipEngine.calls == 1, "retired existing chip still submits \(value)")
    refreshedInteraction.peer = restricted
    tap(message: message, context: refreshedContext, mode: .full, engine: retiredChipEngine, value: value, reactionPeer: { retiredChipPermission() ? allowed : nil }, canSend: retiredChipPermission)
    expect(retiredChipEngine.calls == 1, "retired existing chip rejects a new restriction \(value)")
}
openPickerActions.removeAll()
expect(originalRow == nil, "closing the picker releases its retired row")
for flag in ["unsent", "failed", "ephemeral", "secret", "fake", "saved"] {
    let interaction = Interaction(peer: allowed)
    let item = Row(firstMessage: message, chatInteraction: interaction)
    switch flag {
    case "unsent": item.isUnsent = true
    case "failed": item.isFailed = true
    case "ephemeral": item.firstMessage?.activeEphemeralReplacementMessage = 1
    case "secret": item.firstMessage?.containsSecretMedia = true
    case "fake": item.entry.isFakeMessage = true
    default: interaction.isPeerSavedMessages = true
    }
    let output = Context(peerId: PeerId(value: 1))
    for action in item.pickerActions(message: message, context: output, isTags: false) { action(.builtin) }
    expect(output.reactions.calls == 0, "all picker callbacks retain message eligibility: \(flag)")
    let before = starPickers
    item.openStars(message: message, context: output)
    expect(starPickers == before, "paid picker retains message eligibility: \(flag)")
}
var releasedInteraction: Interaction? = Interaction(peer: allowed)
weak var weakInteraction = releasedInteraction
var releasedRow: Row? = Row(firstMessage: message, chatInteraction: releasedInteraction!)
let releasedPermission = releasedRow!.chipPermission()
releasedRow = nil
releasedInteraction = nil
expect(weakInteraction == nil && !releasedPermission(), "chip callback does not retain its chat interaction")
for index in 0..<3 {
 let interaction = Interaction(peer: allowed)
 var opening = message
 opening.selectedReactions = [2]
 let currentRow = Row(firstMessage: opening, chatInteraction: interaction)
 let output = Context(peerId: PeerId(value: 1))
 let action = currentRow.pickerActions(message: opening, context: output, isTags: false)[index]
 interaction.latestMessage?.selectedReactions = []
 action(.builtin)
 expect(output.reactions.values == [1], "picker \(index) never resurrects a remotely removed reaction")
 interaction.latestMessage?.selectedReactions = [3]
 action(.builtin)
 expect(output.reactions.values == [3,1], "picker \(index) preserves a reaction added after opening")
 let count = output.reactions.calls
 interaction.latestMessage = nil
 action(.builtin)
 expect(output.reactions.calls == count, "picker \(index) ignores a deleted message")
}
for status in ["deleted", "unsent", "failed", "media", "ephemeral", "secret", "valid"] {
 let interaction=Interaction(peer:allowed)
 let item=Row(firstMessage:message,chatInteraction:interaction)
 let output=Context(peerId:PeerId(value:1))
 let action=item.pickerActions(message:message,context:output,isTags:false)[0]
 let retainedStarAction=item.reactionMessageAction
 switch status {
 case "deleted": interaction.latestMessage=nil
 case "unsent": interaction.latestMessage?.flags.insert(.Unsent)
 case "failed": interaction.latestMessage?.flags.insert(.Failed)
 case "media": item.context.account.pendingUpdateMessageManager.media[message.id]=1
 case "ephemeral": interaction.latestMessage?.activeEphemeralReplacementMessage=1
 case "secret": interaction.latestMessage?.containsSecretMedia=true
 default: break
 }
 action(.stars)
 expect(output.reactions.calls == (status == "valid" ? 1:0), "paid picker revalidates current message: \(status)")
 let before=starPickers
 item.openStars(message:message,context:output)
 expect(starPickers == before + (status == "valid" ? 1:0), "existing star chip revalidates current message: \(status)")
 var invoked=false
 retainedStarAction { _ in invoked=true }
 expect(invoked == (status == "valid"), "unchanged retained star chip observes latest state: \(status)")
}
print("\(checks - failures)/\(checks) reaction permission checks passed")
exit(failures == 0 ? 0 : 1)
