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
    let proximity = max(0, 1 - abs(distance) / (length * 2.4))
    return 1 + (horizontal ? 0.10 : 0.70) * proximity * proximity * (3 - 2 * proximity)
}

func chatListFolderDropFittedScale(_ scale: CGFloat, content: NSRect, bounds: NSRect) -> CGFloat {
    guard !content.isEmpty, bounds.contains(content) else { return 1 }
    return max(1, min(scale, bounds.width / content.width, bounds.height / content.height))
}

func chatListFolderDropOffsets(frames: [NSRect], growth: [CGFloat], position: CGFloat, horizontal: Bool, contents: [NSRect] = []) -> [CGFloat] {
    guard frames.count == growth.count else { return Array(repeating: 0, count: frames.count) }
    var offsets = frames.indices.map { index in
        let rect = frames[index]
        let start = horizontal ? rect.minX : rect.minY
        let length = horizontal ? rect.width : rect.height
        let fraction = min(1.5, max(-0.5, (position - start) / max(1, length)))
        return growth[index] * (0.5 - fraction)
    }
    guard contents.count == frames.count, !frames.isEmpty else { return offsets }
    let indices = frames.indices.sorted { horizontal ? frames[$0].midX < frames[$1].midX : frames[$0].midY < frames[$1].midY }
    let pivot = indices.min(by: { abs((horizontal ? frames[$0].midX : frames[$0].midY) - position) < abs((horizontal ? frames[$1].midX : frames[$1].midY) - position) })!
    let pivotIndex = indices.firstIndex(of: pivot)!
    func lower(_ index: Int) -> CGFloat { horizontal ? contents[index].minX : contents[index].minY }
    func upper(_ index: Int) -> CGFloat { horizontal ? contents[index].maxX : contents[index].maxY }
    if pivotIndex + 1 < indices.count {
        for step in (pivotIndex + 1)..<indices.count {
            let index = indices[step], previous = indices[step - 1]
            guard !contents[index].isEmpty, !contents[previous].isEmpty else { continue }
            let gap = min(4, max(0, lower(index) - upper(previous)))
            offsets[index] = max(offsets[index], offsets[previous] + upper(previous) - lower(index) + (growth[previous] + growth[index]) / 2 + gap)
        }
    }
    if pivotIndex > 0 {
        for step in stride(from: pivotIndex - 1, through: 0, by: -1) {
            let index = indices[step], next = indices[step + 1]
            guard !contents[index].isEmpty, !contents[next].isEmpty else { continue }
            let gap = min(4, max(0, lower(next) - upper(index)))
            offsets[index] = min(offsets[index], offsets[next] + lower(next) - upper(index) - (growth[next] + growth[index]) / 2 - gap)
        }
    }
    return offsets
}

func chatListFolderDropContentFrames(_ frames: [NSRect], scale: CGFloat, offset: CGFloat, horizontal: Bool) -> [NSRect] {
    guard let primary = frames.first else { return [] }
    let content = frames.reduce(NSRect.null) { $0.union($1) }
    let growth = (horizontal ? content.width : primary.height) * (scale - 1)
    return frames.enumerated().map { index, rect in
        if horizontal {
            return NSRect(x: content.midX + (rect.minX - content.midX) * scale + offset, y: content.maxY + (rect.minY - content.maxY) * scale, width: rect.width * scale, height: rect.height * scale)
        } else if index < 2 {
            return NSRect(x: primary.maxX + (rect.minX - primary.maxX) * scale, y: primary.minY + (rect.minY - primary.minY) * scale + offset - growth / 2, width: rect.width * scale, height: rect.height * scale)
        } else {
            return rect.offsetBy(dx: 0, dy: offset + growth / 2)
        }
    }
}

func chatListFolderDropBackdropFrame(content: NSRect, bounds: NSRect, neighbors: [NSRect], horizontal: Bool) -> NSRect {
    guard !content.isEmpty, !bounds.isEmpty else { return .zero }
    var lower = horizontal ? bounds.minX : bounds.minY
    var upper = horizontal ? bounds.maxX : bounds.maxY
    let start = horizontal ? content.minX : content.minY
    let end = horizontal ? content.maxX : content.maxY
    for neighbor in neighbors where !neighbor.isEmpty {
        let first = horizontal ? neighbor.minX : neighbor.minY
        let last = horizontal ? neighbor.maxX : neighbor.maxY
        if last <= start { lower = max(lower, (last + start) / 2) }
        if first >= end { upper = min(upper, (first + end) / 2) }
    }
    let available = horizontal ? NSRect(x: lower, y: bounds.minY, width: max(0, upper - lower), height: bounds.height) : NSRect(x: bounds.minX, y: lower, width: bounds.width, height: max(0, upper - lower))
    let result = content.insetBy(dx: -6, dy: -4).intersection(available)
    return result.isNull ? .zero : result
}

