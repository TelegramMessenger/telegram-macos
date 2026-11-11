import Cocoa
import AppKit
import ObjectiveC
import ObjcUtils

public enum ContainedViewLayoutTransitionCurve {
    case linear
    case easeInOut
    case easeOut
    case spring
    case legacy
}

public let listViewAnimationCurveSystem: (CGFloat) -> CGFloat = { t in
    return bezierPoint(0.23, 1.0, 0.32, 1.0, t)
}
public let listViewAnimationCurveEaseInOut: (CGFloat) -> CGFloat = { t in
    return bezierPoint(0.42, 0.0, 0.58, 1.0, t)
}

public let listViewAnimationCurveLinear: (CGFloat) -> CGFloat = { t in
    return t
}

public extension ContainedViewLayoutTransitionCurve {
    var timingFunction: CAMediaTimingFunctionName {
        switch self {
        case .easeInOut:
            return CAMediaTimingFunctionName.easeInEaseOut
        case .spring:
            return CAMediaTimingFunctionName.spring
        case .legacy:
            return CAMediaTimingFunctionName.easeInEaseOut
        case .linear:
            return CAMediaTimingFunctionName.linear
        case .easeOut:
            return CAMediaTimingFunctionName.easeOut
        }
    }
    func solve(at offset: CGFloat) -> CGFloat {
        switch self {
        case .easeInOut:
            return listViewAnimationCurveEaseInOut(offset)
        case .spring:
            return listViewAnimationCurveSystem(offset)
        case .legacy:
             return listViewAnimationCurveEaseInOut(offset)
        case .easeOut:
            return listViewAnimationCurveEaseInOut(offset)
        case .linear:
            return listViewAnimationCurveLinear(offset)
        }
    }
    var animationCurve: NSAnimation.Curve {
        switch self {
        case .easeInOut, .spring, .legacy:
            return .easeInOut
        case .easeOut:
            return .easeOut
        case .linear:
            return .linear
        }
    }
}







public enum ContainedViewLayoutTransition {
    case immediate
    case animated(duration: Double, curve: ContainedViewLayoutTransitionCurve)
    
    public var isAnimated: Bool {
        switch self {
        case .immediate:
            return false
        case .animated:
            return true
        }
    }
    public var duration: Double {
        switch self {
        case .immediate:
            return 0
        case let .animated(duration, _):
            return duration
        }
    }
    public var timingFunction:CAMediaTimingFunctionName  {
        switch self {
        case .immediate:
            return .linear
        case let .animated(_, curve):
            return curve.timingFunction
        }
    }
}



private func _walkLayerTree(_ layer: CALayer, _ visit: (CALayer) -> Void) {
    visit(layer)
    for sub in layer.sublayers ?? [] {
        _walkLayerTree(sub, visit)
    }
}

public extension NSView {
    /// Future / end frame: where the view will land once any in-flight
    /// `bounds` / `position` animation completes. Falls back to the model
    /// frame when no animation is installed. Useful for early-exit checks
    /// in transition.updateFrame so we don't redundantly re-animate to a
    /// destination already scheduled.
    var endFrame: CGRect {
        guard let layer = self.layer else { return self.frame }

        // Position end value (in superlayer / parent coords).
        let endPosition: CGPoint
        if let posAnim = layer.animation(forKey: "position") as? CABasicAnimation,
           let toPos = (posAnim.toValue as? NSValue)?.pointValue {
            endPosition = toPos
        } else {
            endPosition = layer.position
        }

        // Bounds end value (size + bounds origin in own coords).
        var endBounds: CGRect
        if let boundsAnim = layer.animation(forKey: "bounds") as? CABasicAnimation,
           let toBounds = (boundsAnim.toValue as? NSValue)?.rectValue {
            endBounds = toBounds
        } else {
            endBounds = layer.bounds
        }
        if let heightAnimation = layer.animation(forKey: "bounds.size.height") as? CABasicAnimation,
           let height = heightAnimation.toValue as? NSNumber {
            endBounds.size.height = CGFloat(height.doubleValue)
        }

        // Convert layer.position (anchored) → frame.origin.
        let anchor = layer.anchorPoint
        let originX = endPosition.x - anchor.x * endBounds.width
        let originY = endPosition.y - anchor.y * endBounds.height
        return CGRect(x: originX, y: originY, width: endBounds.width, height: endBounds.height)
    }
}

