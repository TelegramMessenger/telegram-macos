import AppKit
import QuartzCore

final class LensSurface {
    static let renderOutset: CGFloat = 32

    static let backgroundInputs: Set<String> = [
        "inputSourceSublayerName", "inputInnerRefractionAmount", "inputInnerRefractionHeight",
        "inputOuterRefractionAmount", "inputOuterRefractionHeight", "inputRefractionOpacity",
        "inputBlurRadius", "inputBlurOpacity0", "inputBlurOpacity1", "inputBlurOpacity2", "inputBlurOpacity3",
        "inputFaceOpacity", "inputFaceColorMatrixWhite", "inputFaceColorMatrixBlack", "inputFaceColorMatrixSaturation",
        "inputFaceColorMatrixFillColor", "inputFaceColorMatrixMaxLuma", "inputFaceColorMatrixMaxLumaSDR",
        "inputBleedOpacity", "inputShadowOffset", "inputShadowAmount", "inputShadowHeight", "inputShadowOpacity",
        "inputShadowColorMatrixFillColor", "inputShadowRadius", "inputRingShadowOffset", "inputRingShadowStrokeWidth",
        "inputRingShadowBlurRadius", "inputRingShadowOpacity", "inputKeyFillHighlightHeight", "inputKeyFillHighlightAngle",
        "inputKeyFillHighlightSpread", "inputKeyFillHighlightSpreadSDR", "inputKeyFillHighlightAmount",
        "inputKeyFillHighlightEffectOffset", "inputKeyFillHighlightColorBias",
        "inputBlurFillLightenOpacity", "inputBlurFillDarkenOpacity", "inputBlurFillNormalOpacity",
    ]
    static let foregroundInputs: Set<String> = [
        "inputSourceSublayerName", "inputRefractionAmount", "inputRefractionHeight", "inputRefractionOffset",
        "inputAberrationAmount", "inputAberrationHeight", "inputAberrationOffset", "inputAberrationAngle",
        "inputEdgeStart", "inputEdgeEnd", "inputEdgeOpacityStart", "inputEdgeOpacityEnd",
    ]

    let backdrop: CALayer
    let surface = CALayer()
    let unlensedContent = CALayer()
    private let background: CALayer
    private let content = CALayer()
    private let foreground: CALayer
    private let highlight: CALayer
    private let contentMask = CAShapeLayer()
    private let backdropField: CALayer
    private let backgroundField: CALayer
    private let contentField: CALayer
    private let foregroundField: CALayer
    private let runtime: LensRuntime
    private var portals: [ObjectIdentifier: CALayer] = [:]
    private var unlensedPortals: [ObjectIdentifier: CALayer] = [:]

    var portalCount: Int {
        return portals.count
    }

