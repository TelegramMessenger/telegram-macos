import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import InputDataUI
import TelegramIconsTheme
import AlertsUI
import InAppSettings
import ApiCredentials
import TelegramMediaUtils


public struct DockIconData {
    public let icon: TelegramApplicationIcons.Icon
    public let selected: Bool
    public let frame: NSRect

}

private let dockPremiumIcon = generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
    ctx.clear(size.bounds)
    
        
    let path = CGMutablePath()
    path.addRoundedRect(in: size.bounds, cornerWidth: size.width / 2, cornerHeight: size.height / 2)
    ctx.addPath(path)
    ctx.clip()
    
    let gradient = CGGradient.evenlySpaced([NSColor(hexString: "#1391FF")!, NSColor(hexString: "#F977CC")!], colorSpace: deviceColorSpace)!
    
    ctx.drawLinearGradient(gradient, start: CGPoint(x: size.width, y: 0), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())
    
    let image = theme.icons.premium_lock

    ctx.draw(image, in: size.bounds.focus(image.backingSize))
    
    
})!




private func createNSImage(fromIcnsFile filePath: String, withSize size: NSSize) -> NSImage? {
    guard let iconFile = NSImage(contentsOfFile: filePath) else {
        print("Failed to load .icns file")
        return nil
    }

    // Create a representation from the icns file for the specific size
    guard let representation = iconFile.bestRepresentation(for: NSRect(x: 0, y: 0, width: size.width, height: size.height), context: nil, hints: nil) else {
        print("Failed to get representation for the specified size")
        return nil
    }

    // Create a new NSImage with the specific size
    let image = NSImage(size: size)
    image.addRepresentation(representation)

    return image
}



public final class DockIconRowItem: GeneralRowItem {
    private(set) var wallpaperImage: CGImage?
    public let icons: [DockIconData]
    public let context: any AccountContextProtocol
    public let callback: (TelegramApplicationIcons.Icon)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, context: any AccountContextProtocol, dockIcons: [TelegramApplicationIcons.Icon], selected: String?, action: @escaping(TelegramApplicationIcons.Icon)->Void, insets: NSEdgeInsets = NSEdgeInsetsMake(0, 20, 0, 20)) {
        self.context = context
        self.callback = action
        var icons: [DockIconData] = []
        var frame: CGRect = CGRect(origin: CGPointMake(20, 20), size: DockIconRowItem.iconSize)
        for (i, icon) in dockIcons.enumerated() {
            icons.append(DockIconData(icon: icon, selected: selected == icon.file.fileName || (icon.file.fileName == TelegramApplicationIcons.Icon.defaultIconName && selected == nil), frame: frame))
            frame.origin.x += DockIconRowItem.iconSize.width
            if (i + 1) % Int(DockIconRowItem.rowCount) == 0 {
                frame.origin.y += DockIconRowItem.iconSize.height
                frame.origin.x = 20
            }
        }
        
        self.icons = icons
        
        
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: insets)
        
        self.wallpaperImage = nil

    }
    
    public override func viewClass() -> AnyClass {
        return DockIconRowView.self
    }
    
    public override var accessibilityLabel: String? {
        return strings().appearanceSettingsDockIcon
    }
    
    public var containerSize: NSSize {
        return NSMakeSize(DockIconRowItem.rowCount * DockIconRowItem.iconSize.width + 40, ceil(CGFloat(icons.count) / DockIconRowItem.rowCount) * DockIconRowItem.iconSize.height + 30)
    }
    
    public static var iconSize: NSSize {
        return NSMakeSize(60, 70)
    }
    public static var rowCount: CGFloat {
        return 4.0
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 20
        
        height += containerSize.height
        
        height += 20
        return height
    }
}

