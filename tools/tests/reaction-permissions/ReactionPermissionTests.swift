import Foundation

struct Namespace: Equatable { let rawValue: Int }
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
}
struct EnginePeer { let peer: Peer; init(_ peer: Peer) { self.peer = peer } }
func canSendReactionsToPeer(_ peer: EnginePeer) -> Bool { peer.peer.allowsReactions }
struct MessageId { let peerId: PeerId; var namespace = Namespaces.Message.Cloud }
struct MessageFlags: OptionSet {
    let rawValue: Int
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
}
enum PeerAllowedReactions { case all, limited([Reaction]), empty }
struct Presentation { var allowedReactions: PeerAllowedReactions? = .all }
struct Interaction { var peer: Peer?; var isPeerSavedMessages = false; var presentation = Presentation() }
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
    }
    var reactionPermissionPeer: Peer? { __REACTION_PEER__ }
    var canReact: Bool { __CAN_REACT__ }
    func pickerActions(message: Message, context: Context, isTags: Bool) -> [(Reaction) -> Void] {
        __CAN_APPLY_REACTION__
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
        let action = { [weak self] in __STAR_ACTION__ }
        action()
    }
}
enum Reaction: Equatable {
    case builtin, custom, stars
    func toUpdate(_ file: Int? = nil) -> Int { 1 }
}
typealias FixtureReaction = Reaction
enum MessageReaction { typealias Reaction = FixtureReaction }
struct Source { var file: Int? }
struct Context { let peerId: PeerId; let window = 0; let reactions = Engine(); var isPremium = true; var isFrozen = false }
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
    func sendStarsReaction(_ messageId: MessageId, count: Int, fromRect: CGRect? = nil) { calls += 1 }
    func react(_ messageId: MessageId, values: [Int], fromRect: CGRect? = nil, storeAsRecentlyUsed: Bool = false, isLarge: Bool = false) { calls += 1 }
}
struct ReactionSettings { var quickReaction: Reaction = .builtin }
struct ChatInterfaceHooks { static let shared = ChatInterfaceHooks(); func freezeAlert(_ context: Context) {} }
struct ChatHistoryUIHooks {
    static let shared = ChatHistoryUIHooks()
    func reactionSettings(_ context: Context) -> ReactionSettings { ReactionSettings() }
    func messageNewReactions(_ message: Message, _ update: Int, _ tags: Bool) -> [Int] { [update] }
    func messageNewReactions(_ message: Message, _ update: UpdateMessageReaction, _ tags: Bool) -> [Int] { [1] }
}
func tap(message: Message, context: Context, mode: Mode, engine: Engine, value: Reaction = .builtin, isFilterTag: Bool = false, reactionPeer: (() -> Peer?)? = nil, tagAction: (Reaction) -> Void = { _ in }) {
    let source = Source()
    let reactionPeer = reactionPeer ?? { message.peers[message.id.peerId] }
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
print("\(checks - failures)/\(checks) reaction permission checks passed")
exit(failures == 0 ? 0 : 1)