private class ChatListFolderDropPlateView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

private final class ChatListFolderDropOverlayView: ChatListFolderDropPlateView {
    override var isFlipped: Bool { return true }
}

public typealias ChatListFolderDropAppearance = (identity: AnyObject, selected: Bool, images: () -> [(CGImage?, CGImage?, CGImage?)])

private let chatListFolderDropAccentDuration: TimeInterval = 0.7

private func chatListFolderDropAnimateOpacity(_ layer: CALayer, to opacity: Float) {
    let current = (layer.presentation() ?? layer).opacity
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = opacity
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = current
    animation.toValue = opacity
    animation.duration = chatListFolderDropAccentDuration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "chatFolderDropAccent")
    CATransaction.commit()
}

func chatListFolderDropHighlightDuration(distance: CGFloat) -> TimeInterval {
    return 0.18 + 0.52 * min(1, max(0, distance) / 560)
}

private final class ChatListFolderDropHighlight {
    let content = CALayer()
    let accent = CALayer()
    let neutral = CALayer()
    let band = CAGradientLayer()
    private var targetId: Int32?
    private var deadline: TimeInterval = 0
    private var initialized = false
    private var neutralTarget = false
    private var startFrame = NSRect.zero
    private var endFrame = NSRect.zero
    private var startTime: TimeInterval = 0
    private var duration: TimeInterval = 0

    init(host: NSView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = host.bounds
        content.zPosition = 1
        accent.frame = host.bounds
        neutral.frame = host.bounds
        neutral.opacity = 0
        content.addSublayer(accent)
        content.addSublayer(neutral)
        band.startPoint = NSPoint(x: 0.5, y: 0)
        band.endPoint = NSPoint(x: 0.5, y: 1)
        band.colors = [theme.colors.text.withAlphaComponent(0).cgColor, theme.colors.text.cgColor, theme.colors.text.cgColor, theme.colors.text.withAlphaComponent(0).cgColor]
        band.locations = [0, 0.04, 0.96, 1]
        content.mask = band
        host.layer?.addSublayer(content)
        CATransaction.commit()
    }

    var visibleFrame: NSRect {
        guard duration > 0 else { return endFrame }
        if let current = band.presentation(), !current.frame.isEmpty {
            return current.frame
        }
        let progress = min(1, max(0, (CACurrentMediaTime() - startTime) / duration))
        let value = CGFloat(progress * progress * (3 - 2 * progress))
        return NSRect(x: startFrame.minX + (endFrame.minX - startFrame.minX) * value, y: startFrame.minY + (endFrame.minY - startFrame.minY) * value, width: startFrame.width + (endFrame.width - startFrame.width) * value, height: startFrame.height + (endFrame.height - startFrame.height) * value)
    }

    var remaining: TimeInterval {
        return max(0, deadline - CACurrentMediaTime())
    }

    func resize(_ bounds: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = bounds
        accent.frame = bounds
        neutral.frame = bounds
        CATransaction.commit()
    }

    func seed(_ frame: NSRect, filterId: Int32) {
        guard !initialized, !frame.isEmpty else { return }
        let frame = NSRect(x: 0, y: frame.minY, width: content.bounds.width, height: frame.height)
        initialized = true
        targetId = filterId
        startFrame = frame
        endFrame = frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.frame = frame
        CATransaction.commit()
    }

