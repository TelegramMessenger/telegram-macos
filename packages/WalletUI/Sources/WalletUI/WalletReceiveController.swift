import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Postbox
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import WalletContext
import QRCodeUtils
import SceneEffects
import Metal
import MetalEngine
import AppAnalytics

private let receiveGradientColors: [NSColor] = [NSColor(rgb: 0x0079ff), NSColor(rgb: 0x46b2ff), NSColor(rgb: 0x46b2ff), NSColor(rgb: 0x067eff)]
private let receiveAccentColor = NSColor(rgb: 0x087cff)
private let receiveMutedGroupColor = NSColor(rgb: 0x8e8e93)
private enum WalletReceiveOnrampSessionResult {
    case unavailable
    case failed
    case session(String)
}

@available(macOS 10.15, *)
private func walletReceiveOnrampSession(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext?, address: String) -> Signal<WalletReceiveOnrampSessionResult, NoError> {
    return (context.engine.payments.getOnrampProviders(cryptoCurrency: "gram")
    |> map(Optional.init)
    |> `catch` { _ -> Signal<[OnrampProviderInfo]?, NoError> in
        return .single(nil)
    })
    |> mapToSignal { providers -> Signal<WalletReceiveOnrampSessionResult, NoError> in
        guard let providers else {
            return .single(.failed)
        }
        guard providers.contains(where: { $0.id == "wallet" }) else {
            return .single(.unavailable)
        }
        return context.engine.payments.createOnrampSession(
            provider: "wallet",
            cryptoCurrency: "gram",
            address: address,
            paymentMethod: nil,
            baseCurrency: walletContext?.stateValue.fiat.selectedCurrency.code,
            theme: nil,
            successReturnUrl: nil,
            failReturnUrl: nil
        )
        |> map { session -> WalletReceiveOnrampSessionResult in
            return .session(session.url)
        }
        |> `catch` { _ -> Signal<WalletReceiveOnrampSessionResult, NoError> in
            return .single(.failed)
        }
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    let copy: () -> Void
    let showQr: () -> Void
    let dismiss: () -> Void
    let buy: () -> Void

    init(context: any AccountContextProtocol, environment: WalletUIEnvironment, copy: @escaping () -> Void, showQr: @escaping () -> Void, dismiss: @escaping () -> Void, buy: @escaping () -> Void) {
        self.context = context
        self.environment = environment
        self.copy = copy
        self.showQr = showQr
        self.dismiss = dismiss
        self.buy = buy
    }
}

private struct State: Equatable {
    var address: String
    var isOwnWallet: Bool
    var displaysAddress: Bool = false
}

private let _id_receive = InputDataIdentifier("_id_receive")

let walletReceiveQrDiamondWidthRatio: CGFloat = 0.72

func walletReceiveQrCutoutFrame(moduleCount: Int, qrSize: NSSize, scale: CGFloat) -> NSRect {
    return qrCodeCutout(size: moduleCount, dimensions: qrSize, scale: scale).1
}

let walletReceiveQrIntroDelay = 0.03
let walletReceiveQrRevealDuration = 0.5
let walletReceiveQrDiamondIntroSpeed = 1.5
let walletReceiveQrDiamondIntroDuration = walletReceiveQrIntroDelay + (InteractiveDiamondIntro.duration - InteractiveDiamondIntro.delay) / walletReceiveQrDiamondIntroSpeed

struct WalletReceiveQrDiamondIntroFrame: Equatable {
    let lift: CGFloat
    let openingScale: CGFloat?
}

func walletReceiveQrDiamondIntroFrame(elapsed: Double) -> WalletReceiveQrDiamondIntroFrame? {
    guard elapsed < max(walletReceiveQrDiamondIntroDuration, walletReceiveQrIntroDelay + walletReceiveQrRevealDuration) else {
        return nil
    }
    let introTime = elapsed + InteractiveDiamondIntro.delay - walletReceiveQrIntroDelay
    let intro = InteractiveDiamondIntro(time: introTime, speed: walletReceiveQrDiamondIntroSpeed, damping: 0.64)
    let bounceAmplitude: CGFloat = intro.progress > 1.0 ? 0.49 : 1.0
    let scale = 1.0 + (intro.scale(from: 5.0, allowsOvershoot: true) - 1.0) * bounceAmplitude
    return WalletReceiveQrDiamondIntroFrame(lift: intro.lift * bounceAmplitude, openingScale: elapsed < walletReceiveQrDiamondIntroDuration ? scale : nil)
}

private final class WalletReceiveRowItem: GeneralRowItem {
    let environment: WalletUIEnvironment
    fileprivate let address: String
    fileprivate let displaysAddress: Bool
    fileprivate let isOwnWallet: Bool
    fileprivate let copyTitle: String
    fileprivate let showQrTitle: String
    fileprivate let captionLayout: TextViewLayout
    fileprivate let copiedLayout: TextViewLayout
    fileprivate let copyAction: () -> Void
    fileprivate let toggleAction: () -> Void
    fileprivate let dismissAction: () -> Void
    fileprivate let buyAction: () -> Void

    fileprivate let cardSize = NSMakeSize(256, 288)
    fileprivate let cardRadius: CGFloat = 20
    fileprivate let cardTop: CGFloat = 88
    fileprivate let qrInset: CGFloat = 10
    fileprivate let gridTopInset: CGFloat = 54
    fileprivate let gridWidth: CGFloat = 192
    fileprivate let gridRowHeight: CGFloat = 26
    fileprivate let actionHeight: CGFloat = 28
    fileprivate let actionBottomInset: CGFloat = 16
    fileprivate let captionSpacing: CGFloat = 44
    fileprivate let buySpacing: CGFloat = 26
    fileprivate let buyHeight: CGFloat = 52
    fileprivate let buySideInset: CGFloat = 30
    fileprivate let bottomInset: CGFloat = 24

    init(_ initialSize: NSSize, stableId: AnyHashable, environment: WalletUIEnvironment, address: String, displaysAddress: Bool, isOwnWallet: Bool, copyAction: @escaping () -> Void, toggleAction: @escaping () -> Void, dismissAction: @escaping () -> Void, buyAction: @escaping () -> Void) {
        self.environment = environment
        self.address = address
        self.displaysAddress = displaysAddress
        self.isOwnWallet = isOwnWallet
        self.copyAction = copyAction
        self.toggleAction = toggleAction
        self.dismissAction = dismissAction
        self.buyAction = buyAction

        let captionText: String
        if isOwnWallet {
            self.copyTitle = strings().walletReceiveControllerCopyAddress
            self.showQrTitle = strings().walletReceiveControllerShowQr
            captionText = strings().walletReceiveControllerCaption
        } else {
            self.copyTitle = strings().walletReceiveControllerCopyPeerAddress
            self.showQrTitle = strings().walletReceiveControllerShowPeerQr
            captionText = strings().walletReceiveControllerPeerCaption
        }
        let copiedText = strings().walletReceiveControllerAddressCopied

        self.captionLayout = TextViewLayout(.initialize(string: captionText, color: .white, font: .normal(15)), alignment: .center, alwaysStaticItems: true)
        self.copiedLayout = TextViewLayout(.initialize(string: copiedText, color: receiveAccentColor, font: .semibold(14)), alignment: .center, alwaysStaticItems: true)
        self.copiedLayout.measure(width: cardSize.width - 40)

        super.init(initialSize, stableId: stableId, viewType: .legacy)

        _ = makeSize(initialSize.width, oldWidth: 0)
    }

    fileprivate var addressGroups: [String] {
        return walletAddressGroups(address)
    }

    fileprivate var gridHeight: CGFloat {
        let rowCount = Int(ceil(CGFloat(addressGroups.count) / 3))
        return CGFloat(rowCount) * gridRowHeight
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        captionLayout.measure(width: width - buySideInset * 2)
        return true
    }

    override var height: CGFloat {
        let buy: CGFloat = isOwnWallet ? buySpacing + buyHeight : 0
        return cardTop + cardSize.height + captionSpacing + captionLayout.layoutSize.height + buy + bottomInset
    }

    override func viewClass() -> AnyClass {
        return WalletReceiveRowView.self
    }

    override var accessibilityLabel: String? {
        return captionLayout.attributedString.string.replacingOccurrences(of: "\n", with: " ")
    }
}

private final class WalletReceiveAddressRingView: NSView {
    private struct Configuration: Equatable {
        let address: String
        let size: NSSize
        let cardSize: NSSize
        let cardCornerRadius: CGFloat
        let pathOffset: CGFloat
        let color: NSColor
    }

    private struct Layout {
        let path: CGPath
        let length: CGFloat
        let glyphPaths: [CGPath]
        let phases: [CGFloat]
    }

    private static let animationSpeed: CGFloat = 18

    private var configuration: Configuration?
    private var ringLayout: Layout?
    private var glyphLayers: [CAShapeLayer] = []
    private var windowAttachment = WindowAttachment()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func update(address: String, size: NSSize, cardSize: NSSize, cardCornerRadius: CGFloat, pathOffset: CGFloat, color: NSColor) {
        let configuration = Configuration(address: address, size: size, cardSize: cardSize, cardCornerRadius: cardCornerRadius, pathOffset: pathOffset, color: color)
        guard configuration != self.configuration else {
            return
        }
        self.configuration = configuration
        rebuild()
    }

    private func rebuild() {
        for layer in glyphLayers {
            layer.removeFromSuperlayer()
        }
        glyphLayers = []
        ringLayout = nil
        guard let configuration, let ringLayout = Self.makeLayout(configuration) else {
            return
        }
        self.ringLayout = ringLayout
        let scale = window?.backingScaleFactor ?? 2
        for glyphPath in ringLayout.glyphPaths {
            let shape = CAShapeLayer()
            shape.path = glyphPath
            shape.fillColor = configuration.color.cgColor
            shape.bounds = CGRect(x: -16, y: -16, width: 32, height: 32)
            shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            shape.contentsScale = scale
            layer?.addSublayer(shape)
            glyphLayers.append(shape)
        }
        applyAnimations()
    }

    private func applyAnimations() {
        guard let ringLayout, ringLayout.length > 0, window != nil else {
            return
        }
        let duration = CFTimeInterval(ringLayout.length / Self.animationSpeed)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (index, shape) in glyphLayers.enumerated() {
            shape.removeAnimation(forKey: "ring")
            let animation = CAKeyframeAnimation(keyPath: "position")
            animation.path = ringLayout.path
            animation.calculationMode = .paced
            animation.rotationMode = .rotateAuto
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.timeOffset = duration * Double(ringLayout.phases[index])
            animation.isRemovedOnCompletion = false
            shape.add(animation, forKey: "ring")
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard windowAttachment.update(window) else {
            return
        }
        if window == nil {
            for shape in glyphLayers {
                shape.removeAnimation(forKey: "ring")
            }
        } else {
            let scale = window?.backingScaleFactor ?? 2
            for shape in glyphLayers {
                shape.contentsScale = scale
            }
            applyAnimations()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for shape in glyphLayers {
            shape.contentsScale = scale
        }
    }

    private static func makeLayout(_ configuration: Configuration) -> Layout? {
        let address = configuration.address
        let size = configuration.size
        guard !address.isEmpty, size.width > 1, size.height > 1 else {
            return nil
        }
        let groupedAddress = walletAddressGroups(address).joined(separator: " ").uppercased()
        guard !groupedAddress.isEmpty else {
            return nil
        }

        let baseFontSize = max(8.0, min(11.0, size.width / 31.0)) * 1.2
        let baseFont: NSFont = .semiboldMonospace(baseFontSize)

        let bounds = CGRect(origin: .zero, size: size)
        let cardRect = CGRect(x: bounds.midX - configuration.cardSize.width * 0.5, y: bounds.midY - configuration.cardSize.height * 0.5, width: configuration.cardSize.width, height: configuration.cardSize.height)
        let pathOffset = max(0, configuration.pathOffset)
        let desiredPathRect = cardRect.insetBy(dx: -pathOffset, dy: -pathOffset)
        let glyphInset = ceil((baseFont.ascender + abs(baseFont.descender)) * 0.5)
        let safeBounds = bounds.insetBy(dx: min(glyphInset, (bounds.width - 1) * 0.5), dy: min(glyphInset, (bounds.height - 1) * 0.5))
        let pathRect = desiredPathRect.intersection(safeBounds)
        guard !pathRect.isNull, !pathRect.isEmpty else {
            return nil
        }
        let radius = min(min(max(0, configuration.cardCornerRadius), min(cardRect.width, cardRect.height) * 0.5) + pathOffset, min(pathRect.width, pathRect.height) * 0.5)
        let horizontalLength = max(0, pathRect.width - radius * 2)
        let verticalLength = max(0, pathRect.height - radius * 2)
        let length = horizontalLength * 2 + verticalLength * 2 + CGFloat.pi * radius * 2
        let halfLength = length * 0.5
        guard halfLength > 0 else {
            return nil
        }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: pathRect.midX, y: pathRect.maxY))
        path.addLine(to: CGPoint(x: pathRect.maxX - radius, y: pathRect.maxY))
        path.addArc(center: CGPoint(x: pathRect.maxX - radius, y: pathRect.maxY - radius), radius: radius, startAngle: .pi * 0.5, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: pathRect.maxX, y: pathRect.minY + radius))
        path.addArc(center: CGPoint(x: pathRect.maxX - radius, y: pathRect.minY + radius), radius: radius, startAngle: 0, endAngle: -.pi * 0.5, clockwise: true)
        path.addLine(to: CGPoint(x: pathRect.minX + radius, y: pathRect.minY))
        path.addArc(center: CGPoint(x: pathRect.minX + radius, y: pathRect.minY + radius), radius: radius, startAngle: -.pi * 0.5, endAngle: -.pi, clockwise: true)
        path.addLine(to: CGPoint(x: pathRect.minX, y: pathRect.maxY - radius))
        path.addArc(center: CGPoint(x: pathRect.minX + radius, y: pathRect.maxY - radius), radius: radius, startAngle: .pi, endAngle: .pi * 0.5, clockwise: true)
        path.addLine(to: CGPoint(x: pathRect.midX, y: pathRect.maxY))

        let unitText = "· \(groupedAddress) "
        guard let glyphLayout = WalletReceiveRowView.ringGlyphLayout(text: unitText, font: baseFont) else {
            return nil
        }
        let glyphScale: CGFloat = glyphLayout.width > halfLength ? halfLength / glyphLayout.width * 0.99 : 1.0
        guard glyphScale > 0, let firstItem = glyphLayout.items.first else {
            return nil
        }
        let tracking = max(0, (halfLength - glyphLayout.width * glyphScale) / CGFloat(glyphLayout.items.count))
        let firstCenter = (firstItem.position.x + firstItem.advance * 0.5) * glyphScale

        var glyphPaths: [CGPath] = []
        var phases: [CGFloat] = []
        for copyIndex in 0 ..< 2 {
            let copyOffset = CGFloat(copyIndex) * halfLength
            for itemIndex in 0 ..< glyphLayout.items.count {
                let item = glyphLayout.items[itemIndex]
                var transform = CGAffineTransform(scaleX: glyphScale, y: glyphScale)
                    .translatedBy(x: -item.advance * 0.5, y: (CTFontGetDescent(item.font) - CTFontGetAscent(item.font)) * 0.5)
                guard let glyphPath = CTFontCreatePathForGlyph(item.font, item.glyph, &transform) else {
                    continue
                }
                let centerOffset = (item.position.x + item.advance * 0.5) * glyphScale - firstCenter
                let distance = copyOffset + centerOffset + CGFloat(itemIndex) * tracking
                var phase = distance.truncatingRemainder(dividingBy: length) / length
                if phase < 0 {
                    phase += 1
                }
                glyphPaths.append(glyphPath)
                phases.append(phase)
            }
        }
        guard !glyphPaths.isEmpty else {
            return nil
        }
        return Layout(path: path, length: length, glyphPaths: glyphPaths, phases: phases)
    }
}

