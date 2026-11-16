import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramUtils
import InputTextView

enum ChatTextSendFlightMotion {
    static let horizontalDuration: Double = 0.185
    static let verticalDelay: Double = 0.07
    static let verticalStiffness: CGFloat = 272.0
    static let verticalDamping: CGFloat = 33.0
}

struct ChatTextSendFlightSource {
    let contents: Any
    let fieldRect: NSRect
    let textRect: NSRect
    let baseline: NSPoint
}

final class ChatTextSendFlight {
    private struct Source {
        let id: Int
        let snapshot: Any
        let fieldRect: NSRect
        let snapshotRect: NSRect
        let baseline: NSPoint
        let knownStableIds: Set<AnyHashable>
        let fadesInMessageBubble: Bool
        let handOff: ((Bool) -> Void)?
    }

    private final class Flight {
        let container: View
        weak var rowItemView: ChatRowView?
        var layers: [CALayer] = []
        var rowViewClips: Bool = true

        init(container: View, rowItemView: ChatRowView) {
            self.container = container
            self.rowItemView = rowItemView
        }
    }

    private weak var view: ChatControllerView?
    private var pending: Source?
    private var nextId: Int = 0
    private var flights: [Flight] = []

    init(view: ChatControllerView) {
        self.view = view
    }

    deinit {
        for flight in self.flights {
            self.finish(flight)
        }
    }

    private func finish(_ flight: Flight) {
        guard let index = self.flights.firstIndex(where: { $0 === flight }) else {
            return
        }
        self.flights.remove(at: index)
        for layer in flight.layers {
            for key in layer.animationKeys() ?? [] where key.hasPrefix("textFlight") {
                layer.removeAnimation(forKey: key)
            }
        }
        flight.rowItemView?.rowView.layer?.masksToBounds = flight.rowViewClips
        flight.rowItemView?.reattachRowView()
        flight.container.removeFromSuperview()
    }

