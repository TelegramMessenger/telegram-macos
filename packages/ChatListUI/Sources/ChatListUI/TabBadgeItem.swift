import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import AvatarUI
import TelegramMedia
import LocalAnimations


final class AvatarTabContainer : View {
    private let avatar = AvatarControl(font: .avatar(12))
    private let disposable = MetaDisposable()
    private var selected: Bool = false
    private let circle: View = View()
    private var laidOutBounds: NSRect?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.userInteractionEnabled = false
        circle.layer?.borderWidth = 1.33
        circle.layer?.borderColor = theme.colors.accentIcon.cgColor
        addSubview(circle)
        addSubview(avatar)
        setSelected(false, animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func setPeer(account: Account, peer: Peer?) {
        avatar.setPeer(account: account, peer: peer)
    }

    func setAccount(_ account: Account) {
        disposable.set((account.postbox.peerView(id: account.peerId) |> map { $0.peers[$0.peerId] } |> deliverOnMainQueue).start(next: { [weak self] peer in
            self?.setPeer(account: account, peer: peer)
        }))
    }

    deinit {
        disposable.dispose()
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        circle.layer?.borderColor = theme.colors.accentIcon.cgColor
    }
    
    
    override func layout() {
        super.layout()
        updateGeometry()
    }
    
    func setSelected(_ selected: Bool, animated: Bool) {
        updateGeometry()
        self.selected = selected
        circle.change(opacity: selected ? 1 : 0, animated: animated, duration: 0.4, timingFunction: .spring)
        updateSelectionScales(animated: animated)
    }

    func lensContentSources(tintColor: NSColor) -> [LiquidGlassLensContentSource] {
        updateGeometry()
        return [
            LiquidGlassLensContentSource(view: circle, lensedTintColor: tintColor, unlensedTintColor: .clear),
            LiquidGlassLensContentSource(view: avatar, lensedScale: bounds.height > 0 ? 24 / bounds.height : 1),
        ]
    }

    private func updateGeometry() {
        guard laidOutBounds != bounds else {
            return
        }
        laidOutBounds = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for view in [avatar, circle] {
            view.layer?.removeAnimation(forKey: "transform")
            view.layer?.transform = CATransform3DIdentity
            view.frame = bounds
        }
        circle.layer?.cornerRadius = bounds.height / 2
        updateSelectionScales(animated: false)
        CATransaction.commit()
    }

    private func updateSelectionScales(animated: Bool) {
        updateScale(selected && bounds.height > 0 ? 24 / bounds.height : 1, for: avatar.layer, animated: animated)
        updateScale(selected ? 1 : 0.5, for: circle.layer, animated: animated)
    }

    private func updateScale(_ scale: CGFloat, for layer: CALayer?, animated: Bool) {
        guard let layer else {
            return
        }
        let center = NSMakePoint((0.5 - layer.anchorPoint.x) * layer.bounds.width, (0.5 - layer.anchorPoint.y) * layer.bounds.height)
        var target = CATransform3DMakeTranslation(center.x, center.y, 0)
        target = CATransform3DScale(target, scale, scale, 1)
        target = CATransform3DTranslate(target, -center.x, -center.y, 0)
        if animated && CATransform3DEqualToTransform(layer.transform, target) {
            return
        }
        let animation = layer.animation(forKey: "transform") as? CABasicAnimation
        let current: CATransform3D
        if let animation {
            current = layer.presentation()?.transform ?? (animation.fromValue as? NSValue)?.caTransform3DValue ?? layer.transform
        } else {
            current = layer.transform
        }
        layer.removeAnimation(forKey: "transform")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        CATransaction.commit()
        if animated && !CATransform3DEqualToTransform(current, target) {
            layer.animate(from: NSValue(caTransform3D: current), to: NSValue(caTransform3D: target), keyPath: "transform", timingFunction: .spring, duration: 0.3)
        }
    }

}


final class TabAnimatedIconView : LottiePlayerView {
    private let sticker: LocalAnimatedSticker
    private let animationData: Data?
    private var selected: Bool = false