private final class DockIconView : Control {
    
    
    private class Indicator : View {
        private let loading = ProgressIndicator(frame: NSMakeRect(0, 0, 30, 30))
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            backgroundColor = NSColor.black.withAlphaComponent(0.2)
            self.layer?.cornerRadius = 10
            addSubview(loading)
            loading.progressColor = NSColor.white.withAlphaComponent(0.6)
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func layout() {
            super.layout()
            loading.center()
        }
    }
    
    
    private let content = SimpleLayer()
    private let selected = SimpleLayer()
    private let selectionOutline = SimpleLayer()
    
    private var locker: SimpleLayer?
    
    private var item: DockIconData?
    private weak var rowItem: DockIconRowItem?
    
    override func accessibilityLabel() -> String? {
        guard let item = item else {
            return super.accessibilityLabel()
        }
        let name = (item.icon.file.fileName ?? "").components(separatedBy: ".").first?.replacingOccurrences(of: "_", with: " ") ?? ""
        return name.isEmpty ? strings().appearanceSettingsDockIcon : name
    }
    
    override func isAccessibilitySelected() -> Bool {
        return item?.selected ?? false
    }
    private var loading: Indicator?
    
    private let statusDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private let imageDisposable = MetaDisposable()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        content.frame = NSMakeRect(0, 0, 60, 60)
        self.layer?.addSublayer(content)
        self.layer?.addSublayer(selectionOutline)
        self.layer?.addSublayer(selected)
        
        
        selectionOutline.frame = content.frame.insetBy(dx: 2, dy: 2)
        selectionOutline.cornerRadius = 14
        selectionOutline.borderWidth = 2
        selectionOutline.opacity = 0

        selected.frame = NSMakeRect(0, 0, 6, 6)
        selected.cornerRadius = selected.frame.height / 2.0
        selected.opacity = 0
        
        set(handler: { [weak self] _ in
            if let rowItem = self?.rowItem, let item = self?.item, !item.selected {
                rowItem.callback(item.icon)
            }
        }, for: .Click)
        
