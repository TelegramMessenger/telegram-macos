import Cocoa
import TGUIKit

final class SenderBindingItem {
    var authorText: TextViewLayout?
    var nameHide: String?
    var isBubbled = true
    var hasBubble = true
    var boostBadge: TextViewLayout?
    var adminBadge: TextViewLayout?
    var adminBadgeAuthorId: Int?
    var adminBadgeIsRank = false
    var adminBadgeColor: NSColor?
    var guestChatBadge: TextViewLayout?
    let context = 0
    init(_ layout: TextViewLayout?, toolTip: String? = nil) { authorText = layout; nameHide = toolTip }
    func boost(morphSource: () -> NSView?) {}
    func adminBadgeInteraction(_ view: NSView) {}
}
final class SenderViaAccessory: View {
    func updateText(layout: TextViewLayout) {}
}
final class SenderInteractiveTextView: Control {
    let textView = TextView()
    func set(text: TextViewLayout, context: Int, emojiOffset: NSPoint = .zero) { textView.update(text) }
}
struct SenderCaption { let view: View }

final class NativeSenderBindingRow: View {
    let rowView: View
    let bubbleView = View()
    let contentView = View()
    let rightView = View()
    var statusControl: View?, forwardStatusControl: View?, replyView: View?, forwardName: View?, forwardPhoto: View?
    var captionViews: [SenderCaption] = []
    var item: Any?
    var nameView: TextView?
    var viaAccessory: SenderViaAccessory?
    var adminBadge: TextView?
    var adminBadgeBg: View?
    var boostBadge: SenderInteractiveTextView?
    var ephemeralBadgeView: SenderInteractiveTextView?
    required init(frame: NSRect) {
        rowView = View(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
        rowView.addSubview(bubbleView)
        rowView.addSubview(contentView)
        (rowView as? ChatLayerRowView)?.layerHitBackground = bubbleView
    }
    required init?(coder: NSCoder) { fatalError() }
    func namePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 25, y: 20) }
    func boostBadgePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 220, y: 20) }
    func adminBadgePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 230, y: 20) }
    func adminBadgeBgRect(_ item: SenderBindingItem) -> NSRect { NSRect(x: 225, y: 18, width: 40, height: 20) }
    func ephemeralBadgePoint(_ item: SenderBindingItem) -> NSPoint { .zero }
    func bubbleFrame(_ item: SenderBindingItem) -> NSRect { NSRect(x: 10, y: 10, width: 270, height: 90) }
    func contentFrameModifier(_ item: SenderBindingItem) -> NSRect { NSRect(x: 25, y: 55, width: 200, height: 30) }
    func bind(_ item: SenderBindingItem, animated: Bool = false) {
        self.item = item
        bubbleView.frame = bubbleFrame(item)
        contentView.frame = contentFrameModifier(item)
        fillName(item, animated: animated)
    }
    func layoutName(_ item: SenderBindingItem, transition: ContainedViewLayoutTransition = .immediate) {
        if let view = nameView {
            transition.updateFrame(view: view, frame: CGRect(origin: namePoint(item), size: view.frame.size))
        }
    }
    func updateNameBackground(_ contentColor: NSColor) {
        nameView?.backgroundColor = contentColor
    }
    func fillName(_ item:SenderBindingItem, animated: Bool) -> Void {
        if let author = item.authorText {
            if item.isBubbled && !item.hasBubble {
                if let view = nameView {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.nameView = nil
                }
                if let view = adminBadge {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.adminBadge = nil
                }
                if let view = adminBadgeBg {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.adminBadgeBg = nil
                }
                if let view = boostBadge {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.boostBadge = nil
                }

                if viaAccessory == nil {
                    viaAccessory = SenderViaAccessory(frame: NSZeroRect)
                }
                guard let viaAccessory = viaAccessory else {return}
                viaAccessory.removeFromSuperview()
                if replyView != nil {
                    replyView?.addSubview(viaAccessory)
                } else {
                    rowView.addSubview(viaAccessory)
                }
                viaAccessory.updateText(layout: author)
            } else {
                if let view = viaAccessory {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.viaAccessory = nil
                }
                
                if nameView == nil {
                    nameView = TextView(frame: CGRect(origin: namePoint(item), size: author.layoutSize))
                    nameView?.isSelectable = false
                    rowView.addSubview(nameView!)
                }
                if let boostBadge = item.boostBadge {
                    if self.boostBadge == nil {
                        self.boostBadge = SenderInteractiveTextView(frame: CGRect(origin: boostBadgePoint(item), size: boostBadge.layoutSize))
                        self.boostBadge?.scaleOnClick = true
                        rowView.addSubview(self.boostBadge!)
                    }
                    self.boostBadge?.removeAllHandlers()
                    self.boostBadge?.set(handler: { [weak item, weak self] _ in
                        item?.boost(morphSource: { [weak self] in self?.boostBadge })
                    }, for: .Click)
                    self.boostBadge?.set(text: boostBadge, context: item.context)
                } else {
                    if let view = boostBadge {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.boostBadge = nil
                    }
                }
                if let adminBadge = item.adminBadge {
                    if self.adminBadge == nil {
                        self.adminBadge = TextView(frame: CGRect(origin: adminBadgePoint(item), size: adminBadge.layoutSize))
                        self.adminBadge?.isSelectable = false
                        rowView.addSubview(self.adminBadge!)
                    }
                    self.adminBadge?.update(adminBadge)
                    self.adminBadge?.removeAllHandlers()
                    if item.adminBadgeAuthorId == nil { self.adminBadge?.controlState = .Normal }
                    self.adminBadge?.scaleOnClick = item.adminBadgeAuthorId != nil
                    self.adminBadge?.userInteractionEnabled = item.adminBadgeAuthorId != nil
                    if item.adminBadgeAuthorId != nil {
                        self.adminBadge?.set(handler: { [weak item] control in
                            item?.adminBadgeInteraction(control)
                        }, for: .Click)
                    }
                    if item.adminBadgeIsRank, let color = item.adminBadgeColor {
                        if self.adminBadgeBg == nil {
                            self.adminBadgeBg = View()
                            rowView.addSubview(self.adminBadgeBg!, positioned: .below, relativeTo: self.adminBadge)
                        }
                        self.adminBadgeBg?.background = color.withAlphaComponent(0.2)
                        let bgFrame = adminBadgeBgRect(item)
                        self.adminBadgeBg?.frame = bgFrame
                        self.adminBadgeBg?.layer?.cornerRadius = bgFrame.height / 2
                    } else {
                        if let view = adminBadgeBg {
                            performSubviewRemoval(view, animated: animated, scale: true)
                            self.adminBadgeBg = nil
                        }
                    }
                } else {
                    if let view = adminBadge {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.adminBadge = nil
                    }
                    if let view = adminBadgeBg {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.adminBadgeBg = nil
                    }
                }
                nameView?.update(author)
                nameView?.toolTip = item.nameHide
            }

        } else {
            if let view = viaAccessory {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.viaAccessory = nil
            }
            if let view = nameView {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.nameView = nil
            }
            if let view = adminBadge {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.adminBadge = nil
            }
            if let view = adminBadgeBg {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.adminBadgeBg = nil
            }
            if let view = boostBadge {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.boostBadge = nil
            }
        }

        if let badge = item.guestChatBadge {
            if self.ephemeralBadgeView == nil {
                self.ephemeralBadgeView = SenderInteractiveTextView(frame: .zero)
                self.ephemeralBadgeView?.userInteractionEnabled = false
                self.ephemeralBadgeView?.textView.isSelectable = false
                rowView.addSubview(self.ephemeralBadgeView!)
            }
            self.ephemeralBadgeView?.set(text: badge, context: item.context, emojiOffset: NSMakePoint(2, 1))
            self.ephemeralBadgeView?.setFrameSize(badge.layoutSize)
            self.ephemeralBadgeView?.setFrameOrigin(ephemeralBadgePoint(item))
        } else if let view = ephemeralBadgeView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.ephemeralBadgeView = nil
        }
    }
    func shakeContentView() {
        
        guard let item = item as? SenderBindingItem else { return }
        
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
            
            struct ShakeItem {
                let view: NSView
                let rect: NSRect
                let tempRect: NSRect
            }
            var views:[NSView] = [self.rightView, self.nameView, self.statusControl, self.forwardStatusControl, self.replyView, self.adminBadge, self.adminBadgeBg, self.boostBadge, self.forwardName, self.forwardPhoto, self.viaAccessory].compactMap { $0 }
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
}

