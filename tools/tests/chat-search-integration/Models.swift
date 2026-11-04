import AppKit
import ColorPalette
import SwiftSignalKit
import TGUIKit

struct PeerId: Equatable, Hashable { let value: Int }
class Peer: Equatable {
  let id: PeerId
  let compactDisplayTitle: String
  var isGroup: Bool
  var isSupergroup: Bool { isGroup }
  var isMonoForum = false
  init(_ id: Int, _ title: String, group: Bool = false) {
    self.id = PeerId(value: id)
    self.compactDisplayTitle = title
    self.isGroup = group
  }
  static func == (a: Peer, b: Peer) -> Bool { a.id == b.id }
}
struct MessageId: Equatable { let value: Int }
struct Message {
  let id: MessageId
  let text: String
}
struct MessageIndex { let messageId: MessageId }
func isEqualMessages(_ a: Message, _ rhs: Message) -> Bool { a.id == rhs.id }
struct SearchMessagesState: Equatable { let offset: Int }
struct EmojiTag: Equatable {
  var file: Int = 0
  var tag = Tag()
  struct Tag: Equatable { var reaction = 0 }
}
enum ChatLocation: Equatable {
  case peer(PeerId)
  var threadId: Int? { nil }
}
enum ChatMode: Equatable {
  case history, scheduled, pinned
  var isThreadMode: Bool { false }
  var isTopicMode: Bool { false }
}
struct ChatPresentationInterfaceState {
  var peer: Peer?
  var chatLocation: ChatLocation
  func updatedPeer(_ f: (Peer?) -> Peer?) -> Self {
    var v = self
    v.peer = f(peer)
    return v
  }
}
struct SearchMessagesResultState {
  let request: String
  let messages: [Message]
  init(_ q: String, _ m: [Message]) {
    request = q
    messages = m
  }
}
enum ChatPresentationInputQuery: Equatable { case mention(query: String, includeRecent: Bool) }
enum ChatPresentationInputQueryResult: Equatable {
  case mentions([Peer])
  case searchMessages(
    ([Message], SearchMessagesState?, (SearchMessagesState?) -> Void), [Peer], String)
  static func == (a: Self, b: Self) -> Bool {
    switch (a, b) {
    case (.mentions(let x), .mentions(let y)): return x == y
    case (.searchMessages(let x, let xp, let xq), .searchMessages(let y, let yp, let yq)):
      return x.0.map { $0.id } == y.0.map { $0.id } && x.1 == y.1 && xp == yp && xq == yq
    default: return false
    }
  }
}
protocol AccountContextProtocol: AnyObject {
  var window: Window { get }
  var account: Int { get }
  var isPremium: Bool { get }
  var peerId: PeerId { get }
}
final class FixtureContext: AccountContextProtocol {
  let window: Window
  var account = 0
  var peerId = PeerId(value: 99)
  var isPremium = true
  init(_ w: Window) { window = w }
}
struct MessageTag { static func customTag(_ value: Int, _ other: Int?) -> Self { Self() } }
enum ReactionsMessageAttribute { static func messageTag(reaction: Int) -> Int { reaction } }
final class ChatInteraction: InterfaceObserver {
  let chatLocation: ChatLocation
  let interactionContext: any AccountContextProtocol
  let mode: ChatMode
  var presentation: ChatPresentationInterfaceState
  var movePeerToInput: (Peer) -> Void = { _ in }
  var focusMessageId: (MessageId?, MessageIndex, Int?) -> Void = { _, _, _ in }
  var loadingMessage = Promise<Bool>(false)
  var results: [SearchMessagesResultState] = []
  var clearSearch: () -> Void = {}
  var peerId: PeerId {
    switch chatLocation {
    case .peer(let id): return id
    }
  }
  init(chatLocation: ChatLocation, context: any AccountContextProtocol, mode: ChatMode) {
    self.chatLocation = chatLocation
    interactionContext = context
    self.mode = mode
    presentation = .init(chatLocation: chatLocation)
  }
  func update(_ f: (ChatPresentationInterfaceState) -> ChatPresentationInterfaceState) {
    let old = presentation
    presentation = f(old)
    notifyObservers(value: presentation, oldValue: old, animated: false)
  }
  func updateSearchRequest(_ value: SearchMessagesResultState) { results.append(value) }
  func setLocationTag(_ value: MessageTag?) {}
}
struct ChatSearchInteractions {
  let searchRequest:
    (String, PeerId?, SearchMessagesState?, [EmojiTag]) -> Signal<
      ([Message], SearchMessagesState?, Int32), NoError
    >
  let jump: (Message) -> Void
  let cancel: () -> Void
  let calendarAction: (Date) -> Void
}
struct ChatHeaderState {
  var canDisplayInline: Bool { true }
  enum State {
    case search(ChatSearchInteractions, Peer?, String?, [EmojiTag]?, EmojiTag?, ChatLocation)
  }
  var main: State
}
protocol ChatHeaderProtocol {
  func update(with: ChatHeaderState, animated: Bool)
  func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition)
  func remove(animated: Bool)
  func measure(_ width: CGFloat)
}
final class ChatSearchTagsView: View {
  var selected: [EmojiTag] = []
  func set(
    tags: [EmojiTag], context: any AccountContextProtocol, animated: Bool,
    callback: @escaping (EmojiTag?) -> Void
  ) {}
}
func chatContextQueryForSearchMention(
  chatLocations: [ChatLocation], _ query: ChatPresentationInputQuery,
  currentQuery: ChatPresentationInputQuery?, context: any AccountContextProtocol, includeSelf: Bool = false
) -> (
  ChatPresentationInputQuery,
  Signal<(ChatPresentationInputQueryResult?) -> ChatPresentationInputQueryResult?, NoError>
)? {
  (query, .single({ _ in .mentions([Peer(42, "Alex Example"), Peer(43, "Jamie Example")]) }))
}
struct FixtureStrings {
  var chatSearchFrom: String { "From:" }
  func chatSearchCount(_ a: Int, _ b: Int) -> String { "\(a) of \(b)" }
  var voiceOverCommonNext: String { "Next" }
  var voiceOverCommonPrevious: String { "Previous" }
  var voiceOverCommonCancel: String { "Cancel" }
  var voiceOverCommonCalendar: String { "Calendar" }
  var voiceOverChatSearchByMember: String { "Search by member" }
}
func strings() -> FixtureStrings { FixtureStrings() }
class AnimationLayerContainer: View {
  func updateLayer(_ layer: InlineStickerItemLayer, isLite: Bool, animated: Bool) {}
}
class InlineStickerItemLayer { init(account: Int, file: Int, size: NSSize) {} }
struct ImageHook {
  let _cgImage: CGImage? = nil
  let size = NSSize(width: 16, height: 16)
}
struct ThemeHooks {
  static let shared = Self()
  func image(_ kind: ImageKind) -> ImageHook { ImageHook() }
}
typealias TelegramThemeHooks = ThemeHooks
enum ImageKind { case iconSearchInputTag }
struct ChatNavigationHooks {
  static let shared = Self()
  func makeCalendarPopover(
    _ c: any AccountContextProtocol, _ p: PeerId, _ t: Int?, _ d: Date,
    _ action: @escaping (Date) -> Void
  ) -> ViewController? { nil }
}
struct PremiumBoardingController {
  enum Source { case saved_tags }
  init(context: any AccountContextProtocol, source: Source, openFeatures: Bool) {}
}
func prem(with: PremiumBoardingController, for: Window) {}
final class TelegramPresentationTheme: PresentationTheme {
  var icons: FixtureIcons { FixtureIcons() }
}
struct FixtureIcons {
  var chat_search_next: CGImage {
    NSImage(named: "Icon_SearchArrow")!.precomposed(theme.colors.text, flipVertical: true)
  }
  var chat_search_prev: CGImage {
    NSImage(named: "Icon_SearchArrow")!.precomposed(theme.colors.text)
  }
  var chat_search_next_disabled: CGImage {
    NSImage(named: "Icon_SearchArrow")!.precomposed(
      theme.colors.text.withAlphaComponent(0.3), flipVertical: true)
  }
  var chat_search_prev_disabled: CGImage {
    NSImage(named: "Icon_SearchArrow")!.precomposed(theme.colors.text.withAlphaComponent(0.3))
  }
  var chat_search_calendar: CGImage {
    NSImage(named: "Icon_Calendar")!.precomposed(theme.colors.text)
  }
  var chat_search_cancel: CGImage {
    NSImage(named: "Icon_Pip_Close")!.precomposed(theme.colors.text)
  }
  var chat_search_from: CGImage {
    NSImage(named: "Icon_ChatSearchFrom")!.precomposed(theme.colors.text)
  }
}
var theme: TelegramPresentationTheme!
