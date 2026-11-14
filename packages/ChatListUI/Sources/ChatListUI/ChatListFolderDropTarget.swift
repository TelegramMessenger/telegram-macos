import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import TelegramTheme

func chatListFolderDropScrollOffset(position: CGFloat, length: CGFloat, offset: CGFloat, contentLength: CGFloat) -> CGFloat {
    guard length > 0, position >= 0, position <= length, contentLength > length else {
        return offset
    }
    let edge = min(36, length / 3)
    let speed: CGFloat
    if position < edge {
        speed = -8 * (1 - position / edge)
    } else if position > length - edge {
        speed = 8 * (1 - (length - position) / edge)
    } else {
        speed = 0
    }
    return min(max(0, offset + speed), contentLength - length)
}

func chatListFolderDropMagnification(distance: CGFloat, length: CGFloat, horizontal: Bool) -> CGFloat {
    guard length > 0 else { return 1 }
    let proximity = max(0, 1 - abs(distance) / (length * 1.6))
    return 1 + (horizontal ? 0.12 : 0.40) * proximity * proximity * (3 - 2 * proximity)
}

func chatListFolderDropFittedScale(_ scale: CGFloat, content: NSRect, bounds: NSRect) -> CGFloat {
    guard !content.isEmpty, bounds.contains(content) else { return 1 }
    let width = bounds.width / content.width
    let height = bounds.height / content.height
    return max(1, min(scale, width, height))
}

private final class ChatListFolderDropPlateView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

private final class ChatListFolderDropFeedback {
    let filterId: Int32
    weak var view: NSView?
    let contents: [NSView]
    private let plate = CALayer()
    private let overlay = ChatListFolderDropPlateView(frame: .zero)
    private var scale: CGFloat = 1
    private var selected = false
    private var contentFrames: [NSRect] = []
    private let animationKey = "chatFolderDrop"

    init(filterId: Int32, view: NSView, contents: [NSView]) {
        self.filterId = filterId
        self.view = view
        self.contents = contents
        overlay.wantsLayer = true
        overlay.layer = plate
        overlay.setAccessibilityElement(false)
        plate.zPosition = 1
        view.addSubview(overlay, positioned: .above, relativeTo: nil)
    }

    func matches(filterId: Int32, contents: [NSView]) -> Bool {
        return self.filterId == filterId && self.contents.count == contents.count && zip(self.contents, contents).allSatisfy { $0 === $1 }
    }

    private var contentRect: NSRect {
        guard let view else { return .zero }
        return contents.reduce(NSRect.null) { $0.union($1.convert($1.bounds, to: view)) }
    }

    private func transform(_ scale: CGFloat, content: NSView) -> CATransform3D {
        guard let view, let layer = content.layer else { return CATransform3DIdentity }
        let rect = contentRect
        let center = content.convert(NSPoint(x: rect.midX, y: rect.midY), from: view)
        let anchor = NSPoint(x: content.bounds.minX + layer.anchorPoint.x * content.bounds.width, y: content.bounds.minY + layer.anchorPoint.y * content.bounds.height)
        let bounds = view.bounds.insetBy(dx: 2, dy: 2)
        let expanded = rect.insetBy(dx: -rect.width * (scale - 1) / 2, dy: -rect.height * (scale - 1) / 2)
        let offset = NSPoint(x: max(bounds.minX - expanded.minX, min(0, bounds.maxX - expanded.maxX)), y: max(bounds.minY - expanded.minY, min(0, bounds.maxY - expanded.maxY)))
        let shifted = content.convert(NSPoint(x: rect.midX + offset.x, y: rect.midY + offset.y), from: view)
        var transform = CATransform3DMakeScale(scale, scale, 1)
        transform.m41 = (center.x - anchor.x) * (1 - scale) + shifted.x - center.x
        transform.m42 = (center.y - anchor.y) * (1 - scale) + shifted.y - center.y
        return transform
    }

