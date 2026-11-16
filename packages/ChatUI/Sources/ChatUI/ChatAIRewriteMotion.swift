import AppKit
import QuartzCore

enum ChatAIRewriteMotion {
    static let minimumProcessing = 0.18
    static let revealDuration = 0.70
    static let departureStart = 0.60
    static let departureDuration = 0.22
    static let fadeStart = 0.20
    static let fadeDuration = 0.60
    static let planeLoop = 0.90
    static let rimLap = 1.25

    static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    static func wordProgress(index: Int, count: Int, elapsed: Double) -> Double {
        let focusDuration = 0.28
        let onset = (revealDuration - focusDuration) * Double(index) / Double(max(1, count - 1))
        return ease((elapsed - onset) / focusDuration)
    }

    static func lightOpacity(elapsed: Double, revealElapsed: Double?) -> Float {
        let rise = ease(elapsed / 0.16)
        let fade = revealElapsed.map { 1 - ease(($0 - fadeStart) / fadeDuration) } ?? 1
        return Float(rise * fade)
    }

    static func planeOffset(elapsed: Double) -> CGPoint {
        let phase = elapsed / planeLoop * 2 * .pi
        return CGPoint(x: 1.9 * sin(phase) + 0.28 * sin(phase * 12), y: 1.1 * (1 - cos(phase)))
    }
}

final class ChatAIRewriteLight {
    let layer = CALayer()
    private let interior = CALayer()
    private let clip = CAShapeLayer()
    private let rim = CAShapeLayer()
    private let aura = CAShapeLayer()
    private let rimHighlight = CALayer()
    private let rimMask = CAShapeLayer()
    private let rimPasses = [CAGradientLayer(), CAGradientLayer()]
    private let passes = [CAGradientLayer(), CAGradientLayer()]
    private let flecks = CAShapeLayer()
    private let dark: Bool
    private var size: CGSize = .zero
    private var radius: CGFloat = 0

    init(dark: Bool) {
        self.dark = dark
        interior.mask = clip
        interior.backgroundColor = color(0.11, 0.25, 0.89, dark ? 0.08 : 0.04).cgColor
        layer.addSublayer(aura)
        layer.addSublayer(interior)
        layer.addSublayer(rim)
        layer.addSublayer(rimHighlight)
        rimHighlight.mask = rimMask
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.white.cgColor
        rimMask.lineWidth = 2
        for pass in rimPasses {
            pass.startPoint = CGPoint(x: 0, y: 0.5)
            pass.endPoint = CGPoint(x: 1, y: 0.5)
            pass.colors = [NSColor.clear, color(0.02, 0.54, 1, 0.22), color(0.30, 0.74, 1, dark ? 0.8 : 0.68), NSColor.clear].map(\.cgColor)
            pass.locations = [0, 0.38, 0.65, 1]
            rimHighlight.addSublayer(pass)
        }
        for pass in passes {
            pass.startPoint = CGPoint(x: 0, y: 0.5)
            pass.endPoint = CGPoint(x: 1, y: 0.5)
            pass.locations = [0, 0.24, 0.49, 0.63, 0.72, 1]
            pass.colors = [
                NSColor.clear, color(0.29, 0.14, 0.99, dark ? 0.10 : 0.06),
                color(0.25, 0.26, 0.99, dark ? 0.23 : 0.17),
                color(0.04, 0.63, 1, dark ? 0.55 : 0.40),
                color(0.28, 0.83, 1, 0.20), NSColor.clear
            ].map(\.cgColor)
            interior.addSublayer(pass)
        }
        let dust = CGMutablePath()
        for index in 0..<32 {
            let x = CGFloat((index * 47 + 13) % 150)
            let y = CGFloat((index * 73 + 29) % 240)
            let size: CGFloat = index.isMultiple(of: 5) ? 1.45 : 0.75
            dust.addEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }
        flecks.path = dust
        flecks.fillColor = color(0.40, 0.84, 1, dark ? 0.7 : 0.35).cgColor
        passes[0].addSublayer(flecks)
        for outline in [aura, rim] {
            outline.fillColor = nil
            outline.strokeColor = color(0.14, 0.54, 1, dark ? 0.27 : 0.21).cgColor
        }
        aura.lineWidth = 2
        aura.shadowColor = color(0.03, 0.38, 1, 1).cgColor
        aura.shadowOffset = .zero
        aura.shadowOpacity = 0.74
        aura.shadowRadius = 7
        rim.lineWidth = 1.1
    }

