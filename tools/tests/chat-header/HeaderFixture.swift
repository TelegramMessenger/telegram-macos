
import AppKit
import TGUIKit
import Translate
enum Mode { case history, preview }
enum MenuMode { case menu, done }
__TRANSLATION_TONE__
struct ChatPresentationInterfaceState {
    struct PeerFixture {
        let restriction: String?
        var isGroup = false
        var isSupergroup = false
        var isChannel = false
        func restrictionText(_ settings: Int?) -> String? { restriction }
    }
    struct TranslateState {
        var canTranslate: Bool = true
        var translate: Bool = false
        var from: String? = "ru"
        var to: String = "en"
        var paywall: Bool = false
        var tone: TranslationTone = .neutral
    }
    var translateState: TranslateState?
    var historyCount: Int? = 10
    var peer: PeerFixture?
    var contentSettings: Int?
    var cachedData: Any?
    var isNotAccessible = false
    var isMonoforum = false
}
struct CachedChannelData { var about: String? }
struct CachedGroupData { var about: String? }
struct PeerView {
    var cachedData: Any?
    var peer: ChatPresentationInterfaceState.PeerFixture?
}
func peerViewMainPeer(_ view: PeerView) -> ChatPresentationInterfaceState.PeerFixture? { view.peer }
final class Context {}
final class ChatInteraction {
    var mode: Mode = .history
    var presentation = ChatPresentationInterfaceState()
    let interactionContext = Context()
    var events: [String] = []
    lazy var restartTopic: () -> Void = { [weak self] in self?.events.append("restart") }
    lazy var toggleTranslate: () -> Void = { [weak self] in self?.events.append("toggle") }
    lazy var hideTranslation: () -> Void = { [weak self] in self?.events.append("hide") }
    lazy var translateTo: (String) -> Void = { [weak self] in self?.events.append("to:" + $0) }
    lazy var setTranslateTone: (TranslationTone) -> Void = { [weak self] in self?.events.append("tone:" + String(describing: $0)) }
    lazy var doNotTranslate: (String) -> Void = { [weak self] in self?.events.append("exclude:" + $0) }
}
struct TextLayout { var attributedString: NSAttributedString }
struct TextFixture { var textLayout: TextLayout? }
struct ImageFixture { var image: CGImage? }
final class RightActionsCluster {
    static let insidePadding: CGFloat = 4
    __WIDTH__
}
final class ChatHeaderBubblesView {
    static let bubbleHeight: CGFloat = 40
    static let topInset: CGFloat = 12
    static let totalHeight: CGFloat = 62
    static let sideInset: CGFloat = 12
    static let interBubbleSpacing: CGFloat = 10
    var leftSideInset: CGFloat = 12
    var hasBackButton = false
    var callHidden = true
    var searchHidden = false
    var menuMode: MenuMode = .menu
    var peerView: PeerView?
    var currentChatTheme: PresentationTheme?
    var theme: PresentationTheme { PresentationTheme.current }
    var titleHandler: (() -> Void)?
    let chatInteraction = ChatInteraction()
    var titleView = TextFixture(textLayout: TextLayout(attributedString: NSAttributedString(string: "FortunaTV - DEEP", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)])))
    var statusView = TextFixture(textLayout: TextLayout(attributedString: NSAttributedString(string: "391 subscribers", attributes: [.font: NSFont.systemFont(ofSize: 12)])))
    var statusControl: NSView?
    var leftStatusControl: NSView?
    var titleImageView: ImageFixture?
    var avatarControl = NSView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
    __GEOMETRY__
}
struct HeaderState {
    enum Value {
        case none, search(Int, Int?, String?, [String]?, String?, Int), pinned(Int), report(Int, Int?), addContact, shareInfo, promo, pendingRequests, requestChat, restartTopic, removePaidMessages, setBotPhoto
    }
    struct BotAd { var height: CGFloat }
    var main: Value = .none
    var voiceChat: Bool?
    var translate: Bool?
    var botManager: Bool?
    var botAd: BotAd?
    var monoforumHorizontal: Bool?
    __STATE_METHODS__
}
struct Header { var state = HeaderState() }
struct Insets { var top: CGFloat }
final class Table {
    var stick: CGFloat = 0
    var calls = 0
    var contentInsets = Insets(top: 0)
    func updateStickInset(_ value: CGFloat, animated: Bool) { stick = value; calls += 1 }
}
final class ControllerFixture {
    var header = Header()
    var frame = CGRect(x: 0, y: 0, width: 1100, height: 700)
    let bubblesView = ChatHeaderBubblesView()
    let chatInteraction = ChatInteraction()
    let tableView = Table()
    var previousHeaderInsets: (stick: CGFloat, content: CGFloat)?
    __INSETS__
    func headerFrame(overflow: CGFloat = 0) -> CGRect {
        let inlineFrame = inlineHeaderFrame(for: frame.width)
        let headerHeight = self.headerHeight
        let headerInset = CGPoint.zero
        let navigationOverflow = overflow
        let inset: CGFloat = 0
        let headerEdge: CGFloat = 12
        let bubblesView = NSView(frame: CGRect(x: 0, y: overflow, width: frame.width, height: 62))
        __FRAME_EXPRESSION__
        return headerFrame
    }
}
struct Appearance { var languageCode = "ru" }
var appAppearance = Appearance()
func _NSLocalizedString(_ value: String) -> String { value.replacingOccurrences(of: "Translate.Language.", with: "") }
var utilityHeaderTitle = "Reopen Topic"
struct Strings {
    var chatHeaderRestartTopic: String { utilityHeaderTitle }
    let voiceOverCommonTranslate = "Translate"
    let chatTranslateShowOriginal = "Show Original"
    let chatTranslateMenuHide = "Hide translation"
    let chatTranslateMenuTo = "Translate to"
    let chatHeaderTone = "Tone"
    let chatHeaderToneFormal = "Formal"
    let chatHeaderToneNeutral = "Neutral"
    let chatHeaderToneCasual = "Casual"
    let chatTranslationPoweredByCocoon = "Cocoon"
    func chatTranslateTo(_ language: String) -> String { "Translate to " + language }
    func chatTranslateMenuDoNotTranslate(_ language: String) -> String { "Do not translate " + language }
}
func strings() -> Strings { Strings() }
enum MenuAnimation {
    case menu_translate, menu_clear_history, menu_check_selected, menu_tune_fork, menu_restrict, menu_cocoon
    var value: (NSColor, ContextMenuItem) -> AppMenuItemImageDrawable {
        { _, _ in MenuIconFixture(frame: .zero) }
    }
}
final class ChatUIHooks {
    static let shared = ChatUIHooks()
    var aboutCount = 0
    func showAboutCocoonModal(_ context: Context) { aboutCount += 1 }
}

final class MenuIconFixture: View, AppMenuItemImageDrawable {
    func updateState(_ controlState: ControlState) {}
    func setColor(_ color: NSColor) {}
    func isEqual(to other: ContextMenuItem) -> Bool { false }
}
extension NSMenuItem {
    func invoke() {
        guard let item = self as? ContextMenuItem, let handler = item.handler else { preconditionFailure("Missing menu action") }
        handler()
    }
}

__TRANSLATION_MENU__