    func move(to frame: NSRect, filterId: Int32, neutral: Bool, settling: Bool = false) {
        guard initialized, !frame.isEmpty else { return }
        let frame = NSRect(x: 0, y: frame.minY, width: content.bounds.width, height: frame.height)
        if neutralTarget != neutral {
            neutralTarget = neutral
            for (layer, opacity) in [(accent, neutral ? Float(0) : 1), (self.neutral, neutral ? Float(1) : 0)] {
                let current = (layer.presentation() ?? layer).opacity
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.opacity = opacity
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = current
                fade.toValue = opacity
                fade.duration = 0.12
                layer.add(fade, forKey: "chatFolderDropTone")
                CATransaction.commit()
            }
        }
        guard targetId != filterId || endFrame != frame else { return }
        let now = CACurrentMediaTime()
        let changedTarget = targetId != filterId
        guard changedTarget || settling || now >= deadline else { return }
        let current = visibleFrame
        duration = changedTarget ? chatListFolderDropHighlightDuration(distance: abs(frame.midY - current.midY)) : 0.14
        targetId = filterId
        startFrame = current
        endFrame = frame
        startTime = now
        deadline = now + duration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.frame = frame
        let positions = CAKeyframeAnimation(keyPath: "position")
        let bounds = CAKeyframeAnimation(keyPath: "bounds")
        positions.values = (0...30).map { index -> NSValue in
            let progress = CGFloat(index) / 30
            let value = progress * progress * (3 - 2 * progress)
            return NSValue(point: NSPoint(x: current.midX + (frame.midX - current.midX) * value, y: current.midY + (frame.midY - current.midY) * value))
        }
        bounds.values = (0...30).map { index -> NSValue in
            let progress = CGFloat(index) / 30
            let value = progress * progress * (3 - 2 * progress)
            return NSValue(rect: NSRect(x: 0, y: 0, width: current.width + (frame.width - current.width) * value, height: current.height + (frame.height - current.height) * value))
        }
        let group = CAAnimationGroup()
        group.animations = [positions, bounds]
        group.duration = duration
        band.add(group, forKey: "chatFolderDropTravel")
        CATransaction.commit()
    }

    func remove() {
        band.removeAllAnimations()
        accent.removeAllAnimations()
        neutral.removeAllAnimations()
        content.removeFromSuperlayer()
    }
}

private final class ChatListFolderDropFeedback {
    let filterId: Int32
    weak var view: NSView?
    let contents: [NSView]
    private let plate = CALayer()
    private let overlay = ChatListFolderDropPlateView(frame: .zero)
    private weak var host: NSView?
    private let horizontal: Bool
    private var replicas: [NSView] = []
    private var idleLayers: [Int: CALayer] = [:]
    private var accentLayers: [Int: CALayer] = [:]
    private var hoverLayers: [Int: CALayer] = [:]
    private let appearance: ChatListFolderDropAppearance?
    private weak var highlight: ChatListFolderDropHighlight?
    private var accented: Bool
    private var neutralHover = false
    private var selected = false
    private var frames: [NSRect] = []
    private var originalFrames: [NSRect] = []
    private let animationKey = "chatFolderDrop"
    private let hiddenKey = "chatFolderDropHidden"
    private var removed = false