public extension ContainedViewLayoutTransition {
    func updateFrame(view: NSView, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            if view.frame != frame && view.endFrame != frame {
                view.frame = frame
            }
            completion?(true)
        case let .animated(duration, curve):
            if view.endFrame == frame {
                completion?(true)
                return
            }

            let curve = curve

            var useViewAnimation = false
            if view is NSVisualEffectView {
                useViewAnimation = true
            }
            if #available(macOS 26.0, *) {
                if view is LiquidGlassView {
                    useViewAnimation = true
                }
            }
            // GlassEffectAppearanceContainer and NSGlassEffectView need the
            // SAME NSAnimationContext-driven path: their frames are written
            // by GlassContainerView.setGhostFrame in lockstep with the
            // surrounding LiquidGlassView, but the SDK glass views ignore
            // _change(size:)/_change(pos:) — animator().frame is the only
            // route that produces visible interpolation.
            var isGlassPart = false
            if view is GlassEffectAppearanceContainer {
                useViewAnimation = true
                isGlassPart = true
            }
            if #available(macOS 26.0, *), view is NSGlassEffectView {
                useViewAnimation = true
                isGlassPart = true
            }
            
            if view is NSVisualEffectView {
                useViewAnimation = true
                isGlassPart = true
            }


            if useViewAnimation {
                if view.frame == frame {
                    completion?(true)
                    return
                }

                // LiquidGlassView: use legacy NSAnimationContext-driven path
                // and setAnimatorFrame so the animation propagates through
                // outer view → appearanceContainer → effectView in lockstep,
                // keeping the merged SDF surface in sync mid-flight.
                if let glass = view as? LiquidGlassView {
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = duration
                        if curve.timingFunction == .spring {
                            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 1.0 + 0.4 / 3.0, 1.0, 1.0)
                        } else {
                            ctx.timingFunction = .init(name: curve.timingFunction)
                        }
                        ctx.allowsImplicitAnimation = true
                        glass.setAnimatorFrame(frame)
                    }, completionHandler: {
                        completion?(true)
                    })
                    return
                }

                // GlassEffectAppearanceContainer / NSGlassEffectView: route
                // through NSAnimationContext + animator().frame. These types
                // sit inside a GlassContainerView as siblings of their owning
                // LiquidGlassView — the same animation block keeps all three
                // (outer wrapper + this view) in lockstep on the layer level.
                if isGlassPart {
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = duration
                        if curve.timingFunction == .spring {
                            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 1.0 + 0.4 / 3.0, 1.0, 1.0)
                        } else {
                            ctx.timingFunction = .init(name: curve.timingFunction)
                        }
                        ctx.allowsImplicitAnimation = true
                        view.animator().frame = frame
                    }, completionHandler: {
                        completion?(true)
                    })
                    return
                }
            }

            // Trigger shadow-layer animation for any NSGlassEffectView
            // descendants (e.g. inside a LiquidGlassView wrapper) BEFORE the
            // default _change path mutates view.frame.
            
   
            

            switch curve {
            case .legacy:
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = duration
                    if curve.timingFunction == .spring {
                        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 1.0 + 0.4 / 3.0, 1.0, 1.0)
                    } else {
                        ctx.timingFunction = .init(name: curve.timingFunction)
                    }
                    view.animator().frame = frame
                }, completionHandler: {
                    completion?(true)
                })
            default:
                
                if let view = view as? TableView {
                    view.change(size: frame.size, animated: true, duration: duration, timingFunction: curve.timingFunction, completion: { completed in
                        completion?(completed)
                    })
                    view.layer?.removeAnimation(forKey: "boundsOriginYAdditive")
                }
                
                var notifyOnOrigin: Bool = false
                var notifyOnSize: Bool = false
                if frame.size != view.frame.size {
                    notifyOnSize = true
                } else if frame.origin != view.frame.origin {
                    notifyOnOrigin = true
                } else {
                    completion?(true)
                }

                // Glass surfaces ignore mid-animation model frame changes (the SDF
                // compositor reads the model directly), so committing
                // origin/size up-front would snap the visible shape. Defer the
                // model write until the animation completes.

                view._change(size: frame.size, animated: true, duration: duration, timingFunction: curve.timingFunction, completion: { completed in
                    if notifyOnSize {
                        completion?(completed)
                    }
                })
                view._change(pos: frame.origin, animated: true, duration: duration, timingFunction: curve.timingFunction, completion: { completed in
                    if notifyOnOrigin {
                        completion?(completed)
                    }
                })
            }
            

        }
    }
    func updateFrame(layer: CALayer, frame: CGRect, completion: ((Bool) -> Void)? = nil, save: Bool = true, updatePosition: Bool = false) {
        switch self {
        case .immediate:
            layer.frame = frame
            if let completion = completion {
                completion(true)
            }
        case let .animated(duration, _):

            
            func animateSize(_ layer: CALayer) -> Void {
                var presentBounds:NSRect = layer.bounds
                let presentation = layer.presentation()
                if let presentation = presentation, layer.animation(forKey:"bounds") != nil {
                    presentBounds.size.width = NSWidth(presentation.bounds)
                    presentBounds.size.height = NSHeight(presentation.bounds)
                }
                layer.animateBounds(from: presentBounds, to: frame.size.bounds, duration: duration, timingFunction: timingFunction, completion: completion)
            }
            func animatePos(_ layer: CALayer) -> Void {
                var presentRect:NSPoint = layer.position
                let presentation = layer.presentation()
                if let presentation = presentation, layer.animation(forKey:"position") != nil {
                    presentRect.x = presentation.position.x
                    presentRect.y = presentation.position.y
                }
                layer.animatePosition(from: presentRect, to: frame.origin, duration: duration, timingFunction: timingFunction, completion: completion)
            }
            if layer.frame.origin != frame.origin {
                animatePos(layer)
            }
            if layer.frame.size != frame.size {
                animateSize(layer)
            }
            if save {
                if updatePosition {
                    layer.frame = frame.size.bounds
                    layer.position = frame.origin
                } else {
                    layer.frame = frame
                }
            }
            
        }
    }
    
       func updateTransformScale(layer: CALayer, scale: CGFloat, beginWithCurrentState: Bool = false, completion: ((Bool) -> Void)? = nil) {
           let t = layer.transform
           let currentScale = sqrt((t.m11 * t.m11) + (t.m12 * t.m12) + (t.m13 * t.m13))
           if currentScale.isEqual(to: scale) {
               if let completion = completion {
                   completion(true)
               }
               return
           }
           
           switch self {
           case .immediate:
               layer.transform = CATransform3DMakeScale(scale, scale, 1.0)
               if let completion = completion {
                   completion(true)
               }
           case let .animated(duration, _):
               let previousScale: CGFloat
               if beginWithCurrentState, let presentation = layer.presentation() {
                   let t = presentation.transform
                   previousScale = sqrt((t.m11 * t.m11) + (t.m12 * t.m12) + (t.m13 * t.m13))
               } else {
                   previousScale = currentScale
               }
            layer.animateScaleSpring(from: previousScale, to: scale, duration: duration, bounce: false, completion: { result in
                if let completion = completion {
                    completion(result)
                }
            })
           }
       }


    

    func updateAlpha(view: NSView, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            // For glass-aware views, write through alphaValue so AppKit
            // syncs both the wrapper and any reparented siblings
            // (appearanceContainer / effectView living in GlassContainerView).
            if Self.isGlassAware(view) {
                view.alphaValue = alpha
                if let liquid = view as? LiquidGlassView {
                    liquid.appearanceContainer.alphaValue = alpha
                    liquid.effectView?.alphaValue = alpha
                }
            } else {
                view.layer?.opacity = Float(alpha)
            }
            completion?(true)
        case let .animated(duration, curve):
            // Glass-aware views need NSAnimationContext + animator() so the
            // SDK's NSGlassEffectView family installs the right Core Animation
            // path. Plain layer.opacity animation flickers on those classes.
            if Self.isGlassAware(view) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = duration
                    if curve.timingFunction == .spring {
                        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 1.0 + 0.4 / 3.0, 1.0, 1.0)
                    } else {
                        ctx.timingFunction = .init(name: curve.timingFunction)
                    }
                    ctx.allowsImplicitAnimation = true
                    view.animator().alphaValue = alpha
                    if let liquid = view as? LiquidGlassView {
                        liquid.appearanceContainer.animator().alphaValue = alpha
                        liquid.effectView?.animator().alphaValue = alpha
                    }
                }, completionHandler: {
                    completion?(true)
                })
                return
            }
            let previousAlpha = view.layer?.presentation()?.opacity ?? view.layer?.opacity ?? 1
            view.layer?.opacity = Float(alpha)
            view.layer?.animateAlpha(from: CGFloat(previousAlpha), to: alpha, duration: duration, timingFunction: curve.timingFunction, completion: { result in
                completion?(result)
            })
        }
    }

    private static func isGlassAware(_ view: NSView) -> Bool {
        if view is NSVisualEffectView { return true }
        if view is GlassEffectAppearanceContainer { return true }
        if #available(macOS 26.0, *) {
            if view is LiquidGlassView { return true }
            if view is NSGlassEffectView { return true }
        }
        return false
    }
    
    func updateAlpha(layer: CALayer, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            layer.opacity = Float(alpha)
            if let completion = completion {
                completion(true)
            }
        case let .animated(duration, curve):
            let previousAlpha = layer.presentation()?.opacity ?? layer.opacity
            layer.opacity = Float(alpha)
            layer.animateAlpha(from: CGFloat(previousAlpha), to: alpha, duration: duration, timingFunction: curve.timingFunction, completion: { result in
                if let completion = completion {
                    completion(result)
                }
            })
        }
    }
    
