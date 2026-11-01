import Foundation
import TGUIKit
import TelegramTheme
import GeneralRows
import Cocoa

public final class EmojiStatusStatusRowItem : GeneralRowItem {
    fileprivate let textLayout: TextViewLayout
    public init(_ initialSize: NSSize, stableId: AnyHashable, status: String, viewType: GeneralViewType) {
        self.textLayout = .init(.initialize(string: status, color: theme.colors.grayText, font: .normal(.text)))
        super.init(initialSize, stableId: stableId, viewType: viewType)
        _ = makeSize(initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: width - viewType.innerInset.left - viewType.innerInset.right)
        return true
    }
    
    public override var height: CGFloat {
        return viewType.innerInset.top + self.textLayout.layoutSize.height + self.viewType.innerInset.bottom
    }
    
    public override func viewClass() -> AnyClass {
        return EmojiStatusStatusRowView.self
    }
    
    public override var accessibilityLabel: String? {
        let text = textLayout.attributedString.string
        return text.isEmpty ? nil : text
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class EmojiStatusStatusRowView: TableRowView {
    private let textView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }
    
    override func layout() {
        super.layout()
        textView.center()
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? EmojiStatusStatusRowItem else {
            return
        }
        textView.update(item.textLayout)
        
        needsLayout = true
    }
}
