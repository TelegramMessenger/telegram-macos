import AppKit
import TGUIKit
import ColorPalette

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let assets = imagePaths.map { name, path -> NSImage in
    let image = NSImage(contentsOfFile: path)!
    image.setName(name)
    return image
}
let originalTheme = PresentationTheme.current
func applyTheme(dark: Bool) {
    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    updateTheme(PresentationTheme(colors: dark ? nightAccentPalette : whitePalette, search: originalTheme.search, inputTheme: originalTheme.inputTheme))
}
applyTheme(dark: true)

final class Row: TableRowItem {
    override var height: CGFloat { 64 }
    override func viewClass() -> AnyClass { RowView.self }
}
final class RowView: TableRowView {
    let title = NSTextField(labelWithString: "")
    required init(frame: NSRect) { super.init(frame: frame); addSubview(title) }
    required init?(coder: NSCoder) { fatalError() }
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        title.stringValue = "Item \(item.index + 1)"
        title.textColor = presentation.colors.text
        title.font = .systemFont(ofSize: 14)
        title.sizeToFit()
    }
    override func layout() { super.layout(); title.frame.origin = NSMakePoint(20, 22) }
}
enum Scenario: String, CaseIterable { case chats, search, settings, calls, forms, emoji, stickers, gifs }
func configure(_ table: TableView, scenario: Scenario, bottom: CGFloat, top: CGFloat) {
    table.contentInsets.bottom = bottom
    let tableView = table
    let genericView = table
    let insets = NSEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
    let contentBottomInset = bottom
    switch scenario {
    case .chats:
        __CHAT_INSETS__
    case .search:
        __SEARCH_INSETS__
    case .settings:
        __SETTINGS_INSETS__
    case .calls:
        let genericView = (tableView: table, unused: false)
        __CALLS_INSETS__
    case .forms:
        let contentInsets = table.contentInsets
        __FORMS_INSETS__
__PICKER_CASES__
    }
}
func scroll(_ table: TableView, progress: CGFloat) {
    let range = max(0, table.documentSize.height - table.contentView.bounds.height + table.contentInsets.bottom)
    table.contentView.scroll(to: NSMakePoint(0, range * progress))
    table.reflectScrolledClipView(table.contentView)
    table.layoutSubtreeIfNeeded()
}
let window = NSWindow(contentRect: NSMakeRect(140, 100, 420, 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let root = View(frame: NSMakeRect(0, 0, 420, 680))
root.backgroundColor = presentation.colors.background
window.contentView = root

if Bundle.main.bundleIdentifier == "local.codex.telegram.SidebarScrollValidation" {
    NSApp.setActivationPolicy(.regular)
    window.title = "Native scrollbars · controlled rows · PID \(ProcessInfo.processInfo.processIdentifier)"
    let table = TableView(frame: root.bounds)
    table.getBackgroundColor = { presentation.colors.background }
    root.addSubview(table)
    for index in 0..<32 { _ = table.addItem(item: Row(table.bounds.size, stableId: index)) }
    configure(table, scenario: .chats, bottom: 72, top: 140)
    let header = View(frame: NSMakeRect(0, 0, 420, 140))
    header.backgroundColor = presentation.colors.background
    root.addSubview(header)
    let note = NSTextField(labelWithString: "Production TableView · native scrollbar · controlled rows")
    note.frame = NSMakeRect(12, 16, 396, 24)
    note.textColor = presentation.colors.grayText
    header.addSubview(note)
    let footer = View(frame: NSMakeRect(0, 608, 420, 72))
    footer.backgroundColor = presentation.colors.grayBackground
    root.addSubview(footer)
    let footerLabel = NSTextField(labelWithString: "Navigation overlay · 72 pt")
    footerLabel.frame = NSMakeRect(20, 24, 360, 24)
    footerLabel.textColor = presentation.colors.grayText
    footer.addSubview(footerLabel)
    final class Button: NSButton {
        var actionBlock: (() -> Void)?
        @objc func invoke() { actionBlock?() }
    }
    func button(_ title: String, x: CGFloat, action: @escaping () -> Void) {
        let b = Button(frame: NSMakeRect(x, 62, 90, 30))
        b.title = title; b.bezelStyle = .rounded; b.target = b; b.action = #selector(Button.invoke); b.actionBlock = action
        header.addSubview(b)
    }
    button("Top", x: 12) { scroll(table, progress: 0); table.flashScrollers() }
    button("Bottom", x: 110) { scroll(table, progress: 1); table.flashScrollers() }
    var dark = true
    button("Theme", x: 208) {
        dark.toggle(); applyTheme(dark: dark); table.updateLocalizationAndTheme(theme: presentation)
        root.backgroundColor = presentation.colors.background; header.backgroundColor = presentation.colors.background
        footer.backgroundColor = presentation.colors.grayBackground
        note.textColor = presentation.colors.grayText; footerLabel.textColor = presentation.colors.grayText
        table.reloadData(); table.flashScrollers()
    }
    let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
    quit.frame = NSMakeRect(306, 62, 90, 30); quit.bezelStyle = .rounded; header.addSubview(quit)
    window.makeKeyAndOrderFront(nil)
    root.layoutSubtreeIfNeeded()
    scroll(table, progress: 1)
    table.flashScrollers()
    NSApp.run()
} else {
    var checks = 0
    var failures = 0
    func check(_ ok: Bool, _ message: String) { checks += 1; if !ok { failures += 1; print("FAIL: \(message)") } }
    for scenario in Scenario.allCases {
        for height: CGFloat in [400, 800] {
            for bottom: CGFloat in ([Scenario.emoji, .stickers, .gifs].contains(scenario) ? [56] : [0, 56, 80]) {
                for top: CGFloat in scenario == .chats ? [0, 90] : [0] {
                    for count in [2, 40] {
                        let table = TableView(frame: scenario != .chats ? NSMakeRect(0, 0, 320, height) : .zero, drawBorder: true)
                        table.setFrameSize(NSMakeSize(320, height))
                        root.addSubview(table)
                        for index in 0..<count { _ = table.addItem(item: Row(table.bounds.size, stableId: index)) }
                        configure(table, scenario: scenario, bottom: bottom, top: top)
                        table.layoutSubtreeIfNeeded()
                        guard let scroller = table.verticalScroller else { check(false, "Missing native scrollbar"); continue }
                        check(scroller.scrollerStyle == .overlay, "Sidebar scrollbar disabled native overlay behavior")
                        check(table.contentView.frame.height == height, "Scrollbar styling changed the content viewport")
                        if table.documentSize.height > height {
                            let tag = "scenario=\(scenario.rawValue) height=\(height) bottom=\(bottom) top=\(top)"
                            check(abs(scroller.frame.maxY - (height - bottom)) < 0.5, "Duplicate bottom scrollbar inset: \(tag)")
                            scroll(table, progress: 0)
                            check(abs(scroller.doubleValue) < 0.001, "Top scroll progress is incorrect: \(tag)")
                            check(abs(scroller.rect(for: .knob).minY - scroller.rect(for: .knobSlot).minY) <= 1, "Thumb misses the top endpoint: \(tag)")
                            scroll(table, progress: 0.5)
                            check(abs(scroller.doubleValue - 0.5) < 0.01, "Midpoint scroll progress is incorrect: \(tag)")
                            scroll(table, progress: 1)
                            check(abs(scroller.doubleValue - 1) < 0.001, "Bottom scroll progress is incorrect: \(tag)")
                            check(abs(scroller.rect(for: .knob).maxY - scroller.rect(for: .knobSlot).maxY) <= 1, "Thumb misses the bottom endpoint: \(tag)")
                            let knob = scroller.rect(for: .knob)
                            check(scroller.testPart(scroller.convert(NSMakePoint(knob.midX, knob.midY), to: nil)) == .knob, "Native thumb hit target was lost: \(tag)")
                        } else {
                            check(scroller.knobProportion == 0 || scroller.knobProportion >= 0.99 || scroller.isHidden, "Short sidebar shows a misleading scrollbar")
                        }
                        table.removeFromSuperview()
                    }
                }
            }
        }
    }
    for height: CGFloat in [400, 800] {
        for bottom: CGFloat in [0, 56, 80] {
            let tableView = TableView(frame: NSMakeRect(0, 0, 320, height), isFlipped: false)
            root.addSubview(tableView)
            for index in 0..<40 { _ = tableView.addItem(item: Row(tableView.bounds.size, stableId: index)) }
            let content: CGFloat = 90
            let bubbleBarHeight = content
            let scrollInset = bottom
            __HISTORY_CONTENT__
            __HISTORY_SCROLLER__
            tableView.layoutSubtreeIfNeeded()
            check(tableView.hasVerticalScroller, "Chat history lost its native scroller")
            check(tableView.contentInsets.top == content && tableView.contentInsets.bottom == 0, "Chat history content insets changed")
            check(abs((tableView.verticalScroller?.frame.maxY ?? -1) - (height - bottom)) < 0.5, "Chat history input-panel exclusion was lost")
            tableView.removeFromSuperview()
        }
    }
    __THEMED_CHECKS__
    print("Application scrollbars: \(checks) checks, \(failures) failures; actual native TableView/NSScroller; source-extracted production inset configuration.")
    window.close()
    exit(failures == 0 ? 0 : 1)
}
