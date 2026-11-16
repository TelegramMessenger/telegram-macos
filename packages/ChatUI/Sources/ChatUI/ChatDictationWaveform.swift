import Foundation
import CoreGraphics

struct ChatDictationButtonOrigin {
    let screenFrame: CGRect
    let icon: CGImage?
}

struct ChatDictationWaveform {
    private(set) var level: CGFloat = 0
    private(set) var samples: [CGFloat] = Array(repeating: 0, count: 28)

    mutating func update(_ value: CGFloat) {
        let target = pow(max(0, min(1, value.isFinite ? value : 0)), 0.7)
        level += (target - level) * (target > level ? 0.65 : 0.28)
        samples.removeFirst()
        samples.append(level)
    }

    func iconPath(size: CGSize) -> CGPath {
        let path = CGMutablePath()
        let spacing: CGFloat = 3.5
        let weights: [CGFloat] = [0.5, 0.75, 1, 0.85, 1, 0.75, 0.5]
        let start = (size.width - spacing * CGFloat(weights.count - 1)) / 2
        for index in weights.indices {
            let sample = samples[samples.count - weights.count + index]
            let height = 2 + sample * max(0, min(17, size.height - 4)) * weights[index]
            let x = start + CGFloat(index) * spacing
            path.move(to: CGPoint(x: x, y: (size.height - height) / 2))
            path.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))
        }
        return path
    }

}
