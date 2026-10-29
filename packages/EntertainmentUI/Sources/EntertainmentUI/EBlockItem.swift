import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import InAppSettings
import Strings

public class EBlockItem: TableRowItem {

    private let _stableId:AnyHashable
    public override var stableId: AnyHashable {
        return _stableId
    }
    
    public override var height: CGFloat {
        return (CGFloat(lineAttr.count) * 34.0)
    }
    
    public private(set) var lineAttr:[[NSAttributedString]]
    private let symbols: [NSAttributedString]
    
    public let account: Account
    public var selectHandler:(String, NSRect)->Void = { _, _ in}
    public let segment: EmojiSegment
    public internal(set) var selectedOrders: [String: Int]
    public let selectionColor: NSColor?
    private let isRecentList: Bool
    
    public init(_ initialSize:NSSize, stableId: AnyHashable, attrLines:[[NSAttributedString]], segment: EmojiSegment, account: Account, selectHandler:@escaping(String, NSRect)->Void, selectedOrders: [String: Int] = [:], selectionColor: NSColor? = nil, isRecentList: Bool = false) {
        self.lineAttr = attrLines
        self.symbols = attrLines.flatMap { $0 }
        self.selectedOrders = selectedOrders
        self.selectionColor = selectionColor
        self.isRecentList = isRecentList
        self._stableId = stableId
        self.account = account
        self.segment = segment
        self.selectHandler = selectHandler
        
        super.init(initialSize)
        _ = makeSize(initialSize.width)
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let perLine = max(1, Int(floor(max(300, width - 20) / 41)))
        self.lineAttr = stride(from: 0, to: symbols.count, by: perLine).map {
            Array(symbols[$0 ..< min($0 + perLine, symbols.count)])
        }
        return true
    }
    
    override open func viewClass() ->AnyClass {
        return EBlockRowView.self;
    }
    
    public override var accessibilityLabel: String? {
        return segment.localizedString
    }
    
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items: [ContextMenuItem] = []
        let postbox = self.account.postbox
        if let view = self.view as? EBlockRowView, let emojiUnderMouse = view.emojiUnderMouse {
            let emoji = emojiUnderMouse.emojiUnmodified
            if emoji.canHaveSkinToneModifier {
                let recentEmoji = self.isRecentList ? emojiUnderMouse : nil
                items.append(EmojiToleranceContextMenuItem(emoji: emoji, callback: { value in
                    _ = modifySkinEmoji(emoji, modifier: value, recentEmoji: recentEmoji, postbox: postbox).start()
                }))
            }
        }
        
       
        return .single(items)
    }
}
