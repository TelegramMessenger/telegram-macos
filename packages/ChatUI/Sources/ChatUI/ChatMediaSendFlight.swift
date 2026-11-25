import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramUtils

public struct ChatMediaSendFlightSource {
    public let rect: NSRect
    public let snapshot: CGImage?
    public let cornerRadius: CGFloat
    public let sourceLayer: CALayer?

    public init(rect: NSRect, snapshot: CGImage?, cornerRadius: CGFloat = 0, sourceLayer: CALayer? = nil) {
        self.rect = rect
        self.snapshot = snapshot
        self.cornerRadius = cornerRadius
        self.sourceLayer = sourceLayer
    }

    public init?(view: NSView, rect: NSRect, cornerRadius: CGFloat = 0, sourceLayer: CALayer? = nil) {
        guard view.window != nil, rect.width >= 1, rect.height >= 1 else {
            return nil
        }
        var snapshot: CGImage?
        if let rep = view.bitmapImageRepForCachingDisplay(in: rect) {
            view.cacheDisplay(in: rect, to: rep)
            snapshot = rep.cgImage
        }
        self.init(rect: view.convert(rect, to: nil), snapshot: snapshot, cornerRadius: cornerRadius, sourceLayer: sourceLayer)
    }
}

public final class ChatMediaSendFlight {
    private final class HiddenSource {
        weak var layer: CALayer?
        let opacity: Float

        init(layer: CALayer) {
            self.layer = layer
            self.opacity = layer.opacity
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0
            CATransaction.commit()
        }

