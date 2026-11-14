import Cocoa
import TGUIKit
import TelegramTheme

struct ChatListFolderDragCompletion {
    private(set) var accepted = false
    private(set) var ended = false
    private(set) var added: Bool?
    private(set) var finished = false

    mutating func accept() {
        accepted = true
    }

    mutating func end() {
        ended = true
    }

    mutating func complete(added: Bool) {
        if self.added == nil {
            self.added = added
        }
    }

    mutating func finish() -> Bool? {
        guard !finished, ended, !accepted || added != nil else {
            return nil
        }
        finished = true
        return added == true
    }
}

struct ChatListFolderDragMotion {
    let frame: NSRect
    let alpha: CGFloat

    static func returnDuration(from start: NSRect, to target: NSRect) -> TimeInterval {
        return 0.30 + 0.15 * min(1, hypot(target.midX - start.midX, target.midY - start.midY) / 600)
    }

    static func reappearance(at target: NSRect, progress: CGFloat, reducedMotion: Bool) -> ChatListFolderDragMotion {
        let progress = min(1, max(0, progress))
        if reducedMotion {
            return ChatListFolderDragMotion(frame: target, alpha: progress * progress * (3 - 2 * progress))
        }
        let remaining = 1 - progress
        let scale = 1 + remaining * remaining * remaining * (5.285043430570758 * progress - 0.96)
        let size = NSSize(width: target.width * scale, height: target.height * scale)
        let opacity = min(1, progress / 0.12)
        return ChatListFolderDragMotion(frame: NSRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2, width: size.width, height: size.height), alpha: opacity * opacity * (3 - 2 * opacity))
    }

    static func value(from start: NSRect, to target: NSRect, progress: CGFloat, added: Bool, reducedMotion: Bool) -> ChatListFolderDragMotion {
        let progress = min(1, max(0, progress))
        func ease(_ value: CGFloat) -> CGFloat {
            let value = min(1, max(0, value))
            return value * value * (3 - 2 * value)
        }
        if reducedMotion {
            return ChatListFolderDragMotion(frame: start, alpha: 1 - ease(progress))
        }
        let dx = target.midX - start.midX
        let dy = target.midY - start.midY
        if added {
            let travel = ease(progress / 0.9)
            let resize = ease((progress - 0.58) / 0.42)
            let size = NSSize(width: start.width + (target.width - start.width) * resize, height: start.height + (target.height - start.height) * resize)
            let center = NSPoint(x: start.midX + dx * travel, y: start.midY + dy * travel)
            return ChatListFolderDragMotion(frame: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), alpha: 1 - ease((progress - 0.88) / 0.12))
        }
        let remaining = 1 - progress
        let travel = 1 - remaining * remaining * remaining * remaining * (1 + 4 * progress)
        let distance = hypot(dx, dy)
        let arc = min(12, distance * 0.035) * 4 * travel * (1 - travel)
        let direction: CGFloat = dx < 0 ? -1 : 1
        let center = NSPoint(x: start.midX + dx * travel - dy / max(1, distance) * direction * arc, y: start.midY + dy * travel + abs(dx) / max(1, distance) * arc)
        let size = NSSize(width: start.width + (target.width - start.width) * travel, height: start.height + (target.height - start.height) * travel)
        return ChatListFolderDragMotion(frame: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), alpha: 1)
    }
}

final class ChatListFolderDragPresentation: NSObject, CAAnimationDelegate {
    private enum Phase {
        case returning
        case landing
        case reappearing
    }

    private struct Playback {
        let phase: Phase
        let from: ChatListFolderDragMotion
        let target: NSRect
        let started: TimeInterval
        let duration: TimeInterval
        let reducedMotion: Bool
        let settling: Bool

        func value(at progress: CGFloat) -> ChatListFolderDragMotion {
            let progress = min(1, max(0, progress))
            let eased = progress * progress * (3 - 2 * progress)
            if reducedMotion {
                if phase == .reappearing {
                    return ChatListFolderDragMotion(frame: target, alpha: from.alpha + (1 - from.alpha) * eased)
                }
                return ChatListFolderDragMotion(frame: from.frame, alpha: from.alpha * (1 - eased))
            }
            if settling {
                let frame = NSRect(x: from.frame.minX + (target.minX - from.frame.minX) * eased, y: from.frame.minY + (target.minY - from.frame.minY) * eased, width: from.frame.width + (target.width - from.frame.width) * eased, height: from.frame.height + (target.height - from.frame.height) * eased)
                return ChatListFolderDragMotion(frame: frame, alpha: from.alpha + ((phase == .landing ? 0 : 1) - from.alpha) * eased)
            }
            if phase == .reappearing {
                return ChatListFolderDragMotion.reappearance(at: target, progress: progress, reducedMotion: false)
            }
            return ChatListFolderDragMotion.value(from: from.frame, to: target, progress: progress, added: phase == .landing, reducedMotion: false)
        }
    }