    init(filterId: Int32, view: NSView, contents: [NSView], host: NSView? = nil, horizontal: Bool = false, appearance: ChatListFolderDropAppearance? = nil, highlight: ChatListFolderDropHighlight? = nil) {
        self.filterId = filterId
        self.view = view
        self.contents = contents
        self.host = host
        self.horizontal = horizontal
        self.appearance = appearance
        self.highlight = highlight
        self.accented = appearance?.selected ?? false
        overlay.wantsLayer = true
        overlay.setAccessibilityElement(false)
        plate.opacity = 0
        if appearance == nil {
            if let host {
                plate.zPosition = -1
                host.layer?.addSublayer(plate)
            } else {
                overlay.layer = plate
                view.addSubview(overlay, positioned: .above, relativeTo: nil)
            }
        }
        if host != nil || appearance != nil {
            let host = host ?? view
            let images = appearance?.images() ?? []
            originalFrames = contents.map { $0.convert($0.bounds, to: host) }
            for (index, content) in contents.enumerated() {
                let replica = ChatListFolderDropPlateView(frame: content.convert(content.bounds, to: host))
                replica.wantsLayer = true
                replica.setAccessibilityElement(false)
                if index < images.count, images[index].0 !== images[index].1 {
                    let idle = CALayer()
                    idle.contents = images[index].0
                    idle.contentsGravity = .resize
                    idle.frame = replica.bounds
                    idle.opacity = highlight == nil && accented ? 0 : 1
                    replica.layer?.addSublayer(idle)
                    idleLayers[index] = idle
                    let accent = CALayer()
                    accent.contents = images[index].1
                    accent.contentsGravity = .resize
                    accent.frame = highlight == nil ? replica.bounds : replica.frame
                    accent.opacity = highlight != nil || accented ? 1 : 0
                    if let highlight {
                        highlight.accent.addSublayer(accent)
                    } else {
                        replica.layer?.addSublayer(accent)
                    }
                    accentLayers[index] = accent
                    if highlight != nil || images[index].2 !== images[index].0 {
                        let hover = CALayer()
                        hover.contents = images[index].2
                        hover.contentsGravity = .resize
                        hover.frame = highlight == nil ? replica.bounds : replica.frame
                        hover.opacity = highlight == nil ? 0 : 1
                        if let highlight {
                            highlight.neutral.addSublayer(hover)
                        } else {
                            replica.layer?.addSublayer(hover)
                        }
                        hoverLayers[index] = hover
                    }
                } else if index < images.count {
                    replica.layer?.contents = images[index].0
                } else if !content.bounds.isEmpty {
                    let image = content.snapshot
                    replica.layer?.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
                replica.layer?.contentsGravity = .resize
                replica.layer?.opacity = Float(content.alphaValue)
                host.addSubview(replica, positioned: .above, relativeTo: nil)
                replicas.append(replica)
                let hidden = CABasicAnimation(keyPath: "opacity")
                hidden.fromValue = 0
                hidden.toValue = 0
                hidden.duration = 0.01
                hidden.fillMode = .both
                hidden.isRemovedOnCompletion = false
                content.layer?.add(hidden, forKey: hiddenKey)
            }
        }
    }

    func matches(filterId: Int32, contents: [NSView]) -> Bool {
        return self.filterId == filterId && self.contents.count == contents.count && zip(self.contents, contents).allSatisfy { $0 === $1 }
    }

    var transfersAccent: Bool {
        return appearance != nil
    }

    func matchesAppearance(_ appearance: ChatListFolderDropAppearance?) -> Bool {
        return self.appearance?.identity === appearance?.identity
    }

    private func updateAccent(_ accented: Bool, neutralHover: Bool) {
        guard self.accented != accented || self.neutralHover != neutralHover else { return }
        self.accented = accented
        self.neutralHover = neutralHover
        var layers: [(CALayer, Float)] = []
        for (index, idle) in idleLayers {
            layers.append((idle, accented || (neutralHover && hoverLayers[index] != nil) ? 0 : 1))
        }
        layers += accentLayers.values.map { ($0, accented ? Float(1) : 0) }
        layers += hoverLayers.values.map { ($0, neutralHover && !accented ? Float(1) : 0) }
        for (layer, target) in layers {
            chatListFolderDropAnimateOpacity(layer, to: target)
        }
    }

    var destination: NSView? {
        return horizontal ? view : replicas.first ?? contents.first
    }

    var isSelection: Bool {
        return appearance?.selected ?? false
    }

    var highlightFrame: NSRect {
        return replicas.filter { !$0.bounds.isEmpty }.reduce(NSRect.null) { $0.union($1.frame) }.insetBy(dx: -4, dy: -3)
    }

    var originalHighlightFrame: NSRect {
        return originalFrames.filter { !$0.isEmpty }.reduce(NSRect.null) { $0.union($1) }.insetBy(dx: -4, dy: -3)
    }

    var geometryMatches: Bool {
        guard let host else { return true }
        return originalFrames == contents.map { $0.convert($0.bounds, to: host) }
    }

    func refreshGeometry() {
        guard let host else { return }
        originalFrames = contents.map { $0.convert($0.bounds, to: host) }
    }

    func update(scale: CGFloat, selected: Bool, offset: CGFloat = 0, backdrop: NSRect? = nil, accented: Bool? = nil, neutralHover: Bool = false) {
        guard let view else { return }
        let coordinateView = host ?? view
        let contentFrames = contents.map { $0.convert($0.bounds, to: coordinateView) }
        let next = chatListFolderDropContentFrames(contentFrames, scale: scale, offset: offset, horizontal: horizontal)
        if let appearance {
            if highlight == nil {
                updateAccent(accented ?? appearance.selected, neutralHover: neutralHover)
            }
        } else {
            updateBackdrop(contentFrames: contentFrames, next: next, coordinateView: coordinateView, selected: selected, backdrop: backdrop)
        }
        guard replicas.count == contents.count, next != frames else { return }
        frames = next
        for (index, frame) in next.enumerated() {
            let replica = replicas[index]
            guard let layer = replica.layer else { continue }
            let current = layer.presentation() ?? layer
            let position = current.position
            let bounds = current.bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            replica.frame = frame
            layer.removeAnimation(forKey: animationKey)
            if let idle = idleLayers[index], let accent = accentLayers[index] {
                for child in [idle, accent, hoverLayers[index]].compactMap({ $0 }) {
                    let current = child.presentation() ?? child
                    let position = current.position
                    let bounds = current.bounds
                    child.frame = highlight != nil && child !== idle ? frame : replica.bounds
                    child.removeAnimation(forKey: animationKey)
                    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        let movement = CABasicAnimation(keyPath: "position")
                        movement.fromValue = NSValue(point: position)
                        movement.toValue = NSValue(point: child.position)
                        let resize = CABasicAnimation(keyPath: "bounds")
                        resize.fromValue = NSValue(rect: bounds)
                        resize.toValue = NSValue(rect: child.bounds)
                        let group = CAAnimationGroup()
                        group.animations = [movement, resize]
                        group.duration = 0.14
                        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        child.add(group, forKey: animationKey)
                    }
                }
            }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let movement = CABasicAnimation(keyPath: "position")
                movement.fromValue = NSValue(point: position)
                movement.toValue = NSValue(point: layer.position)
                let resize = CABasicAnimation(keyPath: "bounds")
                resize.fromValue = NSValue(rect: bounds)
                resize.toValue = NSValue(rect: layer.bounds)
                let group = CAAnimationGroup()
                group.animations = [movement, resize]
                group.duration = 0.14
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(group, forKey: animationKey)
            }
            CATransaction.commit()
        }
    }

    private func updateBackdrop(contentFrames: [NSRect], next: [NSRect], coordinateView: NSView, selected: Bool, backdrop: NSRect?) {
        let content = next.filter { !$0.isEmpty }.reduce(NSRect.null) { $0.union($1) }
        let plateFrame = backdrop ?? chatListFolderDropBackdropFrame(content: content, bounds: coordinateView.bounds.insetBy(dx: 2, dy: 2), neighbors: [], horizontal: horizontal)
        if plate.frame.isEmpty, host != nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            plate.frame = chatListFolderDropBackdropFrame(content: contentFrames.filter { !$0.isEmpty }.reduce(NSRect.null) { $0.union($1) }, bounds: coordinateView.bounds.insetBy(dx: 2, dy: 2), neighbors: [], horizontal: horizontal)
            CATransaction.commit()
        }
        let current = plate.presentation() ?? plate
        let position = current.position
        let bounds = current.bounds
        let opacity = current.opacity
        let geometryChanged = plate.frame != plateFrame
        let hadGeometry = !plate.frame.isEmpty
        let selectionChanged = self.selected != selected
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if host == nil {
            overlay.frame = plateFrame
        } else {
            plate.frame = plateFrame
        }
        plate.cornerRadius = min(12, plate.bounds.height / 2)
        plate.backgroundColor = theme.colors.accent.withAlphaComponent(0.14).cgColor
        plate.borderWidth = 0
        plate.opacity = selected ? 1 : 0
        if geometryChanged && hadGeometry && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let movement = CABasicAnimation(keyPath: "position")
            movement.fromValue = NSValue(point: position)
            movement.toValue = NSValue(point: plate.position)
            let resize = CABasicAnimation(keyPath: "bounds")
            resize.fromValue = NSValue(rect: bounds)
            resize.toValue = NSValue(rect: plate.bounds)
            let group = CAAnimationGroup()
            group.animations = [movement, resize]
            group.duration = 0.14
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            plate.add(group, forKey: "chatFolderDropBackdrop")
        }
        if selectionChanged {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = opacity
            animation.toValue = plate.opacity
            animation.duration = 0.14
            plate.add(animation, forKey: "chatFolderDropPlate")
        }
        CATransaction.commit()
        self.selected = selected
    }

    func impact(horizontal: Bool) {
        update(scale: 1, selected: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.opacity = 0
        CATransaction.commit()
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0.35, 0.65, 0]
        animation.keyTimes = [0, 0.25, 1]
        animation.duration = 0.34
        plate.add(animation, forKey: "chatFolderDropPlate")
    }

    func remove() {
        guard !removed else { return }
        removed = true
        plate.removeAllAnimations()
        plate.removeFromSuperlayer()
        overlay.removeFromSuperview()
        if !replicas.isEmpty {
            for content in contents {
                content.layer?.removeAnimation(forKey: hiddenKey)
            }
        }
        for layer in Array(idleLayers.values) + Array(accentLayers.values) + Array(hoverLayers.values) {
            layer.removeAllAnimations()
            layer.removeFromSuperlayer()
        }
        idleLayers.removeAll()
        accentLayers.removeAll()
        hoverLayers.removeAll()
        for replica in replicas {
            replica.layer?.removeAllAnimations()
            replica.removeFromSuperview()
        }
        replicas.removeAll()
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
    private let appearance: (NSView) -> ChatListFolderDropAppearance?
    private var timer: Foundation.Timer?
    private var sender: NSDraggingInfo?
    private var feedback: [ObjectIdentifier: ChatListFolderDropFeedback] = [:]
    private var impact: ChatListFolderDropFeedback?
    private var impactTimer: Foundation.Timer?
    private var releaseTimer: Foundation.Timer?
    private var landing = false
    private var presentationHost: NSView?
    private var highlight: ChatListFolderDropHighlight?
    private let selectionFrame: () -> (Int32, NSRect)?
    private var generation: UInt64 = 0

    public init(context: any AccountContextProtocol, scrollView: NSScrollView, horizontal: Bool, target: @escaping (NSPoint) -> (ChatListFilter, NSView)?, visibleTargets: @escaping () -> [(ChatListFilter, NSView, [NSView])] = { [] }, appearance: @escaping (NSView) -> ChatListFolderDropAppearance? = { _ in nil }, selectionFrame: @escaping () -> (Int32, NSRect)? = { nil }) {
        self.context = context
        self.scrollView = scrollView
        self.horizontal = horizontal
        self.target = target
        self.visibleTargets = visibleTargets
        self.appearance = appearance
        self.selectionFrame = selectionFrame
    }

    public func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let scrollView, scrollView.window != nil, !scrollView.isHiddenOrHasHiddenAncestor, ChatListFolderDrop.canScroll(sender, context: context), scrollView.visibleRect.contains(scrollView.convert(sender.draggingLocation, from: nil)) else {
            exit()
            return []
        }
        if self.sender == nil {
            generation &+= 1
            releaseTimer?.invalidate()
            releaseTimer = nil
            if landing { clearFeedback() }
            landing = false
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
        guard let scrollView else { return [] }
        let resolved = target(point)
        let selected = resolved.flatMap { filter, view in
            ChatListFolderDrop.validate(sender, context: context, filter: filter).isEmpty ? nil : view
        }
        let hovered = resolved?.1
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reducedMotion {
            if presentationHost != nil { clearFeedback() }
            var retained = Set<ObjectIdentifier>()
            for (filter, view, contents) in visibleTargets() where view.window != nil && !view.isHiddenOrHasHiddenAncestor && !view.visibleRect.isEmpty {
                let appearance = self.appearance(view)
                guard appearance != nil || view === selected else { continue }
                let id = ObjectIdentifier(view)
                let filterId = ChatListUIHooks.shared.chatListFilterId(filter)
                if feedback[id]?.matches(filterId: filterId, contents: contents) != true || feedback[id]?.matchesAppearance(appearance) != true {
                    feedback[id]?.remove()
                    feedback[id] = ChatListFolderDropFeedback(filterId: filterId, view: view, contents: contents, horizontal: horizontal, appearance: appearance)
                }
                feedback[id]?.update(scale: 1, selected: view === selected, accented: hovered == nil ? appearance?.selected : view === selected, neutralHover: view === hovered && selected == nil)
                retained.insert(id)
            }
            for id in Array(feedback.keys) where !retained.contains(id) {
                feedback.removeValue(forKey: id)?.remove()
            }
            return selected == nil ? [] : .copy
        }
        if presentationHost == nil {
            clearFeedback()
            let host = ChatListFolderDropOverlayView(frame: scrollView.contentView.frame)
            host.wantsLayer = true
            host.layer?.masksToBounds = true
            host.setAccessibilityElement(false)
            scrollView.addSubview(host, positioned: .above, relativeTo: nil)
            presentationHost = host
        }
        guard let presentationHost else { return [] }
        presentationHost.frame = scrollView.contentView.frame
        let point = presentationHost.convert(point, from: nil)
        let targets = visibleTargets().filter { $0.1.window != nil && !$0.1.isHiddenOrHasHiddenAncestor && !$0.1.visibleRect.isEmpty }
        if highlight == nil, targets.contains(where: { appearance($0.1) != nil }) {
            highlight = ChatListFolderDropHighlight(host: presentationHost)
        }
        highlight?.resize(presentationHost.bounds)
        let frames = targets.map { $0.1.convert($0.1.bounds, to: presentationHost) }
        var scales: [CGFloat] = []
        var growth: [CGFloat] = []
        for (index, entry) in targets.enumerated() {
            let (_, _, contents) = entry
            let rect = frames[index]
            let length = horizontal ? rect.width : rect.height
            let distance = horizontal ? point.x - rect.midX : point.y - rect.midY
            var scale = chatListFolderDropMagnification(distance: distance, length: length, horizontal: horizontal)
            let contentRect = contents.reduce(NSRect.null) { $0.union($1.convert($1.bounds, to: presentationHost)) }
            if let primary = contents.first, !contentRect.isEmpty {
                let primaryRect = primary.convert(primary.bounds, to: presentationHost)
                let viewport = presentationHost.bounds.insetBy(dx: 2, dy: 2)
                if horizontal {
                    scale = chatListFolderDropFittedScale(scale, content: contentRect, bounds: rect.insetBy(dx: 2, dy: 2))
                    scale = max(1, min(scale, (contentRect.maxY - viewport.minY) / max(1, contentRect.height)))
                } else {
                    scale = max(1, min(scale, (primaryRect.maxX - viewport.minX) / max(1, primaryRect.width)))
                }
                growth.append((horizontal ? contentRect.width : primaryRect.height) * (scale - 1))
            } else {
                scale = 1
                growth.append(0)
            }
            scales.append(scale)
        }
        let contentFrames = targets.map { entry in entry.2.reduce(NSRect.null) { $0.union($1.convert($1.bounds, to: presentationHost)) } }
        let viewport = presentationHost.bounds.insetBy(dx: 2, dy: 2)
        func fits(_ strength: CGFloat) -> Bool {
            let growth = growth.map { $0 * strength }
            let offsets = chatListFolderDropOffsets(frames: frames, growth: growth, position: horizontal ? point.x : point.y, horizontal: horizontal, contents: contentFrames)
            for (index, entry) in targets.enumerated() {
                guard entry.1 === hovered, let primary = entry.2.first else { continue }
                let content = contentFrames[index]
                guard viewport.contains(content) else { continue }
                let originalMin = horizontal ? content.minX : content.minY
                let originalMax = horizontal ? content.maxX : content.maxY
                let extra = horizontal ? 0 : max(0, primary.convert(primary.bounds, to: presentationHost).minY - content.minY) * (scales[index] - 1) * strength
                let lower = horizontal ? viewport.minX : viewport.minY
                let upper = horizontal ? viewport.maxX : viewport.maxY
                if originalMin + offsets[index] - growth[index] / 2 - extra < lower || originalMax + offsets[index] + growth[index] / 2 > upper {
                    return false
                }
            }
            return true
        }
        if !fits(1) {
            var lower: CGFloat = 0
            var upper: CGFloat = 1
            for _ in 0..<10 {
                let middle = (lower + upper) / 2
                if fits(middle) { lower = middle } else { upper = middle }
            }
            for index in growth.indices {
                growth[index] *= lower
                scales[index] = 1 + (scales[index] - 1) * lower
            }
        }
        let offsets = chatListFolderDropOffsets(frames: frames, growth: growth, position: horizontal ? point.x : point.y, horizontal: horizontal, contents: contentFrames)
        let displayFrames = targets.enumerated().map { index, entry in
            chatListFolderDropContentFrames(entry.2.map { $0.convert($0.bounds, to: presentationHost) }, scale: scales[index], offset: offsets[index], horizontal: horizontal).filter { !$0.isEmpty }.reduce(NSRect.null) { $0.union($1) }
        }
        var retained = Set<ObjectIdentifier>()
        for (index, entry) in targets.enumerated() {
            let (filter, view, contents) = entry
            let id = ObjectIdentifier(view)
            let filterId = ChatListUIHooks.shared.chatListFilterId(filter)
            let appearance = self.appearance(view)
            if feedback[id]?.matches(filterId: filterId, contents: contents) != true || feedback[id]?.matchesAppearance(appearance) != true {
                feedback[id]?.remove()
                feedback[id] = ChatListFolderDropFeedback(filterId: filterId, view: view, contents: contents, host: presentationHost, horizontal: horizontal, appearance: appearance, highlight: highlight)
            }
            feedback[id]?.refreshGeometry()
            let backdrop = chatListFolderDropBackdropFrame(content: displayFrames[index], bounds: viewport, neighbors: displayFrames.enumerated().compactMap { $0.offset == index ? nil : $0.element }, horizontal: horizontal)
            feedback[id]?.update(scale: scales[index], selected: view === selected, offset: offsets[index], backdrop: backdrop, accented: view === selected, neutralHover: view === hovered && selected == nil)
            retained.insert(id)
        }
        for id in Array(feedback.keys) where !retained.contains(id) {
            feedback.removeValue(forKey: id)?.remove()
        }
        if let highlight {
            if let original = feedback.values.first(where: { $0.isSelection }) {
                highlight.seed(original.originalHighlightFrame, filterId: original.filterId)
            } else if let (filterId, frame) = selectionFrame() {
                highlight.seed(presentationHost.convert(frame, from: nil), filterId: filterId)
            }
            if let hovered, let destination = feedback[ObjectIdentifier(hovered)] {
                highlight.move(to: destination.highlightFrame, filterId: destination.filterId, neutral: selected == nil)
            }
        }
        return selected == nil ? [] : .copy
    }

    private func clearFeedback() {
        for value in feedback.values { value.remove() }
        feedback.removeAll()
        highlight?.remove()
        highlight = nil
        presentationHost?.removeFromSuperview()
        presentationHost = nil
    }

    private func releaseFeedback() {
        releaseTimer?.invalidate()
        landing = false
        for value in feedback.values {
            let selected = value.view.flatMap { appearance($0)?.selected }
            value.update(scale: 1, selected: false, accented: selected)
        }
        if let highlight {
            if let original = feedback.values.first(where: { $0.isSelection }) {
                highlight.move(to: original.highlightFrame, filterId: original.filterId, neutral: false, settling: true)
            } else if let (filterId, frame) = selectionFrame(), let presentationHost {
                highlight.move(to: presentationHost.convert(frame, from: nil), filterId: filterId, neutral: false, settling: true)
            }
        }
        let start = CACurrentMediaTime()
        let duration = highlight.map { max(0.16, $0.remaining + 0.02) } ?? (feedback.values.contains(where: { $0.transfersAccent }) ? chatListFolderDropAccentDuration + 0.02 : 0.16)
        let timer = Foundation.Timer(timeInterval: 1.0 / 60.0, repeats: true, block: { [weak self] _ in
            guard let self else { return }
            for id in Array(self.feedback.keys) {
                guard let value = self.feedback[id] else { continue }
                if let view = value.view, let contents = self.currentContents(view: view, filterId: value.filterId), value.matches(filterId: value.filterId, contents: contents), value.geometryMatches { continue }
                self.feedback.removeValue(forKey: id)?.remove()
            }
            if CACurrentMediaTime() - start >= duration || self.feedback.isEmpty {
                self.releaseTimer?.invalidate()
                self.releaseTimer = nil
                self.clearFeedback()
            }
        })
        releaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
        timer?.invalidate()
        timer = nil
        self.sender = nil
        guard let scrollView, !scrollView.isHiddenOrHasHiddenAncestor, scrollView.visibleRect.contains(scrollView.convert(sender.draggingLocation, from: nil)), let (filter, view) = target(sender.draggingLocation) else {
            exit()
            return false
        }
        generation &+= 1
        let generation = self.generation
        let filterId = ChatListUIHooks.shared.chatListFilterId(filter)
        landing = true
        releaseTimer?.invalidate()
        let destination: () -> NSView? = { [weak self, weak view] in
            guard let self, self.generation == generation, let view, let contents = self.currentContents(view: view, filterId: filterId) else { return nil }
            if let feedback = self.feedback[ObjectIdentifier(view)], feedback.matches(filterId: filterId, contents: contents), feedback.geometryMatches {
                return feedback.destination
            }
            return self.horizontal ? view : contents.first
        }
        let accepted = ChatListFolderDrop.perform(sender, context: context, filter: filter, destination: destination, completed: { [weak self, weak view] added in
            guard let self, self.generation == generation, self.sender == nil else { return }
            self.releaseFeedback()
            guard added, let view, self.appearance(view) == nil, let contents = self.currentContents(view: view, filterId: filterId) else { return }
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
            })
            self.impactTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        })
        if !accepted {
            landing = false
            exit()
        } else if landing {
            let start = CACurrentMediaTime()
            let timer = Foundation.Timer(timeInterval: 1.0 / 60.0, repeats: true, block: { [weak self, weak view] _ in
                guard let self else { return }
                for id in Array(self.feedback.keys) {
                    guard let value = self.feedback[id] else { continue }
                    if let host = value.view, let contents = self.currentContents(view: host, filterId: value.filterId), value.matches(filterId: value.filterId, contents: contents), value.geometryMatches { continue }
                    self.feedback.removeValue(forKey: id)?.remove()
                }
                if view == nil || destination() == nil || CACurrentMediaTime() - start > 1.5 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    self.releaseFeedback()
                }
            })
            releaseTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        return accepted
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
        if landing, let scrollView, scrollView.window != nil, !scrollView.isHiddenOrHasHiddenAncestor, !context.isFrozen { return }
        if landing {
            landing = false
            releaseTimer?.invalidate()
            releaseTimer = nil
            clearFeedback()
        }
        if let scrollView, scrollView.window != nil, !scrollView.isHiddenOrHasHiddenAncestor, !context.isFrozen, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || feedback.values.contains(where: { $0.transfersAccent }), !feedback.isEmpty {
            if releaseTimer == nil { releaseFeedback() }
        } else {
            releaseTimer?.invalidate()
            releaseTimer = nil
            clearFeedback()
        }
        clearImpact()
    }

    deinit {
        timer?.invalidate()
        releaseTimer?.invalidate()
        impactTimer?.invalidate()
        clearFeedback()
        impact?.remove()
    }
}
