import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramUtils
import Cocoa
import InlineStickerLayer
import Localization


public class GifKeyboardTabRowItem: TableRowItem {
    
    public let selected: Bool
    
    public let select:()->Void
        
    public enum Source {
        case icon(CGImage)
        case file(TelegramMediaFile)
    }
    public let source: Source
    
    private let _stableId: AnyHashable
    public override var stableId: AnyHashable {
        return _stableId
    }
    public let context: any AccountContextProtocol
    public let theme: PresentationTheme
    public let title: String?
    public var tint: NSColor?
    public var frosted: Bool = false
    public init(_ initialSize: NSSize, stableId: AnyHashable, selected: Bool, context: any AccountContextProtocol, source: Source, title: String? = nil, select: @escaping()->Void, theme: PresentationTheme) {
        self.theme = theme
        self.title = title
        self.selected = selected
        self.source = source
        self.select = select
        self._stableId = stableId
        self.context = context
        super.init(initialSize)
    }
    
    public override var height:CGFloat {
        return 36.0
    }
    public override var width: CGFloat {
        return 36.0
    }
    
    public override func viewClass() -> AnyClass {
        return GifKeyboardTabRowView.self
    }
    
    public override var accessibilityLabel: String? {
        if let title = title {
            return title
        }
        switch source {
        case let .file(file):
            return file.customEmojiText ?? file.stickerText ?? strings().voiceOverCommonGIFs
        case .icon:
            return strings().voiceOverCommonGIFs
        }
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func accessibilityPerformPress() -> Bool {
        select()
        return true
    }
}


private final class GifKeyboardTabRowView: HorizontalRowView {
    
    private let selectView: View = View()
    private var selectFrost: PickerFrostView?
    private let control = Control()
    
    private var imageLayer: SimpleLayer?
    private var animationLayer: InlineStickerItemLayer?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        control.set(handler: { [weak self] control in
            if let item = self?.item as? GifKeyboardTabRowItem {
                item.select()
            }
        }, for: .Click)
        
        control.frame = NSMakeRect(0, 0, 36, 36)
        
        selectView.frame = NSMakeRect(0, 0, 36, 36)
        
        addSubview(selectView)
        addSubview(control)
        
    }

    override func updateAnimatableContent() -> Void {
        if let value = self.animationLayer, let superview = value.superview {
            var isKeyWindow: Bool = false
            if let window = window {
                if !window.canBecomeKey {
                    isKeyWindow = true
                } else {
                    isKeyWindow = window.isKeyWindow
                }
            }
            value.isPlayable = NSIntersectsRect(value.frame, superview.visibleRect) && isKeyWindow && !isEmojiLite
        }
    }
    

    override var isEmojiLite: Bool {
        if let item = item as? GifKeyboardTabRowItem {
            return item.context.isLite(.emoji)
        }
        return super.isEmojiLite
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GifKeyboardTabRowItem else {
            return
        }
        
        control.setAccessibilityLabel(item.accessibilityLabel)
        
        switch item.source {
        case let .file(file):
            selectView.layer?.cornerRadius = .cornerRadius
            
            if let layer = self.imageLayer {
                self.imageLayer = nil
                performSublayerRemoval(layer, animated: animated)
            }
            let current: InlineStickerItemLayer
            if let layer = animationLayer, layer.file == file {
                current = layer
            } else {
                self.animationLayer?.removeFromSuperlayer()
                current = InlineStickerItemLayer(account: item.context.account, file: file, size: NSMakeSize(28, 28))
                current.contentsGravity = .center
                self.animationLayer = current
                control.layer?.addSublayer(current)
            }
            current.superview = self.control
            current.frame = CGRect(origin: NSMakePoint(4, 4), size: NSMakeSize(28, 28))

        case let .icon(image):
            selectView.layer?.cornerRadius = selectView.frame.height / 2
            
            if let layer = self.animationLayer {
                self.animationLayer = nil
                performSublayerRemoval(layer, animated: animated)
            }
            let current: SimpleLayer
            if let layer = imageLayer {
                current = layer
            } else {
                current = SimpleLayer()
                current.contentsGravity = .resizeAspectFill
                self.imageLayer = current
                control.layer?.addSublayer(current)
            }
            current.contents = item.tint.map { image._NSImage.precomposed($0) } ?? image
            current.frame = CGRect(origin: NSMakePoint(4, 4), size: NSMakeSize(28, 28))
        }
        
        if item.frosted {
            let frost: PickerFrostView
            if let current = selectFrost {
                frost = current
            } else {
                frost = PickerFrostView(frame: selectView.bounds)
                frost.wantsLayer = true
                frost.material = .selection
                frost.blendingMode = .withinWindow
                frost.state = .active
                frost.autoresizingMask = [.width, .height]
                selectView.addSubview(frost)
                selectFrost = frost
            }
            frost.appearance = NSAppearance.themed(isDark: item.theme.colors.isDark)
            selectView.layer?.masksToBounds = true
            selectView.backgroundColor = .clear
        } else {
            selectFrost?.removeFromSuperview()
            selectFrost = nil
            selectView.backgroundColor = item.theme.colors.grayBackground
        }
        selectView.change(opacity: item.selected ? 1 : 0, animated: animated)
        
        control.frame = NSMakeRect(0, 0, item.height, item.height)
        
        selectView.frame = NSMakeRect(0, 0, item.height, item.height)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