private final class WalletReceiveRowView: TableRowView {
    fileprivate struct RingPerimeterSample {
        let point: CGPoint
        let tangent: CGVector
    }

    fileprivate struct RingPerimeter {
        let rect: CGRect
        let radius: CGFloat
        let horizontalLength: CGFloat
        let verticalLength: CGFloat
        let cornerLength: CGFloat
        let length: CGFloat

        init?(rect inputRect: CGRect, radius proposedRadius: CGFloat) {
            let rect = inputRect.standardized
            guard rect.width > 0, rect.height > 0, proposedRadius.isFinite else {
                return nil
            }
            let radius = min(max(0, proposedRadius), min(rect.width, rect.height) * 0.5)
            let horizontalLength = max(0, rect.width - radius * 2)
            let verticalLength = max(0, rect.height - radius * 2)
            let cornerLength = CGFloat.pi * radius * 0.5
            let length = horizontalLength * 2 + verticalLength * 2 + cornerLength * 4
            guard length.isFinite, length > 0 else {
                return nil
            }
            self.rect = rect
            self.radius = radius
            self.horizontalLength = horizontalLength
            self.verticalLength = verticalLength
            self.cornerLength = cornerLength
            self.length = length
        }

        private func arcSample(center: CGPoint, angle: CGFloat) -> RingPerimeterSample {
            let sine = sin(angle)
            let cosine = cos(angle)
            return RingPerimeterSample(point: CGPoint(x: center.x + radius * cosine, y: center.y + radius * sine), tangent: CGVector(dx: -sine, dy: cosine))
        }

        func sample(at distance: CGFloat) -> RingPerimeterSample {
            var normalized = distance.isFinite ? distance.truncatingRemainder(dividingBy: length) : 0
            if normalized < 0 {
                normalized += length
            }
            var segment = normalized + horizontalLength * 0.5
            if segment >= length {
                segment -= length
            }
            if horizontalLength > 0, segment < horizontalLength {
                return RingPerimeterSample(point: CGPoint(x: rect.minX + radius + segment, y: rect.minY), tangent: CGVector(dx: 1, dy: 0))
            }
            segment -= horizontalLength
            if cornerLength > 0, segment < cornerLength {
                return arcSample(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), angle: -.pi * 0.5 + segment / radius)
            }
            segment -= cornerLength
            if verticalLength > 0, segment < verticalLength {
                return RingPerimeterSample(point: CGPoint(x: rect.maxX, y: rect.minY + radius + segment), tangent: CGVector(dx: 0, dy: 1))
            }
            segment -= verticalLength
            if cornerLength > 0, segment < cornerLength {
                return arcSample(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), angle: segment / radius)
            }
            segment -= cornerLength
            if horizontalLength > 0, segment < horizontalLength {
                return RingPerimeterSample(point: CGPoint(x: rect.maxX - radius - segment, y: rect.maxY), tangent: CGVector(dx: -1, dy: 0))
            }
            segment -= horizontalLength
            if cornerLength > 0, segment < cornerLength {
                return arcSample(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), angle: .pi * 0.5 + segment / radius)
            }
            segment -= cornerLength
            if verticalLength > 0, segment < verticalLength {
                return RingPerimeterSample(point: CGPoint(x: rect.minX, y: rect.maxY - radius - segment), tangent: CGVector(dx: 0, dy: -1))
            }
            segment -= verticalLength
            if cornerLength > 0, segment < cornerLength {
                return arcSample(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), angle: .pi + segment / radius)
            }
            return RingPerimeterSample(point: CGPoint(x: rect.minX + radius, y: rect.minY), tangent: CGVector(dx: 1, dy: 0))
        }
    }

    fileprivate struct RingGlyphItem {
        let glyph: CGGlyph
        let position: CGPoint
        let advance: CGFloat
        let font: CTFont
    }

    fileprivate static func ringGlyphLayout(text: String, font: NSFont) -> (items: [RingGlyphItem], width: CGFloat)? {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        var items: [RingGlyphItem] = []
        let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
        for runValue in glyphRuns {
            let run = runValue as! CTRun
            let glyphCount = CTRunGetGlyphCount(run)
            if glyphCount == 0 {
                continue
            }
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            let range = CFRangeMake(0, glyphCount)
            CTRunGetGlyphs(run, range, &glyphs)
            CTRunGetPositions(run, range, &positions)
            CTRunGetAdvances(run, range, &advances)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName] as! CTFont? else {
                continue
            }
            for index in 0 ..< glyphCount {
                items.append(RingGlyphItem(glyph: glyphs[index], position: positions[index], advance: max(0, advances[index].width), font: runFont))
            }
        }
        items.sort { $0.position.x < $1.position.x }
        guard !items.isEmpty else {
            return nil
        }
        var width: CGFloat = 0
        for item in items {
            width = max(width, item.position.x + item.advance)
        }
        guard width.isFinite, width > 0 else {
            return nil
        }
        return (items, width)
    }

    fileprivate func walletReceiveAddressRingImage(address: String, size: NSSize, cardSize: NSSize, cardCornerRadius: CGFloat, pathOffset: CGFloat, color: NSColor) -> CGImage? {
        guard !address.isEmpty, size.width > 1, size.height > 1 else {
            return nil
        }

        let groupedAddress = walletAddressGroups(address).joined(separator: " ").uppercased()
        guard !groupedAddress.isEmpty else {
            return nil
        }

        let baseFontSize = max(8.0, min(11.0, size.width / 31.0)) * 1.2
        let baseFont: NSFont = .semiboldMonospace(baseFontSize)

        let bounds = CGRect(origin: .zero, size: size)
        let cardRect = CGRect(x: bounds.midX - cardSize.width * 0.5, y: bounds.midY - cardSize.height * 0.5, width: cardSize.width, height: cardSize.height)
        let desiredPathRect = cardRect.insetBy(dx: -pathOffset, dy: -pathOffset)
        let glyphInset = ceil((baseFont.ascender + abs(baseFont.descender)) * 0.5)
        let safeBounds = bounds.insetBy(dx: min(glyphInset, (bounds.width - 1) * 0.5), dy: min(glyphInset, (bounds.height - 1) * 0.5))
        let pathRect = desiredPathRect.intersection(safeBounds)
        guard !pathRect.isNull, !pathRect.isEmpty else {
            return nil
        }
        guard let perimeter = RingPerimeter(rect: pathRect, radius: min(max(0, cardCornerRadius), min(cardRect.width, cardRect.height) * 0.5) + pathOffset) else {
            return nil
        }
        let halfLength = perimeter.length * 0.5
        guard halfLength > 0 else {
            return nil
        }

        let unitText = "· \(groupedAddress) "
        guard let glyphLayout = Self.ringGlyphLayout(text: unitText, font: baseFont) else {
            return nil
        }
        let glyphScale: CGFloat = glyphLayout.width > halfLength ? halfLength / glyphLayout.width * 0.99 : 1.0
        guard glyphScale > 0 else {
            return nil
        }
        let tracking = max(0, (halfLength - glyphLayout.width * glyphScale) / CGFloat(glyphLayout.items.count))
        guard let firstItem = glyphLayout.items.first else {
            return nil
        }
        let firstCenter = (firstItem.position.x + firstItem.advance * 0.5) * glyphScale

        return generateImage(size, rotatedContext: { size, ctx in
            ctx.clear(CGRect(origin: .zero, size: size))
            ctx.setFillColor(color.cgColor)
            ctx.setTextDrawingMode(.fill)
            for copyIndex in 0 ..< 2 {
                let copyOffset = CGFloat(copyIndex) * halfLength
                for itemIndex in 0 ..< glyphLayout.items.count {
                    let item = glyphLayout.items[itemIndex]
                    let centerOffset = (item.position.x + item.advance * 0.5) * glyphScale - firstCenter
                    let distance = copyOffset + centerOffset + CGFloat(itemIndex) * tracking
                    let sample = perimeter.sample(at: distance)
                    let angle = atan2(sample.tangent.dy, sample.tangent.dx)

                    ctx.saveGState()
                    ctx.translateBy(x: sample.point.x, y: sample.point.y)
                    ctx.rotate(by: angle)
                    ctx.scaleBy(x: glyphScale, y: -glyphScale)
                    ctx.textMatrix = .identity

                    var glyph = item.glyph
                    var glyphPosition = CGPoint(x: -item.advance * 0.5, y: (CTFontGetDescent(item.font) - CTFontGetAscent(item.font)) * 0.5)
                    CTFontDrawGlyphs(item.font, &glyph, &glyphPosition, 1, ctx)
                    ctx.restoreGState()
                }
            }
        })
    }

    private let gradientLayer = SimpleGradientLayer()
    private let closeButton = ImageButton()
    private let ringView = ImageView()
    private let animatedRingView = WalletReceiveAddressRingView(frame: .zero)
    private var ringImageKey: String? = nil
    private let cardView = View()
    private let qrContainer = View()
    private let qrView = ImageView()
    #if arch(arm64)
    private let qrDiamondView = InteractiveDiamondView(frame: NSZeroRect)
    private var qrDiamondFrame: NSRect = .zero
    private var qrRevealView: WalletReceiveQrRevealView?
    private var qrRevealStartTime: CFTimeInterval?
    private var qrRevealAnimator: ConstantDisplayLinkAnimator?
    private var qrDidAnimateIn = false
    private var qrRefractionImage: CGImage?
    private var qrRefractionTexture: MTLTexture?
    #endif
    private var qrModuleCount: Int?
    private let gridView = View()
    private var gridLabels: [TextView] = []
    private let copiedView = TextView()
    private let actionButton = TextButton()
    private let captionView = TextView()
    private let buyButton = TextButton()
    private let buyIconView = ImageView()
    private let buyTextView = TextView()
    private let qrDisposable = MetaDisposable()
    private var qrAddress: String?
    private var cardFlipContainer: LayerBackedView?

    private static let cardFlipDuration: Double = 0.4
    private static let cardFlipMinimumScale: CGFloat = 0.9
    private static let cardFlipMaximumShadeOpacity: CGFloat = 0.55

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            finishCardFlip()
        }
        updateQrDiamond()
    }

    private func finishCardFlip() {
        guard let container = cardFlipContainer else {
            return
        }
        cardFlipContainer = nil
        container.layer?.removeAllAnimations()
        for face in container.subviews {
            face.layer?.removeAllAnimations()
        }
        cardView.removeFromSuperview()
        addSubview(cardView, positioned: .above, relativeTo: animatedRingView)
        container.removeFromSuperview()
        needsLayout = true
    }

    private func makeCardFlipFace(cornerRadius: CGFloat, bounds: NSRect) -> (face: LayerBackedView, shade: View) {
        let face = LayerBackedView()
        face.frame = bounds
        face.layer?.isDoubleSided = false
        face.layer?.masksToBounds = true
        face.layer?.cornerRadius = cornerRadius
        face._anchorPoint = NSMakePoint(0.5, 0.5)
        let shade = View(frame: bounds)
        shade.backgroundColor = NSColor(rgb: 0x003a80)
        shade.layer?.cornerRadius = cornerRadius
        shade.layer?.opacity = 0
        shade.isEventLess = true
        return (face, shade)
    }

    private func animateCardFlip(previousSnapshot: CGImage, cornerRadius: CGFloat) {
        finishCardFlip()
        let cardFrame = cardView.frame
        let container = LayerBackedView()
        container.frame = cardFrame
        container.layer?.masksToBounds = false
        container._anchorPoint = NSMakePoint(0.5, 0.5)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 650.0
        container._sublayerTransform = perspective
        addSubview(container, positioned: .above, relativeTo: cardView)
        cardFlipContainer = container

        let outgoing = makeCardFlipFace(cornerRadius: cornerRadius, bounds: container.bounds)
        let outgoingImage = ImageView(frame: container.bounds)
        outgoingImage.image = previousSnapshot
        outgoingImage.isEventLess = true
        outgoingImage.isAccessibilityDecorative = true
        outgoing.face.addSubview(outgoingImage)
        outgoing.face.addSubview(outgoing.shade)

        let incoming = makeCardFlipFace(cornerRadius: cornerRadius, bounds: container.bounds)
        cardView.removeFromSuperview()
        cardView.frame = container.bounds
        incoming.face.addSubview(cardView)
        incoming.face.addSubview(incoming.shade)

        container.addSubview(outgoing.face)
        container.addSubview(incoming.face)

        let steps = 60
        let shadeValues: [NSNumber] = (0 ... steps).map { index in
            let progress = CGFloat(index) / CGFloat(steps)
            return NSNumber(value: Double(sin(progress * .pi) * Self.cardFlipMaximumShadeOpacity))
        }
        let scaleValues: [NSNumber] = (0 ... steps).map { index in
            let progress = CGFloat(index) / CGFloat(steps)
            return NSNumber(value: Double(1.0 - sin(progress * .pi) * (1.0 - Self.cardFlipMinimumScale)))
        }
        let timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock({ [weak self, weak container] in
            guard let self, let container, self.cardFlipContainer === container else {
                return
            }
            self.finishCardFlip()
        })

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = scaleValues
        scale.duration = Self.cardFlipDuration
        scale.timingFunction = timingFunction
        container.layer?.add(scale, forKey: "flipScale")

        for (index, entry) in [outgoing, incoming].enumerated() {
            let shade = CAKeyframeAnimation(keyPath: "opacity")
            shade.values = shadeValues
            shade.duration = Self.cardFlipDuration
            shade.timingFunction = timingFunction
            entry.shade.layer?.add(shade, forKey: "flipShade")

            let isOutgoing = index == 0
            let fromAngle: CGFloat = isOutgoing ? 0 : -.pi
            let toAngle: CGFloat = isOutgoing ? .pi : 0
            entry.face._transformation = CATransform3DMakeRotation(toAngle, 0, 1, 0)
            let rotation = CABasicAnimation(keyPath: "transform.rotation.y")
            rotation.fromValue = NSNumber(value: Double(fromAngle))
            rotation.toValue = NSNumber(value: Double(toAngle))
            rotation.duration = Self.cardFlipDuration
            rotation.timingFunction = timingFunction
            entry.face.layer?.add(rotation, forKey: "flipRotation")
        }
        CATransaction.commit()
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        gradientLayer.colors = receiveGradientColors.map { $0.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.insertSublayer(gradientLayer, at: 0)

        ringView.isEventLess = true
        ringView.isAccessibilityDecorative = true
        qrView.setAccessibilityLabel(strings().voiceOverCommonQRCode)
        closeButton.setAccessibilityLabel(strings().voiceOverCommonClose)
        buyButton.setAccessibilityLabel(strings().walletReceiveControllerBuy)
        buyIconView.isAccessibilityDecorative = true
        buyTextView.isAccessibilityDecorative = true
        captionView.isAccessibilityDecorative = true
        addSubview(ringView)
        addSubview(animatedRingView)

        cardView.backgroundColor = .white
        addSubview(cardView)

        cardView.addSubview(qrContainer)
        qrContainer.addSubview(qrView)
        #if arch(arm64)
        qrDiamondView.onExpansionChanged = { [weak self] expanded in
            guard let self else {
                return
            }
            if expanded, self.qrRevealStartTime != nil {
                self.finishQrReveal()
            }
            self.updateQrDiamondRefraction()
        }
        qrDiamondView.layer?.masksToBounds = false
        qrContainer.layer?.masksToBounds = false
        qrContainer.addSubview(qrDiamondView)
        #endif
        cardView.addSubview(gridView)
        cardView.addSubview(copiedView)
        cardView.addSubview(actionButton)

        copiedView.userInteractionEnabled = false
        copiedView.isSelectable = false
        copiedView.disableBackgroundDrawing = true
        copiedView.backgroundColor = .clear

        captionView.userInteractionEnabled = false
        captionView.isSelectable = false
        captionView.disableBackgroundDrawing = true
        captionView.backgroundColor = .clear
        addSubview(captionView)

        closeButton.autohighlight = false
        closeButton.scaleOnClick = true
        closeButton.set(image: NSImage(named: "Icon_Pip_Close")!.precomposed(NSColor.black), for: .Normal)
        closeButton.setGlassEffect(size: NSMakeSize(36, 36), forceAppearance: .forceLight)
        closeButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        closeButton.layer?.masksToBounds = false
        addSubview(closeButton)

        actionButton.autoSizeToFit = false
        actionButton.scaleOnClick = true

        buyButton.autoSizeToFit = false
        buyButton.scaleOnClick = true
        buyButton.set(background: .white, for: .Normal)
        buyButton.set(background: NSColor(white: 0.92, alpha: 1.0), for: .Highlight)
        addSubview(buyButton)

        buyIconView.image = NSImage(named: "Wallet_ButtonBuy")?.precomposed(receiveAccentColor)
        buyIconView.sizeToFit()
        buyIconView.isEventLess = true
        buyButton.addSubview(buyIconView)

        buyTextView.userInteractionEnabled = false
        buyTextView.isSelectable = false
        buyTextView.disableBackgroundDrawing = true
        buyTextView.isEventLess = true
        let buyLayout = TextViewLayout(.initialize(string: strings().walletReceiveControllerBuy, color: receiveAccentColor, font: .semibold(17)), maximumNumberOfLines: 1)
        buyLayout.measure(width: .greatestFiniteMagnitude)
        buyTextView.update(buyLayout)
        buyButton.addSubview(buyTextView)

        closeButton.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletReceiveRowItem else {
                return
            }
            item.dismissAction()
        }, for: .Click)

        actionButton.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletReceiveRowItem else {
                return
            }
            if item.displaysAddress {
                item.toggleAction()
            } else {
                item.copyAction()
            }
        }, for: .Click)

        buyButton.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletReceiveRowItem else {
                return
            }
            item.buyAction()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    private func updateAddressGrid(_ item: WalletReceiveRowItem) {
        let groups = item.addressGroups
        while gridLabels.count > groups.count {
            gridLabels.removeLast().removeFromSuperview()
        }
        while gridLabels.count < groups.count {
            let label = TextView()
            label.userInteractionEnabled = false
            label.isSelectable = false
            label.disableBackgroundDrawing = true
            label.backgroundColor = .clear
            gridLabels.append(label)
            gridView.addSubview(label)
        }
        let cellWidth = item.gridWidth / 3
        for (index, group) in groups.enumerated() {
            let color: NSColor = index.isMultiple(of: 2) ? .black : receiveMutedGroupColor
            let layout = TextViewLayout(.initialize(string: group, color: color, font: .semiboldMonospace(17)), alignment: .center, alwaysStaticItems: true)
            layout.measure(width: cellWidth)
            gridLabels[index].update(layout)
        }
    }

    private func updateQrCode(_ item: WalletReceiveRowItem) {
        guard qrAddress != item.address else {
            return
        }
        qrAddress = item.address
        qrModuleCount = nil
        #if arch(arm64)
        finishQrReveal()
        qrDidAnimateIn = false
        qrRefractionImage = nil
        qrRefractionTexture = nil
        qrDiamondView.updateRefractionSource(nil)
        #endif
        let side = item.cardSize.width - item.qrInset * 2
        let qrSize = NSMakeSize(side, side)
        #if arch(arm64)
        let icon: QrCodeIcon = .cutout
        #else
        let icon: QrCodeIcon = .custom(NSImage(named: "Wallet_QrGram")?.precomposed())
        #endif
        qrDisposable.set((qrCode(string: "ton://transfer/" + item.address, color: .black, backgroundColor: .white, icon: icon, ecl: "Q")
        |> map { moduleCount, generator in
            return (moduleCount, generator(TransformImageArguments(corners: ImageCorners(), imageSize: qrSize, boundingSize: qrSize, intrinsicInsets: NSEdgeInsets()))?.generateImage())
        }
        |> deliverOnMainQueue).start(next: { [weak self] moduleCount, image in
            self?.qrView.image = image
            self?.qrModuleCount = moduleCount
            self?.needsLayout = true
        }))
    }

    private func updateQrDiamond() {
        #if arch(arm64)
        guard let item = item as? WalletReceiveRowItem, let qrModuleCount else {
            qrDiamondView.isRenderingEnabled = false
            return
        }
        let cutoutFrame = walletReceiveQrCutoutFrame(moduleCount: qrModuleCount, qrSize: qrView.frame.size, scale: backingScaleFactor)
        qrDiamondFrame = cutoutFrame.offsetBy(dx: qrView.frame.minX, dy: qrView.frame.minY)
        qrDiamondView.frame = qrDiamondFrame
        qrDiamondView.update(size: cutoutFrame.size, diamondWidth: cutoutFrame.width * walletReceiveQrDiamondWidthRatio, isVisible: window != nil && !item.displaysAddress, lightBackground: !theme.colors.isDark, animationMode: .continuous)
        updateQrDiamondIntro()
        updateQrReveal()
        updateQrDiamondRefraction()
        #endif
    }

    #if arch(arm64)
    private func finishQrReveal() {
        qrRevealAnimator?.invalidate()
        qrRevealAnimator = nil
        qrRevealStartTime = nil
        qrRevealView?.removeFromSuperview()
        qrRevealView = nil
        qrView.isHidden = false
        qrDiamondView.updateOpeningScale(nil)
        qrDiamondView.frame = qrDiamondFrame
    }

    private func updateQrDiamondIntro() {
        guard let startTime = qrRevealStartTime, let item = item as? WalletReceiveRowItem else {
            return
        }
        guard let frame = walletReceiveQrDiamondIntroFrame(elapsed: CACurrentMediaTime() - startTime),
              window != nil, !item.displaysAddress,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finishQrReveal()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        qrDiamondView.setFrameOrigin(NSMakePoint(qrDiamondFrame.minX, qrDiamondFrame.minY + frame.lift))
        qrDiamondView.updateOpeningScale(frame.openingScale)
        CATransaction.commit()
    }

    private func updateQrDiamondRefraction() {
        guard qrDiamondView.isExpanded, let image = qrView.image else {
            qrDiamondView.updateRefractionSource(nil)
            return
        }
        if qrRefractionImage !== image {
            qrRefractionImage = nil
            qrRefractionTexture = walletReceiveQrRefractionTexture(image)
            if qrRefractionTexture != nil {
                qrRefractionImage = image
            }
        }
        guard let texture = qrRefractionTexture else {
            qrDiamondView.updateRefractionSource(nil)
            return
        }
        let rect = qrView.frame.offsetBy(dx: -qrDiamondView.frame.midX, dy: -qrDiamondView.frame.midY)
        qrDiamondView.updateRefractionSource(InteractiveDiamondView.RefractionSource(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: rect, preservesColors: true))
    }

    private func updateQrReveal() {
        guard let item = item as? WalletReceiveRowItem else {
            return
        }
        guard window != nil, !item.displaysAddress else {
            finishQrReveal()
            return
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            qrDidAnimateIn = true
            finishQrReveal()
            return
        }
        guard !qrDidAnimateIn, let image = qrView.image, let qrModuleCount, qrView.frame.width > 0 else {
            return
        }
        qrDidAnimateIn = true

        let revealView = WalletReceiveQrRevealView(frame: qrView.frame)
        revealView.isEventLess = true
        qrContainer.addSubview(revealView, positioned: .above, relativeTo: qrView)
        qrRevealView = revealView
        qrView.isHidden = true
        qrRevealStartTime = CACurrentMediaTime()
        revealView.animateIn(image: image, moduleCount: qrModuleCount, delay: walletReceiveQrIntroDelay, duration: walletReceiveQrRevealDuration)
        updateQrDiamondIntro()
        let animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] _ in
            self?.updateQrDiamondIntro()
        })
        animator.isPaused = false
        qrRevealAnimator = animator
    }
    #endif

    override func set(item: TableRowItem, animated: Bool = false) {
        let previous = self.item as? WalletReceiveRowItem
        super.set(item: item, animated: animated)

        guard let item = item as? WalletReceiveRowItem else {
            return
        }

        var previousSnapshot: CGImage? = nil
        if animated, let previous, previous.displaysAddress != item.displaysAddress, cardFlipContainer == nil,
           window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            previousSnapshot = cardView.snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        cardView.layer?.cornerRadius = item.cardRadius

        captionView.update(item.captionLayout)
        copiedView.update(item.copiedLayout)

        updateQrCode(item)
        updateAddressGrid(item)

        actionButton.set(font: .semibold(14), for: .Normal)
        actionButton.set(color: receiveAccentColor, for: .Normal)
        actionButton.set(background: receiveAccentColor.withAlphaComponent(0.1), for: .Normal)
        actionButton.set(background: NSColor(rgb: 0xc8e4ff), for: .Highlight)
        if item.displaysAddress {
            actionButton.removeImage(for: .Normal)
            actionButton.set(text: item.showQrTitle, for: .Normal)
        } else {
            if let copyIcon = NSImage(named: "Wallet_ReceiveCopy")?.precomposed(receiveAccentColor) {
                actionButton.set(image: copyIcon, for: .Normal)
            }
            actionButton.set(text: item.copyTitle, for: .Normal)
        }
        actionButton.sizeToFit(NSMakeSize(28, 0), NSMakeSize(0, item.actionHeight), thatFit: true)
        actionButton.layer?.cornerRadius = item.actionHeight / 2

        qrContainer.isHidden = item.displaysAddress
        gridView.isHidden = !item.displaysAddress
        buyButton.isHidden = !item.isOwnWallet

        let isToggling = animated && previous != nil && previous?.displaysAddress != item.displaysAddress
        if isToggling, let previousSnapshot, cardFlipContainer == nil {
            copiedView.layer?.opacity = item.displaysAddress ? 1 : 0
            needsLayout = true
            layout()
            animateCardFlip(previousSnapshot: previousSnapshot, cornerRadius: item.cardRadius)
        } else if isToggling {
            let appearing: [NSView] = item.displaysAddress ? [gridView] : [qrContainer]
            for view in appearing {
                view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            copiedView._change(opacity: item.displaysAddress ? 1 : 0, animated: true, duration: 0.2)
            actionButton.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        } else {
            copiedView.layer?.opacity = item.displaysAddress ? 1 : 0
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? WalletReceiveRowItem else {
            return
        }

        gradientLayer.frame = bounds

        closeButton.setFrameOrigin(NSMakePoint(16, 16))

        let cardX = floorToScreenPixels(backingScaleFactor, (frame.width - item.cardSize.width) / 2)
        let cardFrame = NSMakeRect(cardX, item.cardTop, item.cardSize.width, item.cardSize.height)
        if let container = cardFlipContainer {
            container.frame = cardFrame
            for face in container.subviews {
                face.frame = container.bounds
            }
            cardView.frame = container.bounds
        } else {
            cardView.frame = cardFrame
        }

        let ringSize = NSMakeSize(max(1, min(max(1, frame.width - 32), item.cardSize.width + 76)), item.cardSize.height + 56)
        ringView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, cardFrame.midX - ringSize.width / 2), floorToScreenPixels(backingScaleFactor, cardFrame.midY - ringSize.height / 2), ringSize.width, ringSize.height)
        animatedRingView.frame = ringView.frame
        let ringColor = NSColor(rgb: 0x0052b3).withAlphaComponent(0.48)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ringView.isHidden = !reduceMotion
        animatedRingView.isHidden = reduceMotion
        if reduceMotion {
            let ringKey = "\(item.address)|\(Int(ringSize.width))x\(Int(ringSize.height))"
            if ringImageKey != ringKey {
                ringImageKey = ringKey
                ringView.image = walletReceiveAddressRingImage(address: item.address, size: ringSize, cardSize: item.cardSize, cardCornerRadius: item.cardRadius, pathOffset: 14, color: ringColor)
            }
        } else {
            animatedRingView.update(address: item.address, size: ringSize, cardSize: item.cardSize, cardCornerRadius: item.cardRadius, pathOffset: 14, color: ringColor)
        }

        let qrSide = item.cardSize.width - item.qrInset * 2
        qrContainer.frame = NSMakeRect(item.qrInset, item.qrInset, qrSide, qrSide)
        qrView.frame = qrContainer.bounds
        updateQrDiamond()

        let gridX = floorToScreenPixels(backingScaleFactor, (item.cardSize.width - item.gridWidth) / 2)
        gridView.frame = NSMakeRect(gridX, item.gridTopInset, item.gridWidth, item.gridHeight)

        let cellWidth = item.gridWidth / 3
        for (index, label) in gridLabels.enumerated() {
            let column = CGFloat(index % 3)
            let row = CGFloat(index / 3)
            let cellRect = NSMakeRect(column * cellWidth, row * item.gridRowHeight, cellWidth, item.gridRowHeight)
            label.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, cellRect.midX - label.frame.width / 2), floorToScreenPixels(backingScaleFactor, cellRect.midY - label.frame.height / 2)))
        }

        copiedView.centerX(y: gridView.frame.maxY + 16)

        actionButton.centerX(y: item.cardSize.height - item.actionBottomInset - item.actionHeight)

        captionView.centerX(y: cardFrame.maxY + item.captionSpacing)

        let buyY = cardFrame.maxY + item.captionSpacing + item.captionLayout.layoutSize.height + item.buySpacing
        buyButton.frame = NSMakeRect(item.buySideInset, buyY, frame.width - item.buySideInset * 2, item.buyHeight)
        buyButton.layer?.cornerRadius = item.buyHeight / 2

        let buyGap: CGFloat = 10
        let buyGroupWidth = buyIconView.frame.width + buyGap + buyTextView.frame.width
        let buyStartX = floorToScreenPixels(backingScaleFactor, (buyButton.frame.width - buyGroupWidth) / 2)
        buyIconView.setFrameOrigin(NSMakePoint(buyStartX, floorToScreenPixels(backingScaleFactor, (buyButton.frame.height - buyIconView.frame.height) / 2)))
        buyTextView.setFrameOrigin(NSMakePoint(buyStartX + buyIconView.frame.width + buyGap, floorToScreenPixels(backingScaleFactor, (buyButton.frame.height - buyTextView.frame.height) / 2)))
    }

    deinit {
        #if arch(arm64)
        qrRevealAnimator?.invalidate()
        #endif
        qrDisposable.dispose()
    }
}

