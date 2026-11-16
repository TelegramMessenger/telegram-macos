import Cocoa
import TGUIKit
import TelegramCore
import TelegramMedia
import TelegramTheme
import InlineStickerLayer

final class PeerMediaTabsView: View, HorizontalScrollConsuming {
    struct Tab: Equatable {
        let id: Int64
        let title: String
        let gifts: [ProfileGiftsContext.State.StarGift]
    }

    static let height: CGFloat = 40
    private static let lensInset: CGFloat = 3
    private static let itemInset: CGFloat = 16
    private static let giftIconSize: CGFloat = 18
    private static let giftIconSpacing: CGFloat = 1
    private static let giftTitleSpacing: CGFloat = 2
    private static let scrollLookahead: CGFloat = 100

    private final class ItemView: View {
        private let textView = TextView()
        private var giftViews: [AnyHashable: InlineStickerView] = [:]
        private var giftOrder: [AnyHashable] = []
        private(set) var contentWidth: CGFloat = 0

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            addSubview(textView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(tab: Tab, account: Account, theme: TelegramPresentationTheme, animated: Bool) {
            let layout = TextViewLayout(.initialize(string: tab.title, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
            layout.measure(width: .greatestFiniteMagnitude)
            textView.update(layout)

            var validIds: [AnyHashable] = []
            for (index, gift) in tab.gifts.enumerated() {
                let id: AnyHashable = gift.reference.flatMap { AnyHashable($0) } ?? AnyHashable(index)
                guard let file = PeerMediaTabsView.iconFile(gift) else {
                    continue
                }
                validIds.append(id)
                if giftViews[id] == nil {
                    let size = NSMakeSize(PeerMediaTabsView.giftIconSize, PeerMediaTabsView.giftIconSize)
                    let view = InlineStickerView(account: account, file: file, size: size, playPolicy: .playCount(1))
                    addSubview(view)
                    giftViews[id] = view
                    if animated {
                        view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                        view.layer?.animateScaleCenter(from: 0.01, to: 1, duration: 0.2)
                    }
                }
            }
            for (id, view) in giftViews where !validIds.contains(id) {
                giftViews.removeValue(forKey: id)
                if animated {
                    view.layer?.animateScaleCenter(from: 1, to: 0.01, duration: 0.25, removeOnCompletion: false)
                }
                performSubviewRemoval(view, animated: animated, duration: 0.25)
            }
            giftOrder = validIds

            var width = textView.frame.width
            if !validIds.isEmpty {
                width += PeerMediaTabsView.giftIconSpacing + CGFloat(validIds.count) * (PeerMediaTabsView.giftIconSize + PeerMediaTabsView.giftIconSpacing)
            }
            contentWidth = width
            needsLayout = true
        }

        override func layout() {
            super.layout()
            let originX = floorToScreenPixels(backingScaleFactor, (frame.width - contentWidth) / 2)
            textView.setFrameOrigin(NSMakePoint(originX, floorToScreenPixels(backingScaleFactor, (frame.height - textView.frame.height) / 2)))
            var iconX = textView.frame.maxX + PeerMediaTabsView.giftTitleSpacing
            for id in giftOrder {
                if let view = giftViews[id] {
                    view.setFrameOrigin(NSMakePoint(iconX, floorToScreenPixels(backingScaleFactor, (frame.height - view.frame.height) / 2)))
                    iconX += PeerMediaTabsView.giftIconSize + PeerMediaTabsView.giftIconSpacing
                }
            }
        }
    }

    private struct SelectionGesture {
        let start: NSPoint
        let center: CGFloat
        let range: ClosedRange<CGFloat>
        var position: CGFloat
        var isDragging = false
    }

    private let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: PeerMediaTabsView.height / 2, hasShadow: true, hasBorder: true)
    private let clipView = View()
    private let contentView = View()
    private let selectionView = View()
    private var itemViews: [Int64: ItemView] = [:]

    private(set) var tabs: [Tab] = []
    private(set) var selectedId: Int64?
    private var selectionPosition: CGFloat?
    private var scrollOffset: CGFloat = 0
    private var currentTheme: TelegramPresentationTheme = theme
    private var account: Account?
    private var focusSelectedOnLayout = false
    private lazy var lens: GlassSelectionLens = {
        let lens = GlassSelectionLens(host: self, selectionView: selectionView)
        lens.onCancel = { [weak self] in
            self?.cancelSelection(animated: true)
        }
        return lens
    }()
    private var gesture: SelectionGesture?

    var didSelect: ((Int64) -> Void)?
    var menuItems: ((Int64, Int) -> [ContextMenuItem])?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        isHidden = true
        addSubview(glass)
        clipView.layer?.masksToBounds = true
        clipView.layer?.cornerRadius = (PeerMediaTabsView.height - PeerMediaTabsView.lensInset * 2) / 2
        addSubview(clipView)
        clipView.addSubview(contentView)
        selectionView.isHidden = true
        selectionView.layer?.cornerRadius = (PeerMediaTabsView.height - PeerMediaTabsView.lensInset * 2) / 2
        contentView.addSubview(selectionView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHidden: Bool {
        didSet {
            if isHidden {
                cancelSelection(animated: false)
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelSelection(animated: false)
    }

    static func iconFile(_ gift: ProfileGiftsContext.State.StarGift) -> TelegramMediaFile? {
        switch gift.gift {
        case let .generic(gift):
            return gift.file
        case let .unique(gift):
            for attribute in gift.attributes {
                if case let .model(_, file, _, _) = attribute {
                    return file
                }
            }
            return nil
        }
    }

    func index(of id: Int64) -> Int? {
        return tabs.firstIndex(where: { $0.id == id })
    }

    func contains(_ id: Int64) -> Bool {
        return index(of: id) != nil
    }

    private var itemFrames: [NSRect] {
        var x: CGFloat = 0
        return tabs.map { tab in
            let width = (itemViews[tab.id]?.contentWidth ?? 0) + PeerMediaTabsView.itemInset * 2
            let frame = NSMakeRect(x, 0, width, PeerMediaTabsView.height - PeerMediaTabsView.lensInset * 2)
            x = frame.maxX
            return frame
        }
    }

    private var contentWidth: CGFloat {
        return itemFrames.last?.maxX ?? 0
    }

    func size(fitting width: CGFloat) -> NSSize {
        return NSMakeSize(min(width, contentWidth + PeerMediaTabsView.lensInset * 2), PeerMediaTabsView.height)
    }

    func update(tabs: [Tab], selected: Int64?, account: Account, animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.4, curve: .spring) : .immediate
        let previousIds = Set(self.tabs.map { $0.id })
        let selectionChanged = self.selectedId != selected
        if gesture != nil, self.tabs.map({ $0.id }) != tabs.map({ $0.id }) {
            finishGesture()
        }

        self.tabs = tabs
        self.selectedId = selected
        self.account = account
        self.isHidden = tabs.isEmpty

        let validIds = Set(tabs.map { $0.id })
        for (id, view) in itemViews where !validIds.contains(id) {
            itemViews.removeValue(forKey: id)
            if animated {
                view.layer?.animateScaleCenter(from: 1, to: 0.01, duration: 0.25, removeOnCompletion: false)
            }
            performSubviewRemoval(view, animated: animated, duration: 0.25)
        }
        for tab in tabs {
            let view: ItemView
            if let current = itemViews[tab.id] {
                view = current
            } else {
                view = ItemView(frame: .zero)
                contentView.addSubview(view)
                itemViews[tab.id] = view
            }
            view.update(tab: tab, account: account, theme: currentTheme, animated: animated && previousIds.contains(tab.id))
        }

        let frames = itemFrames
        for (tab, itemFrame) in zip(tabs, frames) {
            guard let view = itemViews[tab.id] else {
                continue
            }
            if !previousIds.contains(tab.id) {
                view.frame = itemFrame
                if animated, !previousIds.isEmpty {
                    view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    view.layer?.animateScaleCenter(from: 0.01, to: 1, duration: 0.3)
                }
            } else {
                transition.updateFrame(view: view, frame: itemFrame)
            }
            view.needsLayout = true
        }

        selectionPosition = selected.flatMap { id in tabs.firstIndex(where: { $0.id == id }) }.flatMap { CGFloat($0) }
        if selectionChanged {
            focusSelectedOnLayout = true
        }
    }

    func apply(frame: NSRect, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self, frame: frame)
        updateLayout(size: frame.size, transition: transition)
    }

    func setSelection(position: CGFloat, animated: Bool) {
        if gesture != nil {
            finishGesture()
        }
        if !animated {
            selectionView.layer?.removeAllAnimations()
        }
        selectionPosition = position
        focusSelectedOnLayout = true
        updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.4, curve: .spring) : .immediate)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        guard let theme = theme as? TelegramPresentationTheme else {
            return
        }
        currentTheme = theme
        if let account {
            update(tabs: tabs, selected: selectedId, account: account, animated: false)
        }
        updateLayout(size: frame.size, transition: .immediate)
    }

