import Cocoa
import TGUIKit
import SwiftSignalKit
import InAppSettings
import TelegramMediaUtils
import TelegramTheme

private let xAdd:CGFloat = 41
private let yAdd:CGFloat = 34


private final class LineLayer : SimpleLayer {
    
    struct Key: Hashable {
        let value: Int
        let index: Int
    }
    
    private let content = SimpleLayer()
    private var selectionLayer: SimpleLayer?
    private var badgeLayer: SimpleLayer?
    private var order: Int?

    func setSelection(order: Int?, color: NSColor, accent: NSColor, animated: Bool) {
        guard self.order != order || (order != nil && self.selectionLayer?.backgroundColor != color.withAlphaComponent(0.2).cgColor) else {
            return
        }
        let previousScale = self.content.presentation()?.transform.m11 ?? self.content.transform.m11
        let scale: CGFloat = order == nil ? 1.0 : 0.8
        self.order = order
        if let order {
            let side = emojiSelectionOrderCircleSide
            let selection: SimpleLayer
            if let current = self.selectionLayer {
                selection = current
            } else {
                selection = SimpleLayer()
                self.insertSublayer(selection, below: self.content)
                self.selectionLayer = selection
            }
            selection.frame = NSMakeRect(floorToScreenPixels((xAdd - side) / 2 + 0.5), floorToScreenPixels((yAdd - side) / 2 - 1.5), side, side)
            selection.cornerRadius = side / 2
            selection.backgroundColor = color.withAlphaComponent(0.2).cgColor
            let badge: SimpleLayer
            if let current = self.badgeLayer {
                badge = current
            } else {
                badge = SimpleLayer()
                badge.zPosition = 10
                self.addSublayer(badge)
                self.badgeLayer = badge
            }
            badge.contents = emojiSelectionOrderBadge(order, color: accent)
            badge.frame = emojiSelectionOrderBadgeFrame(selection: selection.frame)
        } else {
            self.selectionLayer?.removeFromSuperlayer()
            self.selectionLayer = nil
            self.badgeLayer?.removeFromSuperlayer()
            self.badgeLayer = nil
        }
        self.content.transform = CATransform3DMakeScale(scale, scale, 1)
        if animated, previousScale != scale {
            self.content.animateScale(from: previousScale, to: scale, duration: 0.18, timingFunction: .easeOut)
        }
    }

    init(emoji: NSAttributedString) {
        self.emoji = emoji
        super.init()
        addSublayer(content)
        let signal = generateEmoji(emoji) |> deliverOnMainQueue
        
        let value = cachedEmoji(emoji: emoji.string, scale: System.backingScale)
        
        content.frame = NSMakeSize(xAdd, yAdd).bounds.focus(NSMakeSize(30, 33))
        content.contents = value
        if value == nil {
            self.disposable = signal.start(next: { [weak self] image in
                self?.content.contents = image
                if let image = image {
                    cacheEmoji(image, emoji: emoji.string, scale: System.backingScale)
                }
            })
        }
    }
    
    deinit {
        disposable?.dispose()
    }
    
    private var disposable: Disposable?
    
    let emoji: NSAttributedString
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class EBlockRowView: TableRowView {
    
    public var selectedEmoji:String = ""
    
    private let content = EntertainmentGridControl()
    
    
    private var lines:[LineLayer.Key : LineLayer] = [:]
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(content)

        content.accessibilityCells = { [weak self] in
            return self?.accessibilityCells() ?? []
        }
        
        content.set(handler: { [weak self] _ in
            self?.updateDown()
        }, for: .Down)
        
        content.set(handler: { [weak self] _ in
            self?.updateDragging()
        }, for: .MouseDragging)
        
        content.set(handler: { [weak self] _ in
            self?.updateUp()
        }, for: .Up)
    }
    
