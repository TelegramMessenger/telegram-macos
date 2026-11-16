import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import Localization
import SidebarUI

enum ForumDisplayMode: Equatable {
    case sidebar
    case tabs
    case list
}

final class ForumDisplayModeItem: GeneralRowItem {
    let mode: ForumDisplayMode
    let select: (ForumDisplayMode) -> Void
    let sidebarImage: CGImage
    let tabsImage: CGImage
    let listImage: CGImage

    init(_ initialSize: NSSize, stableId: AnyHashable, mode: ForumDisplayMode, select: @escaping (ForumDisplayMode) -> Void) {
        self.mode = mode
        self.select = select
        sidebarImage = ForumSettingsHooks.shared.sidebarPreviewImage().precomposed(theme.colors.grayIcon.withAlphaComponent(0.8))
        tabsImage = ForumSettingsHooks.shared.sidebarImage(.iconForumTabs).precomposed(theme.colors.grayIcon.withAlphaComponent(0.8))
        listImage = ForumSettingsHooks.shared.sidebarImage(.iconForumList).precomposed(theme.colors.grayIcon.withAlphaComponent(0.8))
        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }

    override var height: CGFloat { 178 }

    override func viewClass() -> AnyClass { ForumDisplayModeView.self }
}

private final class ForumDisplayChoice: Control {
    let imageView = ImageView()
    let titleLabel = NSTextField(labelWithString: "")

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(titleLabel)
        imageView.isEventLess = true
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(image: CGImage, title: String, selected: Bool) {
        imageView.image = image
        titleLabel.stringValue = title
        titleLabel.textColor = selected ? theme.colors.accent : theme.colors.text
        setAccessibilityLabel(title)
        setAccessibilityValue(selected ? strings().voiceOverCommonSelected : strings().voiceOverCommonNotSelected)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = selected ? theme.colors.accent.withAlphaComponent(0.1).cgColor : NSColor.clear.cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        imageView.frame = NSMakeRect((bounds.width - 100) / 2, 7, 100, 110)
        titleLabel.frame = NSMakeRect(0, 125, bounds.width, 20)
    }
}

private final class ForumDisplayModeView: GeneralContainableRowView {
    private let sidebar = ForumDisplayChoice(frame: .zero)
    private let tabs = ForumDisplayChoice(frame: .zero)
    private let list = ForumDisplayChoice(frame: .zero)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(sidebar)
        addSubview(tabs)
        addSubview(list)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? ForumDisplayModeItem else { return }
        sidebar.set(image: item.sidebarImage, title: "Sidebar", selected: item.mode == .sidebar)
        tabs.set(image: item.tabsImage, title: strings().chatListMonoforumTabBarTabs, selected: item.mode == .tabs)
        list.set(image: item.listImage, title: strings().chatListMonoforumTabBarList, selected: item.mode == .list)
        for view in [sidebar, tabs, list] { view.removeAllHandlers() }
        sidebar.set(handler: { [weak item] _ in item?.select(.sidebar) }, for: .Click)
        tabs.set(handler: { [weak item] _ in item?.select(.tabs) }, for: .Click)
        list.set(handler: { [weak item] _ in item?.select(.list) }, for: .Click)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8
        let width = max(0, (containerView.bounds.width - inset * 4) / 3)
        sidebar.frame = NSMakeRect(inset, 12, width, 150)
        tabs.frame = NSMakeRect(inset * 2 + width, 12, width, 150)
        list.frame = NSMakeRect(inset * 3 + width * 2, 12, width, 150)
    }
}