    private func selectionFrame(at position: CGFloat, frames: [NSRect]) -> NSRect {
        let clamped = min(max(position, 0), CGFloat(frames.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, frames.count - 1)
        let progress = clamped - CGFloat(lower)
        let minX = frames[lower].minX + (frames[upper].minX - frames[lower].minX) * progress
        let width = frames[lower].width + (frames[upper].width - frames[lower].width) * progress
        return NSMakeRect(minX, 0, width, frames[lower].height)
    }

    private func position(at x: CGFloat, frames: [NSRect]) -> CGFloat {
        for index in 0 ..< max(0, frames.count - 1) where x < frames[index + 1].midX {
            let distance = frames[index + 1].midX - frames[index].midX
            return CGFloat(index) + min(1, max(0, (x - frames[index].midX) / max(1, distance)))
        }
        return CGFloat(max(0, frames.count - 1))
    }

    private func clampedScrollOffset(_ offset: CGFloat, visibleWidth: CGFloat) -> CGFloat {
        return max(0, min(offset, contentWidth - visibleWidth))
    }

    private func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if lens.updateMode(content: [clipView]) {
            finishGesture()
        }
        let focusSelected = focusSelectedOnLayout
        focusSelectedOnLayout = false
        selectionView.backgroundColor = currentTheme.colors.text.withAlphaComponent(currentTheme.colors.isDark ? 0.1 : 0.075)

        transition.updateFrame(view: glass, frame: size.bounds)
        glass.updateLayout(size: size, transition: transition)

        let inset = PeerMediaTabsView.lensInset
        let clipFrame = NSMakeRect(inset, inset, max(0, size.width - inset * 2), max(0, size.height - inset * 2))
        transition.updateFrame(view: clipView, frame: clipFrame)

        let frames = itemFrames
        var selection: NSRect?
        if let position = selectionPosition, !frames.isEmpty {
            selection = selectionFrame(at: position, frames: frames)
        }

        var offset = clampedScrollOffset(scrollOffset, visibleWidth: clipFrame.width)
        if focusSelected, let selection {
            let lookahead = PeerMediaTabsView.scrollLookahead
            if offset + clipFrame.width - lookahead < selection.maxX {
                offset = selection.maxX - clipFrame.width + lookahead
            }
            if offset > selection.minX - lookahead {
                offset = selection.minX - lookahead
            }
            offset = clampedScrollOffset(offset, visibleWidth: clipFrame.width)
        }
        scrollOffset = offset
        transition.updateFrame(view: contentView, frame: NSMakeRect(-offset, 0, max(contentWidth, clipFrame.width), clipFrame.height))

        if let selection {
            let selectionTransition: ContainedViewLayoutTransition = selectionView.isHidden ? .immediate : transition
            selectionView.isHidden = false
            selectionTransition.updateFrame(view: selectionView, frame: selection)
        } else {
            selectionView.isHidden = true
        }
        updateLens(transition: transition)
    }