    func update(scale: CGFloat, selected: Bool) {
        guard let view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.frame = view.bounds.insetBy(dx: 2, dy: 2)
        plate.cornerRadius = min(10, plate.bounds.height / 2)
        plate.backgroundColor = theme.colors.accent.withAlphaComponent(selected ? 0.20 : 0).cgColor
        plate.borderColor = theme.colors.accent.withAlphaComponent(selected ? 0.75 : 0).cgColor
        plate.borderWidth = selected ? 1.5 : 0
        CATransaction.commit()
        if selected && !self.selected {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0
            animation.toValue = 1
            animation.duration = 0.12
            plate.add(animation, forKey: "chatFolderDropPlate")
        }
        self.selected = selected
        let scale = chatListFolderDropFittedScale(scale, content: contentRect, bounds: view.bounds.insetBy(dx: 2, dy: 2))
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            for content in contents { content.layer?.removeAnimation(forKey: animationKey) }
        }
        let frames = contents.map { $0.convert($0.bounds, to: view) }
        guard self.scale != scale || contentFrames != frames else { return }
        self.scale = scale
        contentFrames = frames
        for content in contents {
            guard let layer = content.layer else { continue }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                layer.removeAnimation(forKey: animationKey)
            } else if scale != 1 || layer.animation(forKey: animationKey) != nil {
                let animation = CABasicAnimation(keyPath: "transform")
                animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
                animation.toValue = NSValue(caTransform3D: transform(scale, content: content))
                animation.duration = 0.10
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: animationKey)
            }
        }
    }

    func impact(horizontal: Bool) {
        update(scale: 1, selected: true)
        if !horizontal && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let view {
            let rebound = chatListFolderDropFittedScale(1.14, content: contentRect, bounds: view.bounds.insetBy(dx: 2, dy: 2))
            for content in contents {
                let animation = CAKeyframeAnimation(keyPath: "transform")
                animation.values = [1, 0.82, rebound, 1].map { NSValue(caTransform3D: transform($0, content: content)) }
                animation.keyTimes = [0, 0.22, 0.58, 1]
                animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeOut)]
                animation.duration = 0.34
                content.layer?.add(animation, forKey: animationKey)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.opacity = 0
        CATransaction.commit()
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0.45, 1, 0]
        animation.keyTimes = [0, 0.25, 1]
        animation.duration = 0.34
        plate.add(animation, forKey: "chatFolderDropPlate")
    }

    func remove() {
        overlay.removeFromSuperview()
        for content in contents {
            content.layer?.removeAnimation(forKey: animationKey)
        }
    }

    deinit {
        remove()
    }
}

public final class ChatListFolderDropTarget {
    private let context: any AccountContextProtocol
    private weak var scrollView: NSScrollView?
    private let horizontal: Bool
    private let target: (NSPoint) -> (ChatListFilter, NSView)?
    private let visibleTargets: () -> [(ChatListFilter, NSView, [NSView])]
    private var timer: Foundation.Timer?
    private var sender: NSDraggingInfo?
    private var feedback: [ObjectIdentifier: ChatListFolderDropFeedback] = [:]
    private var impact: ChatListFolderDropFeedback?
    private var impactTimer: Foundation.Timer?
    private var generation: UInt64 = 0

    public init(context: any AccountContextProtocol, scrollView: NSScrollView, horizontal: Bool, target: @escaping (NSPoint) -> (ChatListFilter, NSView)?, visibleTargets: @escaping () -> [(ChatListFilter, NSView, [NSView])] = { [] }) {
        self.context = context
        self.scrollView = scrollView
        self.horizontal = horizontal
        self.target = target
        self.visibleTargets = visibleTargets
    }

    public func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let scrollView, scrollView.window != nil, !scrollView.isHiddenOrHasHiddenAncestor, ChatListFolderDrop.canScroll(sender, context: context), scrollView.visibleRect.contains(scrollView.convert(sender.draggingLocation, from: nil)) else {
            exit()
            return []
        }
        if self.sender == nil {
            generation &+= 1
            clearImpact()
        }
        self.sender = sender
        if timer == nil {
            let timer = Foundation.Timer(timeInterval: 1.0 / 60.0, repeats: true, block: { [weak self] _ in
                self?.tick()
            })
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        return updateTarget(sender.draggingLocation, sender: sender)
    }

    private func updateTarget(_ point: NSPoint, sender: NSDraggingInfo) -> NSDragOperation {
        guard let (filter, view) = target(point), !ChatListFolderDrop.validate(sender, context: context, filter: filter).isEmpty else {
            clearFeedback()
            return []
        }
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var retained = Set<ObjectIdentifier>()
        for (filter, host, contents) in visibleTargets() {
            guard host.window != nil, !host.isHiddenOrHasHiddenAncestor, !host.visibleRect.isEmpty, !ChatListFolderDrop.validate(sender, context: context, filter: filter).isEmpty else { continue }
            let rect = host.convert(host.bounds, to: nil)
            let distance = horizontal ? point.x - rect.midX : point.y - rect.midY
            let scale = reducedMotion || horizontal ? 1 : chatListFolderDropMagnification(distance: distance, length: horizontal ? rect.width : rect.height, horizontal: horizontal)
            guard host === view || scale > 1 else { continue }
            let id = ObjectIdentifier(host)
            let filterId = ChatListUIHooks.shared.chatListFilterId(filter)
            if feedback[id]?.matches(filterId: filterId, contents: contents) != true {
                feedback[id]?.remove()
                feedback[id] = ChatListFolderDropFeedback(filterId: filterId, view: host, contents: contents)
            }
            feedback[id]?.update(scale: host === view ? scale : min(scale, horizontal ? 1.03 : 1.08), selected: host === view)
            retained.insert(id)
        }
        for id in Array(feedback.keys) where !retained.contains(id) {
            feedback.removeValue(forKey: id)?.remove()
        }
        return .copy
    }

