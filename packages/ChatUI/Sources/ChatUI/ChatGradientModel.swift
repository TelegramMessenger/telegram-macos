import Cocoa
import TGUIKit

private let maskInset: CGFloat = 1.0


/// Identity of a composed cut-out, so `updateLayout` (which runs on every layout pass) only rebuilds
/// the bitmap when something it depends on actually changed.
private struct ChatBubbleCutKey: Equatable {
    let size: NSSize
    let bands: [ChatUnsupportedPapercutBand]
    let tailInsets: ChatUnsupportedPapercutTailInsets
    let mask: ObjectIdentifier?
    let border: ObjectIdentifier?
}

final class ChatBubbleSliceLayer: SimpleLayer {
    override init() {
        super.init()
        anchorPoint = .zero
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var data: (CGImage, NSEdgeInsets)? {
        didSet {
            if let image = data {
                contentsScale = System.backingScale
                let imageSize = image.0.backingSize
                let insets = image.1
                let halfPixelFudge: CGFloat = 0.49
                let otherPixelFudge: CGFloat = 0.02
                var contentsCenter: CGRect = NSMakeRect(0.0, 0.0, 1.0, 1.0)
                if insets.left > 0 || insets.right > 0 {
                    contentsCenter.origin.x = (insets.left + halfPixelFudge) / imageSize.width
                    contentsCenter.size.width = (imageSize.width - (insets.left + insets.right + 1.0) + otherPixelFudge) / imageSize.width
                }
                if insets.top > 0 || insets.bottom > 0 {
                    contentsCenter.origin.y = (insets.top + halfPixelFudge) / imageSize.height
                    contentsCenter.size.height = (imageSize.height - (insets.top + insets.bottom + 1.0) + otherPixelFudge) / imageSize.height
                }
                self.contentsGravity = .resize
                self.contentsCenter = contentsCenter
                self.contents = image.0
            } else {
                self.contents = nil
            }
        }
    }
}

public final class ChatMessageBubbleBackdrop: NSView {
    private var backgroundContent: SimpleLayer?
    private let borderLayer = ChatBubbleSliceLayer()
    private var maskLayer: ChatBubbleSliceLayer?

    private var lastUpdate: (rect: CGRect, containerSize: CGSize, rotated: Bool)?

    private var maskData: (CGImage, NSEdgeInsets)?
    private var borderData: (CGImage, NSEdgeInsets)?
    private var cutZones: [CGRect] = []
    private var cutIncoming: Bool = true
    private var appliedCut: ChatBubbleCutKey?
    private var currentSize: NSSize = .zero

    var gradientLayer: CALayer? {
        return self.backgroundContent
    }

    public init() {
        
        super.init(frame: NSZeroRect)
        autoresizingMask = []
        autoresizesSubviews = false
        wantsLayer = true
        self.layer?.masksToBounds = true
        self.layer?.addSublayer(self.borderLayer)
        self.layer?.disableActions()
    }
    
    public required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let layer = maskLayer {
            transition.updateFrame(layer: layer, frame: size.bounds)
        }
        transition.updateFrame(layer: borderLayer, frame: size.bounds)
        self.currentSize = size
        self.applyImages()
    }

    /// Bands of the bubble to erase, in this view's coordinates. Empty — the overwhelmingly common case
    /// — leaves the plain 9-sliced bubble mask untouched; non-empty composes an exact-size mask with
    /// the torn bands cleared out of it, so the wallpaper shows through the bubble.
    public func setCutBands(_ zones: [CGRect], incoming: Bool) {
        if self.cutZones == zones, self.cutIncoming == incoming {
            return
        }
        self.cutZones = zones
        self.cutIncoming = incoming
        // Callers set the bubble's frame immediately before this (both change together while a rich
        // message streams), so take the size from the frame rather than waiting for `updateLayout` —
        // otherwise every frame composes the mask twice, once at the stale size.
        self.currentSize = self.frame.size
        self.applyImages()
    }

    private var appliedType: (image: CGImage?, imageInsets: NSEdgeInsets, border: CGImage?, borderInsets: NSEdgeInsets, background: CGImage)?
    
    public func setType(image: (CGImage, NSEdgeInsets)?, border: (CGImage, NSEdgeInsets)?, background: CGImage) {
        let noInsets = NSEdgeInsetsZero
        if let applied = self.appliedType, applied.image === image?.0, NSEdgeInsetsEqual(applied.imageInsets, image?.1 ?? noInsets), applied.border === border?.0, NSEdgeInsetsEqual(applied.borderInsets, border?.1 ?? noInsets), applied.background === background {
            return
        }
        self.appliedType = (image?.0, image?.1 ?? noInsets, border?.0, border?.1 ?? noInsets, background)
        lastUpdate = nil
        if let _ = image {
            if self.maskLayer == nil {
                let maskLayer = ChatBubbleSliceLayer()
                maskLayer.frame = self.bounds
                self.maskLayer = maskLayer
                self.layer?.mask = maskLayer
            }
        } else {
            if let _ = self.maskLayer {
                self.layer?.mask = nil
                self.maskLayer = nil
            }
        }
        self.maskData = image
        self.borderData = border
        self.appliedCut = nil
        if image == nil {
            if let layer = self.backgroundContent {
                performSublayerRemoval(layer, animated: false)
            }
            self.backgroundContent = nil
        } else {
            let current: SimpleLayer
            if let layer = self.backgroundContent {
                current = layer
            } else {
                current = SimpleLayer()
                current.anchorPoint = .zero
                self.backgroundContent = current
                self.layer?.insertSublayer(current, below: self.borderLayer)
            }
            current.contents = background
        }

        self.applyImages()
    }

