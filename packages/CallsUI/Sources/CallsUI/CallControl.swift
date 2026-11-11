import Cocoa
import TGUIKit
import TelegramMedia
import TelegramTheme
import LocalAnimations
import ColorPalette
import Localization

public struct CallControlData {
    public enum Mode: Equatable {
        case normal(NSColor, CGImage)
        case visualEffect(CGImage)
        case animated(LocalAnimatedSticker, NSColor)
    }
    
    public let text: String?
    public let mode: Mode
    public let iconSize: NSSize

    public init(text: String?, mode: Mode, iconSize: NSSize) {
        self.text = text
        self.mode = mode
        self.iconSize = iconSize
    }
    
    public func isProperView(_ view: NSView?) -> Bool {
        guard let view = view else {
            return false
        }
        switch mode {
        case .visualEffect:
            return view is NSVisualEffectView
        case .animated:
            return view is LottiePlayerView
        case .normal:
            return !(view is LottiePlayerView) && !(view is NSVisualEffectView)
        }
    }
}

public final class CallControl : Control {
    private let imageView: ImageView = ImageView()
    private var imageBackgroundView:NSView? = nil
    private var glassBackgroundView: NSView?
    private var glassFallbackView: View?
    private var textView: TextView?

    private var progressView: RadialProgressView?

    public var modalMorphSource: NSView {
        return imageBackgroundView ?? self
    }

