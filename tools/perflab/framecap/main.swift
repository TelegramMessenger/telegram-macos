import AppKit
import CoreMedia
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 4, let pid = pid_t(arguments[1]), let duration = Double(arguments[2]) else {
    FileHandle.standardError.write("usage: framecap <pid> <seconds> <out dir> [threshold %]\n".data(using: .utf8)!)
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[3])
let threshold = arguments.count > 4 ? Double(arguments[4]) ?? 0.02 : 0.02
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

final class Recorder: NSObject, SCStreamOutput {
    private var previous: [UInt8]?
    private var log: [String] = []
    private let queue = DispatchQueue(label: "framecap")
    private(set) var frames = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]], let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            return
        }
        let step = 4
        let sampledWidth = width / step
        let sampledHeight = height / step
        var gray = [UInt8](repeating: 0, count: sampledWidth * sampledHeight)
        for y in 0 ..< sampledHeight {
            let row = base + (y * step) * bytesPerRow
            for x in 0 ..< sampledWidth {
                let pixel = row + (x * step) * 4
                gray[y * sampledWidth + x] = UInt8((Int(pixel[0]) + Int(pixel[1]) * 2 + Int(pixel[2])) / 4)
            }
        }
        var changed = 100.0
        if let previous, previous.count == gray.count {
            var count = 0
            for index in 0 ..< gray.count where abs(Int(gray[index]) - Int(previous[index])) > 16 {
                count += 1
            }
            changed = Double(count) / Double(gray.count) * 100
        }
        self.previous = gray
        self.frames += 1
        guard changed >= threshold else {
            return
        }
        let name = String(format: "%.4f", time)
        self.log.append(String(format: "%.4f %.3f", time, changed))
        guard let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let image = context.makeImage() else {
            return
        }
        let url = outputDirectory.appendingPathComponent("\(name).jpg")
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
    }

    func writeLog() {
        try? self.log.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
    }
}

let application = NSApplication.shared
let recorder = Recorder()
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.frame.width > 400 && $0.frame.height > 300 }
        guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            FileHandle.standardError.write("no window for pid \(pid)\n".data(using: .utf8)!)
            exit(2)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width)
        configuration.height = Int(window.frame.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "framecap.output"))
        try await stream.startCapture()
        print("capturing window \(window.windowID) \(window.frame)")
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        recorder.writeLog()
        try? await stream.stopCapture()
        print("frames \(recorder.frames)")
        exit(0)
    } catch {
        recorder.writeLog()
        FileHandle.standardError.write("error \(error)\n".data(using: .utf8)!)
        exit(3)
    }
}
RunLoop.main.run()
