import Cocoa

import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import SystemPermissions
import TelegramMediaUtils
import Postbox

private func generateValueImage(_ color: NSColor, height: CGFloat) -> CGImage {
    return generateImage(NSMakeSize(4, height), rotatedContext: { size, ctx in
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.round(size, 2)
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
    })!
}

public class MicrophonePreviewRowItem: GeneralRowItem {
    fileprivate let controller: MicroListenerContext
    fileprivate var powerLevel: Int = 0 {
        didSet {
            if powerLevel != oldValue {
                self.redraw(animated: true, presentAsNew: false)
            }
        }
    }
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any SharedAccountContextProtocol, viewType: GeneralViewType, customTheme: GeneralRowItem.Theme? = nil) {
        controller = MicroListenerContext(devices: CallSettingsHooks.shared.devicesContext(context), accountManager: context.accountManager)
        
        super.init(initialSize, height: 40, stableId: stableId, viewType: viewType, customTheme: customTheme)
       
        controller.resume (onSpeaking: { [weak self] value in
            self?.powerLevel = max(min(Int(36 * value), 36), 0)
        }, always: true)
    }

    
    public override var accessibilityLabel: String? {
        return strings().callSettingsInputLevel
    }

    public override var accessibilityValue: String? {
        return "\(Int(round(Double(powerLevel) / 36 * 100)))%"
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return MicrophonePreviewRowView.self
    }
}

private final class PreviewView : View {
    
    fileprivate var customTheme: GeneralRowItem.Theme?
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        let onsize = NSMakeSize(4, frame.height - 8)
        
        let count = Int(ceil(frame.width / (onsize.width * 2)))
        var pos: NSPoint = NSMakePoint(0, 4)
        
        
        
        let active: CGImage
        let passive: CGImage
        if let theme = self.customTheme {
            active = generateValueImage(theme.accentColor, height: onsize.height)
            passive = generateValueImage(theme.secondaryColor, height: onsize.height)
        } else {
            active = generateValueImage(theme.colors.accentIcon, height: onsize.height)
            passive = generateValueImage(theme.colors.grayIcon, height: onsize.height)
        }
        
        let percent = Float(powerLevel) / Float(36)
        let value = Int(floor(percent * Float(count)))
        for i in 0 ..< count {
            if value > i {
                ctx.draw(active, in: CGRect(origin: pos, size: onsize))
            } else {
                ctx.draw(passive, in: CGRect(origin: pos, size: onsize))
            }
            pos.x += onsize.width * 2
        }
    }
    
    
    public var powerLevel: Int = 0 {
        didSet {
            needsDisplay = true
        }
    }
}

private final class MicrophonePreviewRowView : GeneralContainableRowView {
    private let view = PreviewView(frame: .zero)
    private let title: TextView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(view)
        addSubview(title)
        title.userInteractionEnabled = false
        title.isSelectable = false
    }
    public override var backdorColor: NSColor {
        guard let item = item as? MicrophonePreviewRowItem else {
            return super.backdorColor
        }
        if let theme = item.customTheme {
            return theme.backgroundColor
        }
        return super.backdorColor
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? MicrophonePreviewRowItem else {
            return
        }
        view.customTheme = item.customTheme
        view.powerLevel = item.powerLevel
        needsLayout = true
        
        let layout = TextViewLayout(.initialize(string: strings().callSettingsInputLevel, color: item.customTheme?.textColor ?? theme.colors.text, font: item.settingsPresentation != nil ? .normal(SettingsRowMetrics.titleSize) : .normal(.title)))
        layout.measure(width: 200)
        title.update(layout)
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? MicrophonePreviewRowItem else {
            return
        }
        view.setFrameSize(NSMakeSize(160, 20))
        view.centerY(x: containerView.frame.width - view.frame.width - item.viewType.innerInset.right)
        
        title.centerY(x: item.viewType.innerInset.left)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