    private var isLoading: Bool = false
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.imageView.isEventLess = true
        self.imageView.isAccessibilityDecorative = true
        self.layer?.masksToBounds = false
    }
    
    public func updateLoading(_ isLoading: Bool, animated: Bool) {
        self.isLoading = isLoading
        if isLoading {
            if progressView == nil {
                progressView = RadialProgressView(theme: RadialProgressTheme(backgroundColor: .clear, foregroundColor: .grayIcon), twist: true)
                
                addSubview(progressView!)
                
                if animated {
                    progressView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.4)
                }
            }
            let rect = imageBackgroundView?.bounds ?? NSMakeRect(0, 0, 40, 40)
            
            progressView?.frame = NSMakeRect(rect.minX + 1, rect.minY + 1, rect.width - 2, rect.height - 2)
            progressView?.state = .ImpossibleFetching(progress: 0.2, force: !animated)
        } else {
            if let progressView = self.progressView {
                self.progressView = nil
                progressView.state = .ImpossibleFetching(progress: 1.0, force: false)
                if animated {
                    progressView.layer?.animateAlpha(from: 1, to: 0, duration: 0.4, removeOnCompletion: false, completion: { [weak progressView] _ in
                        progressView?.removeFromSuperview()
                    })
                } else {
                    progressView.removeFromSuperview()
                }
            }
        }
    }
    
    public override var isEnabled: Bool {
        get {
            return super.isEnabled && !isLoading
        }
        set {
            super.isEnabled = newValue
        }
    }
    
    public override var mouseDownCanMoveWindow: Bool {
        return false
    }
    private var previousState: ControlState?
    
    public override func stateDidUpdate( _ state: ControlState) {
        let hasGlassStretch = glassBackgroundView != nil
        switch controlState {
        case .Highlight:
            imageBackgroundView?._change(opacity: 0.9)
            textView?.change(opacity: 0.9)
            if !hasGlassStretch {
                imageBackgroundView?.layer?.animateScaleCenter(from: 1, to: 0.95, duration: 0.2, removeOnCompletion: false)
            }
        default:
            imageBackgroundView?._change(opacity: 1.0)
            textView?.change(opacity: 1.0)
            if !hasGlassStretch, let previousState = previousState, previousState == .Highlight {
                imageBackgroundView?.layer?.animateScaleCenter(from: 0.95, to: 1.0, duration: 0.2)
            }
        }
        previousState = state
    }
    
    public func updateEnabled(_ enabled: Bool, animated: Bool) {
        self.isEnabled = enabled
        
        change(opacity: enabled ? 1 : 0.7, animated: animated)
    }
    
    public var size: NSSize {
        return imageBackgroundView?.frame.size ?? frame.size
    }

    private var accessibilityText: String?

    public override var accessibilityDefaultLabel: String? {
        return accessibilityText
    }
    
    public func updateWithData(_ data: CallControlData, animated: Bool) {
        self.accessibilityText = data.text
        
        if let text = data.text?.lowercased() {
            let current: TextView
            if let textView = self.textView {
                current = textView
            } else {
                current = TextView()
                self.textView = current
                current.isSelectable = false
                current.userInteractionEnabled = false
                current.isEventLess = true
                current.isAccessibilityDecorative = true
                addSubview(current)
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            let layout = TextViewLayout(.initialize(string: text, color: .white, font: .normal(12)), maximumNumberOfLines: 1)
            layout.measure(width: max(data.iconSize.width, 100))
            current.update(layout)
        } else {
            if let textView = self.textView {
                self.textView = nil
                textView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak textView] _ in
                    textView?.removeFromSuperview()
                })
            }
        }
        
        switch data.mode {
        case let .visualEffect(icon):
            if !data.isProperView(self.imageBackgroundView) {
                self.imageBackgroundView?.removeFromSuperview()
                self.imageBackgroundView = NSVisualEffectView(frame: NSMakeRect(0, 0, data.iconSize.width, data.iconSize.height))
                self.imageBackgroundView?.wantsLayer = true
                self.addSubview(self.imageBackgroundView!)
            }
            let view = self.imageBackgroundView as! NSVisualEffectView
            
            view.material = .light
            view.state = .active
            view.blendingMode = .withinWindow
            
            imageView.isHidden = false
            imageView.animates = animated
            imageView.image = icon
            imageView.setFrameSize(data.iconSize)
            
        case let .normal(color, icon):
            if !data.isProperView(self.imageBackgroundView) {
                self.imageBackgroundView?.removeFromSuperview()
                self.imageBackgroundView = NSView(frame: NSMakeRect(0, 0, data.iconSize.width, data.iconSize.height))
                self.imageBackgroundView?.wantsLayer = true
                self.addSubview(self.imageBackgroundView!)
            }
            imageView.isHidden = false
            imageView.animates = animated
            imageView.image = icon
            imageView.setFrameSize(data.iconSize)

            self.imageBackgroundView?.background = .clear
            updateGlassBackground(size: data.iconSize, tintColor: color, needsFallback: true)

        case let .animated(value, color):
            if !data.isProperView(self.imageBackgroundView) {
                self.imageBackgroundView?.removeFromSuperview()
                self.imageBackgroundView = LottiePlayerView(frame: NSMakeRect(0, 0, data.iconSize.width, data.iconSize.height))
                self.imageBackgroundView?.wantsLayer = true
                self.addSubview(self.imageBackgroundView!)
            }
            imageView.isHidden = true
            let player = self.imageBackgroundView as? LottiePlayerView
            if let animationData = value.data {
                let policy: LottiePlayPolicy
                if animated {
                    policy = .toEnd(from: 1)
                } else {
                    policy = .toEnd(from: .max)
                }
                player?.set(LottieAnimation(compressed: animationData, key: .init(key: .bundle(value.rawValue), size: data.iconSize), type: .lottie, cachePurpose: .none, playPolicy: policy, colors: [.init(keyPath: "", color: NSColor(0xffffff))], runOnQueue: .mainQueue()))
            }
            self.imageBackgroundView?.background = .clear
            updateGlassBackground(size: data.iconSize, tintColor: color, needsFallback: true)

        }


        imageView.removeFromSuperview()
        self.imageBackgroundView?.addSubview(imageView)
        
        imageBackgroundView!._change(size: data.iconSize, animated: animated)
        imageBackgroundView!.layer?.cornerRadius = data.iconSize.height / 2
        
        
        if let textView = self.textView {
            change(size: NSMakeSize(data.iconSize.width, data.iconSize.height + 5 + textView.frame.height), animated: animated)
            
            imageView._change(pos: imageBackgroundView!.focus(imageView.frame.size).origin, animated: animated)
            textView._change(pos: NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - textView.frame.width) / 2), imageBackgroundView!.frame.height + 5), animated: animated)
            imageBackgroundView!._change(pos: NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - imageBackgroundView!.frame.width) / 2), 0), animated: animated)
        } else {
            change(size: data.iconSize, animated: animated)
            imageView._change(pos: imageBackgroundView!.focus(imageView.frame.size).origin, animated: animated)
            imageBackgroundView!._change(pos: focus(imageBackgroundView!.frame.size).origin, animated: animated)
        }
        
        needsLayout = true
    }
    
    private func updateGlassBackground(size: NSSize, tintColor: NSColor, needsFallback: Bool = false) {
        if glassFallbackView == nil, needsFallback {
            let fallback = View(frame: NSMakeRect(0, 0, size.width, size.height))
            fallback.wantsLayer = true
            fallback.layer?.cornerRadius = size.height / 2
            if let imageBackgroundView = imageBackgroundView {
                addSubview(fallback, positioned: .below, relativeTo: imageBackgroundView)
            } else {
                addSubview(fallback)
            }
            glassFallbackView = fallback
        }
        glassFallbackView?.background = tintColor

        if glassBackgroundView == nil {
            let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: size.height / 2, hasShadow: true, hasBorder: true, forceAppearance: .forceDark)
            glassBackgroundView = glass
            if let imageBackgroundView = imageBackgroundView {
                addSubview(glass, positioned: .below, relativeTo: imageBackgroundView)
            } else {
                addSubview(glass)
            }
            self.stretchReferenceView = glass
        }
        (glassBackgroundView as? LiquidGlassView)?.customTint = tintColor
    }

    public override func layout() {
        super.layout()

        imageView.center()
        if let imageBackgroundView = imageBackgroundView {
            if let textView = textView {
                imageBackgroundView.centerX(y: 0)
                textView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - textView.frame.width) / 2), imageBackgroundView.frame.height + 5))
            } else {
                imageBackgroundView.center()
            }
            glassBackgroundView?.frame = imageBackgroundView.frame
            glassFallbackView?.frame = imageBackgroundView.frame
        }

    }

    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