    func update(frame: CGRect, cornerRadius: CGFloat, elapsed: Double, revealElapsed: Double?) {
        layer.frame = frame
        layer.opacity = ChatAIRewriteMotion.lightOpacity(elapsed: elapsed, revealElapsed: revealElapsed)
        if size != frame.size || radius != cornerRadius {
            size = frame.size
            radius = cornerRadius
            let bounds = CGRect(origin: .zero, size: size)
            interior.frame = bounds
            clip.frame = bounds
            clip.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
            let outline = bounds.insetBy(dx: 0.8, dy: 0.8)
            let path = CGPath(roundedRect: outline, cornerWidth: radius, cornerHeight: radius, transform: nil)
            rimHighlight.frame = bounds
            for edge in [aura, rim, rimMask] {
                edge.frame = bounds
                edge.path = path
            }
        }
        let bandWidth = min(380, max(150, size.width * 0.38))
        flecks.setAffineTransform(CGAffineTransform(scaleX: bandWidth / 150, y: 1))
        let bandHeight = max(240, size.height * 2.2)
        for (index, pass) in passes.enumerated() {
            let period = index == 0 ? 1.14 : 1.72
            let phase = (elapsed + (index == 0 ? 0.24 : 0.10)).truncatingRemainder(dividingBy: period) / period
            let progress = 0.55 * phase + 0.45 * ChatAIRewriteMotion.ease(phase)
            let margin = bandWidth + size.height * 0.60
            pass.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: bandHeight)
            let processingX = -margin + (size.width + 2 * margin) * progress
            if let revealElapsed, index == 0 {
                let sweep = ChatAIRewriteMotion.ease(revealElapsed / ChatAIRewriteMotion.revealDuration)
                pass.position = CGPoint(x: size.width * sweep - bandWidth * 0.13, y: size.height / 2)
            } else {
                pass.position = CGPoint(x: processingX, y: size.height / 2)
            }
            pass.setAffineTransform(CGAffineTransform(rotationAngle: index == 0 ? -0.46 : -0.34))
            pass.opacity = index == 0 ? 1 : Float(0.55 * (1 - ChatAIRewriteMotion.ease((revealElapsed ?? 0) / 0.18)))
            let edge = rimPasses[index]
            edge.bounds = pass.bounds
            edge.position = pass.position
            edge.setAffineTransform(pass.affineTransform())
            edge.opacity = pass.opacity
        }
    }

    private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

final class ChatAIRewritePlane {
    let layer = CALayer()
    private let rim = CAShapeLayer()
    private let tails = (0..<3).map { _ in CAShapeLayer() }
    private let streaks = CAShapeLayer()
    private let plane = CALayer()

    init(image: CGImage, scale: CGFloat) {
        plane.contents = image
        plane.contentsScale = scale
        plane.contentsGravity = .resizeAspect
        for (index, tail) in tails.enumerated() {
            tail.fillColor = nil
            tail.strokeColor = NSColor(srgbRed: 0.66, green: 0.91, blue: 1, alpha: 0.78 / CGFloat(index + 1)).cgColor
            tail.lineWidth = 1.8
            tail.lineCap = .round
            layer.addSublayer(tail)
        }
        rim.fillColor = nil
        rim.strokeColor = NSColor(srgbRed: 0.43, green: 0.80, blue: 1, alpha: 0.38).cgColor
        rim.lineWidth = 1.2
        layer.addSublayer(rim)
        streaks.fillColor = nil
        streaks.strokeColor = NSColor.white.withAlphaComponent(0.70).cgColor
        streaks.lineWidth = 0.8
        streaks.lineCap = .round
        layer.addSublayer(streaks)
        layer.addSublayer(plane)
    }

    func update(frame: CGRect, elapsed: Double, revealElapsed: Double?) {
        layer.frame = frame
        let bounds = CGRect(origin: .zero, size: frame.size)
        let outline = bounds.insetBy(dx: 2.25, dy: 2.25)
        let radius = outline.height / 2
        let rimPath = CGPath(roundedRect: outline, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let path = CGMutablePath()
        path.addPath(rimPath)
        path.addPath(rimPath)
        rim.frame = bounds
        rim.path = rimPath
        let light = ChatAIRewriteMotion.lightOpacity(elapsed: elapsed, revealElapsed: revealElapsed)
        rim.opacity = light
        let head = 0.5 + CGFloat((elapsed / ChatAIRewriteMotion.rimLap).truncatingRemainder(dividingBy: 1)) / 2
        for (index, tail) in tails.enumerated() {
            tail.frame = bounds
            tail.path = path
            tail.strokeEnd = head
            tail.strokeStart = head - [0.035, 0.085, 0.16][index]
            tail.opacity = light
        }
        let departure = revealElapsed.map { ChatAIRewriteMotion.ease(($0 - ChatAIRewriteMotion.departureStart) / ChatAIRewriteMotion.departureDuration) } ?? 0
        let flight = ChatAIRewriteMotion.planeOffset(elapsed: elapsed)
        let takeoff = ChatAIRewriteMotion.ease(elapsed / 0.22)
        let scale = (1 - 0.22 * takeoff) * (1 - 0.26 * departure)
        plane.bounds = CGRect(x: 0, y: 0, width: 23, height: 23)
        plane.position = CGPoint(x: bounds.midX + flight.x + 24 * departure, y: bounds.midY + flight.y - 12 * departure)
        let angle = 0.07 * sin(elapsed / ChatAIRewriteMotion.planeLoop * 2 * .pi)
        plane.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: scale, y: scale))
        plane.opacity = Float(1 - departure)
        let lines = CGMutablePath()
        for index in 0..<4 {
            let phase = (elapsed * 1.75 + Double(index) / 4).truncatingRemainder(dividingBy: 1)
            let x = bounds.midX + CGFloat(index % 2) * 6 - 13 * phase
            let y = bounds.midY + CGFloat(index) * 3 + 6 * phase
            lines.move(to: CGPoint(x: x, y: y))
            lines.addLine(to: CGPoint(x: x + 3.5, y: y - 2.5))
        }
        streaks.frame = bounds
        streaks.path = lines
        streaks.opacity = Float(takeoff * (1 - departure)) * light
    }
}
