import Foundation
import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import ColorPalette
import Localization
import TelegramTheme
import TelegramIconsTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InlineStickerLayer

public final class QuickReactionRowItem : GeneralRowItem {
    public let context: any AccountContextProtocol
    public let reaction: ContextReaction
    public let select: (Control)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, reaction: ContextReaction, viewType: GeneralViewType, select:@escaping(Control)->Void) {
        self.context = context
        self.reaction = reaction
        self.select = select
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public override var height: CGFloat {
        return 42
    }
    
    public override func viewClass() -> AnyClass {
        return QuickReactionRowView.self
    }

    public override var accessibilityLabel: String? {
        return strings().reactionSettingsQuickTitle
    }

    public override var accessibilityValue: String? {
        switch reaction {
        case let .builtin(value, _, _, _, _):
            if case let .builtin(emoji) = value {
                return emoji
            }
            return nil
        default:
            return nil
        }
    }
}

private final class QuickReactionRowView : GeneralContainableRowView {
    private var imageLayer: InlineStickerItemLayer?
    private let control = Control(frame: NSMakeRect(0, 0, 25, 25))
    private let textView = TextView()
    private let imageView = ImageView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        addSubview(textView)
        addSubview(imageView)
        control.setAccessibilityLabel(strings().voiceOverCommonReactions)
        imageView.isAccessibilityDecorative = true
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        
        containerView.setStateChangeHandler { [weak self] in
            self?.updateColors()
        }
        
        
        control.set(handler: { [weak self] control in
            if let item = self?.item as? QuickReactionRowItem {
                item.select(control)
            }
        }, for: .Click)
        
        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? QuickReactionRowItem, let control = self?.control {
                item.select(control)
            }
        }, for: .Click)
    }
    
    var highlightColor: NSColor {
        return theme.colors.grayHighlight
    }
    
    
    override func updateColors() {
        super.updateColors()
        if let item = item as? GeneralRowItem {
            self.background = item.viewType.rowBackground
            let highlighted = isSelect ? self.backdorColor : highlightColor
            containerView.set(background: self.backdorColor, for: .Normal)
            containerView.set(background: highlighted, for: .Highlight)
        }
        containerView.needsDisplay = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        if let item = item as? GeneralRowItem {
            var rect = containerView.focus(control.frame.size)
            rect.origin.x = containerView.frame.width - rect.size.width - item.viewType.innerInset.right
            control.frame = rect
            
            imageView.centerY(x: item.viewType.innerInset.left)
            textView.centerY(x: imageView.frame.maxX + 10)
        }
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        let previous = self.item as? QuickReactionRowItem
        super.set(item: item, animated: animated)
        
        guard let item = item as? QuickReactionRowItem else {
            return
        }
        imageView.image = theme.icons.installed_stickers_reactions
        imageView.sizeToFit()
        
        let textLayout = TextViewLayout.init(.initialize(string: strings().reactionSettingsQuickTitle, color: theme.colors.text, font: item.settingsPresentation != nil ? .normal(SettingsRowMetrics.titleSize) : .normal(.title)))
        textLayout.measure(width: .greatestFiniteMagnitude)
        
        self.textView.update(textLayout)
        
        if previous?.reaction != item.reaction {
            if let imageLayer = self.imageLayer {
                performSublayerRemoval(imageLayer, animated: animated, scale: true)
                self.imageLayer = nil
            }
            let size = NSMakeSize(25, 25)
            let current: InlineStickerItemLayer
            switch item.reaction {
            case let .builtin(_, staticFile, _, _, _):
               current = InlineStickerItemLayer(account: item.context.account, file: staticFile, size: size)
            case let .custom(_, fileId, file, _):
                current = InlineStickerItemLayer(account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, emoji: .init(fileId: fileId, file: file, emoji: ""), size: size)
            case let .stars(file, _):
                current = InlineStickerItemLayer(account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, emoji: .init(fileId: item.reaction.fileId, file: file, emoji: ""), size: size)
            }
            current.superview = self
            self.imageLayer = current
            self.control.layer?.addSublayer(current)
            current.isPlayable = true
            current.frame = CGRect(origin: .zero, size: size)
            if animated {
                current.animateAlpha(from: 0, to: 1, duration: 0.2)
                current.animateScale(from: 0.1, to: 1, duration: 0.2)
            }
        }
        needsLayout = true
    }
}
