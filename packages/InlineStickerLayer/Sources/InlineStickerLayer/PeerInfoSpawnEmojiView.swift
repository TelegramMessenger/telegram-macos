import Cocoa
import InputView
import TelegramUtils
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramMediaResources
import TelegramTheme
import TelegramContext
import LokiRng
#if SHARE
import InlineStickersShare
#else
import InlineStickers
#endif
private func windowFunction(t: CGFloat) -> CGFloat {
    return bezierPoint(0.6, 0.0, 0.4, 1.0, t)
}

public func patternScaleValueAt(fraction: CGFloat, t: CGFloat, reverse: Bool) -> CGFloat {
    let windowSize: CGFloat = 0.8

    let effectiveT: CGFloat
    let windowStartOffset: CGFloat
    let windowEndOffset: CGFloat
    if reverse {
        effectiveT = 1.0 - t
        windowStartOffset = 1.0
        windowEndOffset = -windowSize
    } else {
        effectiveT = t
        windowStartOffset = -windowSize
        windowEndOffset = 1.0
    }

    let windowPosition = (1.0 - fraction) * windowStartOffset + fraction * windowEndOffset
    let windowT = max(0.0, min(windowSize, effectiveT - windowPosition)) / windowSize
    let localT = 1.0 - windowFunction(t: windowT)

    return localT
}

open class PeerInfoSpawnEmojiView : View {
    private var patternTarget: InlineStickerItemLayer?

    private let avatarBackgroundPatternContainer: CALayer = SimpleLayer()

    private var avatarPatternContentLayers:[SimpleLayer] = []
    private var patternColor: NSColor = .clear

    open var _alpha: CGFloat? = nil

    /// Like the iOS cover of a coloured profile: the shapes are black at up to 60% fading towards the edge, in the overlay blend mode, so they read as a darker shade of the cover.
    open var darkensCover: Bool = false

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.addSublayer(avatarBackgroundPatternContainer)
        avatarBackgroundPatternContainer.frame = NSMakeRect(frameRect.width / 2, frameRect.height / 2 - 30, frameRect.width, frameRect.height)

        self.layer?.masksToBounds = false
        avatarBackgroundPatternContainer.masksToBounds = false

    }

    open func set(fileId: Int64, color: NSColor, context: any AccountContextProtocol, inlinePacksContext: InlineStickersContext, animated: Bool) {
        let color: NSColor = self.darkensCover ? .black : color
        self.patternColor = color
        if patternTarget?.fileId != fileId || patternTarget?.textColor != color {
            let patternTarget:InlineStickerItemLayer = .init(account: context.account, inlinePacksContext: inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: clown), size: NSMakeSize(64, 64), playPolicy: .loop, textColor: color, contentDidUpdate: { [weak self] content in
                self?.updatePatternLayerImages(content)
            })
            patternTarget.noDelayBeforeplay = true
            patternTarget.isPlayable = true

            self.patternTarget = patternTarget
        }
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        updateLayout(size: frame.size, transition: transition)
    }

    open var fraction: CGFloat = 0 {
        didSet {
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
    }

    open func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        avatarBackgroundPatternContainer.frame = NSMakeRect(size.width / 2, size.height / 2 - 30, size.width, size.height)
        var avatarBackgroundPatternLayerCount = 0
        let lokiRng = LokiRng(seed0: 123, seed1: 0, seed2: 0)
        for row in 0 ..< 4 {
            let avatarPatternCount = row % 2 == 0 ? 9 : 9
            let avatarPatternAngleSpan: CGFloat = CGFloat.pi * 2.0 / CGFloat(avatarPatternCount - 1)

            for i in 0 ..< avatarPatternCount - 1 {
                let baseItemDistance: CGFloat = 80 + CGFloat(row) * 28.0

                let itemDistanceFraction = max(0.0, min(1.0, baseItemDistance / 140.0))
                let itemScaleFraction = patternScaleValueAt(fraction: fraction, t: itemDistanceFraction, reverse: false)
                let itemDistance = baseItemDistance * (1.0 - itemScaleFraction) + 20.0 * itemScaleFraction

                var itemAngle = -CGFloat.pi * 0.5 + CGFloat(i) * avatarPatternAngleSpan
                if row % 2 != 0 {
                    itemAngle += avatarPatternAngleSpan * 0.5
                }
                let itemPosition = CGPoint(x: cos(itemAngle) * itemDistance, y: sin(itemAngle) * itemDistance)

                let itemScale: CGFloat = 0.7 + CGFloat(lokiRng.next()) * (1.0 - 0.7)
                let itemSize: CGFloat = floor(26.0 * itemScale)
                let itemFrame = CGSize(width: itemSize, height: itemSize).centered(around: itemPosition)

                let itemLayer: SimpleLayer
                if self.avatarPatternContentLayers.count > avatarBackgroundPatternLayerCount {
                    itemLayer = self.avatarPatternContentLayers[avatarBackgroundPatternLayerCount]
                } else {
                    itemLayer = SimpleLayer()
                    itemLayer.contents = self.patternTarget?.contents
                    self.avatarBackgroundPatternContainer.addSublayer(itemLayer)
                    self.avatarPatternContentLayers.append(itemLayer)
                }

                itemLayer.frame = itemFrame
                itemLayer.layerTintColor = patternColor.cgColor
                if self.darkensCover {
                    let ellipse = hypot(itemPosition.x / 190.0, itemPosition.y / 90.0)
                    itemLayer.compositingFilter = "overlayBlendMode"
                    transition.updateAlpha(layer: itemLayer, alpha: 0.6 * max(0.0, 1.0 - ellipse / sqrt(2.0)) * (1.0 - itemScaleFraction))
                } else {
                    itemLayer.compositingFilter = nil
                    transition.updateAlpha(layer: itemLayer, alpha: _alpha ?? (1.0 - CGFloat(row) / 5.0) * (1.0 - itemScaleFraction))
                }

                avatarBackgroundPatternLayerCount += 1
            }
        }
        if avatarBackgroundPatternLayerCount > self.avatarPatternContentLayers.count {
            for i in avatarBackgroundPatternLayerCount ..< self.avatarPatternContentLayers.count {
                self.avatarPatternContentLayers[i].removeFromSuperlayer()
            }
            self.avatarPatternContentLayers.removeSubrange(avatarBackgroundPatternLayerCount ..< self.avatarPatternContentLayers.count)
        }
    }

    open func animateIn(delay: Double = 0) {
        let center = NSValue(point: .zero)
        for layer in avatarPatternContentLayers {
            layer.animate(from: center, to: NSValue(point: layer.position), keyPath: "position", timingFunction: .spring, duration: 0.4, delay: delay)
        }
        avatarBackgroundPatternContainer.animate(from: NSNumber(value: 0), to: NSNumber(value: 1), keyPath: "opacity", timingFunction: .linear, duration: 0.01, delay: delay)
    }

    private func updatePatternLayerImages(_ image: CGImage) {
        for layer in avatarPatternContentLayers {
            layer.contents = image
        }
    }


    open override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
