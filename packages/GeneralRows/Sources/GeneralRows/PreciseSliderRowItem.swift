import Cocoa
import TGUIKit
import TelegramTheme
import ColorPalette
import Localization



public final class PrecieSliderRowItem : GeneralRowItem {
    fileprivate let update:(CGFloat)->Void
    fileprivate let current: CGFloat
    fileprivate let magnit: [CGFloat]
    fileprivate let markers: [String]
    fileprivate let showValue: String?
    fileprivate let valueDetail: String?
    fileprivate let editValue: (() -> Void)?
    fileprivate let minValue: CGFloat
    public init(_ initialSize: NSSize, stableId: AnyHashable, current: CGFloat, minValue: CGFloat = 0, magnit: [CGFloat] = [], markers: [String] = [], showValue: String? = nil, valueDetail: String? = nil, editValue: (() -> Void)? = nil, update: @escaping(CGFloat)->Void, viewType: GeneralViewType, customTheme: GeneralRowItem.Theme? = nil) {
        self.markers = markers
        self.current = current
        self.magnit = magnit
        self.update = update
        self.showValue = showValue
        self.valueDetail = valueDetail
        self.editValue = editValue
        self.minValue = minValue
        super.init(initialSize, stableId: stableId, viewType: viewType, customTheme: customTheme)
    }
    
    
    public override var height: CGFloat {
        if editValue != nil {
            return 68
        }
        return markers.isEmpty && showValue == nil ? 40 : 40 + 20
    }
    
    public override func viewClass() -> AnyClass {
        return PrecieSliderRowView.self
    }

    private var accessibilityCurrentValue: String {
        return showValue ?? "\(Int((current * 100).rounded()))%"
    }

    public override var accessibilityLabel: String? {
        if markers.count >= 2, let first = markers.first, let last = markers.last {
            return "\(first) – \(last)"
        }
        return accessibilityCurrentValue
    }

    public override var accessibilityValue: String? {
        return markers.count >= 2 ? accessibilityCurrentValue : nil
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .slider
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    private var accessibilityLiveValue: CGFloat?

    private func accessibilityStep(_ delta: CGFloat) -> Bool {
        let value = min(1, max(minValue, (accessibilityLiveValue ?? current) + delta))
        accessibilityLiveValue = value
        update(value)
        return true
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        var actions = [
            NSAccessibilityCustomAction(name: strings().voiceOverCommonUp, handler: { [weak self] in
                return self?.accessibilityStep(0.1) ?? false
            }),
            NSAccessibilityCustomAction(name: strings().voiceOverCommonDown, handler: { [weak self] in
                return self?.accessibilityStep(-0.1) ?? false
            })
        ]
        if editValue != nil {
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonSetPrice, handler: { [weak self] in
                return self?.accessibilityPerformPress() ?? false
            }))
        }
        return actions
    }

    public override func accessibilityPerformPress() -> Bool {
        guard let editValue else {
            return false
        }
        editValue()
        return true
    }
}

private final class PrecieSliderRowView : GeneralContainableRowView {
    private let slider = LinearProgressControl(progressHeight: 3)
    private let valueButton = Control(frame: .zero)
    private var leftMarker: TextView?
    private var rightMarker: TextView?
    private var currentValue: TextView?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(slider)
        valueButton.isHidden = true
        valueButton.scaleOnClick = true
        valueButton.layer?.cornerRadius = 8
        addSubview(valueButton)
        
        
    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? PrecieSliderRowItem else {
            return super.backdorColor
        }
        return item.customTheme?.backgroundColor ?? super.backdorColor
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PrecieSliderRowItem else {
            return
        }
        
        let theme = item.customTheme ?? .initialize(theme)
        
        slider.scrubberImage = generateImage(NSMakeSize(20, 20), contextGenerator: { size, ctx in
            let rect = CGRect(origin: .zero, size: size)
            
 
            ctx.clear(rect)
            
            ctx.setFillColor(theme.borderColor.cgColor)
            ctx.fillEllipse(in: size.bounds)

            ctx.setFillColor((item.editValue == nil ? theme.backgroundColor : NSColor.white).cgColor)
            ctx.fillEllipse(in: size.bounds.insetBy(dx: 1, dy: 1))

            
            // Restore graphics state
            ctx.restoreGState()
        })
        
        slider.roundCorners = true
        slider.alignment = .center
        slider.containerBackground = theme.grayTextColor
        slider.style = ControlStyle(foregroundColor: theme.accentColor, backgroundColor: .clear, highlightColor: .clear)
        slider.fetchingColor = theme.grayTextColor
        slider.set(progress: item.current)
        slider.set(fetchingProgress: item.current)
        
        slider.onUserChanged = { [weak item] value in
            item?.update(CGFloat(value))
        }
        slider.onLiveScrobbling = { [weak item] value in
            if let value {
                item?.update(CGFloat(value))
            }
        }
        