//    func updatePosition(layer: CALayer, position: NSPoint, completion: ((Bool) -> Void)? = nil) {
//        switch self {
//        case .immediate:
//            layer.position = position
//            if let completion = completion {
//                completion(true)
//            }
//        case let .animated(duration, curve):
//            let previousAlpha = layer.presentation()?.opacity ?? layer.opacity
//            layer.position = position
//            layer.animateAlpha(from: CGFloat(previousAlpha), to: alpha, duration: duration, timingFunction: curve.timingFunction, completion: { result in
//                if let completion = completion {
//                    completion(result)
//                }
//            })
//        }
//    }

    
    func animatePositionWithKeyframes(layer: CALayer, keyframes: [CGPoint], removeOnCompletion: Bool = true, additive: Bool = false, completion: ((Bool) -> Void)? = nil) {
           switch self {
           case .immediate:
               completion?(true)
           case let .animated(duration, curve):
               layer.animateKeyframes(values: keyframes.map(NSValue.init(point:)), duration: duration, keyPath: "position", timingFunction: curve.timingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
           }
       }
    
    
    func setShapeLayerStrokeEnd(layer: CAShapeLayer, strokeEnd: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            layer.strokeEnd = strokeEnd
            completion?(true)
        case let .animated(duration, curve):
            let previousStrokeEnd = layer.strokeEnd
            layer.strokeEnd = strokeEnd
            
            layer.animate(
                from: previousStrokeEnd as NSNumber,
                to: strokeEnd as NSNumber,
                keyPath: "strokeEnd",
                timingFunction: curve.timingFunction,
                duration: duration,
                delay: 0.0,
                removeOnCompletion: true,
                additive: false,
                completion: completion
            )
        }
    }


}

public protocol ContainableController: AnyObject {
    var view: View! { get }
    
    func containerLayoutUpdated(transition: ContainedViewLayoutTransition)
}