    private func updateLens(transition: ContainedViewLayoutTransition) {
        let frames = itemFrames
        let position = gesture?.position ?? selectionPosition
        let selection = position.flatMap { frames.isEmpty ? nil : contentView.convert(selectionFrame(at: $0, frames: frames), to: self) }
        let visible = clipView.bounds
        let sources: [NSView] = tabs.compactMap { tab in
            guard let view = itemViews[tab.id], visible.contains(view.convert(view.bounds, to: clipView)) else {
                return nil
            }
            return view
        }
        lens.update(selection: selection, clip: clipView.frame, lifted: gesture != nil, sources: sources, appearance: currentTheme.appearance, transition: transition)
    }

    private func beginSelection(at point: NSPoint) -> Bool {
        if lens.updateMode(content: [clipView]) {
            finishGesture()
        }
        guard lens.liftsOnPress, !isHidden, let tab = tabId(at: point) else {
            return false
        }
        finishGesture()
        let frames = itemFrames
        let visible = NSMakeRect(scrollOffset, 0, clipView.frame.width, clipView.frame.height)
        let fullyVisible = frames.indices.filter { visible.contains(frames[$0]) }
        let lower = min(fullyVisible.first ?? tab.index, tab.index)
        let upper = max(fullyVisible.last ?? tab.index, tab.index)
        gesture = SelectionGesture(start: point, center: frames[tab.index].midX, range: CGFloat(lower) ... CGFloat(upper), position: CGFloat(tab.index))
        lens.startTracking()
        updateLens(transition: .animated(duration: 0.4, curve: .spring))
        return true
    }