    init?(runtime: LensRuntime) {
        guard let backgroundFilter = runtime.makeFilter("glassBackground", inputs: Self.backgroundInputs),
              let foregroundFilter = runtime.makeFilter("glassForeground", inputs: Self.foregroundInputs),
              let highlightFilter = runtime.makeFilter("vibrantColorMatrix", inputs: ["inputColorMatrix", "inputClamp"]),
              let backdropDisplacement = runtime.makeFilter("displacementMap", inputs: ["inputAmount", "inputSourceSublayerName"]),
              let contentDisplacement = runtime.makeFilter("displacementMap", inputs: ["inputAmount", "inputSourceSublayerName"]) else {
            return nil
        }
        self.runtime = runtime
        backdrop = runtime.layer("CABackdropLayer")
        background = runtime.layer("CABackdropLayer")
        foreground = runtime.layer("CABackdropLayer")

        let backdropEffect = runtime.effect("CASDFGlassDisplacementEffect")
        let contentEffect = runtime.effect("CASDFGlassDisplacementEffect")
        for effect in [backdropEffect, contentEffect] {
            effect.setValue(1.0, forKey: "curvature")
            effect.setValue(0.0, forKey: "angle")
            effect.setValue(0.0, forKey: "maskOffset")
        }
        backdropField = runtime.shape(size: .zero, radius: 0, effect: backdropEffect, name: "lensBackdropField")
        contentField = runtime.shape(size: .zero, radius: 0, effect: contentEffect, name: "lensContentField")
        func output() -> NSObject {
            let effect = runtime.effect("CASDFOutputEffect")
            effect.setValue(-10000.0, forKey: "minimum")
            effect.setValue(Self.renderOutset, forKey: "maximum")
            return effect
        }
        backgroundField = runtime.shape(size: .zero, radius: 0, effect: output(), name: "lensBackgroundField")
        foregroundField = runtime.shape(size: .zero, radius: 0, effect: output(), name: "lensForegroundField")
        let highlightEffect = runtime.effect("CASDFKeyFillHighlightEffect")
        highlightEffect.setValue(NSColor.white.cgColor, forKey: "keyColor")
        highlightEffect.setValue(NSColor.white.cgColor, forKey: "fillColor")
        for (key, value) in ["keyHeight": 1.0, "fillHeight": 1.0, "keyAngle": 0.0, "fillAngle": Double.pi,
                             "keySpread": 1.396263401595464, "fillSpread": 1.396263401595464,
                             "keyAmount": 0.5, "fillAmount": 0.5, "diffuseAmountScale": 0.15, "curvature": 0.75] {
            highlightEffect.setValue(value, forKey: key)
        }
        highlight = runtime.shape(size: .zero, radius: 0, effect: highlightEffect, name: "lensHighlight")
        let matrix: [Float] = [
            1.1201999, -0.1894, -0.019, 0, 0.1471,
            -0.0563, 0.98709995, -0.0191, 0, 0.1471,
            -0.0563, -0.1893, 1.1574, 0, 0.1471,
            0, 0, 0, 1, 0,
        ]
        let matrixValue = matrix.withUnsafeBufferPointer {
            NSValue(bytes: $0.baseAddress!, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
        }
        highlightFilter.setValue(matrixValue, forKey: "inputColorMatrix")
        highlightFilter.setValue(1.0, forKey: "inputClamp")
        highlight.filters = [highlightFilter]

        for (filter, name, field) in [
            (backgroundFilter, "lensBackground", backgroundField),
            (foregroundFilter, "lensForeground", foregroundField),
            (backdropDisplacement, "lensBackdrop", backdropField),
            (contentDisplacement, "lensContent", contentField),
        ] {
            filter.setValue(name, forKey: "name")
            filter.setValue(field.name!, forKey: "inputSourceSublayerName")
        }
        for key in ["inputOuterRefractionAmount", "inputOuterRefractionHeight", "inputRefractionOpacity", "inputBlurRadius",
                    "inputBlurOpacity0", "inputBlurOpacity1", "inputBlurOpacity2", "inputBlurOpacity3",
                    "inputFaceColorMatrixBlack", "inputBleedOpacity", "inputShadowHeight",
                    "inputBlurFillLightenOpacity", "inputBlurFillDarkenOpacity", "inputBlurFillNormalOpacity"] {
            backgroundFilter.setValue(0.0, forKey: key)
        }
        for key in ["inputFaceOpacity", "inputFaceColorMatrixWhite", "inputFaceColorMatrixSaturation",
                    "inputFaceColorMatrixMaxLuma", "inputFaceColorMatrixMaxLumaSDR"] {
            backgroundFilter.setValue(1.0, forKey: key)
        }
        backgroundFilter.setValue(NSColor.clear.cgColor, forKey: "inputFaceColorMatrixFillColor")
        backgroundFilter.setValue(NSColor.black.cgColor, forKey: "inputShadowColorMatrixFillColor")
        backgroundFilter.setValue(NSValue(size: NSSize(width: 0, height: 7)), forKey: "inputShadowOffset")
        for (key, value) in ["inputShadowOpacity": 0.001, "inputShadowRadius": 8.0, "inputRingShadowOffset": 8.0,
                             "inputRingShadowStrokeWidth": 4.0, "inputRingShadowBlurRadius": 3.0, "inputRingShadowOpacity": 0.1,
                             "inputKeyFillHighlightHeight": 1.0, "inputKeyFillHighlightAngle": Double.pi / 2,
                             "inputKeyFillHighlightSpread": Double.pi / 2, "inputKeyFillHighlightSpreadSDR": Double.pi * 2 / 3,
                             "inputKeyFillHighlightAmount": 0.5, "inputKeyFillHighlightEffectOffset": -1.0,
                             "inputKeyFillHighlightColorBias": -0.3] {
            backgroundFilter.setValue(value, forKey: key)
        }
        for (key, value) in ["inputRefractionAmount": 0.0, "inputRefractionHeight": 0.0, "inputRefractionOffset": 0.0,
                             "inputAberrationHeight": 0.0, "inputAberrationAngle": -Double.pi / 12,
                             "inputEdgeEnd": 0.0, "inputEdgeOpacityStart": 1.0, "inputEdgeOpacityEnd": 0.0] {
            foregroundFilter.setValue(value, forKey: key)
        }
        backdropDisplacement.setValue(0.0, forKey: "inputAmount")
        contentDisplacement.setValue(0.0, forKey: "inputAmount")
        backdrop.filters = [backdropDisplacement]
        background.filters = [backgroundFilter]
        content.filters = [contentDisplacement]
        foreground.filters = [foregroundFilter]
        backdrop.addSublayer(backdropField)
        background.addSublayer(backgroundField)
        content.addSublayer(contentField)
        foreground.addSublayer(foregroundField)
        contentField.zPosition = -1
        unlensedContent.name = "lensUnlensedContent"
        for layer in [surface, content, contentMask, unlensedContent] {
            layer.anchorPoint = .zero
            layer.masksToBounds = false
        }
        content.mask = contentMask
        contentMask.fillColor = NSColor.black.cgColor
        for layer in [background, content, foreground, highlight] {
            surface.addSublayer(layer)
        }
    }

    func update(frame: CGRect, progress: CGFloat, canvasSize: CGSize, sources: [NSView], scale: CGFloat, animation: LiquidGlassLensAnimation) {
        let radius = frame.height / 2
        let bounds = CGRect(origin: .zero, size: frame.size)
        let fieldBounds = bounds.insetBy(dx: -Self.renderOutset, dy: -Self.renderOutset)
        unlensedContent.frame = CGRect(origin: .zero, size: canvasSize)
        animation.frame(backdrop, frame.insetBy(dx: -Self.renderOutset, dy: -Self.renderOutset), boundsOrigin: fieldBounds.origin)
        animation.frame(surface, frame)
        for layer in [backdrop, background, foreground, highlight] {
            animation.update(layer, key: "opacity", value: Float(progress))
        }
        for layer in [content, contentMask] {
            animation.frame(layer, bounds)
            layer.contentsScale = scale
        }
        for layer in [background, foreground] {
            animation.frame(layer, fieldBounds, boundsOrigin: fieldBounds.origin)
            layer.contentsScale = scale
        }
        for field in [backdropField, backgroundField, contentField, foregroundField, highlight] {
            animation.frame(field, fieldBounds, boundsOrigin: fieldBounds.origin)
            field.contentsScale = scale
            if let shape = field.sublayers?.first {
                animation.frame(shape, bounds)
                animation.update(shape, key: "cornerRadius", value: radius)
                shape.contentsScale = scale
            }
        }
        for layer in [backdrop, background, foreground] {
            layer.setValue(scale, forKey: "scale")
        }
        animation.update(contentMask, key: "path", value: CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        animation.update(backdrop, key: "filters.lensBackdrop.inputAmount", value: 9 * progress)
        animation.update(backdropField, key: "effect.height", value: canvasSize.height * 0.75)
        animation.update(background, key: "filters.lensBackground.inputInnerRefractionAmount", value: -0.3 * radius)
        animation.update(background, key: "filters.lensBackground.inputInnerRefractionHeight", value: 0.2 * radius)
        animation.update(background, key: "filters.lensBackground.inputShadowAmount", value: 0.5 * radius)
        animation.update(content, key: "filters.lensContent.inputAmount", value: -0.4 * radius * progress)
        animation.update(contentField, key: "effect.height", value: 0.32 * radius)
        animation.update(foreground, key: "filters.lensForeground.inputAberrationAmount", value: frame.height / 19)
        animation.update(foreground, key: "filters.lensForeground.inputAberrationOffset", value: radius / 0.9)
        animation.update(foreground, key: "filters.lensForeground.inputEdgeStart", value: -0.4 * radius)
        updatePortals(sources: sources, frame: frame, progress: progress, scale: scale, animation: animation)
    }

    private func updatePortals(sources: [NSView], frame: CGRect, progress: CGFloat, scale: CGFloat, animation: LiquidGlassLensAnimation) {
        let identifiers = Set(sources.compactMap { $0.layer.map(ObjectIdentifier.init) })
        for identifier in Array(portals.keys) where !identifiers.contains(identifier) {
            portals.removeValue(forKey: identifier)?.setValue(nil, forKey: "sourceLayer")
            unlensedPortals.removeValue(forKey: identifier)?.setValue(nil, forKey: "sourceLayer")
        }
        for portal in content.sublayers ?? [] where portal !== contentField && !portals.values.contains(where: { $0 === portal }) {
            portal.removeFromSuperlayer()
        }
        for portal in unlensedContent.sublayers ?? [] where !unlensedPortals.values.contains(where: { $0 === portal }) {
            portal.removeFromSuperlayer()
        }
        for source in sources {
            guard let sourceLayer = source.layer else {
                continue
            }
            let identifier = ObjectIdentifier(sourceLayer)
            let portal: CALayer
            if let existing = portals[identifier] {
                portal = existing
            } else {
                portal = runtime.layer("CAPortalLayer")
                portal.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                portal.setValue(sourceLayer, forKey: "sourceLayer")
                portal.setValue(true, forKey: "hidesSourceLayer")
                portal.setValue(false, forKey: "matchesPosition")
                portal.setValue(false, forKey: "matchesTransform")
                content.addSublayer(portal)
                portals[identifier] = portal
                let original = runtime.layer("CAPortalLayer")
                original.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                original.setValue(sourceLayer, forKey: "sourceLayer")
                original.setValue(true, forKey: "hidesSourceLayer")
                original.setValue(false, forKey: "matchesPosition")
                original.setValue(false, forKey: "matchesTransform")
                unlensedContent.addSublayer(original)
                unlensedPortals[identifier] = original
            }
            portal.contentsScale = scale
            if let original = unlensedPortals[identifier] {
                original.frame = source.frame
                original.bounds = source.bounds
                original.contentsScale = scale
            }
            animation.update(portal, key: "bounds", value: NSValue(rect: source.bounds))
            animation.update(portal, key: "position", value: NSValue(point: CGPoint(x: source.frame.midX - frame.minX, y: source.frame.midY - frame.minY)))
            let magnification = 1 + 0.1 * progress
            animation.update(portal, key: "transform", value: NSValue(caTransform3D: CATransform3DMakeScale(magnification, magnification, 1)))
        }
    }

    func remove() {
        for portal in Array(portals.values) + Array(unlensedPortals.values) {
            portal.setValue(nil, forKey: "sourceLayer")
            portal.removeFromSuperlayer()
        }
        portals.removeAll()
        unlensedPortals.removeAll()
        backdrop.removeFromSuperlayer()
        unlensedContent.removeFromSuperlayer()
        surface.removeFromSuperlayer()
    }
}
