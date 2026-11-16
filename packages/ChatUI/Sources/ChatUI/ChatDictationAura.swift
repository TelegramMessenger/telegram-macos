import Foundation
import CoreGraphics

enum ChatDictationAura {
    static let padding: CGFloat = 30

    static func path(around rect: CGRect, level: CGFloat, time: Double, band: CGFloat, motion: Bool, expansion: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return path }
        let level = max(0, min(1, level.isFinite ? level : 0))
        let time = CGFloat(time.isFinite ? time : 0)
        let radius = min(20, min(rect.width, rect.height) / 2)
        let horizontal = rect.width - radius * 2
        let vertical = rect.height - radius * 2
        let corner = .pi * radius / 2
        let lengths = [horizontal, corner, vertical, corner, horizontal, corner, vertical, corner]
        let perimeter = lengths.reduce(0, +)
        let count = max(128, min(400, Int(perimeter / 5)))
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for index in 0 ..< count {
            let position = CGFloat(index) / CGFloat(count)
            var distance = position * perimeter
            var segment = 0
            while segment < lengths.count - 1, distance > lengths[segment] {
                distance -= lengths[segment]
                segment += 1
            }
            let point: CGPoint
            let normal: CGPoint
            switch segment {
            case 0:
                point = CGPoint(x: radius + distance, y: 0)
                normal = CGPoint(x: 0, y: -1)
            case 2:
                point = CGPoint(x: rect.width, y: radius + distance)
                normal = CGPoint(x: 1, y: 0)
            case 4:
                point = CGPoint(x: rect.width - radius - distance, y: rect.height)
                normal = CGPoint(x: 0, y: 1)
            case 6:
                point = CGPoint(x: 0, y: rect.height - radius - distance)
                normal = CGPoint(x: -1, y: 0)
            default:
                let angle = CGFloat(segment - 1) * .pi / 4 - .pi / 2 + distance / radius
                let center = CGPoint(x: segment == 1 || segment == 3 ? rect.width - radius : radius,
                                     y: segment == 1 || segment == 7 ? radius : rect.height - radius)
                normal = CGPoint(x: cos(angle), y: sin(angle))
                point = CGPoint(x: center.x + normal.x * radius, y: center.y + normal.y * radius)
            }
            let phase = position * .pi * 2
            let ripple = sin(phase * 3 - time * 1.8 + band * 1.7) * 0.55
                + sin(phase * 7 + time * 1.1 + band) * 0.25
                + sin(phase + time * 0.7) * 0.2
            let spread = expansion + (motion ? 1.7 + level * 2 + (0.5 + ripple * 0.5) * (1 + level * 4.5) + band * 0.8 : 2)
            points.append(CGPoint(x: rect.minX + point.x + normal.x * spread, y: rect.minY + point.y + normal.y * spread))
        }
        path.move(to: points[0])
        for index in points.indices {
            let previous = points[(index + count - 1) % count]
            let start = points[index]
            let end = points[(index + 1) % count]
            let next = points[(index + 2) % count]
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + (end.x - previous.x) / 6, y: start.y + (end.y - previous.y) / 6),
                          control2: CGPoint(x: end.x - (next.x - start.x) / 6, y: end.y - (next.y - start.y) / 6))
        }
        path.closeSubpath()
        return path
    }
}

struct ChatDictationAuraPulse {
    static let lifetime: Double = 1.35
    let born: Double
    let energy: CGFloat

    init(born: Double, energy: CGFloat) {
        self.born = born
        self.energy = max(0, min(1, energy.isFinite ? energy : 0))
    }

    func progress(at time: Double) -> CGFloat {
        return CGFloat(max(0, min(1, (time - born) / Self.lifetime)))
    }

    func expansion(at time: Double) -> CGFloat {
        return (1 - pow(1 - progress(at: time), 1.1)) * (11 + energy * 9)
    }

    func opacity(at time: Double) -> Float {
        let progress = progress(at: time)
        return Float(min(1, progress * 10) * pow(1 - progress, 1.7) * energy)
    }
}