    private weak var origin: NSView?
    private var destination: (() -> NSView?)?
    private var hiddenViews: [(NSView, CGFloat)]
    private let image: NSImage
    private let size: NSSize
    var dragFrame: NSRect = .zero
    private var screenPoint: NSPoint = .zero
    private var state = ChatListFolderDragCompletion()
    private var panel: NSPanel?
    private var previewLayer: CALayer?
    private var timeout: Foundation.Timer?
    private var animationTimer: Foundation.Timer?
    private var playback: Playback?
    private var animationId = 0
    private var destinationUnavailable = false
    private let animationKey = "chatFolderDragMotion"
    private var invalidated = false
    private var completed: ((Bool) -> Void)?

    init(origin: NSView, decorations: [NSView]) {
        self.origin = origin
        self.image = origin.snapshot
        self.size = origin.bounds.size
        self.hiddenViews = ([origin] + decorations).map { ($0, $0.alphaValue) }
        super.init()
    }

    var draggingImage: NSImage {
        let inset: CGFloat = 8
        let result = NSImage(size: NSSize(width: size.width + inset * 2, height: size.height + inset * 2))
        result.lockFocus()
        let shadow = NSShadow()
        shadow.shadowColor = theme.colors.text.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        image.draw(in: NSRect(origin: NSPoint(x: inset, y: inset), size: size))
        result.unlockFocus()
        return result
    }

    func lift() {
        for (view, _) in hiddenViews {
            view.alphaValue = 0
        }
    }

    func move(to point: NSPoint) {
        screenPoint = point
    }

    func accept(destination: (() -> NSView?)?) {
        self.destination = destination
        state.accept()
    }

    func complete(added: Bool, completed: @escaping (Bool) -> Void) {
        guard !invalidated, !state.finished else { return }
        if self.completed == nil {
            self.completed = completed
        }
        state.complete(added: added)
        finishIfReady()
    }