    private func applyImages() {
        let cuts: [ChatUnsupportedPapercutBand]
        if self.currentSize.width > 0.0, self.currentSize.height > 0.0 {
            cuts = ChatUnsupportedPapercutEdges.resolveBands(self.cutZones, backgroundSize: self.currentSize)
        } else {
            cuts = []
        }
        let tailInsets = ChatUnsupportedPapercutTailInsets(incoming: self.cutIncoming)
        // Size only participates when there is something to compose: the plain 9-sliced path is
        // size-independent, and re-assigning layer contents on every layout pass is exactly the cost
        // this early-out exists to avoid.
        let key = ChatBubbleCutKey(
            size: cuts.isEmpty ? .zero : self.currentSize,
            bands: cuts,
            tailInsets: tailInsets,
            mask: self.maskData.map { ObjectIdentifier($0.0) },
            border: self.borderData.map { ObjectIdentifier($0.0) }
        )
        if self.appliedCut == key {
            return
        }
        self.appliedCut = key

        guard !cuts.isEmpty else {
            self.maskLayer?.data = self.maskData
            self.borderLayer.data = self.borderData
            return
        }

        if let maskData = self.maskData {
            let composed = ChatMessageBubbleBackdrop.composeCut(maskData, size: self.currentSize, bands: cuts, tailInsets: tailInsets)
            self.maskLayer?.data = composed.map { ($0, NSEdgeInsets()) } ?? maskData
        } else {
            self.maskLayer?.data = nil
        }
        if let borderData = self.borderData {
            let composed = ChatMessageBubbleBackdrop.composeCut(borderData, size: self.currentSize, bands: cuts, tailInsets: tailInsets)
            self.borderLayer.data = composed.map { ($0, NSEdgeInsets()) } ?? borderData
        } else {
            self.borderLayer.data = nil
        }
    }

    /// 9-slices `data` to the exact backdrop size and erases the torn bands out of it. Assigned with
    /// zero cap insets, so `SImageView`'s `contentsCenter` degenerates to a 1:1 blit.
    private static func composeCut(
        _ data: (CGImage, NSEdgeInsets),
        size: NSSize,
        bands: [ChatUnsupportedPapercutBand],
        tailInsets: ChatUnsupportedPapercutTailInsets
    ) -> CGImage? {
        let source = NSImage(cgImage: data.0, size: data.0.backingSize)
        return generateImage(size, contextGenerator: { size, ctx in
            func drawSource() {
                let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphics
                source.drawInRect(rect: size.bounds, withCapInsets: data.1)
                NSGraphicsContext.restoreGraphicsState()
            }

            ctx.clear(size.bounds)
            drawSource()

            // The band geometry is authored top-down (it comes from view coordinates), the bitmap is
            // bottom-up: flip once and erase.
            ctx.saveGState()
            ctx.translateBy(x: 0.0, y: size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            for band in bands {
                ChatUnsupportedPapercutEdges.cutBand(in: ctx, band: band, tailInsets: tailInsets, restoreBubble: { ctx in
                    ctx.saveGState()
                    ctx.translateBy(x: 0.0, y: size.height)
                    ctx.scaleBy(x: 1.0, y: -1.0)
                    drawSource()
                    ctx.restoreGState()
                })
            }
            ctx.restoreGState()
        }, scale: System.backingScale)
    }


    public func update(rect: CGRect, within containerSize: CGSize, transition: ContainedViewLayoutTransition, rotated: Bool = false) {

        if let last = lastUpdate, last.rect == rect, last.containerSize == containerSize, last.rotated == rotated {
            return
        }

        if let backgroundContent = backgroundContent {
            let newFrame = CGRect(origin: CGPoint(x: -rect.minX, y: -rect.minY), size: containerSize)
            if case .immediate = transition {
                backgroundContent.frame = newFrame
            } else {
                transition.updateFrame(layer: backgroundContent, frame: newFrame)
            }
            if lastUpdate?.rotated != rotated, rotated {
                backgroundContent.setAffineTransform(backgroundContent.affineTransform().rotated(by: .pi))
                backgroundContent.frame = newFrame
            }
        }

        lastUpdate = (rect, containerSize, rotated)
    }

}