    private func clearFeedback() {
        for value in feedback.values { value.remove() }
        feedback.removeAll()
    }

    private func tick() {
        guard let sender, let scrollView, let window = scrollView.window, !scrollView.isHiddenOrHasHiddenAncestor, ChatListFolderDrop.canScroll(sender, context: context), NSEvent.pressedMouseButtons & 1 != 0 else {
            exit()
            return
        }
        let point = window.mouseLocationOutsideOfEventStream
        let local = scrollView.convert(point, from: nil)
        guard scrollView.visibleRect.contains(local) else {
            exit()
            return
        }
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        if horizontal {
            origin.x = chatListFolderDropScrollOffset(position: local.x - scrollView.visibleRect.minX, length: clip.bounds.width, offset: origin.x, contentLength: clip.documentRect.width)
        } else {
            origin.y = chatListFolderDropScrollOffset(position: local.y - scrollView.visibleRect.minY, length: clip.bounds.height, offset: origin.y, contentLength: clip.documentRect.height)
        }
        if origin != clip.bounds.origin {
            clip.scroll(to: origin)
            scrollView.reflectScrolledClipView(clip)
        }
        _ = updateTarget(point, sender: sender)
    }

    private func currentContents(view: NSView, filterId: Int32) -> [NSView]? {
        guard !context.isFrozen, let scrollView, scrollView.window != nil, !scrollView.isHiddenOrHasHiddenAncestor, view.window === scrollView.window, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty else { return nil }
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        guard scrollView.visibleRect.contains(scrollView.convert(point, from: nil)), let (current, currentView) = target(point), currentView === view, ChatListUIHooks.shared.chatListFilterId(current) == filterId else { return nil }
        return visibleTargets().first(where: { $0.1 === view && ChatListUIHooks.shared.chatListFilterId($0.0) == filterId })?.2
    }

    public func perform(_ sender: NSDraggingInfo) -> Bool {
        exit()
        guard let scrollView, !scrollView.isHiddenOrHasHiddenAncestor, scrollView.visibleRect.contains(scrollView.convert(sender.draggingLocation, from: nil)), let (filter, view) = target(sender.draggingLocation) else {
            return false
        }
        generation &+= 1
        let generation = self.generation
        let filterId = ChatListUIHooks.shared.chatListFilterId(filter)
        let destination: () -> NSView? = { [weak self, weak view] in
            guard let self, self.generation == generation, let view, let contents = self.currentContents(view: view, filterId: filterId) else { return nil }
            return self.horizontal ? view : contents.first
        }
        return ChatListFolderDrop.perform(sender, context: context, filter: filter, destination: destination, completed: { [weak self, weak view] added in
            guard added, let self, self.generation == generation, self.sender == nil, let view, let contents = self.currentContents(view: view, filterId: filterId) else { return }
            self.clearImpact()
            let impact = ChatListFolderDropFeedback(filterId: filterId, view: view, contents: contents)
            self.impact = impact
            impact.impact(horizontal: self.horizontal)
            let start = CACurrentMediaTime()
            let timer = Foundation.Timer(timeInterval: 1.0 / 60.0, repeats: true, block: { [weak self, weak view] _ in
                guard let self else { return }
                guard let view, let contents = self.currentContents(view: view, filterId: filterId), impact.matches(filterId: filterId, contents: contents), CACurrentMediaTime() - start < 0.34 else {
                    self.clearImpact()
                    return
                }
                impact.update(scale: 1, selected: true)
            })
            self.impactTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        })
    }

    private func clearImpact() {
        impactTimer?.invalidate()
        impactTimer = nil
        impact?.remove()
        impact = nil
    }

    public func exit() {
        timer?.invalidate()
        timer = nil
        sender = nil
        clearFeedback()
        clearImpact()
    }

    deinit {
        timer?.invalidate()
        impactTimer?.invalidate()
        clearFeedback()
        impact?.remove()
    }
}
