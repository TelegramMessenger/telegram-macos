import AppKit
import TGUIKit

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let fixtureImages: [NSImage] = __IMAGE_PATHS__.map { name, path in
    guard let image = NSImage(contentsOfFile: path) else { preconditionFailure("Missing \(name)") }
    image.setName(name)
    return image
}

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
let controller = ControllerFixture()
for width: CGFloat in [1100, 800, 650, 520, 350, 900] {
    controller.frame.size.width = width
    controller.header.state = HeaderState(main: .pinned(1))
    controller.updateHeaderInsets(width: width, animated: false)
    let pinned = controller.headerFrame()
    let insets = (controller.tableView.stick, controller.tableView.contentInsets.top)
    controller.header.state.main = .search(0, nil, nil, nil, nil, 0)
    controller.updateHeaderInsets(width: width, animated: false)
    let searchFrame = controller.headerFrame()
    if searchFrame == pinned {
        check(controller.tableView.stick == insets.0 && controller.tableView.contentInsets.top == insets.1, "inline search shifted history")
    } else {
        check(searchFrame.minY == 62 && searchFrame.width > pinned.width, "search did not fall back to a usable full row")
    }
    if let inline = controller.inlineHeaderFrame(for: width) {
        check(searchFrame == inline, "search missed inline frame")
        check(controller.headerHeight == 0, "inline header reserved another row")
        check(pinned.width >= 320 && pinned.maxX <= width, "inline controls overflowed")
    } else {
        check(searchFrame.minY == 62 && controller.headerHeight == 40, "narrow search did not use safe fallback")
    }
    let calls = controller.tableView.calls
    controller.updateHeaderInsets(width: width, animated: false)
    check(controller.tableView.calls == calls, "unchanged layout updated scroll insets")
    controller.header.state.main = .pinned(1)
    check(controller.headerFrame() == pinned, "closing search did not restore pinned slot")
}
for action: HeaderState.Value in [.restartTopic] {
    controller.header.state = HeaderState(main: action)
    for width: CGFloat in [1100, 350, 800, 350, 1100] {
        controller.frame.size.width = width
        controller.updateHeaderInsets(width: width, animated: false)
        let rect = controller.headerFrame()
        if controller.bubblesView.inlineHeaderFrame(for: width) != nil {
            check(rect.minY == 12 && rect.height == 40, "utility action missed the inline header slot")
            check(controller.headerHeight == 0 && controller.tableView.contentInsets.top == 62, "inline utility action left an empty row")
        } else {
            check(rect.minY == 62 && rect.height == 36, "narrow utility action lost its standalone row")
            check(controller.tableView.contentInsets.top == 98, "narrow utility action overlaps history")
        }
    }
    controller.header.state = HeaderState(main: action, voiceChat: true)
    check(!controller.header.state.canDisplayInline, "utility action overlaps the active call banner")
    controller.header.state = HeaderState(main: action, monoforumHorizontal: true)
    check(!controller.header.state.canDisplayInline, "utility action overlaps forum controls")
}
for action: HeaderState.Value in [.report(0, nil), .addContact, .promo, .removePaidMessages, .shareInfo, .pendingRequests, .requestChat, .setBotPhoto] {
    check(!HeaderState(main: action).canDisplayInline, "multi-action or explanatory banner was compacted")
}
controller.frame.size.width = 1100
controller.header.state = HeaderState(main: .search(0, nil, nil, [], nil, 0))
check(controller.headerHeight == 75 && controller.headerFrame().minY == 62, "saved-message tags lost their row")
controller.header.state = HeaderState(main: .search(0, nil, nil, nil, nil, 0), voiceChat: true)
check(controller.headerHeight == 80, "group-call controls overlapped inline search")
controller.header.state = HeaderState(main: .pinned(1), monoforumHorizontal: true)
check(controller.headerHeight == 80, "forum controls overlapped inline header")
controller.header.state = HeaderState(main: .pinned(1))
check(controller.headerFrame(overflow: 18).minY == 30, "navigation overflow was ignored")
controller.chatInteraction.presentation.historyCount = 0
controller.frame.size.width = 350
controller.updateHeaderInsets(width: 350, animated: false)
check(controller.tableView.contentInsets.top == 62, "empty history gained a content inset")
for back in [false, true] {
    for call in [false, true] {
        controller.bubblesView.hasBackButton = back
        controller.bubblesView.callHidden = !call
        for width: CGFloat in [350, 650, 800, 1200] {
            if let rect = controller.bubblesView.inlineHeaderFrame(for: width) {
                check(rect.width >= 320 && rect.minY == 12 && rect.height == 40, "invalid inline geometry")
                check(rect.maxX <= width - 12, "inline content covered the action cluster")
            }
        }
    }
}
let interaction = ChatInteraction()
check(chatTranslationMenuItem(chatInteraction: interaction) == nil, "translation shown without eligibility")
interaction.presentation.translateState = .init(canTranslate: false)
check(chatTranslationMenuItem(chatInteraction: interaction) == nil, "unavailable translation shown")
interaction.presentation.translateState = .init()
interaction.presentation.peer = .init(restriction: "Restricted content")
check(chatTranslationMenuItem(chatInteraction: interaction) == nil, "translation shown for restricted content")
interaction.presentation.peer = nil
for active in [false, true] {
    interaction.presentation.translateState = .init(translate: active)
    let item = chatTranslationMenuItem(chatInteraction: interaction)!
    check((item.state == .on) == active, "active translation is not marked")
    let menu = item.submenu!
    check(menu.items[0].title == (active ? "Show Original" : "Translate to English"), "wrong translation toggle")
    menu.items[0].invoke()
    check(interaction.events.last == "toggle", "toggle bypassed existing translation action")
    let languages = menu.items.first { $0.title == "Translate to" }!.submenu!
    check(languages.items.first!.title == "Russian", "app language no longer preferred")
    check((languages.items.first { $0.title == "English" } as? ContextMenuItem)?.itemImage != nil, "target language not marked")
    languages.items.first { $0.title == "German" }!.invoke()
    check(interaction.events.last == "to:de", "language selection not wired")
    menu.items.first { $0.title == "Tone" }!.submenu!.items.first { $0.title == "Casual" }!.invoke()
    check(interaction.events.last == "tone:casual", "tone selection lost")
    menu.items.first { $0.title == "Do not translate Russian" }!.invoke()
    check(interaction.events.last == "exclude:ru", "language exclusion lost")
    menu.items.first { $0.title == "Hide translation" }!.invoke()
    check(interaction.events.last == "hide", "hide action lost")
    menu.items.first { $0.title == "Cocoon" }!.invoke()
    check(ChatUIHooks.shared.aboutCount > 0, "translation provider information lost")
}
interaction.presentation.translateState = .init(paywall: true)
let paywall = chatTranslationMenuItem(chatInteraction: interaction)!.submenu!
check(paywall.items.map { $0.title } == ["Translate to English", "", "Hide translation"], "paywall exposed protected settings")
paywall.items[0].invoke()
check(interaction.events.last == "toggle", "paywall bypassed existing upgrade action")
var ephemeral: ChatInteraction? = ChatInteraction()
ephemeral!.presentation.translateState = .init()
let staleMenu = chatTranslationMenuItem(chatInteraction: ephemeral!)!.submenu!
weak var weakInteraction = ephemeral
ephemeral = nil
check(weakInteraction == nil, "menu retained chat interaction")
for item in staleMenu.items.compactMap({ $0 as? ContextMenuItem }) { item.handler?() }
print("PASS: \(checks) exact-source header placement, history inset, translation menu and callback checks")

runNativeSearchChecks()
runActivityChecks()

runUtilityHeaderChecks()
