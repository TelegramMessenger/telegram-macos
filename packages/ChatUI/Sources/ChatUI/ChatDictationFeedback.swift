import Cocoa
import InAppSettings

enum ChatDictationFeedback {
    private static let startSound: NSSound? = {
        let sampleRate = 24000
        let count = sampleRate * 14 / 100
        var samples = Data()
        for index in 0 ..< count {
            let time = Double(index) / Double(sampleRate)
            let progress = Double(index) / Double(count)
            let envelope = pow(sin(.pi * progress), 2)
            let frequency = 660.0
            let first = sin(2 * .pi * frequency * time)
            let second = sin(2 * .pi * frequency * 1.5 * time)
            var sample = Int16((first * (1 - progress) + second * progress) * envelope * 9000).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var wave = Data()
        func append(_ value: UInt32) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) }
        }
        wave.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + samples.count))
        wave.append(contentsOf: "WAVEfmt ".utf8)
        append(16)
        wave.append(contentsOf: [1, 0, 1, 0])
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        wave.append(contentsOf: [2, 0, 16, 0])
        wave.append(contentsOf: "data".utf8)
        append(UInt32(samples.count))
        wave.append(samples)
        let sound = NSSound(data: wave)
        sound?.volume = 0.25
        return sound
    }()

    static func started() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if FastSettings.inAppSounds {
            startSound?.stop()
            startSound?.play()
        }
    }

    static func finished() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
