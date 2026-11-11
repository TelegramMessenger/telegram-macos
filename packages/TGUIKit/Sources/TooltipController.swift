import Cocoa
import SwiftSignalKit
import AppKit

private func tooltipCornerRadius(for size: NSSize, arrowWidth: CGFloat) -> CGFloat {
    return max(0, min(14, floor(size.height * 0.4), floor((size.width - arrowWidth) / 2)))
}

private final class TooltipView: View {
    let textView = TextView()
    private let textContainer = View()
    let cornerView = ImageView()

    var button: TextButton?
    var buttonSpacing: CGFloat = 5

    var didRemoveFromWindow:(()->Void)?
    fileprivate var scrollListenerRemovals: [()->Void] = []

    fileprivate func removeScrollListeners() {
        let removals = scrollListenerRemovals
        scrollListenerRemovals.removeAll()
        for removal in removals {
            removal()
        }
    }

    weak var view: NSView? {
        didSet {
            oldValue?.removeObserver(self, forKeyPath: "window")
            if let view = view {
                view.addObserver(self, forKeyPath: "window", options: .new, context: nil)
            }
        }
    }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if self.view?.window == nil {
            self.didRemoveFromWindow?()
        }
    }
    
    var cornerX: CGFloat? = nil {
        didSet {
            needsLayout = true
        }
    }
    
    
    func move(corner cornerX: CGFloat, animated: Bool) {
        self.cornerX = cornerX
        
        let point: NSPoint
        let radius = tooltipCornerRadius(for: textContainer.frame.size, arrowWidth: cornerView.frame.width)
        if frame.width >= cornerView.frame.width + radius * 2 {
            point = NSMakePoint(max(min(cornerX - cornerView.frame.width / 2, frame.width - cornerView.frame.width - radius), radius), textContainer.frame.maxY)
        } else {
            let center = self.focus(cornerView.frame.size)
            point = NSMakePoint(center.minX, textContainer.frame.maxY)
        }
        cornerView.change(pos: point, animated: animated)
    }
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textContainer.backgroundColor = .black
        textContainer.addSubview(textView)
        addSubview(textContainer)
        addSubview(cornerView)
        cornerView.animates = false
        cornerView.image = generateImage(NSMakeSize(30, 10), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(NSColor.black.cgColor)
            context.scaleBy(x: 0.333, y: 0.333)
            let _ = try? drawSvgPath(context, path: "M85.882251,0 C79.5170552,0 73.4125613,2.52817247 68.9116882,7.02834833 L51.4264069,24.5109211 C46.7401154,29.1964866 39.1421356,29.1964866 34.4558441,24.5109211 L16.9705627,7.02834833 C12.4696897,2.52817247 6.36519576,0 0,0 L85.882251,0 ")
            context.fillPath()
        })!
        
        cornerView.sizeToFit()
        textView.disableBackgroundDrawing = true
        textView.isSelectable = false
    }
    
    func update(text: NSAttributedString, button: (String, ()->Void)?, maxWidth: CGFloat, interactions: TextViewInteractions, animated: Bool, alignment: NSTextAlignment, buttonSpacing: CGFloat = 5) {

        self.buttonSpacing = buttonSpacing

        if let buttonData = button {
            let button: TextButton
            if self.button == nil {
                button = TextButton()
                self.button = button
                textContainer.addSubview(button)
            } else {
                button = self.button!
            }
            button.removeAllHandlers()
            button.set(text: buttonData.0, for: .Normal)
            button.set(font: .medium(.title), for: .Normal)
            button.set(color: .accent, for: .Normal)
            _ = button.sizeToFit()
            button.set(handler: { _ in
                buttonData.1()
            }, for: .Click)
        } else {
            self.button?.removeFromSuperview()
            self.button = nil
        }

        let layout = TextViewLayout(text, alignment: alignment, alwaysStaticItems: true)
        layout.measure(width: maxWidth - (self.button != nil ? self.button!.frame.width + buttonSpacing : 0))
        textView.update(layout)
        let containerSize = NSMakeSize(max(40, layout.layoutSize.width + 18 + (self.button != nil ? self.button!.frame.width + buttonSpacing : 0)), max(layout.layoutSize.height + 8, button != nil ? 40 : 0))
        let radius = tooltipCornerRadius(for: containerSize, arrowWidth: cornerView.frame.width)
        if animated, let layer = textContainer.layer, layer.cornerRadius != radius {
            layer.animate(from: NSNumber(value: Float(layer.cornerRadius)), to: NSNumber(value: Float(radius)), keyPath: "cornerRadius", timingFunction: .easeOut, duration: 0.2)
        }
        textContainer.layer?.cornerRadius = radius
        textContainer.change(size: containerSize, animated: animated)
        change(size: NSMakeSize(textContainer.frame.width, textContainer.frame.height + 14), animated: animated)
        needsLayout = true

        layout.interactions = interactions


    }
    
    override func layout() {
        super.layout()
        textContainer.centerX(y: 0)
        if let button = button {
            textView.centerY(x: 7)
            button.centerY(x: textView.frame.maxX + buttonSpacing)
        } else {
            textView.center()
        }
        let radius = tooltipCornerRadius(for: textContainer.frame.size, arrowWidth: cornerView.frame.width)
        if let cornerX = cornerX, frame.width >= cornerView.frame.width + radius * 2 {
            cornerView.setFrameOrigin(max(min(cornerX - cornerView.frame.width / 2, frame.width - cornerView.frame.width - radius), radius), textContainer.frame.maxY)
        } else {
            cornerView.centerX(y: textContainer.frame.maxY)
        }
    }
    
    deinit {
        DispatchQueue.main.async {
            removeShownAnimation = false
        }
        view?.removeObserver(self, forKeyPath: "window")
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TooltipController: ViewController {
    
    
    
}

private var removeShownAnimation:Bool = false


private let delayDisposable = MetaDisposable()
private var shouldRemoveTooltip: Bool = true
public func dismissTooltip(for view: NSView) {
    guard let tooltip = view.window?.contentView?.subviews.first(where: { $0 is TooltipView }) as? TooltipView,
          tooltip.view === view else { return }
    tooltip.didRemoveFromWindow?()
}

public func tooltip(for view: NSView, text: String, attributedText: NSAttributedString? = nil, interactions: TextViewInteractions = TextViewInteractions(), button: (String, ()->Void)? = nil, maxWidth: CGFloat = 350, autoCorner: Bool = true, offset: NSPoint = .zero, timeout: Double = 3.0, updateText: @escaping(@escaping(String)->Bool)->Void = { _ in }, alignment: NSTextAlignment = .center, buttonSpacing: CGFloat = 5, rect: NSRect? = nil) -> Void {
    guard let window = view.window as? Window else { return }

    if view.visibleRect.height != view.frame.height {
      //  return
    }

    let tooltip: TooltipView
    let isExists: Bool
    if let exists = window.contentView?.subviews.first(where: { $0 is TooltipView }) as? TooltipView {
        tooltip = exists
        isExists = true
        shouldRemoveTooltip = false
    } else {
        tooltip = TooltipView(frame: NSZeroRect)
        isExists = false
        shouldRemoveTooltip = (NSEvent.pressedMouseButtons & (1 << 0)) == 0
    }

    tooltip.view = view


    window.contentView?.addSubview(tooltip)

    let location = window.mouseLocationOutsideOfEventStream

    let text = attributedText ?? NSAttributedString.initialize(string: text, color: .white, font: .medium(.text))

    updateText() { [weak tooltip] text in
        tooltip?.update(text: .initialize(string: text, color: .white, font: .medium(.text)), button: button, maxWidth: maxWidth, interactions: interactions, animated: false, alignment: alignment, buttonSpacing: buttonSpacing)
        return tooltip != nil
    }

    tooltip.update(text: text, button: button, maxWidth: maxWidth, interactions: interactions, animated: isExists, alignment: alignment, buttonSpacing: buttonSpacing)



    var removeTooltip:(Bool) -> Void = { _ in

    }

    let positioningRect = rect ?? view.bounds
    let positioningWidth = positioningRect.width

    let updatePosition:(Bool)->Void = { [weak tooltip, weak view, weak window] animated in
        if let tooltip = tooltip, let view = view, let window = window {
            var point = view.convert(rect?.origin ?? NSZeroPoint, to: nil)
            if window.contentView!.isFlipped {
                point.y = window.contentView!.frame.height - point.y - positioningRect.height / 2 - 10
            }
            point.y += offset.y
            let pos = NSMakePoint(min(max(floorToScreenPixels(System.backingScale, point.x - (tooltip.frame.width - positioningWidth) / 2), 10), window.frame.width - tooltip.frame.width - 10), point.y)
//            if view.visibleRect.height != view.frame.height {
//                removeTooltip(true)
//            } else {
                tooltip.change(pos: pos, animated: isExists || animated)
//            }
        }

    }

    updatePosition(isExists)


    if autoCorner {
        let point = tooltip.convert(NSMakePoint(positioningRect.minX + floorToScreenPixels(System.backingScale, positioningWidth / 2), 0), from: view)
        tooltip.move(corner: point.x, animated: isExists)
    } else {
        let mousePoint = tooltip.convert(location, from: nil)
        tooltip.move(corner: mousePoint.x, animated: isExists)
    }
    
    
    if let scroll = view.enclosingScrollView as? TableView {
        let listener = TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { _ in
            updatePosition(true)
        })
        scroll.addScroll(listener: listener)
        tooltip.scrollListenerRemovals.append({ [weak scroll] in
            scroll?.removeScroll(listener: listener)
        })
    }
    
    if !isExists && !removeShownAnimation {
        CATransaction.begin()
        tooltip.layer?.animateAlpha(from: 0.3, to: 1, duration: 0.2)
        tooltip.layer?.animatePosition(from: NSMakePoint(tooltip.frame.minX, tooltip.frame.minY - 5), to: tooltip.frame.origin)
        CATransaction.commit()
    }
    removeTooltip = { [weak tooltip, weak window] animated in
        guard let tooltip = tooltip else { return }
        tooltip.removeScrollListeners()
        if animated {
            CATransaction.begin()
            tooltip.layer?.animatePosition(from: tooltip.frame.origin, to: NSMakePoint(tooltip.frame.minX, tooltip.frame.minY - 5), removeOnCompletion: false)
            //tooltip.change(pos: NSMakePoint(tooltip.frame.minX, tooltip.frame.minY - 5), animated: true)
            tooltip.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak tooltip, weak window] _ in
                if let tooltip = tooltip {
                    tooltip.removeFromSuperview()
                    window?.removeAllHandlers(for: tooltip)
                }
            })
            //            tooltip.change(opacity: 0, true, removeOnCompletion: false, duration: 0.2, completion: { [weak tooltip] _ in
            //                if let tooltip = tooltip {
            //                    tooltip.removeFromSuperview()
            //                    window.removeAllHandlers(for: tooltip)
            //                }
            //            })
            CATransaction.commit()
        } else {
            removeShownAnimation = true
            tooltip.removeFromSuperview()
            window?.removeAllHandlers(for: tooltip)
        }
    }
    
    
    
    tooltip.didRemoveFromWindow = {
        removeTooltip(true)
    }
    
    delayDisposable.set((Signal<Never, NoError>.complete() |> delay(timeout, queue: .mainQueue())).start(completed: {
        removeTooltip(true)
    }))
    
    
    window.set(mouseHandler: { _ -> KeyHandlerResult in
        DispatchQueue.main.async {
            if shouldRemoveTooltip {
                removeTooltip(true)
            }
            shouldRemoveTooltip = !isExists
        }
        return .rejected
    }, with: tooltip, for: .leftMouseUp, priority: .supreme)
    
    
    
    window.set(mouseHandler: { _ -> KeyHandlerResult in
        removeTooltip(false)
        return .rejected
    }, with: tooltip, for: .scrollWheel, priority: .supreme)
    
    
    window.set(handler: { _ -> KeyHandlerResult in
        removeTooltip(false)
        return .rejected
    }, with: tooltip, for: .All, priority: .supreme)
    
    
    
}