final class LayerSenderBindingRow: View {
    let rowView: View
    let bubbleView = View()
    let contentView = View()
    let rightView = View()
    var statusControl: View?, forwardStatusControl: View?, replyView: View?, forwardName: View?, forwardPhoto: View?
    var captionViews: [SenderCaption] = []
    var item: Any?
    
    var viaAccessory: SenderViaAccessory?
    var adminBadge: TextView?
    var adminBadgeBg: View?
    var boostBadge: SenderInteractiveTextView?
    var ephemeralBadgeView: SenderInteractiveTextView?
    required init(frame: NSRect) {
        rowView = ChatLayerRowView(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
        rowView.addSubview(bubbleView)
        rowView.addSubview(contentView)
        (rowView as? ChatLayerRowView)?.layerHitBackground = bubbleView
    }
    required init?(coder: NSCoder) { fatalError() }
    func namePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 25, y: 20) }
    func boostBadgePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 220, y: 20) }
    func adminBadgePoint(_ item: SenderBindingItem) -> NSPoint { NSPoint(x: 230, y: 20) }
    func adminBadgeBgRect(_ item: SenderBindingItem) -> NSRect { NSRect(x: 225, y: 18, width: 40, height: 20) }
    func ephemeralBadgePoint(_ item: SenderBindingItem) -> NSPoint { .zero }
    func bubbleFrame(_ item: SenderBindingItem) -> NSRect { NSRect(x: 10, y: 10, width: 270, height: 90) }
    func contentFrameModifier(_ item: SenderBindingItem) -> NSRect { NSRect(x: 25, y: 55, width: 200, height: 30) }
    func bind(_ item: SenderBindingItem, animated: Bool = false) {
        self.item = item
        bubbleView.frame = bubbleFrame(item)
        contentView.frame = contentFrameModifier(item)
        fillName(item, animated: animated)
    }
    func layoutName(_ item: SenderBindingItem, transition: ContainedViewLayoutTransition = .immediate) {
        (rowView as? ChatLayerRowView)?.layoutSenderName(origin: namePoint(item), transition: transition)
    }
    func updateNameBackground(_ contentColor: NSColor) {
        (rowView as? ChatLayerRowView)?.senderName?.layer.backgroundColor = contentColor.cgColor
    }
    func fillName(_ item:SenderBindingItem, animated: Bool) -> Void {
        if let author = item.authorText {
            if item.isBubbled && !item.hasBubble {
                (rowView as? ChatLayerRowView)?.updateSenderName(nil, toolTip: nil, frame: .zero, animated: animated)
                if let view = adminBadge {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.adminBadge = nil
                }
                if let view = adminBadgeBg {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.adminBadgeBg = nil
                }
                if let view = boostBadge {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.boostBadge = nil
                }

                if viaAccessory == nil {
                    viaAccessory = SenderViaAccessory(frame: NSZeroRect)
                }
                guard let viaAccessory = viaAccessory else {return}
                viaAccessory.removeFromSuperview()
                if replyView != nil {
                    replyView?.addSubview(viaAccessory)
                } else {
                    rowView.addSubview(viaAccessory)
                }
                viaAccessory.updateText(layout: author)
            } else {
                if let view = viaAccessory {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.viaAccessory = nil
                }
                
                (rowView as? ChatLayerRowView)?.updateSenderName(author, toolTip: item.nameHide, frame: CGRect(origin: namePoint(item), size: author.layoutSize), animated: animated)
                if let boostBadge = item.boostBadge {
                    if self.boostBadge == nil {
                        self.boostBadge = SenderInteractiveTextView(frame: CGRect(origin: boostBadgePoint(item), size: boostBadge.layoutSize))
                        self.boostBadge?.scaleOnClick = true
                        rowView.addSubview(self.boostBadge!)
                    }
                    self.boostBadge?.removeAllHandlers()
                    self.boostBadge?.set(handler: { [weak item, weak self] _ in
                        item?.boost(morphSource: { [weak self] in self?.boostBadge })
                    }, for: .Click)
                    self.boostBadge?.set(text: boostBadge, context: item.context)
                } else {
                    if let view = boostBadge {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.boostBadge = nil
                    }
                }
                if let adminBadge = item.adminBadge {
                    if self.adminBadge == nil {
                        self.adminBadge = TextView(frame: CGRect(origin: adminBadgePoint(item), size: adminBadge.layoutSize))
                        self.adminBadge?.isSelectable = false
                        rowView.addSubview(self.adminBadge!)
                    }
                    self.adminBadge?.update(adminBadge)
                    self.adminBadge?.removeAllHandlers()
                    if item.adminBadgeAuthorId == nil { self.adminBadge?.controlState = .Normal }
                    self.adminBadge?.scaleOnClick = item.adminBadgeAuthorId != nil
                    self.adminBadge?.userInteractionEnabled = item.adminBadgeAuthorId != nil
                    if item.adminBadgeAuthorId != nil {
                        self.adminBadge?.set(handler: { [weak item] control in
                            item?.adminBadgeInteraction(control)
                        }, for: .Click)
                    }
                    if item.adminBadgeIsRank, let color = item.adminBadgeColor {
                        if self.adminBadgeBg == nil {
                            self.adminBadgeBg = View()
                            rowView.addSubview(self.adminBadgeBg!, positioned: .below, relativeTo: self.adminBadge)
                        }
                        self.adminBadgeBg?.background = color.withAlphaComponent(0.2)
                        let bgFrame = adminBadgeBgRect(item)
                        self.adminBadgeBg?.frame = bgFrame
                        self.adminBadgeBg?.layer?.cornerRadius = bgFrame.height / 2
                    } else {
                        if let view = adminBadgeBg {
                            performSubviewRemoval(view, animated: animated, scale: true)
                            self.adminBadgeBg = nil
                        }
                    }
                } else {
                    if let view = adminBadge {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.adminBadge = nil
                    }
                    if let view = adminBadgeBg {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.adminBadgeBg = nil
                    }
                }
            }

        } else {
            if let view = viaAccessory {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.viaAccessory = nil
            }
            (rowView as? ChatLayerRowView)?.updateSenderName(nil, toolTip: nil, frame: .zero, animated: animated)
            if let view = adminBadge {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.adminBadge = nil
            }
            if let view = adminBadgeBg {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.adminBadgeBg = nil
            }
            if let view = boostBadge {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.boostBadge = nil
            }
        }

        if let badge = item.guestChatBadge {
            if self.ephemeralBadgeView == nil {
                self.ephemeralBadgeView = SenderInteractiveTextView(frame: .zero)
                self.ephemeralBadgeView?.userInteractionEnabled = false
                self.ephemeralBadgeView?.textView.isSelectable = false
                rowView.addSubview(self.ephemeralBadgeView!)
            }
            self.ephemeralBadgeView?.set(text: badge, context: item.context, emojiOffset: NSMakePoint(2, 1))
            self.ephemeralBadgeView?.setFrameSize(badge.layoutSize)
            self.ephemeralBadgeView?.setFrameOrigin(ephemeralBadgePoint(item))
        } else if let view = ephemeralBadgeView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.ephemeralBadgeView = nil
        }
    }
    func shakeContentView() {
        
        guard let item = item as? SenderBindingItem else { return }
        
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
}
