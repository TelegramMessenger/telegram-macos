import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows

public final class WalletTabsRowItem: GeneralRowItem {
    fileprivate let titles: [String]
    fileprivate let selectedIndex: Int
    fileprivate let callback: (Int) -> Void

    public init(_ initialSize: NSSize, stableId: AnyHashable, titles: [String], selectedIndex: Int, viewType: GeneralViewType, callback: @escaping (Int) -> Void) {
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.callback = callback
        super.init(initialSize, height: WalletTabsView.height, stableId: stableId, viewType: viewType)
    }

    public override func viewClass() -> AnyClass {
        return WalletTabsRowView.self
    }

    public override var accessibilityLabel: String? {
        guard titles.indices.contains(selectedIndex) else {
            return titles.joined(separator: ", ")
        }
        return titles[selectedIndex]
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        let callback = self.callback
        return titles.enumerated().map { index, title in
            return NSAccessibilityCustomAction(name: title, handler: {
                callback(index)
                return true
            })
        }
    }
}

private final class WalletTabsRowView: GeneralRowView {
    private let tabsView = WalletTabsView(frame: .zero)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        layer?.zPosition = 1
        addSubview(tabsView)

        tabsView.didSelect = { [weak self] index in
            (self?.item as? WalletTabsRowItem)?.callback(index)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletTabsRowItem else {
            return
        }
        tabsView.update(titles: item.titles, selectedIndex: item.selectedIndex, animated: animated)
        needsLayout = true
    }

    override func updateColors() {
        super.updateColors()
        tabsView.updateTheme()
    }

    override func layout() {
        super.layout()
        guard let item = item as? GeneralRowItem else {
            return
        }
        tabsView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), 0, item.blockWidth, WalletTabsView.height)
    }
}

private final class WalletTabsView: View {
    static let height: CGFloat = 40
    private static let lensInset: CGFloat = 3
    private static let itemInset: CGFloat = 16

