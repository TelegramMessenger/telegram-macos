import Foundation
import TGUIKit
import AppKit
import TelegramMedia

public final class EmojiAnimationEffectView : View {
    public enum Source {
        case builtin(LottieAnimation)
        case custom(CustomReactionEffectView)
    }
    private let player: NSView
    private let animation: Source
    public let animationSize: NSSize
    private var animationPoint: CGPoint
    
    public var index: Int? = nil
    
    public init(animation: Source, animationSize: NSSize, animationPoint: CGPoint, frameRect: NSRect) {
        self.animation = animation
        self.animationSize = animationSize
        self.animationPoint = animationPoint
        let view: NSView
        
        
        switch animation {
        case let .builtin(animation):
            let player = LottiePlayerView(frame: .init(origin: animationPoint, size: animationSize))
            player.set(animation)
            view = player
            player.isEventLess = true
        case let .custom(current):
            view = current
        }
        self.player = view
        super.init(frame: frameRect)
        addSubview(view)
        isEventLess = true
        updateLayout(size: frameRect.size, transition: .immediate)
        
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
        
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self.player, frame: CGRect(origin: animationPoint, size: animationSize))
        if let view = player as? LottiePlayerView {
            view.update(size: animationSize, transition: transition)
        }
    }
    
    public func animateContentScale(from: CGFloat, to: CGFloat, duration: Double, spring: Bool = false, completion: ((Bool) -> Void)? = nil) {
        if spring {
            player.layer?.animateScaleSpring(from: from, to: to, duration: duration, removeOnCompletion: false, bounce: false, completion: completion)
        } else {
            player.layer?.animateScaleCenter(from: from, to: to, duration: duration, removeOnCompletion: false, completion: completion)
        }
    }

    public func updatePoint(_ point: NSPoint, transition: ContainedViewLayoutTransition) {
        self.animationPoint = point
        self.updateLayout(size: frame.size, transition: transition)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}
