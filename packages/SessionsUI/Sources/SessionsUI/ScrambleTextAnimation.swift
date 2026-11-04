import Cocoa
import SwiftSignalKit

final class ScrambleTextAnimation {
    private static let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    private var timer: SwiftSignalKit.Timer?

    var isRunning: Bool {
        return timer != nil
    }

    func start(from source: String, to target: String, duration: Double = 0.6, update: @escaping (String) -> Void) {
        cancel()
        let source = Array(source)
        let destination = Array(target)
        let start = CACurrentMediaTime()

        let tick: () -> Void = { [weak self] in
            let progress = min(1, (CACurrentMediaTime() - start) / duration)
            if progress >= 1 {
                self?.cancel()
                update(target)
            } else {
                update(ScrambleTextAnimation.text(from: source, to: destination, progress: progress))
            }
        }

        let timer = SwiftSignalKit.Timer(timeout: 1.0 / 30.0, repeat: true, completion: tick, queue: .mainQueue())
        self.timer = timer
        timer.start()
        tick()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    private static func text(from source: [Character], to destination: [Character], progress: Double) -> String {
        let length = Int((Double(source.count) + Double(destination.count - source.count) * min(1, progress * 2)).rounded())
        var result: [Character] = []
        for index in 0 ..< max(0, length) {
            let reveal = 0.15 + 0.8 * Double(index + 1) / Double(max(destination.count, 1) + 1)
            if progress >= reveal, index < destination.count {
                result.append(destination[index])
            } else if index < destination.count, destination[index] == " " {
                result.append(" ")
            } else if progress < 0.1, index < source.count {
                result.append(source[index])
            } else {
                result.append(characters.randomElement()!)
            }
        }
        return String(result)
    }
}