    private let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: WalletTabsView.height / 2, hasShadow: true, hasBorder: true)
    private let selectionView = View()
    private var labels: [TextView] = []
    private var titles: [String] = []
    private var selectedIndex: Int?
    private var selectionPosition: CGFloat?
    private lazy var lens = GlassSelectionLens(host: self, selectionView: selectionView)
    private var lifted = false

    var didSelect: ((Int) -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        addSubview(glass)
        selectionView.isHidden = true
        selectionView.layer?.cornerRadius = (WalletTabsView.height - WalletTabsView.lensInset * 2) / 2
        addSubview(selectionView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(titles: [String], selectedIndex: Int, animated: Bool) {
        if self.titles != titles {
            self.titles = titles
            while labels.count > titles.count {
                labels.removeLast().removeFromSuperview()
            }
            while labels.count < titles.count {
                let label = TextView()
                label.userInteractionEnabled = false
                label.isSelectable = false
                (lens.contentView ?? self).addSubview(label)
                labels.append(label)
            }
            updateTheme()
        }
        setSelected(selectedIndex, animated: animated)
    }

    func updateTheme() {
        selectionView.backgroundColor = theme.colors.text.withAlphaComponent(theme.colors.isDark ? 0.1 : 0.075)
        for (label, title) in zip(labels, titles) {
            let layout = TextViewLayout(.initialize(string: title, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
            layout.measure(width: .greatestFiniteMagnitude)
            label.update(layout)
        }
        needsLayout = true
    }

    private func setSelected(_ index: Int, animated: Bool) {
        guard selectedIndex != index else {
            return
        }
        selectedIndex = index
        setSelection(position: CGFloat(index), animated: animated)
    }

    private func setSelection(position: CGFloat, animated: Bool) {
        if !animated {
            selectionView.layer?.removeAllAnimations()
        }
        selectionPosition = position
        updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.4, curve: .spring) : .immediate)
    }

    private func selectionFrame(at position: CGFloat, slots: [NSRect]) -> NSRect {
        let clamped = min(max(position, 0), CGFloat(slots.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, slots.count - 1)
        let progress = clamped - CGFloat(lower)
        let minX = slots[lower].minX + (slots[upper].minX - slots[lower].minX) * progress
        let width = slots[lower].width + (slots[upper].width - slots[lower].width) * progress
        return NSMakeRect(minX, slots[lower].minY, width, slots[lower].height)
    }

    private func position(forCenterX x: CGFloat, slots: [NSRect]) -> CGFloat {
        let centers = slots.map { $0.midX }
        for index in 0 ..< max(centers.count - 1, 0) where x < centers[index + 1] {
            return CGFloat(index) + max(0, x - centers[index]) / (centers[index + 1] - centers[index])
        }
        return CGFloat(max(centers.count - 1, 0))
    }

    private var slotFrames: [NSRect] {
        let itemWidths = labels.map { $0.frame.width + WalletTabsView.itemInset * 2 }
        let lensWidth = max(0, frame.width - WalletTabsView.lensInset * 2)
        let slotWidths = walletTabsFillSlotWidths(itemWidths: itemWidths, availableWidth: lensWidth, paddingAllowance: WalletTabsView.lensInset * 2) ?? itemWidths
        var x = WalletTabsView.lensInset
        return slotWidths.map { width in
            let slot = NSMakeRect(x, WalletTabsView.lensInset, width, WalletTabsView.height - WalletTabsView.lensInset * 2)
            x = slot.maxX
            return slot
        }
    }

    private func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if lens.updateMode(content: labels) {
            lifted = false
        }
        transition.updateFrame(view: glass, frame: size.bounds)
        glass.updateLayout(size: size, transition: transition)

        let slots = slotFrames
        for (label, slot) in zip(labels, slots) {
            label.setFrameOrigin(NSMakePoint(slot.minX + floorToScreenPixels(backingScaleFactor, (slot.width - label.frame.width) / 2), floorToScreenPixels(backingScaleFactor, (size.height - label.frame.height) / 2)))
        }

        var selection: NSRect?
        if let selectionPosition, !slots.isEmpty {
            let frame = selectionFrame(at: selectionPosition, slots: slots)
            let selectionTransition: ContainedViewLayoutTransition = selectionView.isHidden ? .immediate : transition
            selectionView.isHidden = false
            selectionTransition.updateFrame(view: selectionView, frame: frame)
            selection = frame
        } else {
            selectionView.isHidden = true
        }
        lens.update(selection: selection, lifted: lifted, sources: labels, appearance: theme.appearance, transition: transition)
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    override func mouseDown(with event: NSEvent) {
        let slots = slotFrames
        let start = convert(event.locationInWindow, from: nil)
        guard let window, !slots.isEmpty else {
            return
        }
        let pressedIndex = slots.firstIndex(where: { start.x < $0.maxX }) ?? slots.count - 1
        var position = CGFloat(pressedIndex)
        var moved = false
        lens.updateMode(content: labels)
        lifted = lens.liftsOnPress
        if pressedIndex != selectedIndex || lifted {
            setSelection(position: position, animated: true)
        }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .pressure]) {
            if next.type == .leftMouseUp {
                let index = Int(position.rounded())
                lifted = false
                if moved || bounds.contains(convert(next.locationInWindow, from: nil)) {
                    setSelection(position: CGFloat(index), animated: true)
                    if index != selectedIndex {
                        selectedIndex = index
                        didSelect?(index)
                    }
                } else if let selectedIndex {
                    setSelection(position: CGFloat(selectedIndex), animated: true)
                } else {
                    updateLayout(size: frame.size, transition: .animated(duration: 0.4, curve: .spring))
                }
                break
            }
            guard next.type == .leftMouseDragged else {
                continue
            }
            let point = convert(next.locationInWindow, from: nil)
            moved = moved || abs(point.x - start.x) > 2
            if moved {
                position = self.position(forCenterX: slots[pressedIndex].midX + point.x - start.x, slots: slots)
                setSelection(position: position, animated: false)
            }
        }
    }
}

private func walletTabsFillSlotWidths(itemWidths: [CGFloat], availableWidth: CGFloat, paddingAllowance: CGFloat) -> [CGFloat]? {
    if itemWidths.isEmpty {
        return []
    }
    let totalWidth = itemWidths.reduce(0, +)
    if totalWidth > availableWidth + paddingAllowance {
        return nil
    }

    let exactWidths: [CGFloat]
    if totalWidth > availableWidth {
        let paddingReduction = (totalWidth - availableWidth) / CGFloat(itemWidths.count)
        exactWidths = itemWidths.map { $0 - paddingReduction }
    } else {
        var remainingWidth = availableWidth
        var remainingCount = itemWidths.count
        var commonWidth = availableWidth
        for itemWidth in itemWidths.sorted(by: >) {
            commonWidth = remainingWidth / CGFloat(remainingCount)
            if itemWidth <= commonWidth {
                break
            }
            remainingWidth -= itemWidth
            remainingCount -= 1
        }
        exactWidths = itemWidths.map { max($0, commonWidth) }
    }

    var slotWidths: [CGFloat] = []
    var exactEdge: CGFloat = 0
    var edge: CGFloat = 0
    for (index, exactWidth) in exactWidths.enumerated() {
        exactEdge += exactWidth
        let nextEdge = index == exactWidths.count - 1 ? availableWidth : exactEdge.rounded()
        slotWidths.append(nextEdge - edge)
        edge = nextEdge
    }
    return slotWidths
}
