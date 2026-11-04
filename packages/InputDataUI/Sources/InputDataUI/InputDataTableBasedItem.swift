import ColorPalette
import GeneralRows
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import Cocoa
import TGUIKit


public final class InputDataTableBasedItem : GeneralRowItem {
    
    public struct Row {
        public struct Right {
            public struct Badge {
                public var text: String
                public var tooltipText: String?
                public var color: NSColor?
                public var callback:()->Void
                public var destructive: Bool = false

                public init(text: String, tooltipText: String? = nil, color: NSColor? = nil, callback: @escaping () -> Void, destructive: Bool = false) {
                    self.text = text
                    self.tooltipText = tooltipText
                    self.color = color
                    self.callback = callback
                    self.destructive = destructive
                }
            }
            public var name: TextViewLayout
            public var leftView: ((NSView?)->NSView)?
            public var rightView: ((NSView?)->NSView?)?
            public var rightToCorner: Bool = false
            public var badge: Badge?

            public init(name: TextViewLayout, leftView: ((NSView?) -> NSView)? = nil, rightView: ((NSView?) -> NSView?)? = nil, rightToCorner: Bool = false, badge: Badge? = nil) {
                self.name = name
                self.leftView = leftView
                self.rightView = rightView
                self.rightToCorner = rightToCorner
                self.badge = badge
            }
        }
        public let left: TextViewLayout?
        public let right: Right
        fileprivate let badgeLayout: TextViewLayout?

        public init(left: TextViewLayout?, right: Right) {
            self.left = left
            self.right = right
            self.badgeLayout = right.badge.map { TextViewLayout(.initialize(string: $0.text, font: .normal(.small))) }
        }

        public var height: CGFloat {
            return (left?.layoutSize.height ?? 16) + 8 + right.name.layoutSize.height + additionalBadgeHeight
        }

        fileprivate var isBadgeOnNextLine: Bool {
            guard let badgeLayout else {
                return false
            }
            return badgeLayout.numberOfLines > 1 || right.name.layoutSize.width + badgeLayout.layoutSize.width + 16 > right.name.constrainedWidth
        }

        fileprivate var additionalBadgeHeight: CGFloat {
            if isBadgeOnNextLine, let badgeLayout {
                return badgeLayout.layoutSize.height + 10
            }
            return 0
        }

        public static let leftViewReserved: CGFloat = 25
        public static let rightViewReserved: CGFloat = 26

        public func measure(_ width: CGFloat, basic: CGFloat) {
            var additional: CGFloat = 0
            if right.leftView != nil {
                additional += Row.leftViewReserved
            }
            if right.rightView != nil {
                additional += Row.rightViewReserved
            }
            let contentWidth = (left == nil ? basic : width) - 20
            right.name.measure(width: max(1, contentWidth - additional))
            badgeLayout?.measure(width: max(1, contentWidth - 10))
        }
        public func prepare(width: CGFloat) {
            left?.measure(width: width / 1.5 - 40)
        }
        public var leftWidth: CGFloat {
            if let left {
                return 10 + left.layoutSize.width + 10
            } else {
                return 0
            }
        }
    }
    fileprivate let rows: [Row]
    fileprivate let context: any AccountContextProtocol
    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, rows: [Row], context: any AccountContextProtocol) {
        self.rows = rows
        self.context = context
        super.init(initialSize, stableId: stableId, viewType: viewType)
        for row in rows {
            row.prepare(width: initialSize.width)
        }
        assert(rows.count != 0)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        for row in rows {
            row.prepare(width: width)
        }
        
        let maxLeft = rows.map { $0.leftWidth }.max()!
        
        for row in rows {
            row.measure(width - inset.left * 2 - maxLeft, basic: width - inset.left * 2)
        }
        
        return true
    }
    
    public override var height: CGFloat {
        return rows.reduce(0, { $0 + $1.height })
    }
    
    public override func viewClass() -> AnyClass {
        return InputDataTableBasedItemView.self
    }

    public override var accessibilityLabel: String? {
        let lines: [String] = rows.compactMap { row in
            let right = row.right.name.attributedString.string
            if let left = row.left?.attributedString.string, !left.isEmpty {
                return right.isEmpty ? left : "\(left): \(right)"
            }
            return right.isEmpty ? nil : right
        }
        return lines.isEmpty ? nil : lines.joined(separator: ", ")
    }
}


final class InputDataTableBasedItemView: TableRowView {
    
    class RowView: View {
        
        private class BadgeView : Control {
            private let textView = TextView()
            required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(textView)
                textView.userInteractionEnabled = false
                textView.isSelectable = false
                textView.isEventLess = true
                self.scaleOnClick = true
            }
            
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            func set(badge: InputDataTableBasedItem.Row.Right.Badge, width: CGFloat) -> NSSize {
                let badgeColor: NSColor
                if let color = badge.color {
                    badgeColor = color
                } else if badge.destructive {
                    badgeColor = theme.colors.redUI
                } else {
                    badgeColor = theme.colors.accent
                }
                let layout = TextViewLayout(.initialize(string: badge.text, color: badgeColor, font: .normal(.small)))
                layout.measure(width: width)
                textView.update(layout)

                self.appTooltip = badge.tooltipText


                setSingle(handler: { _ in
                    badge.callback()
                }, for: .Click)

                self.backgroundColor = badgeColor.withAlphaComponent(0.2)
                self.layer?.cornerRadius = (layout.layoutSize.height + 4) / 2

                return textView.frame.insetBy(dx: -5, dy: -2).size
            }
            