    private var currentDownItem: (LineLayer, NSAttributedString, Bool)?
    private let dragTracker = EntertainmentDragTracker()
    private func updateDown() {
        if let item = itemUnderMouse {
            self.currentDownItem = (item.0, item.1, true)
            self.dragTracker.down(in: window)
        }
        if let itemUnderMouse = self.currentDownItem {
            itemUnderMouse.0.animateScale(from: 1, to: 0.85, duration: 0.2, removeOnCompletion: false)
        }
    }
    private func updateDragging() {
        if let current = self.currentDownItem, let item = item as? EBlockItem, let drag = item.dragHandler, dragTracker.dragged(in: window, begin: { point in
            guard drag(current.1.string, .moved(point)) else {
                return false
            }
            if current.2 {
                current.0.animateScale(from: 0.85, to: 1, duration: 0.2, removeOnCompletion: true)
                self.currentDownItem?.2 = false
            }
            return true
        }, move: { point in
            _ = drag(current.1.string, .moved(point))
        }) {
            return
        }
        if let current = self.currentDownItem {
            if self.itemUnderMouse?.1 != current.1, current.2  {
                current.0.animateScale(from: 0.85, to: 1, duration: 0.2, removeOnCompletion: true)
                self.currentDownItem?.2 = false
            } else if !current.2, self.itemUnderMouse?.1 == current.1 {
                current.0.animateScale(from: 1, to: 0.85, duration: 0.2, removeOnCompletion: false)
                self.currentDownItem?.2 = true
            }
        }
    }
    private func updateUp() {
        if let current = self.currentDownItem, let item = item as? EBlockItem, dragTracker.up(in: window, end: { point in
            _ = item.dragHandler?(current.1.string, .ended(point))
        }) {
            self.currentDownItem = nil
            return
        }
        if let itemUnderMouse = self.currentDownItem {
            itemUnderMouse.0.animateScale(from: 0.85, to: 1, duration: 0.2, removeOnCompletion: true)
            if itemUnderMouse.1 == self.itemUnderMouse?.1 {
                self.click()
            }
        }
        self.currentDownItem = nil
    }
    
    public var emojiUnderMouse: String? {
        return itemUnderMouse?.1.string
    }
    
    private var itemUnderMouse: (LineLayer, NSAttributedString)? {
        guard let window = self.window else {
            return nil
        }
        let point = self.content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        

        let firstLayer = self.lines.first(where: { layer in
            return NSPointInRect(point, layer.1.frame)
        })?.value
        
        if let firstLayer = firstLayer {
            return (firstLayer, firstLayer.emoji)
        }
        
        return nil
    }
    
    private func accessibilityCells() -> [EntertainmentAccessibilityCell] {
        guard let item = item as? EBlockItem else {
            return []
        }
        var cells: [EntertainmentAccessibilityCell] = []
        var point: NSPoint = NSMakePoint(10, 0)
        var index: Int = 0
        for line in item.lineAttr {
            for symbol in line {
                let emoji = symbol.string
                let rect = CGRect(origin: point, size: NSMakeSize(xAdd, yAdd))
                cells.append(EntertainmentAccessibilityCell(id: AnyHashable(index), label: emoji, frame: rect, press: { [weak self, weak item] in
                    guard let self = self, let item = item else {
                        return
                    }
                    item.selectHandler(emoji, self.content.convert(rect, to: nil))
                }))
                point.x += xAdd
                index += 1
            }
            point.y += yAdd
            point.x = 10
        }
        return cells
    }
    
    private func click() {
        if let currentDownItem = currentDownItem, let item = item as? EBlockItem {
            let wrect = self.content.convert(currentDownItem.0.frame, to: nil)
            item.selectHandler(currentDownItem.1.string, wrect)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        content.frame = bounds
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item:TableRowItem, animated:Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? EBlockItem else {
            return
        }
        
        updateLines(item: item, animated: animated)
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for (_, line) in lines {
            line.contentsScale = backingScaleFactor
        }
    }
    
    public func updateLines(item: EBlockItem, animated: Bool) {
        
        var validIds: [LineLayer.Key] = []
        var point: NSPoint = NSMakePoint(10, 0)
        var index: Int = 0
        for line in item.lineAttr {
            for symbol in line {
                let id = LineLayer.Key(value: symbol.string.hashValue, index: index)
                let view: LineLayer
                if let current = self.lines[id] {
                    view = current
                } else {
                    view = LineLayer(emoji: symbol)
                    self.lines[id] = view
                    self.content.layer?.addSublayer(view)
                    
                    if animated {
                       // view.animateScale(from: 0.1, to: 1, duration: 0.3, timingFunction: .spring)
                       // view.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                }
                let size = NSMakeSize(xAdd, yAdd)
                view.frame = CGRect(origin: point, size: size)
                view.setSelection(order: item.selectedOrders[emojiSelectionKey(symbol.string)], color: item.selectionColor ?? theme.colors.text, accent: theme.colors.accent, animated: animated)
                point.x += xAdd
                
                validIds.append(id)
                index += 1
            }
            point.y += yAdd
            point.x = 10
        }
        
        
        var removeKeys: [LineLayer.Key] = []
        for (key, itemLayer) in self.lines {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.lines.removeValue(forKey: key)
        }
    }
    
    
}