#if arch(arm64)
func walletReceiveQrRefractionTexture(_ image: CGImage) -> MTLTexture? {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else {
        return nil
    }
    for offset in stride(from: 0, to: bytes.count, by: 4) {
        let alpha = 255 - bytes[offset + 2]
        bytes[offset] = 0
        bytes[offset + 1] = 0
        bytes[offset + 2] = 0
        bytes[offset + 3] = alpha
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = .shaderRead
    guard let texture = MetalEngine.shared.device.makeTexture(descriptor: descriptor) else {
        return nil
    }
    bytes.withUnsafeBytes { storage in
        if let base = storage.baseAddress {
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: width * 4)
        }
    }
    return texture
}
#endif

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    let address = state.address
    let displaysAddress = state.displaysAddress

    entries.append(.custom(sectionId: 0, index: 0, value: .none, identifier: _id_receive, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return WalletReceiveRowItem(
            initialSize,
            stableId: stableId,
            environment: arguments.environment,
            address: address,
            displaysAddress: displaysAddress,
            isOwnWallet: state.isOwnWallet,
            copyAction: arguments.copy,
            toggleAction: arguments.showQr,
            dismissAction: arguments.dismiss,
            buyAction: arguments.buy
        )
    }))

    return entries
}

@available(macOS 10.15, *)
public func WalletReceiveController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext?, address: String, isOwnWallet: Bool = true, appeared: (() -> Void)? = nil, closed: (() -> Void)? = nil) -> InputDataModalController {
    var appeared = appeared
    let actionsDisposable = DisposableSet()
    let availabilityDisposable = MetaDisposable()
    actionsDisposable.add(availabilityDisposable)

    var close: (() -> Void)? = nil
    var getAnalyticsContext: () -> AnalyticsContext = { Analytics.shared.unresolvedContext() }

    let initialState = State(address: address, isOwnWallet: isOwnWallet)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let arguments = Arguments(context: context, environment: environment, copy: {
        environment.copyToClipboard(stateValue.with { $0.address })
        updateState { current in
            var current = current
            current.displaysAddress = true
            return current
        }
    }, showQr: {
        updateState { current in
            var current = current
            current.displaysAddress = false
            return current
        }
    }, dismiss: {
        close?()
    }, buy: {
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { withExtendedLifetime(presentation) {} }
        let signal = showModalProgress(signal: walletReceiveOnrampSession(context: context, environment: environment, walletContext: walletContext, address: address), for: context.window)
        |> deliverOnMainQueue
        availabilityDisposable.set(analyticsContext.preservingPresentation(signal).start(next: { result in
            switch result {
            case .unavailable:
                environment.alert(for: context.window, header: strings().walletReceiveControllerPurchaseUnavailableTitle, info: strings().walletReceiveControllerPurchaseUnavailableInfo)
            case .failed:
                environment.alert(for: context.window, header: strings().walletReceiveControllerPurchaseFailedTitle, info: strings().walletReceiveControllerPurchaseFailedInfo)
            case let .session(url):
                guard let navigate = environment.prepareOnrampNavigation(url) else {
                    environment.alert(for: context.window, header: strings().walletReceiveControllerPurchaseFailedTitle, info: strings().walletReceiveControllerPurchaseFailedInfo)
                    return
                }
                close?()
                navigate()
            }
        }))
    })

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "", hasDone: false)
    controller.analyticsScreen = .walletReceive
    getAnalyticsContext = { [weak controller] in
        return controller?.analyticsContext ?? Analytics.shared.unresolvedContext()
    }

    controller.getBackgroundColor = {
        return receiveGradientColors[0]
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
        closed?()
    }

    controller.didAppear = { _ in
        let completion = appeared
        appeared = nil
        completion?()
    }

    let modalController = WalletModalController(controller, size: NSMakeSize(380, 0))
    modalController._hasBorder = false

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