    init(sticker: LocalAnimatedSticker, animationData: Data? = nil) {
        self.sticker = sticker
        self.animationData = animationData
        super.init(frame: NSMakeRect(0, 0, 48, 48))
        isEventLess = true
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var colors: [LottieColor] {
        return [.init(keyPath: "", color: selected ? theme.colors.accentIcon : theme.colors.grayIcon)]
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        self.selected = selected
        apply(playing: animated && selected)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        if self.animation?.colors != colors {
            apply(playing: false)
        }
    }

    private func apply(playing: Bool) {
        guard let data = animationData ?? sticker.data else {
            return
        }
        let policy: LottiePlayPolicy = playing ? .toEnd(from: 0) : .toEnd(from: .max)
        let animation = LottieAnimation(compressed: data, key: .init(key: .bundle(sticker.rawValue), size: frame.size), cachePurpose: .none, playPolicy: policy, colors: colors, runOnQueue: .mainQueue())
        set(animation, reset: playing, saveContext: true)
    }
}

public class TabAnimatedItem: TabItem {
    public let sticker: LocalAnimatedSticker
    public init(_ sticker: LocalAnimatedSticker, image: CGImage, selectedImage: CGImage, controller: ViewController, subNode: Node? = nil, longHoverHandler: ((Control)->Void)? = nil) {
        self.sticker = sticker
        super.init(image: image, selectedImage: selectedImage, controller: controller, subNode: subNode, longHoverHandler: longHoverHandler)
    }

    public override func withUpdatedImages(_ image: CGImage, _ selectedImage: CGImage) -> TabItem {
        let item = TabAnimatedItem(sticker, image: image, selectedImage: selectedImage, controller: self.controller, subNode: self.subNode, longHoverHandler: self.longHoverHandler)
        item.accessibilityTitle = accessibilityTitle
        return item
    }

    public override func makeView() -> NSView {
        return TabAnimatedIconView(sticker: sticker)
    }

    public override func supportsLensTint(for view: NSView) -> Bool {
        return view is TabAnimatedIconView
    }

    public override func lensContentSources(for view: NSView, lensedTintColor: NSColor, unlensedTintColor: NSColor) -> [LiquidGlassLensContentSource] {
        if let avatar = view as? AvatarTabContainer {
            return avatar.lensContentSources(tintColor: lensedTintColor)
        }
        return super.lensContentSources(for: view, lensedTintColor: lensedTintColor, unlensedTintColor: unlensedTintColor)
    }

    public override func setSelected(_ selected: Bool, for view: NSView, animated: Bool) {
        if let view = view as? TabAnimatedIconView {
            view.setSelected(selected, animated: animated)
        } else {
            super.setSelected(selected, for: view, animated: animated)
        }
    }
}

public class TabBadgeItem: TabAnimatedItem {
    private let context:any AccountContextProtocol
    public init(_ context: any AccountContextProtocol, controller:ViewController, image: CGImage, selectedImage: CGImage, longHoverHandler:((Control)->Void)? = nil, subNode: Node? = nil) {
        self.context = context
        super.init(.tab_chats, image: image, selectedImage: selectedImage, controller: controller, subNode: subNode ?? ChatListUIHooks.shared.makeTabBadgeNode(context), longHoverHandler: longHoverHandler)
    }
    public override func withUpdatedImages(_ image: CGImage, _ selectedImage: CGImage) -> TabItem {
        let item = TabBadgeItem(context, controller: self.controller, image: image, selectedImage: selectedImage, longHoverHandler: self.longHoverHandler, subNode: subNode)
        item.accessibilityTitle = accessibilityTitle
        return item
    }
}
public class TabAllBadgeItem: TabAnimatedItem {
    private let context:any AccountContextProtocol
    public init(_ context: any AccountContextProtocol, image: CGImage, selectedImage: CGImage, controller:ViewController, subNode:Node? = nil, longHoverHandler:((Control)->Void)? = nil) {
        self.context = context
        super.init(.tab_settings, image: image, selectedImage: selectedImage, controller: controller, subNode: subNode ?? ChatListUIHooks.shared.makeTabAllBadgeNode(context), longHoverHandler: longHoverHandler)
    }
    
    public override func withUpdatedImages(_ image: CGImage, _ selectedImage: CGImage) -> TabItem {
        let item = TabAllBadgeItem(context, image: image, selectedImage: selectedImage, controller: self.controller, subNode: self.subNode, longHoverHandler: self.longHoverHandler)
        item.accessibilityTitle = accessibilityTitle
        return item
    }
    
    public override func makeView() -> NSView {
        let context = self.context
        
        let semaphore = DispatchSemaphore(value: 0)
        var isMultiple = true
        _ = (context.sharedContext.activeAccounts |> take(1)).start(next: { accounts in
            isMultiple = accounts.accounts.count > 1
            semaphore.signal()
        })

        semaphore.wait()
        
        if !isMultiple {
            return super.makeView()
        }
        
        let view = AvatarTabContainer(frame: NSMakeRect(0, 0, 30, 30))
        /*
         |> distinctUntilChanged(isEqual: { lhs, rhs -> Bool in
         return lhs?.smallProfileImage != rhs?.smallProfileImage
         })
 */
        view.setAccount(context.account)
        
        return view
    }
    
    public override func setSelected(_ selected: Bool, for view: NSView, animated: Bool) {
        (view as? AvatarTabContainer)?.setSelected(selected, animated: animated)
        super.setSelected(selected, for: view, animated: animated)
    }
    
}
