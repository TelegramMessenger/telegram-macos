import Cocoa
import TGUIKit

struct ForwardBindingContext { let account = 0 }
struct ForwardBindingInfo { let author: Int }
struct ForwardBindingMessage { let forwardInfo: ForwardBindingInfo? }
final class ForwardBindingItem {
    var forwardNameLayout: TextViewLayout?
    var forwardPhotoPlaceRange: NSRange?
    var isBubbled = true
    var hasBubble = true
    let context = ForwardBindingContext()
    var message: ForwardBindingMessage? = ForwardBindingMessage(forwardInfo: ForwardBindingInfo(author: 42))
    var actions = 0
    init(_ layout: TextViewLayout?, photo: Bool = false) {
        forwardNameLayout = layout
        forwardPhotoPlaceRange = photo ? NSRange(location: 1, length: 2) : nil
    }
    func openForwardInfo() { actions += 1 }
}
final class ForwardBindingAvatar: Control {
    private(set) var peer: Int?
    init(font: NSFont) {
        super.init(frame: .zero)
        backgroundColor = .systemOrange
        layer?.cornerRadius = 7
    }
    required init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    func setPeer(account: Int, peer: Int?, message: ForwardBindingMessage?) { self.peer = peer }
}
final class ForwardBindingAccessory: View {
    private(set) var text: TextViewLayout?
    func updateText(layout: TextViewLayout, replyView: View?) { text = layout }
}
struct ForwardTooltipCapture {
    weak var view: NSView?
    let rect: NSRect
    let text: String
    let autoCorner: Bool
}
var forwardTooltipCapture: ForwardTooltipCapture?
func recordForwardTooltip(for view: NSView, text: String, autoCorner: Bool, rect: NSRect? = nil) {
    forwardTooltipCapture = ForwardTooltipCapture(view: view, rect: rect ?? view.bounds, text: text, autoCorner: autoCorner)
}