    private var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || TelegramUtilsHooks.shared.isLite(.animations)
    }

    private func cancelPending() {
        let handOff = self.pending?.handOff
        self.pending = nil
        handOff?(false)
    }

    private func canLaunch(_ view: ChatControllerView) -> Bool {
        guard !self.reduceMotion, view.window != nil, view.tableView.documentOffset.y < 20 else {
            return false
        }
        var hasAd = false
        view.tableView.enumerateVisibleItems(with: { item in
            if let item = item as? ChatRowItem, item.isAdRow {
                hasAd = true
                return false
            }
            return true
        })
        return !hasAd
    }

    func launch(from source: ChatTextSendFlightSource, handOff: @escaping (Bool) -> Void) {
        self.cancelPending()
        guard let view = self.view, self.canLaunch(view) else {
            handOff(false)
            return
        }
        self.enqueue(view: view, snapshot: source.contents, fieldRect: view.convert(source.fieldRect, from: nil), snapshotRect: view.convert(source.textRect, from: nil), baseline: view.convert(source.baseline, from: nil), fadesInMessageBubble: false, handOff: handOff)
    }

    func launch(compactSource: Bool = false) {
        self.cancelPending()
        guard let view = self.view, self.canLaunch(view) else {
            return
        }
        let textView = view.inputView.textView
        let scrollView = textView.scrollView
        let input = textView.inputView
        let fieldView = view.inputView.textFieldContainer
        guard !fieldView.isHidden, !scrollView.bounds.isEmpty, let layoutManager = input.layoutManager, layoutManager.numberOfGlyphs > 0 else {
            return
        }

        let fragment = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let location = layoutManager.location(forGlyphAt: 0)
        let origin = input.textContainerOrigin
        let baseline = input.convert(NSMakePoint(origin.x + fragment.minX + location.x, origin.y + fragment.minY + location.y), to: view)

        let insertionPointColor = input.insertionPointColor
        input.insertionPointColor = .clear
        var hiddenViews = (input.superview?.subviews ?? []).filter { $0 is TextView && !$0.isHidden }
        if #available(macOS 14.0, *) {
            hiddenViews += input.subviews.filter { $0 is NSTextInsertionIndicator && !$0.isHidden }
        }
        hiddenViews.forEach { $0.isHidden = true }
        let snapshot = scrollView.snapshot._cgImage
        hiddenViews.forEach { $0.isHidden = false }
        input.insertionPointColor = insertionPointColor
        guard let snapshot else {
            return
        }
        var fieldBounds = fieldView.bounds
        if compactSource, let container = input.textContainer {
            let usedRect = layoutManager.usedRect(for: container).offsetBy(dx: origin.x, dy: origin.y)
            let textRect = input.convert(usedRect, to: fieldView)
            let sourceWidth = ceil(textRect.maxX - fieldBounds.minX + 16)
            if sourceWidth > 0 {
                fieldBounds.size.width = min(fieldBounds.width, sourceWidth)
            }
        }
        self.enqueue(view: view, snapshot: snapshot, fieldRect: fieldView.convert(fieldBounds, to: view), snapshotRect: scrollView.convert(scrollView.bounds, to: view), baseline: baseline, fadesInMessageBubble: true, handOff: nil)
    }

    private func enqueue(view: ChatControllerView, snapshot: Any, fieldRect: NSRect, snapshotRect: NSRect, baseline: NSPoint, fadesInMessageBubble: Bool, handOff: ((Bool) -> Void)?) {
        var knownStableIds = Set<AnyHashable>()
        view.tableView.enumerateItems(with: { item in
            if let item = item as? ChatRowItem, let message = item.message, !message.flags.contains(.Incoming), message.flags.contains(.Unsent) {
                knownStableIds.insert(item.stableId)
            }
            return true
        })

        self.nextId += 1
        let id = self.nextId
        self.pending = Source(id: id, snapshot: snapshot, fieldRect: fieldRect, snapshotRect: snapshotRect, baseline: baseline, knownStableIds: knownStableIds, fadesInMessageBubble: fadesInMessageBubble, handOff: handOff)
        delay(ChatVoiceSendFlightMotion.handOverTimeout, closure: { [weak self] in
            if let self, self.pending?.id == id {
                self.cancelPending()
            }
        })
    }

    func tableDidUpdate() {
        guard let view = self.view else {
            return
        }
        for flight in self.flights {
            if let rowItemView = flight.rowItemView, rowItemView.convert(rowItemView.bounds, to: view) == flight.container.frame {
                continue
            }
            self.finish(flight)
        }
        guard let pending = self.pending else {
            return
        }
        var target: ChatMessageView?
        var targetIndex: MessageIndex?
        view.tableView.enumerateVisibleViews(with: { rowItemView in
            guard let rowItemView = rowItemView as? ChatMessageView, let item = rowItemView.item as? ChatMessageItem, let message = item.message, !message.flags.contains(.Incoming), message.flags.contains(.Unsent), !pending.knownStableIds.contains(item.stableId) else {
                return
            }
            let index = MessageIndex(message)
            if let current = targetIndex, current > index {
                return
            }
            target = rowItemView
            targetIndex = index
        })
        guard let target else {
            return
        }
        self.pending = nil
        for flight in self.flights {
            self.finish(flight)
        }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.timingFunction = nil
        NSAnimationContext.current.allowsImplicitAnimation = false
        let started = self.start(source: pending, rowItemView: target, view: view)
        NSAnimationContext.endGrouping()
        pending.handOff?(started)
    }

    private func start(source: Source, rowItemView: ChatMessageView, view: ChatControllerView) -> Bool {
        rowItemView.layoutSubtreeIfNeeded()
        guard let item = rowItemView.item as? ChatMessageItem, item.isBubbled, item.hasBubble, rowItemView.window === view.window, let text = rowItemView.textContentView, let textBaseline = rowItemView.firstTextBaseline(in: view) else {
            return false
        }
        let rowView = rowItemView.rowView
        let bubbleView = rowItemView.bubbleView
        let tableRect = view.tableView.convert(view.tableView.bounds, to: view)
        let bubbleRect = bubbleView.convert(bubbleView.bounds, to: view)
        guard !bubbleRect.isEmpty, tableRect.contains(bubbleRect) else {
            return false
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let container = View(frame: rowItemView.convert(rowItemView.bounds, to: view))
        container.isEventLess = true
        container.backgroundColor = .clear
        container.layer?.masksToBounds = false
        view.addSubview(container, positioned: .above, relativeTo: view.inputView)

        let bubble = container.convert(bubbleRect, from: view)
        let field = container.convert(source.fieldRect, from: view)
        let offset = NSMakePoint(field.minX - bubble.minX, field.maxY - bubble.maxY)
        let startField = NSMakeRect(bubble.minX, bubble.maxY - field.height, field.width, field.height)
        let inputBaseline = container.convert(source.baseline, from: view)
        let bubbleBaseline = container.convert(textBaseline, from: view)
        let textOffset = NSMakePoint(inputBaseline.x - offset.x - bubbleBaseline.x, inputBaseline.y - offset.y - bubbleBaseline.y)

        let rowViewFrame = rowView.frame
        container.addSubview(rowView)
        rowView.frame = rowViewFrame
        rowView.layer?.removeAllAnimations()

        let flight = Flight(container: container, rowItemView: rowItemView)
        flight.rowViewClips = rowView.layer?.masksToBounds ?? true
        rowView.layer?.masksToBounds = false
        self.flights.append(flight)

        let fade = CAMediaTimingFunction(name: .easeInEaseOut)

        func addHorizontal(_ layer: CALayer, _ keyPath: String, from: Any, to: Any, additive: Bool, removeOnCompletion: Bool = true, key: String) {
            layer.add(flightAnimation(keyPath: keyPath, from: from, to: to, duration: ChatTextSendFlightMotion.horizontalDuration, timingFunction: fade, additive: additive, removeOnCompletion: removeOnCompletion), forKey: key)
        }

        func addVertical(_ layer: CALayer, _ keyPath: String, from: Any, to: Any, additive: Bool, removeOnCompletion: Bool = true, key: String, completion: (() -> Void)? = nil) {
            let animation = CASpringAnimation(keyPath: keyPath)
            animation.mass = 1.0
            animation.stiffness = ChatTextSendFlightMotion.verticalStiffness
            animation.damping = ChatTextSendFlightMotion.verticalDamping
            animation.fromValue = from
            animation.toValue = to
            animation.duration = animation.settlingDuration
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + ChatTextSendFlightMotion.verticalDelay
            animation.fillMode = .both
            animation.isAdditive = additive
            animation.isRemovedOnCompletion = removeOnCompletion
            if let completion {
                animation.delegate = CALayerAnimationDelegate(completion: { _ in
                    completion()
                })
            }
            layer.add(animation, forKey: key)
        }

        func animateFrame(_ layer: CALayer, from: NSRect, to: NSRect) {
            let anchor = layer.anchorPoint
            addHorizontal(layer, "position.x", from: NSNumber(value: Double(from.minX + anchor.x * from.width)), to: NSNumber(value: Double(to.minX + anchor.x * to.width)), additive: false, key: "textFlightPositionX")
            addVertical(layer, "position.y", from: NSNumber(value: Double(from.minY + anchor.y * from.height)), to: NSNumber(value: Double(to.minY + anchor.y * to.height)), additive: false, key: "textFlightPositionY")
            addHorizontal(layer, "bounds.size.width", from: NSNumber(value: Double(from.width)), to: NSNumber(value: Double(to.width)), additive: false, key: "textFlightWidth")
            addVertical(layer, "bounds.size.height", from: NSNumber(value: Double(from.height)), to: NSNumber(value: Double(to.height)), additive: false, key: "textFlightHeight")
        }

        if let layer = container.layer {
            let mask = CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            mask.anchorPoint = .zero
            mask.frame = bubble
            layer.mask = mask
            animateFrame(mask, from: startField, to: bubble)

            let snapshot = CALayer()
            snapshot.contents = source.snapshot
            snapshot.frame = container.convert(source.snapshotRect, from: view).offsetBy(dx: -offset.x, dy: -offset.y)
            layer.addSublayer(snapshot)
            addHorizontal(snapshot, "position", from: NSValue(point: .zero), to: NSValue(point: NSMakePoint(-textOffset.x, 0)), additive: true, removeOnCompletion: false, key: "textFlightPositionX")
            addVertical(snapshot, "position", from: NSValue(point: .zero), to: NSValue(point: NSMakePoint(0, -textOffset.y)), additive: true, removeOnCompletion: false, key: "textFlightPositionY")
            snapshot.add(flightAnimation(keyPath: "opacity", from: 1.0 as NSNumber, to: 0.0 as NSNumber, duration: 0.1, timingFunction: fade, additive: false, removeOnCompletion: false), forKey: "textFlightAlpha")

            addHorizontal(layer, "position", from: NSValue(point: NSMakePoint(offset.x, 0)), to: NSValue(point: .zero), additive: true, key: "textFlightX")
            addVertical(layer, "position", from: NSValue(point: NSMakePoint(0, offset.y)), to: NSValue(point: .zero), additive: true, key: "textFlightY", completion: { [weak self, weak flight] in
                if let flight {
                    self?.finish(flight)
                }
            })
        }

        if let layer = bubbleView.layer {
            let bubbleFrame = bubbleView.frame
            let startFrame = rowView.convert(startField, from: container)
            animateFrame(layer, from: startFrame, to: bubbleFrame)
            flight.layers.append(layer)
            for slice in ([layer.mask] + (layer.sublayers ?? [])).compactMap({ $0 as? ChatBubbleSliceLayer }) {
                animateFrame(slice, from: startFrame.size.bounds, to: bubbleFrame.size.bounds)
                flight.layers.append(slice)
            }
            if let gradient = bubbleView.gradientLayer {
                flight.layers.append(gradient)
                addHorizontal(gradient, "position", from: NSValue(point: NSMakePoint(-offset.x, 0)), to: NSValue(point: .zero), additive: true, key: "textFlightGradientX")
                addVertical(gradient, "position", from: NSValue(point: NSMakePoint(0, offset.y)), to: NSValue(point: .zero), additive: true, key: "textFlightGradientY")
            }
            if source.fadesInMessageBubble {
                layer.add(flightAnimation(keyPath: "opacity", from: 0.0 as NSNumber, to: 1.0 as NSNumber, duration: 0.1, timingFunction: fade, additive: false), forKey: "textFlightAlpha")
            }
        }

        if let layer = text.layer {
            flight.layers.append(layer)
            addHorizontal(layer, "position", from: NSValue(point: NSMakePoint(textOffset.x, 0)), to: NSValue(point: .zero), additive: true, key: "textFlightPositionX")
            addVertical(layer, "position", from: NSValue(point: NSMakePoint(0, textOffset.y)), to: NSValue(point: .zero), additive: true, key: "textFlightPositionY")
            layer.add(flightAnimation(keyPath: "opacity", from: 0.0 as NSNumber, to: 1.0 as NSNumber, duration: 0.08, timingFunction: fade, additive: false), forKey: "textFlightAlpha")
        }

        if let layer = rowItemView.rightView.flightLayer {
            flight.layers.append(layer)
            addHorizontal(layer, "position", from: NSValue(point: NSMakePoint(field.width - bubble.width, 0)), to: NSValue(point: .zero), additive: true, key: "textFlightPosition")
            layer.add(flightAnimation(keyPath: "opacity", from: 0.0 as NSNumber, to: 1.0 as NSNumber, duration: 0.25, timingFunction: fade, additive: false), forKey: "textFlightAlpha")
        }

        if let layer = rowItemView.webpageContent?.layer {
            flight.layers.append(layer)
            addVertical(layer, "position", from: NSValue(point: NSMakePoint(0, bubble.height - field.height)), to: NSValue(point: .zero), additive: true, key: "textFlightPosition")
        }

        CATransaction.commit()
        return true
    }
}