        if !item.markers.isEmpty {
            do {
                let current: TextView
                if let view = self.leftMarker {
                    current = view
                } else {
                    current = TextView()
                    current.isSelectable = false
                    current.userInteractionEnabled = false
                    self.addSubview(current)
                    self.leftMarker = current
                    
                }
                let leftLayout = TextViewLayout(.initialize(string: item.markers[0], color: theme.grayTextColor, font: .normal(.text)))
                leftLayout.measure(width: .greatestFiniteMagnitude)
                current.update(leftLayout)
            }
            
            do {
                let current: TextView
                if let view = self.rightMarker {
                    current = view
                } else {
                    current = TextView()
                    current.isSelectable = false
                    current.userInteractionEnabled = false
                    self.addSubview(current)
                    self.rightMarker = current
                    
                }
                let rightLayout = TextViewLayout(.initialize(string: item.markers[1], color: theme.grayTextColor, font: .normal(.text)))
                rightLayout.measure(width: .greatestFiniteMagnitude)
                current.update(rightLayout)
            }
        } else {
            if let view = self.leftMarker {
                performSubviewRemoval(view, animated: animated)
                self.leftMarker = nil
            }
            if let view = self.rightMarker {
                performSubviewRemoval(view, animated: animated)
                self.rightMarker = nil
            }
        }
        
        valueButton.isHidden = item.editValue == nil || item.showValue == nil
        valueButton.removeAllHandlers()
        if let editValue = item.editValue {
            valueButton.set(background: theme.accentColor.withAlphaComponent(0.12), for: .Normal)
            valueButton.set(background: theme.accentColor.withAlphaComponent(0.20), for: .Hover)
            valueButton.set(handler: { _ in editValue() }, for: .Click)
        }

        if let showValue = item.showValue {
            do {
                let current: TextView
                if let view = self.currentValue {
                    current = view
                } else {
                    current = TextView()
                    current.isSelectable = false
                    current.userInteractionEnabled = false
                    current.isEventLess = true
                    self.currentValue = current
                }
                let parent = valueButton.isHidden ? containerView as NSView : valueButton
                if current.superview !== parent {
                    current.removeFromSuperview()
                    parent.addSubview(current)
                }
                let title = NSMutableAttributedString()
                title.append(string: showValue, color: valueButton.isHidden ? theme.textColor : theme.accentColor, font: .normal(.title))
                if let valueDetail = item.valueDetail {
                    title.append(string: "  " + valueDetail, color: theme.accentColor.withAlphaComponent(0.72), font: .normal(.text))
                }
                let layout = TextViewLayout(title, maximumNumberOfLines: 1, truncationType: .end)
                layout.measure(width: .greatestFiniteMagnitude)
                current.update(layout)
            }
        } else {
            if let view = self.currentValue {
                performSubviewRemoval(view, animated: animated)
                self.currentValue = nil
            }
        }

        needsLayout = true

    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? PrecieSliderRowItem else {
            return
        }
        
        var rect = containerView.focus(NSMakeSize(containerView.frame.width - 40, 20))

        if item.showValue != nil || !item.markers.isEmpty {
            rect.origin.y = containerView.frame.height - rect.height - 10
        }
        
        let headerCenterY = (containerView.bounds.minY + rect.minY) / 2
        if !valueButton.isHidden {
            if let leftMarker {
                leftMarker.setFrameOrigin(rect.minX, headerCenterY - leftMarker.frame.height / 2)
            }
            if let rightMarker {
                rightMarker.setFrameOrigin(rect.maxX - rightMarker.frame.width, headerCenterY - rightMarker.frame.height / 2)
            }
        } else if let leftMarker, let rightMarker {
            leftMarker.setFrameOrigin(NSMakePoint(rect.minX, rect.minY - leftMarker.frame.height - 5))
            rightMarker.setFrameOrigin(NSMakePoint(rect.maxX - rightMarker.frame.width, rect.minY - rightMarker.frame.height - 5))
        }
        
        
        if let currentValue {
            if valueButton.isHidden {
                currentValue.centerX(y: rect.minY - currentValue.frame.height - 5)
            } else if let layout = currentValue.textLayout {
                let markerWidth = max(leftMarker?.frame.width ?? 0, rightMarker?.frame.width ?? 0)
                let horizontalPadding: CGFloat = 8
                layout.measure(width: max(1, rect.width - 2 * (markerWidth + 8 + horizontalPadding)))
                currentValue.update(layout)
                let size = NSSize(width: layout.layoutSize.width + 2 * horizontalPadding, height: 24)
                valueButton.frame = NSRect(x: (containerView.bounds.width - size.width) / 2, y: headerCenterY - size.height / 2, width: size.width, height: size.height)
                currentValue.center()
            }
        }
        
        slider.frame = rect
    }
}