final class NativeForwardBindingRow: View {
    let rowView: View
    let bubbleView = View()
    let contentView = View()
    let rightView = View()
    var statusControl: View?, forwardStatusControl: View?, replyView: View?, adminBadge: View?, adminBadgeBg: View?, boostBadge: View?, viaAccessory: View?
    var captionViews: [SenderCaption] = []
    var item: Any?
    var forwardName: TextView?
    var forwardPhoto: ForwardBindingAvatar?
    var forwardAccessory: ForwardBindingAccessory?
    required init(frame: NSRect) {
        rowView = BeforeForwardNameRowView(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
        rowView.addSubview(bubbleView)
        rowView.addSubview(contentView)
        (rowView as? BeforeForwardNameRowView)?.layerHitBackground = bubbleView
    }
    required init?(coder: NSCoder) { fatalError() }
    func forwardNamePoint(_ item: ForwardBindingItem) -> NSPoint { NSPoint(x: 25, y: 20) }
    func forwardPhotoPoint(_ item: ForwardBindingItem) -> NSPoint { NSPoint(x: 39, y: 20) }
    func bubbleFrame(_ item: ForwardBindingItem) -> NSRect { NSRect(x: 10, y: 10, width: 270, height: 90) }
    func contentFrameModifier(_ item: ForwardBindingItem) -> NSRect { NSRect(x: 25, y: 70, width: 200, height: 20) }
    func bind(_ item: ForwardBindingItem, animated: Bool = false) {
        self.item = item
        bubbleView.frame = bubbleFrame(item)
        contentView.frame = contentFrameModifier(item)
        fillForward(item, animated: animated)
    }
    func layoutName(_ item: ForwardBindingItem, transition: ContainedViewLayoutTransition = .immediate) {
        if let view = forwardName {
            transition.updateFrame(view: view, frame: CGRect(origin: forwardNamePoint(item), size: view.frame.size))
        }
    }
    func updateNameBackground(_ contentColor: NSColor) {
        forwardName?.backgroundColor = contentColor
    }
    func fillForward(_ item:ForwardBindingItem, animated: Bool) -> Void {
        if let forwardNameLayout = item.forwardNameLayout {
            if item.isBubbled && !item.hasBubble {
                if let view = forwardName {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    forwardName = nil
                }
                
                if let view = self.forwardPhoto {
                    performSubviewRemoval(view, animated: animated)
                    self.forwardPhoto = nil
                }
                
                if forwardAccessory == nil {
                    forwardAccessory = ForwardBindingAccessory(frame: CGRect(origin: forwardNamePoint(item), size: forwardNameLayout.layoutSize))
                    rowView.addSubview(forwardAccessory!)
                }
                forwardAccessory?.updateText(layout: forwardNameLayout, replyView: self.replyView)
                
            } else {
                if let view = forwardAccessory {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    forwardAccessory = nil
                }
                if forwardName == nil {
                    forwardName = TextView(frame: CGRect(origin: forwardNamePoint(item), size: forwardNameLayout.layoutSize))
                    forwardName?.isSelectable = false
                    rowView.addSubview(forwardName!)
                }
                
                if item.forwardPhotoPlaceRange != nil {
                    let current: ForwardBindingAvatar
                    if let view = self.forwardPhoto {
                        current = view
                    } else {
                        current = ForwardBindingAvatar(font: .avatar(6))
                        current.setFrameSize(NSMakeSize(14, 14))
                        current.setFrameOrigin(forwardPhotoPoint(item))
                        rowView.addSubview(current)
                        self.forwardPhoto = current
                    }
                    current.setPeer(account: item.context.account, peer: item.message?.forwardInfo?.author, message: item.message)
                    
                    current.removeAllHandlers()
                    current.set(handler: { [weak item] _ in
                        item?.openForwardInfo()
                    }, for: .Click)
                } else if let view = self.forwardPhoto {
                    performSubviewRemoval(view, animated: animated)
                    self.forwardPhoto = nil
                }
                
                forwardName?.update(forwardNameLayout)
            }
            
        } else {
            if let view = forwardName {
                performSubviewRemoval(view, animated: animated, scale: true)
                forwardName = nil
            }
            if let view = forwardAccessory {
                performSubviewRemoval(view, animated: animated, scale: true)
                forwardAccessory = nil
            }
            if let view = self.forwardPhoto {
                performSubviewRemoval(view, animated: animated)
                self.forwardPhoto = nil
            }
        }
    }
    func shakeContentView() {
        
        guard let item = item as? ForwardBindingItem else { return }
        
        if bubbleView.layer?.animation(forKey: "shake") != nil {
            return
        }
        
        let translation = CAKeyframeAnimation(keyPath: "transform.translation.x");
        translation.timingFunction = CAMediaTimingFunction(name: .linear)
        translation.values = [-2, 2, -2, 2, -2, 2, -2, 2, 0]
        
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = [-0.5, -0.5, -0.5, 0.5, -0.5, 0.5, -0.5, -0.5, 0].map {
            ( degrees: Double) -> Double in
            let radians: Double = (.pi * degrees) / 180.0
            return radians
        }
        
        let shakeGroup: CAAnimationGroup = CAAnimationGroup()
        shakeGroup.isRemovedOnCompletion = true
        shakeGroup.animations = [rotation]
        shakeGroup.timingFunction = .init(name: .easeInEaseOut)
        shakeGroup.duration = 0.5
        
        
        
        let frame = bubbleFrame(item)
        let contentFrame = self.contentFrameModifier(item)
        
        
        contentView.layer?.position = NSMakePoint(contentFrame.minX + contentFrame.width / 2, contentFrame.minY + contentFrame.height / 2)
        contentView.layer?.anchorPoint = NSMakePoint(0.5, 0.5);
        
        if item.hasBubble {
            let restoreSenderName = (rowView as? BeforeForwardNameRowView)?.moveSenderNameForShake(into: bubbleView)
            struct ShakeItem {
                let view: NSView
                let rect: NSRect
                let tempRect: NSRect
            }
            var views:[NSView] = [self.rightView, self.statusControl, self.forwardStatusControl, self.replyView, self.adminBadge, self.adminBadgeBg, self.boostBadge, self.forwardName, self.forwardPhoto, self.viaAccessory].compactMap { $0 }
            views.append(contentsOf: self.captionViews.map { $0.view })
            let shakeItems = views.map { view -> ShakeItem in
                return ShakeItem(view: view, rect: view.frame, tempRect: self.bubbleView.convert(view.frame, from: view.superview))
            }
            
            for item in shakeItems {
                item.view.removeFromSuperview()
                item.view.frame = item.tempRect
                bubbleView.addSubview(item.view)
            }
            
            
            shakeGroup.delegate = CALayerAnimationDelegate(completion: { [weak self] _ in
                restoreSenderName?()
                guard let `self` = self else {
                    return
                }
                for item in shakeItems {
                    item.view.removeFromSuperview()
                    item.view.frame = item.rect
                    self.rowView.addSubview(item.view)
                }
            })
        }
        
        bubbleView.layer?.position = NSMakePoint(frame.minX + frame.width / 2, frame.minY + frame.height / 2)
        bubbleView.layer?.anchorPoint = NSMakePoint(0.5, 0.5);

        
        bubbleView.layer?.add(shakeGroup, forKey: "shake")
        contentView.layer?.add(shakeGroup, forKey: "shake")

        
    }
func showHiddenForwardTooltip() { guard let forwardName else { return }; recordForwardTooltip(for: forwardName, text: "Hidden sender", autoCorner: false) }
}

final class LayerForwardBindingRow: View {
    let rowView: View
    let bubbleView = View()
    let contentView = View()
    let rightView = View()
    var statusControl: View?, forwardStatusControl: View?, replyView: View?, adminBadge: View?, adminBadgeBg: View?, boostBadge: View?, viaAccessory: View?
    var captionViews: [SenderCaption] = []
    var item: Any?
    