    private func updateSelection(at point: NSPoint) {
        guard var gesture, gesture.isDragging || abs(point.x - gesture.start.x) >= 3 else {
            return
        }
        gesture.isDragging = true
        let position = min(max(self.position(at: gesture.center + point.x - gesture.start.x, frames: itemFrames), gesture.range.lowerBound), gesture.range.upperBound)
        let changed = gesture.position != position
        gesture.position = position
        self.gesture = gesture
        if changed {
            updateLens(transition: .immediate)
        }
    }

    private func endSelection(at point: NSPoint) {
        guard let current = gesture else {
            return
        }
        if current.isDragging {
            updateSelection(at: point)
        } else if !bounds.contains(point) {
            cancelSelection(animated: true)
            return
        }
        let index = Int((gesture?.position ?? current.position).rounded())
        finishGesture()
        guard tabs.indices.contains(index) else {
            updateLens(transition: .animated(duration: 0.4, curve: .spring))
            return
        }
        let id = tabs[index].id
        if CGFloat(index) != selectionPosition {
            selectionPosition = CGFloat(index)
            selectionView.layer?.removeAllAnimations()
            selectionView.frame = itemFrames[index]
            focusSelectedOnLayout = true
        }
        updateLayout(size: frame.size, transition: .animated(duration: 0.4, curve: .spring))
        didSelect?(id)
    }

    private func cancelSelection(animated: Bool) {
        guard gesture != nil else {
            return
        }
        finishGesture()
        updateLens(transition: animated ? .animated(duration: 0.4, curve: .spring) : .immediate)
    }

    private func finishGesture() {
        gesture = nil
        lens.stopTracking()
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    private func tabId(at point: NSPoint) -> (id: Int64, index: Int)? {
        let location = contentView.convert(point, from: self)
        for (index, itemFrame) in itemFrames.enumerated() where location.x >= itemFrame.minX && location.x < itemFrame.maxX {
            return (tabs[index].id, index)
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
        } else {
            _ = beginSelection(at: convert(event.locationInWindow, from: nil))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if gesture != nil {
            endSelection(at: point)
            return
        }
        guard !event.modifierFlags.contains(.control) else {
            return
        }
        if bounds.contains(point), let tab = tabId(at: point) {
            didSelect?(tab.id)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let tab = tabId(at: point), let items = menuItems?(tab.id, tab.index), !items.isEmpty else {
            return
        }
        ContextMenu.show(items: items, view: self, event: event)
    }

    func consumesHorizontalScroll(atWindowPoint windowPoint: NSPoint) -> Bool {
        return !isHidden && contentWidth > clipView.frame.width && bounds.contains(convert(windowPoint, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        let visibleWidth = clipView.frame.width
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), contentWidth > visibleWidth {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 10
            scrollOffset = clampedScrollOffset(scrollOffset - delta, visibleWidth: visibleWidth)
            contentView.setFrameOrigin(NSMakePoint(-scrollOffset, 0))
            updateLens(transition: .immediate)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
