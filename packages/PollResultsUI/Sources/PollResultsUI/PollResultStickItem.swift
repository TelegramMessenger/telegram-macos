import Cocoa
import TGUIKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import ShortPeerRow
import StatisticsUI
import SwiftSignalKit
import TelegramCore
import Postbox
import LocalAnimations

public class PollResultStickItem: TableStickItem {
    
    public let leftLayout:TextViewLayout
    public let leftAdditionLayout: TextViewLayout
    public let rightLayout: TextViewLayout
    public let viewType: GeneralViewType
    public let inset: NSEdgeInsets
    public let collapse: (()->Void)?
    public let _stableId: AnyHashable
    public let context: (any AccountContextProtocol)?
    public init(_ initialSize:NSSize, stableId: AnyHashable, left: NSAttributedString, context: any AccountContextProtocol, additionText: String, right: String, collapse: (()->Void)?, viewType: GeneralViewType) {
        self.viewType = viewType
        self._stableId = stableId
        self.context = context
        self.inset = NSEdgeInsets(left: 20, right: 20)
        self.collapse = collapse
        self.leftLayout = TextViewLayout(left, maximumNumberOfLines: 1, truncationType: .end)
        self.leftAdditionLayout = TextViewLayout(.initialize(string: additionText, color: theme.colors.listGrayText, font: .normal(11.5)), maximumNumberOfLines: 1, truncationType: .end)

        if let collapse = collapse {
            let attrs = parseMarkdownIntoAttributedString(strings().pollResultsCollapse, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(11.5), textColor: theme.colors.listGrayText), bold: MarkdownAttributeSet(font: .bold(11.5), textColor: theme.colors.listGrayText), link: MarkdownAttributeSet(font: .normal(11.5), textColor: theme.colors.link), linkAttribute: { contents in
                return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents, { _ in }))
            }))
            
            self.rightLayout = TextViewLayout(attrs, maximumNumberOfLines: 1, truncationType: .end, alignment: .center)
            self.rightLayout.interactions = TextViewInteractions(processURL: { _ in
                collapse()
            })
        } else {
            self.rightLayout = TextViewLayout(.initialize(string: right, color: theme.colors.listGrayText, font: .normal(11.5)), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)
        }
        

        
        super.init(initialSize)
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    

    
    public override var canBeAnchor: Bool {
        return false
    }

    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        let text = self.leftLayout.attributedString.string
        return .single([
            ContextMenuItem(strings().textCopy, handler: {
                copyToClipboard(text)
            }, itemImage: MenuAnimation.menu_copy.value)
        ])
    }
    
    public required init(_ initialSize: NSSize) {
        self.viewType = .legacy
        self.leftLayout = TextViewLayout(NSAttributedString())
        self.rightLayout = TextViewLayout(NSAttributedString())
        self.leftAdditionLayout = TextViewLayout(NSAttributedString())
        self.inset = NSEdgeInsets(left: 20, right: 20)
        self.collapse = nil
        self.context = nil
        self._stableId = arc4random()
        super.init(initialSize)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        rightLayout.measure(width: .greatestFiniteMagnitude)
        leftAdditionLayout.measure(width: .greatestFiniteMagnitude)
        
        let blockWidth = min(600, width - inset.left - inset.right)
        leftLayout.measure(width: blockWidth - rightLayout.layoutSize.width - viewType.innerInset.left * 3 - leftAdditionLayout.layoutSize.width)
        
        return success
    }
    
    public override var stableId: AnyHashable {
        return self._stableId
    }
    
    public override var height: CGFloat {
        return 30
    }
    
    public override func viewClass() -> AnyClass {
        return PollResultStickView.self
    }
    
}


private final class PollResultStickView : TableStickView {
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private let textView = InteractiveTextView(frame: .zero)
    private let textAdditionView = TextView()

    private let rightView = TextView()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(self.containerView)
        containerView.addSubview(self.textView)
        containerView.addSubview(self.rightView)
        containerView.addSubview(self.textAdditionView)
        self.textView.textView.isSelectable = true
        self.textView.userInteractionEnabled = true
        
        self.textAdditionView.disableBackgroundDrawing = true
        self.textAdditionView.isSelectable = false
        self.textAdditionView.userInteractionEnabled = false
        
        self.rightView.disableBackgroundDrawing = true
        self.rightView.isSelectable = false
        
    }
    
    public override var header: Bool {
        didSet {
            updateColors()
        }
    }
    
    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    public override func updateColors() {
        guard let item = item as? PollResultStickItem else {
            return
        }
        self.backgroundColor = item.viewType.rowBackground
        self.containerView.backgroundColor = backdorColor
    }
    
    public override func layout() {
        super.layout()
        guard let item = item as? PollResultStickItem else {
            return
        }
        
        let blockWidth = min(600, frame.width - item.inset.left - item.inset.right)
        
        self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - blockWidth) / 2), item.inset.top, blockWidth, frame.height - item.inset.bottom - item.inset.top)
        self.containerView.setCorners([])
        
        textView.centerY(x: item.viewType.innerInset.left)
        textAdditionView.centerY(x: textView.frame.maxX)
        rightView.centerY(x: self.containerView.frame.width - item.viewType.innerInset.left - rightView.frame.width)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PollResultStickItem else {
            return
        }
        self.textView.set(text: item.leftLayout, context: item.context)
        self.textAdditionView.update(item.leftAdditionLayout)
        self.rightView.update(item.rightLayout)

        needsLayout = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
