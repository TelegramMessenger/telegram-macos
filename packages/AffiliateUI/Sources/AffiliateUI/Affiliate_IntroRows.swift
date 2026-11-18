import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import SceneEffects
import ObjcUtils

public final class Affiliate_HeaderItem : GeneralRowItem {
    fileprivate let titleLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    public let peer: Peer?
    public let context: (any AccountContextProtocol)
    public let presentation: TelegramPresentationTheme
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), presentation: TelegramPresentationTheme, peer: Peer?, title: String, info: String, detectBold: Bool, viewType: GeneralViewType) {
        
        self.context = context
        self.peer = peer
        self.presentation = presentation
        
        let titleAttr: NSAttributedString = .initialize(string: title, color: presentation.colors.text, font: .medium(.header))
        let infoAttr = NSMutableAttributedString()
        _ = infoAttr.append(string: info, color: presentation.colors.text, font: .normal(.text))
        if detectBold {
            infoAttr.detectBoldColorInString(with: .medium(.text))
        }
        
        self.titleLayout = .init(titleAttr, alignment: .center)
        self.titleLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        
        self.infoLayout = .init(infoAttr, alignment: .center)
        self.infoLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        super.init(initialSize, stableId: stableId, viewType: viewType)
        _ = makeSize(initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        let textWidth = blockWidth - viewType.innerInset.left - viewType.innerInset.right
        titleLayout.measure(width: textWidth)
        infoLayout.measure(width: textWidth)

        return true
    }
    
    public override var height: CGFloat {
        return 100 + 10 + titleLayout.layoutSize.height + 10 + infoLayout.layoutSize.height + 10
    }
    
    public override func viewClass() -> AnyClass {
        return Affiliate_HeaderItemView.self
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }
}

private final class Affiliate_HeaderItemView : TableRowView {
    private var premiumView: (PremiumSceneView & NSView)?
    private let titleView = TextView()
    private let infoView = TextView()
    private var timer: SwiftSignalKit.Timer?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(infoView)
        
        titleView.isSelectable = false
        infoView.isSelectable = false
        
        self.layer?.masksToBounds = false
    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? Affiliate_HeaderItem else {
            return theme.colors.listBackground
        }
        return item.presentation.colors.listBackground
    }
    
    public override func layout() {
        super.layout()
        if let premiumView = premiumView {
            premiumView.centerX(y: -30)
            titleView.centerX(y: premiumView.frame.maxY - 30 + 10)
        }
        infoView.centerX(y: titleView.frame.maxY + 10)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? Affiliate_HeaderItem else {
            return
        }
        titleView.update(item.titleLayout)
        infoView.update(item.infoLayout)
        
        timer = SwiftSignalKit.Timer(timeout: 5.0, repeat: true, completion: { [weak self] in
            self?.premiumView?.playAgain()
        }, queue: .mainQueue())
        
        timer?.start()
        
        var current: (PremiumSceneView & NSView)
        if let view = self.premiumView {
            current = view
        } else {
            let scene = PremiumCoinSceneView(frame: NSMakeRect(0, 0, frame.width, 150))
            scene.mode = .affiliate
            current = scene
            addSubview(current)
            self.premiumView = current
        }
        current.sceneBackground = backdorColor
        current.updateLayout(size: current.frame.size, transition: .immediate)
        
        addSubview(titleView)

        needsLayout = true
    }
}

public struct Affiliate_PromoOption {
    public let image: CGImage
    public let title: String
    public let text: String
    public init(image: CGImage, title: String, text: String) {
        self.image = image
        self.title = title
        self.text = text
    }
}

public final class Affiliate_PromoItem : GeneralRowItem {
    
    public let context: (any AccountContextProtocol)
    public let options: [OptionsListView.Option]

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), options: [Affiliate_PromoOption]) {
        self.context = context
        self.options = options.map { option in
            return .init(image: option.image, header: .init(.initialize(string: option.title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: option.text, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40)
        }
        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        for option in options {
            option.makeSize(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right)
        }
        
        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0
        height += 15
        height += OptionsListView.height(options: options, spacing: 15) + 15
        return height
    }
    
    public override func viewClass() -> AnyClass {
        return Affiliate_PromoItemView.self
    }

    public override var accessibilityLabel: String? {
        return options.map { $0.header.attributedString.string }.joined(separator: ", ")
    }
}

private final class Affiliate_PromoItemView: GeneralContainableRowView {
    private let optionsView = OptionsListView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(optionsView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        optionsView.centerX(y: 15)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? Affiliate_PromoItem else {
            return
        }
        optionsView.spacing = 15
        optionsView.update(options: item.options)
        
        needsLayout = true
    }
}