    var forwardPhoto: ForwardBindingAvatar?
    var forwardAccessory: ForwardBindingAccessory?
    required init(frame: NSRect) {
        rowView = ChatLayerRowView(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
        rowView.addSubview(bubbleView)
        rowView.addSubview(contentView)
        (rowView as? ChatLayerRowView)?.layerHitBackground = bubbleView
    }
    required init?(coder: NSCoder) { fatalError() }
    func forwardNamePoint(_ item: ForwardBindingItem) -> NSPoint { NSPoint(x: 25, y: 20) }
    func forwardPhotoPoint(_ item: ForwardBindingItem) -> NSPoint { NSPoint(x: 39, y: 20) }
    func bubbleFrame(_ item: ForwardBindingItem) -> NSRect { NSRect(x: 10, y: 10, width: 270, height: 90) }
    func contentFrameModifier(_ item: ForwardBindingItem) -> NSRect { NSRect(x: 25, y: 70, width: 200, height: 20) }
    func bind(_ item: ForwardBindingItem, animated: Bool = false) {
        self.item = item
        bubbleView.frame = bubbleFrame(item)
        contentView.frame = contentFrameModifier(item)
        fillForward(item, animated: animated)
    }
    func layoutName(_ item: ForwardBindingItem, transition: ContainedViewLayoutTransition = .immediate) {
        (rowView as? ChatLayerRowView)?.layoutForwardName(origin: forwardNamePoint(item), transition: transition)
    }
    func updateNameBackground(_ contentColor: NSColor) {
        (rowView as? ChatLayerRowView)?.forwardName?.layer.backgroundColor = contentColor.cgColor
    }
    func fillForward(_ item:ForwardBindingItem, animated: Bool) -> Void {
        if let forwardNameLayout = item.forwardNameLayout {
            if item.isBubbled && !item.hasBubble {
                guard (rowView as? ChatLayerRowView)?.updateForwardName(nil, frame: .zero, animated: animated) != false else { return }
                
                if let view = self.forwardPhoto {
                    performSubviewRemoval(view, animated: animated)
                    self.forwardPhoto = nil
                }
                
                if forwardAccessory == nil {
                    forwardAccessory = ForwardBindingAccessory(frame: CGRect(origin: forwardNamePoint(item), size: forwardNameLayout.layoutSize))
                    rowView.addSubview(forwardAccessory!)
                }
                forwardAccessory?.updateText(layout: forwardNameLayout, replyView: self.replyView)
                
            } else {
                if let view = forwardAccessory {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    forwardAccessory = nil
                }
                
                if item.forwardPhotoPlaceRange != nil {
                    let current: ForwardBindingAvatar
                    if let view = self.forwardPhoto {
                        current = view
                    } else {
                        current = ForwardBindingAvatar(font: .avatar(6))
                        current.layer?.zPosition = 2
                        current.setFrameSize(NSMakeSize(14, 14))
                        current.setFrameOrigin(forwardPhotoPoint(item))
                        rowView.addSubview(current)
                        self.forwardPhoto = current
                    }
                    current.setPeer(account: item.context.account, peer: item.message?.forwardInfo?.author, message: item.message)
                    
                    current.removeAllHandlers()
                    current.set(handler: { [weak item] _ in
                        item?.openForwardInfo()
                    }, for: .Click)
                } else if let view = self.forwardPhoto {
                    performSubviewRemoval(view, animated: animated)
                    self.forwardPhoto = nil
                }
                
                (rowView as? ChatLayerRowView)?.updateForwardName(forwardNameLayout, frame: CGRect(origin: forwardNamePoint(item), size: forwardNameLayout.layoutSize), animated: animated)
            }
            
        } else {
            guard (rowView as? ChatLayerRowView)?.updateForwardName(nil, frame: .zero, animated: animated) != false else { return }
            if let view = forwardAccessory {
                performSubviewRemoval(view, animated: animated, scale: true)
                forwardAccessory = nil
            }
            if let view = self.forwardPhoto {
                performSubviewRemoval(view, animated: animated)
                self.forwardPhoto = nil
            }
        }
    }
    func shakeContentView() {
        
        guard let item = item as? ForwardBindingItem else { return }
        
        if bubbleView.layer?.animation(forKey: "shake") != nil {
            return
        }
        
        let translation = CAKeyframeAnimation(keyPath: "transform.translation.x");
        translation.timingFunction = CAMediaTimingFunction(name: .linear)
        translation.values = [-2, 2, -2, 2, -2, 2, -2, 2, 0]
        
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = [-0.5, -0.5, -0.5, 0.5, -0.5, 0.5, -0.5, -0.5, 0].map {
            ( degrees: Double) -> Double in
            let radians: Double = (.pi * degrees) / 180.0
            return radians
        }
        
        let shakeGroup: CAAnimationGroup = CAAnimationGroup()
        shakeGroup.isRemovedOnCompletion = true
        shakeGroup.animations = [rotation]
        shakeGroup.timingFunction = .init(name: .easeInEaseOut)
        shakeGroup.duration = 0.5
        
        
        
        let frame = bubbleFrame(item)
        let contentFrame = self.contentFrameModifier(item)
        
        
        contentView.layer?.position = NSMakePoint(contentFrame.minX + contentFrame.width / 2, contentFrame.minY + contentFrame.height / 2)
        contentView.layer?.anchorPoint = NSMakePoint(0.5, 0.5);
        
        if item.hasBubble {
            let restoreSenderName = (rowView as? ChatLayerRowView)?.moveSenderNameForShake(into: bubbleView)
            let restoreForwardName = (rowView as? ChatLayerRowView)?.moveForwardNameForShake(into: bubbleView)
            struct ShakeItem {
                let view: NSView
                let rect: NSRect
                let tempRect: NSRect
            }
            var views:[NSView] = [self.rightView, self.statusControl, self.forwardStatusControl, self.replyView, self.adminBadge, self.adminBadgeBg, self.boostBadge, self.forwardPhoto, self.viaAccessory].compactMap { $0 }
            views.append(contentsOf: self.captionViews.map { $0.view })
            let shakeItems = views.map { view -> ShakeItem in
                return ShakeItem(view: view, rect: view.frame, tempRect: self.bubbleView.convert(view.frame, from: view.superview))
            }
            
            for item in shakeItems {
                item.view.removeFromSuperview()
                item.view.frame = item.tempRect
                bubbleView.addSubview(item.view)
            }
            
            
            shakeGroup.delegate = CALayerAnimationDelegate(completion: { [weak self] _ in
                restoreSenderName?()
                restoreForwardName?()
                guard let `self` = self else {
                    return
                }
                for item in shakeItems {
                    item.view.removeFromSuperview()
                    item.view.frame = item.rect
                    self.rowView.addSubview(item.view)
                }
            })
        }
        
        bubbleView.layer?.position = NSMakePoint(frame.minX + frame.width / 2, frame.minY + frame.height / 2)
        bubbleView.layer?.anchorPoint = NSMakePoint(0.5, 0.5);

        
        bubbleView.layer?.add(shakeGroup, forKey: "shake")
        contentView.layer?.add(shakeGroup, forKey: "shake")

        
    }
    func showHiddenForwardTooltip() {
        guard let host = rowView as? ChatLayerRowView, let rect = host.forwardNameFrame else { return }
        recordForwardTooltip(for: host, text: "Hidden sender", autoCorner: false, rect: rect)
    }
}