            override func layout() {
                super.layout()
                textView.center()
            }
        }
        
        private let leftView = TextView()
        private let rightView = InteractiveTextView()
        private let left = View()
        
        private var rightLeft: NSView?
        private var rightRight: NSView?
        private var rightBadge: BadgeView?
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            
            addSubview(left)

            
            addSubview(leftView)
            addSubview(rightView)
            
            leftView.userInteractionEnabled = false
            leftView.isSelectable = false
            
            rightView.textView.userInteractionEnabled = true

        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private var row: InputDataTableBasedItem.Row?
        private var startRight: CGFloat = 0

        func update(_ row: InputDataTableBasedItem.Row, startRight: CGFloat, hasSeparator: Bool, context: (any AccountContextProtocol)?) {
            self.row = row
            self.startRight = row.left == nil ? 10 : startRight
            leftView.update(row.left)
            rightView.set(text: row.right.name, context: context)
            self.border = hasSeparator ? [.Bottom] : nil
            
            left.backgroundColor = theme.colors.border.withAlphaComponent(0.3)
            left.border = [.Right]
            left.borderColor = theme.colors.border
                        
            let rightLeft = row.right.leftView?(self.rightLeft)

            if rightLeft !== self.rightLeft {
                self.rightLeft?.removeFromSuperview()
                self.rightLeft = rightLeft
                if let rightLeft {
                    addSubview(rightLeft)
                }
            }

            let rightRight = row.right.rightView?(self.rightRight)

            if rightRight !== self.rightRight {
                self.rightRight?.removeFromSuperview()
                self.rightRight = rightRight
                if let rightRight {
                    addSubview(rightRight)
                }
            }
            
            if let badge = row.right.badge, let badgeLayout = row.badgeLayout {
                let current: BadgeView
                if let view = self.rightBadge {
                    current = view
                } else {
                    current = BadgeView(frame: .zero)
                    self.rightBadge = current
                    addSubview(current)
                }
                let size = current.set(badge: badge, width: badgeLayout.constrainedWidth)
                current.setFrameSize(size)
            } else if let rightBadge {
                performSubviewRemoval(rightBadge, animated: false)
                self.rightBadge = nil
            }
            
            updateLayout()

        }
        
        func updateLayout() {
            guard let row = self.row else {
                return
            }
            
            let addition = -row.additionalBadgeHeight / 2
            leftView.centerY(x: 10, addition: addition)
            if let rightLeft = rightLeft {
                rightLeft.centerY(x: startRight, addition: addition)
                rightView.centerY(x: rightLeft.frame.maxX + 5, addition: addition)
            } else {
                rightView.centerY(x: startRight, addition: addition)
            }

            var rightOffset = rightView.frame.maxX + 6
            if let rightRight = rightRight {
                if row.right.rightToCorner {
                    rightRight.centerY(x: frame.width - rightRight.frame.width - 8, addition: addition)
                } else {
                    rightOffset -= 2
                    rightRight.centerY(x: rightOffset, addition: addition)
                    rightOffset += rightRight.frame.width + 2
                }
            }

            if let rightBadge {
                if row.isBadgeOnNextLine {
                    let contentMaxY = max(rightView.frame.maxY, rightLeft?.frame.maxY ?? 0, rightRight?.frame.maxY ?? 0)
                    rightBadge.setFrameOrigin(NSMakePoint(startRight, contentMaxY + 6))
                } else {
                    rightBadge.centerY(x: rightOffset)
                }
            }
            
           
            left.frame = NSMakeRect(0, 0, startRight - 10, frame.height)
        }
        
        override func layout() {
            super.layout()
            updateLayout()
            
        }
    }
    private let container = View()
    
    private let left = View()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(container)
        container.layer?.cornerRadius = 20
        container.layer?.borderWidth = .borderSize
    }
    
    override func layout() {
        super.layout()
        guard let item = item as? InputDataTableBasedItem else {
            return
        }
        container.frame = bounds.insetBy(dx: item.inset.left, dy: 0)
        layoutRows(item.rows)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func updateColors() {
        container.backgroundColor = theme.colors.background
        container.layer?.borderColor = theme.colors.border.cgColor
        
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? InputDataTableBasedItem else {
            return
        }
        
        while self.container.subviews.count > item.rows.count {
            self.container.subviews.last?.removeFromSuperview()
        }
        while self.container.subviews.count < item.rows.count {
            self.container.addSubview(RowView(frame: NSMakeRect(0, 0, container.frame.width, 40)))
        }

        updateRows(item.rows, item: item)
        layoutRows(item.rows)
    }

    private func updateRows(_ rows: [InputDataTableBasedItem.Row], item: InputDataTableBasedItem) {
        let maxLeft = rows.map { $0.leftWidth }.max()!
        for (i, row) in rows.enumerated() {
            let view = container.subviews[i] as! RowView
            view.update(row, startRight: maxLeft + 10, hasSeparator: i < rows.count - 1, context: item.context)
        }
    }

    private func layoutRows(_ rows: [InputDataTableBasedItem.Row]) {
        var y: CGFloat = 0
        let maxLeft = rows.map { $0.leftWidth }.max()!
        for (i, row) in rows.enumerated() {
            let view = container.subviews[i] as! RowView
            view.frame = NSMakeRect(0, y, container.frame.width, row.height)
            y += row.height
            view.updateLayout()
        }
        left.frame = NSMakeRect(container.frame.minX, 0, maxLeft, container.frame.height)
    }
}