    func ended(at point: NSPoint) {
        guard !state.ended else { return }
        screenPoint = point
        state.end()
        if !invalidated {
            showPreview()
        }
        finishIfReady()
        if !state.finished, !invalidated {
            let timer = Foundation.Timer(timeInterval: 0.8, repeats: false, block: { [self] _ in
                state.complete(added: false)
                finishIfReady()
            })
            timeout = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func restore() {
        for (view, alpha) in hiddenViews {
            view.alphaValue = alpha
        }
        hiddenViews.removeAll()
    }

    func invalidate() {
        invalidated = true
        completed = nil
        timeout?.invalidate()
        timeout = nil
        animationTimer?.invalidate()
        animationTimer = nil
        animationId += 1
        playback = nil
        previewLayer?.removeAllAnimations()
        previewLayer = nil
        panel?.close()
        panel = nil
        restore()
    }

    private func showPreview() {
        guard panel == nil else { return }
        let previewImage = draggingImage
        let fallback = NSRect(x: screenPoint.x - previewImage.size.width / 2, y: screenPoint.y - previewImage.size.height / 2, width: previewImage.size.width, height: previewImage.size.height)
        let panel = NSPanel(contentRect: dragFrame.isEmpty ? fallback : dragFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = theme.colors.background.withAlphaComponent(0)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        let contentView = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        contentView.wantsLayer = true
        let layer = CALayer()
        layer.contents = previewImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        layer.contentsGravity = .resize
        layer.frame = contentView.bounds
        contentView.layer?.addSublayer(layer)
        panel.contentView = contentView
        self.previewLayer = layer
        self.panel = panel
        panel.orderFront(nil)
    }

    private func targetFrame(added: Bool) -> NSRect? {
        guard let target = added ? destination?() : origin, let window = target.window, window.isVisible, !target.isHiddenOrHasHiddenAncestor, !target.visibleRect.isEmpty else { return nil }
        let rect = window.convertToScreen(target.convert(target.bounds, to: nil))
        let targetSize = added ? NSSize(width: 12, height: 12) : NSSize(width: rect.width * (size.width + 16) / max(1, size.width), height: rect.height * (size.height + 16) / max(1, size.height))
        return NSRect(x: rect.midX - targetSize.width / 2, y: rect.midY - targetSize.height / 2, width: targetSize.width, height: targetSize.height)
    }

    private func visibleMotion() -> ChatListFolderDragMotion? {
        guard let panel, let layer = previewLayer else { return nil }
        if let presentation = layer.presentation() {
            return ChatListFolderDragMotion(frame: presentation.frame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY), alpha: CGFloat(presentation.opacity))
        }
        if let playback {
            return playback.value(at: CGFloat((CACurrentMediaTime() - playback.started) / playback.duration))
        }
        return ChatListFolderDragMotion(frame: layer.frame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY), alpha: CGFloat(layer.opacity))
    }

    private func animate(_ playback: Playback) {
        guard let panel, let layer = previewLayer else { return }
        animationId += 1
        let id = animationId
        self.playback = playback
        animationTimer?.invalidate()
        let values = (0...60).map { playback.value(at: CGFloat($0) / 60) }
        let frame = values.reduce(NSRect.null) { $0.union($1.frame) }.insetBy(dx: -4, dy: -4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        panel.setFrame(frame, display: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        let final = values[60]
        layer.bounds = NSRect(origin: .zero, size: final.frame.size)
        layer.position = NSPoint(x: final.frame.midX - frame.minX, y: final.frame.midY - frame.minY)
        layer.opacity = Float(final.alpha)
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = values.map { NSValue(point: NSPoint(x: $0.frame.midX - frame.minX, y: $0.frame.midY - frame.minY)) }
        let bounds = CAKeyframeAnimation(keyPath: "bounds")
        bounds.values = values.map { NSValue(rect: NSRect(origin: .zero, size: $0.frame.size)) }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = values.map { NSNumber(value: Double($0.alpha)) }
        for animation in [position, bounds, opacity] {
            animation.keyTimes = (0...60).map { NSNumber(value: Double($0) / 60) }
            animation.duration = playback.duration
            animation.calculationMode = .linear
        }
        let group = CAAnimationGroup()
        group.animations = [position, bounds, opacity]
        group.duration = playback.duration
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        group.delegate = self
        group.setValue(NSNumber(value: id), forKey: "chatFolderDragId")
        layer.add(group, forKey: animationKey)
        CATransaction.commit()
        let timer = Foundation.Timer(timeInterval: 1.0 / 30.0, repeats: true, block: { [weak self] _ in
            self?.validateAnimation()
        })
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func validateAnimation() {
        guard !invalidated, let playback else { return }
        let target = targetFrame(added: playback.phase == .landing)
        let reducedMotion = playback.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if target == nil && playback.phase == .reappearing {
            invalidate()
            return
        }
        if target == nil && playback.phase == .landing {
            destinationUnavailable = true
        }
        let fade = reducedMotion || target == nil
        if fade == playback.reducedMotion && ((fade && playback.phase != .reappearing) || target == playback.target) {
            return
        }
        guard let current = visibleMotion() else {
            invalidate()
            return
        }
        if fade && playback.phase == .returning {
            restore()
        }
        let remaining = max(0.12, min(0.20, playback.duration - (CACurrentMediaTime() - playback.started)))
        animate(Playback(phase: playback.phase, from: current, target: target ?? current.frame, started: CACurrentMediaTime(), duration: fade ? 0.15 : remaining, reducedMotion: fade, settling: true))
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag, !invalidated, (anim.value(forKey: "chatFolderDragId") as? NSNumber)?.intValue == animationId, let playback else { return }
        let id = animationId
        validateAnimation()
        guard id == animationId, !invalidated else { return }
        self.playback = nil
        animationTimer?.invalidate()
        animationTimer = nil
        if playback.phase == .landing {
            let completed = self.completed
            self.completed = nil
            completed?(!destinationUnavailable)
            guard !invalidated else { return }
            guard let target = targetFrame(added: false) else {
                invalidate()
                return
            }
            let reducedMotion = playback.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let initial = ChatListFolderDragMotion.reappearance(at: target, progress: 0, reducedMotion: reducedMotion)
            animate(Playback(phase: .reappearing, from: initial, target: target, started: CACurrentMediaTime(), duration: reducedMotion ? 0.18 : 0.40, reducedMotion: reducedMotion, settling: false))
        } else {
            restore()
            let timer = Foundation.Timer(timeInterval: 1.0 / 60.0, repeats: false, block: { [self] _ in
                guard !invalidated, animationId == id else { return }
                let completed = self.completed
                self.completed = nil
                invalidate()
                completed?(false)
            })
            animationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func finishIfReady() {
        guard !invalidated, let added = state.finish() else { return }
        timeout?.invalidate()
        timeout = nil
        showPreview()
        guard let current = visibleMotion() else {
            restore()
            return
        }
        let target = targetFrame(added: added)
        destinationUnavailable = added && target == nil
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || target == nil
        if !added && reducedMotion {
            restore()
        }
        let duration = reducedMotion ? 0.15 : (added ? 0.32 : ChatListFolderDragMotion.returnDuration(from: current.frame, to: target ?? current.frame))
        animate(Playback(phase: added ? .landing : .returning, from: current, target: target ?? current.frame, started: CACurrentMediaTime(), duration: duration, reducedMotion: reducedMotion, settling: false))
    }

    deinit {
        timeout?.invalidate()
        animationTimer?.invalidate()
        previewLayer?.removeAllAnimations()
        panel?.close()
        restore()
    }
}
