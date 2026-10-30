import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import InAppSettings
import Strings
import Localization
import LocalAnimations

let recentEmojiSourceKey = NSAttributedString.Key("recentEmojiSource")

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
    public let dragHandler: ((String, EntertainmentStickerDrag) -> Bool)?
    public let segment: EmojiSegment
    public internal(set) var selectedOrders: [String: Int]
    public let selectionColor: NSColor?
    public let removeRecent: ((String) -> Void)?
    
    public init(_ initialSize:NSSize, stableId: AnyHashable, attrLines:[[NSAttributedString]], segment: EmojiSegment, account: Account, selectHandler:@escaping(String, NSRect)->Void, dragHandler: ((String, EntertainmentStickerDrag) -> Bool)? = nil, selectedOrders: [String: Int] = [:], selectionColor: NSColor? = nil, removeRecent: ((String) -> Void)? = nil) {
        self.lineAttr = attrLines
        self.symbols = attrLines.flatMap { $0 }
        self.selectedOrders = selectedOrders
        self.selectionColor = selectionColor
        self.removeRecent = removeRecent
        self._stableId = stableId
        self.account = account
        self.segment = segment
        self.selectHandler = selectHandler
        self.dragHandler = dragHandler
        
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
        if let view = self.view as? EBlockRowView, let selectedEmoji = view.emoji(at: location) {
            let emoji = selectedEmoji.string.emojiUnmodified
            if emoji.canHaveSkinToneModifier {
                items.append(EmojiToleranceContextMenuItem(emoji: emoji, callback: { value in
                    _ = modifySkinEmoji(emoji, modifier: value, postbox: postbox).start()
                }))
            }
            if let removeRecent = removeRecent {
                if !items.isEmpty {
                    items.append(ContextSeparatorItem())
                }
                let source = selectedEmoji.attribute(recentEmojiSourceKey, at: 0, effectiveRange: nil) as? String ?? selectedEmoji.string
                items.append(ContextMenuItem(strings().searchRemoveFromRecent, handler: {
                    removeRecent(source)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
        }
        
       
        return .single(items)
    }
}