        func restore() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.opacity = self.opacity
            CATransaction.commit()
        }
    }

    private final class Pending {
        let id: Int
        let source: ChatMediaSendFlightSource
        let knownStableIds: Set<AnyHashable>
        let parked: CALayer?

        init(id: Int, source: ChatMediaSendFlightSource, knownStableIds: Set<AnyHashable>, parked: CALayer?) {
            self.id = id
            self.source = source
            self.knownStableIds = knownStableIds
            self.parked = parked
        }
    }

    private final class Lift {
        let container: View
        weak var rowItemView: ChatRowView?

        init(container: View, rowItemView: ChatRowView) {
            self.container = container
            self.rowItemView = rowItemView
        }
    }

    private final class Flight {
        var lifts: [Lift] = []
        var snapshotView: View?
        var hidden: HiddenSource?
    }

    private weak var view: ChatControllerView?
    private let canLaunch: () -> Bool
    private var host: View?
    private var pending: Pending?
    private var nextId: Int = 0
    private var flights: [Flight] = []

    init(view: ChatControllerView, canLaunch: @escaping () -> Bool) {
        self.view = view
        self.canLaunch = canLaunch
    }

    deinit {
        for flight in self.flights {
            self.finish(flight)
        }
        self.pending?.parked?.removeFromSuperlayer()
        self.host?.removeFromSuperview()
    }

    private var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || TelegramUtilsHooks.shared.isLite(.animations)
    }

    public func launch(_ source: ChatMediaSendFlightSource) {
        self.dropPending(animated: false)
        guard !self.reduceMotion, self.canLaunch(), let view = self.view, view.chatTheme?.bubbled == true, let window = view.window, view.tableView.documentOffset.y < 20, let contentView = window.contentView else {
            return
        }

        var knownStableIds = Set<AnyHashable>()
        view.tableView.enumerateItems(with: { item in
            if let item = item as? ChatRowItem, let message = item.message, !message.flags.contains(.Incoming), message.flags.contains(.Unsent) {
                knownStableIds.insert(item.stableId)
            }
            return true
        })

        let host: View
        if let current = self.host, current.superview === contentView {
            host = current
        } else {
            self.host?.removeFromSuperview()
            host = View(frame: contentView.bounds)
            host.isEventLess = true
            host.backgroundColor = .clear
            host.layer?.masksToBounds = false
            host.autoresizingMask = [.width, .height]
            self.host = host
        }
        contentView.addSubview(host)

        var parked: CALayer?
        if let snapshot = source.snapshot, let hostLayer = host.layer {
            let layer = CALayer()
            layer.contents = snapshot
            layer.contentsGravity = .resize
            layer.cornerRadius = source.cornerRadius
            layer.masksToBounds = source.cornerRadius > 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = host.convert(source.rect, from: nil)
            hostLayer.addSublayer(layer)
            CATransaction.commit()
            parked = layer
        }

        self.nextId += 1
        let id = self.nextId
        self.pending = Pending(id: id, source: source, knownStableIds: knownStableIds, parked: parked)
        delay(ChatVoiceSendFlightMotion.handOverTimeout, closure: { [weak self] in
            if self?.pending?.id == id {
                self?.dropPending(animated: true)
            }
        })
    }

    private func dropPending(animated: Bool) {
        guard let pending = self.pending else {
            return
        }
        self.pending = nil
        if let parked = pending.parked {
            if animated {
                parked.opacity = 0
                parked.add(flightAnimation(keyPath: "opacity", from: 1.0 as NSNumber, to: 0.0 as NSNumber, duration: 0.15, timingFunction: CAMediaTimingFunction(name: .easeInEaseOut), additive: false, completion: { [weak self, weak parked] in
                    parked?.removeFromSuperlayer()
                    self?.releaseHostIfIdle()
                }), forKey: "mediaFlightAlpha")
            } else {
                parked.removeFromSuperlayer()
            }
        }
        self.releaseHostIfIdle()
    }

    private func releaseHostIfIdle() {
        guard self.pending == nil, self.flights.isEmpty, let host = self.host else {
            return
        }
        if host.layer?.sublayers?.contains(where: { $0.animation(forKey: "mediaFlightAlpha") != nil }) == true {
            return
        }
        host.removeFromSuperview()
        self.host = nil
    }

    private func finish(_ flight: Flight) {
        guard let index = self.flights.firstIndex(where: { $0 === flight }) else {
            return
        }
        self.flights.remove(at: index)
        for lift in flight.lifts {
            lift.container.layer?.removeAllAnimations()
            if let layer = lift.rowItemView?.rowView.layer {
                for key in layer.animationKeys() ?? [] where key.hasPrefix("mediaFlight") {
                    layer.removeAnimation(forKey: key)
                }
            }
            lift.rowItemView?.reattachRowView()
            lift.container.removeFromSuperview()
        }
        flight.snapshotView?.removeFromSuperview()
        flight.hidden?.restore()
        self.releaseHostIfIdle()
    }

    func tableDidUpdate() {
        guard let host = self.host else {
            return
        }
        for flight in self.flights {
            let stale = flight.lifts.contains(where: { lift in
                guard let rowItemView = lift.rowItemView else {
                    return true
                }
                return rowItemView.convert(rowItemView.bounds, to: host) != lift.container.frame
            })
            if stale {
                self.finish(flight)
            }
        }
        guard let pending = self.pending, let view = self.view else {
            return
        }
        var targets: [ChatRowView] = []
        view.tableView.enumerateVisibleViews(with: { rowItemView in
            guard let rowItemView = rowItemView as? ChatRowView, let item = rowItemView.item as? ChatRowItem, let message = item.message, !message.flags.contains(.Incoming), message.flags.contains(.Unsent), !pending.knownStableIds.contains(item.stableId) else {
                return
            }
            targets.append(rowItemView)
        })
        guard !targets.isEmpty else {
            return
        }
        self.pending = nil
        pending.parked?.removeFromSuperlayer()
        for flight in self.flights {
            self.finish(flight)
        }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.timingFunction = nil
        NSAnimationContext.current.allowsImplicitAnimation = false
        self.start(source: pending.source, targets: targets, host: host, view: view)
        NSAnimationContext.endGrouping()
        self.releaseHostIfIdle()
    }

    private func start(source: ChatMediaSendFlightSource, targets: [ChatRowView], host: View, view: ChatControllerView) {
        var rows: [(ChatRowView, NSRect)] = []
        var union: NSRect?
        for rowItemView in targets {
            rowItemView.layoutSubtreeIfNeeded()
            guard rowItemView.window === host.window, let item = rowItemView.item as? ChatRowItem else {
                continue
            }
            let content: NSView = item.hasBubble ? rowItemView.bubbleView : rowItemView.contentView
            let contentRect = content.convert(content.bounds, to: host)
            guard !contentRect.isEmpty else {
                continue
            }
            rows.append((rowItemView, rowItemView.convert(rowItemView.bounds, to: host)))
            union = union.map { $0.union(contentRect) } ?? contentRect
        }
        let visibleRect = view.tableView.convert(view.tableView.bounds, to: host)
        let sourceRect = host.convert(source.rect, from: nil)
        guard let target = union, !rows.isEmpty, visibleRect.contains(target), sourceRect.width > 0, sourceRect.height > 0 else {
            return
        }

        let offset = NSMakePoint(sourceRect.midX - target.midX, sourceRect.midY - target.midY)
        let scale = NSMakeSize(sourceRect.width / target.width, sourceRect.height / target.height)
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)

        let flight = Flight()
        flight.hidden = source.sourceLayer.map(HiddenSource.init)
        self.flights.append(flight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        func move(_ view: View, completion: (() -> Void)?) {
            guard let layer = view.layer else {
                return
            }
            let pivot = view.convert(NSMakePoint(target.midX, target.midY), from: host)
            let anchor = NSMakePoint(layer.anchorPoint.x * layer.bounds.width + layer.bounds.minX, layer.anchorPoint.y * layer.bounds.height + layer.bounds.minY)
            let transform = CATransform3DConcat(CATransform3DMakeScale(scale.width, scale.height, 1), CATransform3DMakeTranslation((1 - scale.width) * (pivot.x - anchor.x), (1 - scale.height) * (pivot.y - anchor.y), 0))
            layer.add(flightAnimation(keyPath: "transform", from: NSValue(caTransform3D: transform), to: NSValue(caTransform3D: CATransform3DIdentity), duration: ChatTextSendFlightMotion.horizontalDuration, timingFunction: ease, additive: false), forKey: "mediaFlightScale")
            layer.add(flightAnimation(keyPath: "position", from: NSValue(point: NSMakePoint(offset.x, 0)), to: NSValue(point: .zero), duration: ChatTextSendFlightMotion.horizontalDuration, timingFunction: ease, additive: true), forKey: "mediaFlightX")

            let animation = CASpringAnimation(keyPath: "position")
            animation.mass = 1.0
            animation.stiffness = ChatTextSendFlightMotion.verticalStiffness
            animation.damping = ChatTextSendFlightMotion.verticalDamping
            animation.fromValue = NSValue(point: NSMakePoint(0, offset.y))
            animation.toValue = NSValue(point: .zero)
            animation.duration = animation.settlingDuration
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + ChatTextSendFlightMotion.verticalDelay
            animation.fillMode = .both
            animation.isAdditive = true
            if let completion {
                animation.delegate = CALayerAnimationDelegate(completion: { _ in
                    completion()
                })
            }
            layer.add(animation, forKey: "mediaFlightY")
        }

        for (index, (rowItemView, rowRect)) in rows.enumerated() {
            let rowView = rowItemView.rowView
            let container = View(frame: rowRect)
            container.isEventLess = true
            container.backgroundColor = .clear
            container.layer?.masksToBounds = false
            host.addSubview(container)

            let rowViewFrame = rowView.frame
            container.addSubview(rowView)
            rowView.frame = rowViewFrame
            rowView.layer?.removeAllAnimations()
            if source.snapshot != nil {
                rowView.layer?.add(flightAnimation(keyPath: "opacity", from: 0.0 as NSNumber, to: 1.0 as NSNumber, duration: 0.1, timingFunction: ease, additive: false), forKey: "mediaFlightAlpha")
            }

            flight.lifts.append(Lift(container: container, rowItemView: rowItemView))
            move(container, completion: index == 0 ? { [weak self, weak flight] in
                if let flight {
                    self?.finish(flight)
                }
            } : nil)
        }

        if let snapshot = source.snapshot {
            let snapshotView = View(frame: target)
            snapshotView.isEventLess = true
            snapshotView.backgroundColor = .clear
            snapshotView.layer?.masksToBounds = false
            host.addSubview(snapshotView)
            let layer = CALayer()
            layer.contents = snapshot
            layer.contentsGravity = .resize
            layer.frame = snapshotView.bounds
            if source.cornerRadius > 0 {
                layer.cornerRadius = source.cornerRadius / max(scale.width, scale.height)
                layer.masksToBounds = true
            }
            layer.opacity = 0
            layer.add(flightAnimation(keyPath: "opacity", from: 1.0 as NSNumber, to: 0.0 as NSNumber, duration: 0.1, timingFunction: ease, additive: false), forKey: "mediaFlightAlpha")
            snapshotView.layer?.addSublayer(layer)
            move(snapshotView, completion: nil)
            flight.snapshotView = snapshotView
        }

        CATransaction.commit()
    }
}
