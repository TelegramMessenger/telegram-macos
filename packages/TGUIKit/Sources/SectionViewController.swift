import Cocoa
import SwiftSignalKit
import AppKit

public class SectionControllerView : View {
    fileprivate var onLayout: (() -> Void)?

    public var _backgroundColor: NSColor? {
        didSet {
            updateLocalizationAndTheme(theme: presentation)
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateLocalizationAndTheme(theme: presentation)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.backgroundColor = _backgroundColor ?? presentation.colors.background
    }

    public override func layout() {
        super.layout()
        onLayout?()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class SectionControllerItem {
    public let title: ()->String
    public let controller: ViewController
    public init(title: @escaping()->String, controller: ViewController) {
        self.title = title
        self.controller = controller
    }
}


open class SectionViewController: GenericViewController<SectionControllerView> {
    private enum Appearance {
        case disappeared
        case appearing
        case appeared
        case disappearing
    }

    private enum Axis {
        case undecided
        case horizontal
        case vertical
    }

    private struct Gesture {
        var axis: Axis = .undecided
        var beganPassedThrough: Bool = false
        var samples: [(timestamp: TimeInterval, delta: CGFloat)] = []
    }

    private static let settleDuration: Double = 0.4
    private static let velocityWindow: TimeInterval = 0.1
    private static let switchVelocity: CGFloat = 180
    private static let switchFraction: CGFloat = 0.35

    public private(set) var sections:[SectionControllerItem] = []
    public private(set) var selectedIndex: Int
    public var selectedSection: SectionControllerItem {
        return sections[selectedIndex]
    }

    public var selectionUpdateHandler:((Int)->Void)?
    public var selectorPositionHandler:((CGFloat, Bool)->Void)?

    private let disposable = MetaDisposable()
    private var appearances: [Appearance]
    private var attached: Set<Int> = []
    private var parkedIndex: Int?
    private var pendingIndex: Int?
    private var offset: CGFloat = 0
    private var settleGeneration: Int = 0
    private var gesture: Gesture?
    private var swallowsMomentum: Bool = false
    private var isVisible: Bool = false

    public init(sections: [SectionControllerItem], selected: Int = 0, hasBar: Bool = false) {
        assert(!sections.isEmpty)
        self.sections = sections
        self.selectedIndex = selected
        self.appearances = sections.map { _ in .disappeared }
        super.init()
        bar = .init(height: hasBar ? 64 : 0)
    }

    deinit {
        disposable.dispose()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        genericView.onLayout = { [weak self] in
            self?.layoutPages()
        }
        attach(selectedIndex)
        self.ready.set(selectedSection.controller.ready.get())
    }

    public func select(_ index:Int, _ animated: Bool) {
        guard sections.indices.contains(index), index != pendingIndex else {
            return
        }
        cancelPendingSelect()
        guard index != selectedIndex else {
            return
        }
        let controller = sections[index].controller
        controller._frameRect = NSMakeRect(0, 0, frame.width, frame.height)
        controller.loadViewIfNeeded()
        pendingIndex = index
        setAppearance(index, .appearing, animated: animated)
        disposable.set((controller.ready.get() |> filter { $0 } |> take(1)).start(next: { [weak self] _ in
            self?.pendingIndex = nil
            self?.performSelect(index, animated: animated)
        }))
    }

    private func cancelPendingSelect() {
        guard let index = pendingIndex else {
            return
        }
        pendingIndex = nil
        disposable.set(nil)
        if !attached.contains(index) {
            setAppearance(index, .disappeared, animated: false)
        }
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setAppearance(selectedIndex, .appearing, animated: animated)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        setAppearance(selectedIndex, .appeared, animated: animated)

        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self else {return .rejected}
            self.select((self.selectedIndex + 1) % self.sections.count, true)
            return .invoked
        }, with: self, for: .Tab, priority: .high)

        window?.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
            return self?.handleScroll(event) ?? .rejected
        }, with: genericView, for: .scrollWheel, priority: .modal)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.remove(object: self, for: .Tab)
        window?.removeAllHandlers(for: genericView)
        cancelPendingSelect()
        isVisible = false
        gesture = nil
        swallowsMomentum = false
        parkedIndex = nil
        settleGeneration += 1
        offset = 0
        for index in attached {
            sections[index].controller.view.layer?.removeAnimation(forKey: "position")
        }
        for index in attached where index != selectedIndex {
            detach(index)
        }
        layoutPages()
        selectorPositionHandler?(CGFloat(selectedIndex), false)
        setAppearance(selectedIndex, .disappearing, animated: animated)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        setAppearance(selectedIndex, .disappeared, animated: animated)
    }

    private func performSelect(_ index: Int, animated: Bool) {
        guard index != selectedIndex else {
            return
        }
        gesture = nil
        catchSettle()
        for attachedIndex in attached where attachedIndex != selectedIndex && attachedIndex != index {
            detach(attachedIndex)
        }
        attach(index)
        settle(to: index, animated: animated)
    }

    private func pageFrame(_ index: Int) -> NSRect {
        let bounds = genericView.bounds
        let position = CGFloat(max(-1, min(1, index - selectedIndex)))
        return NSMakeRect(position * bounds.width + offset, 0, bounds.width, bounds.height)
    }

    private func layoutPages() {
        for index in attached where index != parkedIndex {
            let view = sections[index].controller.view
            view.alphaValue = 1
            let frame = pageFrame(index)
            if view.frame != frame {
                view.frame = frame
            }
        }
    }

    private func attach(_ index: Int, parked: Bool = false) {
        guard !attached.contains(index) else {
            return
        }
        let controller = sections[index].controller
        controller._frameRect = genericView.bounds
        controller.loadViewIfNeeded()
        controller.updateContainerContentInsets(containerContentInsets, transition: .immediate)
        controller.view.frame = parked ? genericView.bounds : pageFrame(index)
        controller.view.alphaValue = parked ? 0 : 1
        attached.insert(index)
        if parked {
            parkedIndex = index
        }
        setAppearance(index, .appearing, animated: true)
        let selectedView = selectedSection.controller.view
        if index != selectedIndex, selectedView.superview === genericView {
            genericView.addSubview(controller.view, positioned: .below, relativeTo: selectedView)
        } else {
            genericView.addSubview(controller.view)
        }
    }

    open override func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
        super.updateContainerContentInsets(insets, transition: transition)
        for section in sections {
            section.controller.updateContainerContentInsets(insets, transition: transition)
        }
    }

    private func detach(_ index: Int) {
        guard attached.contains(index) else {
            return
        }
        attached.remove(index)
        if parkedIndex == index {
            parkedIndex = nil
        }
        let view = sections[index].controller.view
        setAppearance(index, .disappearing, animated: true)
        view.layer?.removeAnimation(forKey: "position")
        view.removeFromSuperview()
        setAppearance(index, .disappeared, animated: true)
    }

    private func setAppearance(_ index: Int, _ target: Appearance, animated: Bool) {
        let controller = sections[index].controller
        let current = appearances[index]
        let isShown = current == .appearing || current == .appeared
        switch target {
        case .appearing:
            guard !isShown else {
                return
            }
            controller.viewWillAppear(animated)
        case .appeared:
            guard current != .appeared else {
                return
            }
            if !isShown {
                controller.viewWillAppear(animated)
            }
            controller.viewDidAppear(animated)
        case .disappearing:
            guard isShown else {
                return
            }
            controller.viewWillDisappear(animated)
        case .disappeared:
            guard current != .disappeared else {
                return
            }
            if isShown {
                controller.viewWillDisappear(animated)
            }
            controller.viewDidDisappear(animated)
        }
        appearances[index] = target
    }

    private func catchSettle() {
        settleGeneration += 1
        parkedIndex = nil
        if let layer = selectedSection.controller.view.layer, layer.animation(forKey: "position") != nil, let presentation = layer.presentation() {
            offset = presentation.frame.minX
        }
        for index in attached {
            sections[index].controller.view.layer?.removeAnimation(forKey: "position")
        }
        for index in attached where abs(index - selectedIndex) > 1 {
            detach(index)
        }
        layoutPages()
    }

    private func settle(to target: Int, animated: Bool) {
        settleGeneration += 1
        let generation = settleGeneration
        parkedIndex = nil
        layoutPages()
        if target != selectedIndex {
            setAppearance(selectedIndex, .disappearing, animated: animated)
            selectedIndex = target
            attach(target)
            selectionUpdateHandler?(target)
        }
        offset = 0
        selectorPositionHandler?(CGFloat(target), animated)

        guard animated else {
            layoutPages()
            finishSettle()
            return
        }
        let duration = SectionViewController.settleDuration
        for index in attached where index != target {
            sections[index].controller.view._change(pos: pageFrame(index).origin, animated: true, duration: duration, timingFunction: .spring)
        }
        sections[target].controller.view._change(pos: pageFrame(target).origin, animated: true, duration: duration, timingFunction: .spring, completion: { [weak self] completed in
            guard let `self` = self, completed, self.settleGeneration == generation else {
                return
            }
            self.finishSettle()
        })
    }

    private func finishSettle() {
        for index in attached where index != selectedIndex {
            detach(index)
        }
        if isVisible {
            setAppearance(selectedIndex, .appeared, animated: true)
        }
    }

    private func canBeginPaging(towards delta: CGFloat) -> Bool {
        guard isVisible, let window = self.window, let contentView = window.contentView else {
            return false
        }
        let neighbor = delta > 0 ? selectedIndex - 1 : selectedIndex + 1
        guard sections.indices.contains(neighbor) else {
            return false
        }
        let point = window.mouseLocationOutsideOfEventStream
        guard let hit = contentView.hitTest(point), hit.isDescendant(of: genericView) else {
            return false
        }
        if hit.enclosingHorizontalScrollConsumer(atWindowPoint: point) != nil {
            return false
        }
        var view: NSView? = hit
        while let current = view, current !== genericView {
            if current is HorizontalTableView || current is HorizontalScrollView {
                return false
            }
            view = current.superview
        }
        return selectedSection.controller.supportSwipes
    }

    private func fingerDelta(_ event: NSEvent) -> CGFloat {
        return System.isScrollInverted ? event.scrollingDeltaX : -event.scrollingDeltaX
    }

    private func handleScroll(_ event: NSEvent) -> KeyHandlerResult {
        if !event.momentumPhase.isEmpty {
            guard swallowsMomentum else {
                return .rejected
            }
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                swallowsMomentum = false
            }
            return .invoked
        }

        let phase = event.phase
        if phase.isEmpty {
            return .rejected
        }
        if phase.contains(.mayBegin) || phase.contains(.began) {
            swallowsMomentum = false
            gesture = Gesture()
        }
        guard var current = gesture else {
            return .rejected
        }
        let isEnd = phase.contains(.ended) || phase.contains(.cancelled)

        switch current.axis {
        case .undecided:
            if isEnd {
                gesture = nil
                return .rejected
            }
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            if deltaX == 0 && deltaY == 0 {
                if phase.contains(.began) {
                    current.beganPassedThrough = true
                }
                gesture = current
                return .rejected
            }
            if abs(deltaX) > abs(deltaY), canBeginPaging(towards: fingerDelta(event)) {
                current.axis = .horizontal
                cancelPendingSelect()
                catchSettle()
                track(event, gesture: &current)
                gesture = current
                return .invoked
            }
            current.axis = .vertical
            gesture = current
            return .rejected
        case .vertical:
            if isEnd {
                gesture = nil
            }
            return .rejected
        case .horizontal:
            if isEnd {
                gesture = nil
                swallowsMomentum = true
                release(at: event.timestamp, samples: current.samples)
                return current.beganPassedThrough ? .rejected : .invoked
            }
            track(event, gesture: &current)
            gesture = current
            return .invoked
        }
    }

    private func track(_ event: NSEvent, gesture: inout Gesture) {
        let width = genericView.frame.width
        guard width > 0 else {
            return
        }
        let delta = fingerDelta(event)
        gesture.samples.append((timestamp: event.timestamp, delta: delta))
        let minOffset: CGFloat = selectedIndex == sections.count - 1 ? 0 : -width
        let maxOffset: CGFloat = selectedIndex == 0 ? 0 : width
        offset = min(max(offset + delta, minOffset), maxOffset)

        let neighbor: Int? = offset > 0 ? selectedIndex - 1 : (offset < 0 ? selectedIndex + 1 : nil)
        if let neighbor = neighbor, !attached.contains(neighbor) {
            attach(neighbor, parked: true)
            return
        }
        parkedIndex = nil
        layoutPages()
        selectorPositionHandler?(CGFloat(selectedIndex) - offset / width, false)
    }

    private func release(at timestamp: TimeInterval, samples: [(timestamp: TimeInterval, delta: CGFloat)]) {
        let width = genericView.frame.width
        let recent = samples.filter { timestamp - $0.timestamp <= SectionViewController.velocityWindow }
        var velocity: CGFloat = 0
        if let first = recent.first {
            let span = max(CGFloat(timestamp - first.timestamp), 1.0 / 60.0)
            velocity = recent.reduce(CGFloat(0), { $0 + $1.delta }) / span
        }

        var target = selectedIndex
        if offset != 0 {
            let neighbor = offset > 0 ? selectedIndex - 1 : selectedIndex + 1
            if abs(velocity) > SectionViewController.switchVelocity {
                if (velocity > 0) == (offset > 0) {
                    target = neighbor
                }
            } else if abs(offset) > width * SectionViewController.switchFraction {
                target = neighbor
            }
        }
        settle(to: target, animated: true)
    }
}
