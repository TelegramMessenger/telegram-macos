import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows

final class StarTransactionTabsRowItem: GeneralRowItem {
    let items: [ScrollableSegmentItem]
    let callback: (Int64) -> Void

    static let contentInset: CGFloat = 16

    init(_ initialSize: NSSize, stableId: AnyHashable, items: [ScrollableSegmentItem], viewType: GeneralViewType, callback: @escaping (Int64) -> Void) {
        self.items = items
        self.callback = callback
        super.init(initialSize, height: GlassSegmentView.height + Self.contentInset * 2, stableId: stableId, viewType: viewType)
    }

    override var hasBorder: Bool {
        return false
    }

    override func viewClass() -> AnyClass {
        return StarTransactionTabsRowView.self
    }

    override var accessibilityLabel: String? {
        return items.first(where: { $0.selected })?.title ?? items.first?.title
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .radioGroup
    }
}

private final class StarTransactionTabAccessibilityElement: NSAccessibilityElement {
    weak var view: NSView?
    var frameInView: NSRect = .zero
    var press: (() -> Bool)?
    var reveal: (() -> Void)?

    override func accessibilityFrame() -> NSRect {
        guard let view else { return .zero }
        return NSAccessibility.screenRect(fromView: view, rect: frameInView)
    }

    override func accessibilityPerformPress() -> Bool {
        return press?() ?? false
    }

    override func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        if accessibilityFocused {
            reveal?()
        }
        super.setAccessibilityFocused(accessibilityFocused)
    }
}

private final class StarTransactionTabsRowView: GeneralContainableRowView {
    private let scrollView = HorizontalScrollView(frame: .zero)
    private let documentView = View()
    private let segments = GlassSegmentView(frame: .zero)
    private var accessibilityTabs: [StarTransactionTabAccessibilityElement] = []
    private var focusSelection = false
    private var animateSelection = false

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scrollView)
        scrollView.documentView = documentView
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.contentView.drawsBackground = false
        documentView.addSubview(segments)
        segments.didSelect = { [weak self] index in
            guard let item = self?.item as? StarTransactionTabsRowItem, item.items.indices.contains(index) else {
                return
            }
            item.callback(item.items[index].uniqueId)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityChildren() -> [Any]? {
        return TGUIKitAccessibility.isEnabled ? accessibilityTabs : nil
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? StarTransactionTabsRowItem else { return }
        let selected = item.items.firstIndex(where: { $0.selected })
        focusSelection = focusSelection || segments.selectedIndex != selected || segments.titles != item.items.map { $0.title }
        animateSelection = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        segments.updateLocalizationAndTheme(theme: theme)
        segments.set(titles: item.items.map { $0.title }, selected: selected, animated: animateSelection)
        let previous = accessibilityTabs
        let frames = segments.itemFrames
        accessibilityTabs = item.items.enumerated().map { index, tab in
            let identifier = String(tab.uniqueId)
            let element = previous.first(where: { $0.accessibilityIdentifier() == identifier }) ?? StarTransactionTabAccessibilityElement()
            element.view = segments
            element.frameInView = frames[index]
            element.setAccessibilityElement(true)
            element.setAccessibilityParent(self)
            element.setAccessibilityIdentifier(identifier)
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityLabel(tab.accessibilityLabel?() ?? tab.title)
            element.setAccessibilityValue(NSNumber(value: tab.selected))
            element.setAccessibilitySelected(tab.selected)
            element.reveal = { [weak self] in
                self?.revealTab(tab.uniqueId)
            }
            element.press = { [weak self] in
                guard let self, let item = self.item as? StarTransactionTabsRowItem, item.items.contains(where: { $0.uniqueId == tab.uniqueId }) else {
                    return false
                }
                self.revealTab(tab.uniqueId)
                item.callback(tab.uniqueId)
                return true
            }
            return element
        }
        needsLayout = true
    }

    private func revealTab(_ id: Int64) {
        guard let item = item as? StarTransactionTabsRowItem, let index = item.items.firstIndex(where: { $0.uniqueId == id }) else {
            return
        }
        layoutSubtreeIfNeeded()
        scrollToSegment(at: index, animated: false)
    }

    private func scrollToSegment(at index: Int, animated: Bool) {
        guard segments.itemFrames.indices.contains(index) else { return }
        let frame = segments.convert(segments.itemFrames[index], to: documentView)
        let maxOffset = max(0, documentView.frame.width - scrollView.clipView.bounds.width)
        let offset = min(max(0, frame.midX - scrollView.clipView.bounds.width / 2), maxOffset)
        let point = NSPoint(x: offset, y: 0)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if point != scrollView.documentOffset {
                scrollView.clipView.scroll(to: point, animated: true)
            }
        } else {
            scrollView.clipView.updateBounds(to: point, cancel: true)
            scrollView.clipView.layer?.removeAnimation(forKey: "bounds")
        }
        scrollView.reflectScrolledClipView(scrollView.clipView)
    }

    override func updateColors() {
        super.updateColors()
        segments.updateLocalizationAndTheme(theme: theme)
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        needsLayout = true
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        let contentSize = segments.contentSize
        let inset = StarTransactionTabsRowItem.contentInset
        let documentSize = NSMakeSize(contentSize.width + inset * 2, contentSize.height + inset * 2)
        let viewportWidth = min(max(0, containerView.bounds.width), documentSize.width)
        let frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (containerView.bounds.width - viewportWidth) / 2), 0, viewportWidth, documentSize.height)
        let resized = scrollView.frame.size != frame.size || documentView.frame.size != documentSize
        transition.updateFrame(view: scrollView, frame: frame)
        documentView.setFrameSize(documentSize)
        segments.frame = NSRect(origin: NSPoint(x: inset, y: inset), size: contentSize)
        if (focusSelection || resized), let selected = segments.selectedIndex {
            scrollToSegment(at: selected, animated: focusSelection && animateSelection && !resized)
        } else if resized {
            let maxOffset = max(0, documentSize.width - viewportWidth)
            let offset = min(max(0, scrollView.clipView.bounds.minX), maxOffset)
            scrollView.clipView.updateBounds(to: NSPoint(x: offset, y: 0), cancel: true)
            scrollView.clipView.layer?.removeAnimation(forKey: "bounds")
            scrollView.reflectScrolledClipView(scrollView.clipView)
        }
        focusSelection = false
        animateSelection = false
    }
}