        self.layer?.masksToBounds = false
    }
    
    public override func layout() {
        super.layout()
        self.selected.frame = CGRect(origin: NSMakePoint((frame.width - selected.frame.width) / 2, content.frame.maxY), size: selected.frame.size)
    }

    public override func stateDidUpdate(_ state: ControlState) {
        scaleOnClick = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        super.stateDidUpdate(state)
    }
    
    public func set(item: DockIconData, rowItem: DockIconRowItem, context: any AccountContextProtocol, animated: Bool) {
       
        let sameIcon = self.item?.icon == item.icon
        if !sameIcon {
            self.imageDisposable.set(nil)
            self.content.contents = nil
        }
        self.item = item
        self.rowItem = rowItem
        
        let signal = context.account.postbox.mediaBox.resourceStatus(item.icon.file.resource, approximateSynchronousValue: true) |> deliverOnMainQueue
        
        
        statusDisposable.set(signal.start(next: { [weak self] status in
            self?.updateItem(item, context: context, status: status)
        }))
        
        fetchDisposable.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: .media(media: AnyMediaReference.message(message: item.icon.reference, media: item.icon.file), resource: item.icon.file.resource)).start())
        
        if !context.isPremium, item.icon.isPremium {
            let current: SimpleLayer
            if let layer = self.locker {
                current = layer
            } else {
                current = SimpleLayer()
                self.layer?.addSublayer(current)
                self.locker = current
            }
            let image = dockPremiumIcon
            current.contents = image
            current.frame = CGRect(origin: NSMakePoint(content.frame.maxX - image.backingSize.width, content.frame.minY), size: image.backingSize)
        } else if let locker = locker {
            performSublayerRemoval(locker, animated: animated)
            self.locker = nil
        }
        self.updateSelection(item.selected && self.locker == nil, animated: animated && sameIcon)
    }

    private func updateSelection(_ isSelected: Bool, animated: Bool) {
        selected.backgroundColor = theme.colors.accent.cgColor
        selectionOutline.borderColor = theme.colors.accent.cgColor

        let opacity: Float = isSelected ? 1 : 0
        let previousOpacity = selected.presentation()?.opacity ?? selected.opacity
        let selectionChanged = selected.opacity != opacity
        selected.opacity = opacity
        selectionOutline.opacity = opacity

        if animated && selectionChanged {
            selected.animateAlpha(from: CGFloat(previousOpacity), to: CGFloat(opacity), duration: 0.18)
            selectionOutline.animateAlpha(from: CGFloat(previousOpacity), to: CGFloat(opacity), duration: 0.18)
            if isSelected && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                selectionOutline.animateScale(from: 0.94, to: 1, duration: 0.2, timingFunction: .easeOut)
            } else {
                selectionOutline.removeAnimation(forKey: "transform.scale")
            }
        } else if !animated {
            selected.removeAllAnimations()
            selectionOutline.removeAllAnimations()
        }
    }
    
    deinit {
        fetchDisposable.dispose()
        statusDisposable.dispose()
        imageDisposable.dispose()
    }
    
    private func updateItem(_ item: DockIconData, context: any AccountContextProtocol, status: MediaResourceStatus) {
        let progress: Float?
        switch status {
        case let .Fetching(_, value):
            progress = value
        case .Local:
            progress = nil
        default:
            progress = 0
        }
        
        if let _ = progress {
            let current: Indicator
            if let view = self.loading {
                current = view
            } else {
                current = Indicator(frame: NSMakeRect(5, 5, 50, 50))
                self.loading = current
                addSubview(current)
            }
        } else if let view = loading {
            performSubviewRemoval(view, animated: true)
            self.loading = nil
        }
        
        self.userInteractionEnabled = progress == nil
        
        if progress == nil {
            let signal: Signal<CGImage?, NoError> = Signal { subscriber in
                let image = createNSImage(fromIcnsFile: context.account.postbox.mediaBox.resourcePath(item.icon.file.resource), withSize: NSMakeSize(60, 60))?._cgImage
                subscriber.putNext(image)
                subscriber.putCompletion()
                return EmptyDisposable
            } 
            |> runOn(.concurrentDefaultQueue())
            |> deliverOnMainQueue
            
            if self.content.contents == nil {
                imageDisposable.set(signal.start(next: { [weak self] image in
                    guard let self, self.item?.icon == item.icon else {
                        return
                    }
                    self.content.contents = image
                    self.content.animateContents()
                }))
            }
        } else {
            imageDisposable.set(nil)
            self.content.contents = nil
            self.content.animateContents()
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class Container : NSVisualEffectView {
    public override var isFlipped: Bool {
        return true
    }
}

public final class DockIconRowView : GeneralContainableRowView {
    private let backgroundView = BackgroundView(frame: .zero)
    private let visualEffect = Container()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(visualEffect)
        
        visualEffect.wantsLayer = true
        visualEffect.state = .active
        visualEffect.blendingMode = .withinWindow
        visualEffect.autoresizingMask = []
        visualEffect.material = .light
        
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.borderWidth = 1
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        guard let item = item as? DockIconRowItem else {
            return
        }
        backgroundView.frame = containerView.bounds
        visualEffect.frame = containerView.focus(item.containerSize)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? DockIconRowItem else {
            return
        }
        
        while visualEffect.subviews.count > item.icons.count {
            visualEffect.subviews.last?.removeFromSuperview()
        }
        while visualEffect.subviews.count < item.icons.count {
            let iconView = DockIconView(frame: DockIconRowItem.iconSize.bounds)
            visualEffect.addSubview(iconView)
        }
        
        for (i, icon) in item.icons.enumerated() {
            let view = visualEffect.subviews[i] as! DockIconView
            view.set(item: icon, rowItem: item, context: item.context, animated: animated)
            view.frame = icon.frame
        }
        
        backgroundView.backgroundMode = theme.backgroundMode
        
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        

        needsLayout = true
    }
}
