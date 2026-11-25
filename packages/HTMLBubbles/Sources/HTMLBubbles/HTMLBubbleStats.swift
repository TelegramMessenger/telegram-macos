import Cocoa
import Darwin
import HTMLScript
import HTML3D
import WidgetSandbox

final class HTMLRenderStats {
    struct Snapshot {
        let cpuNanoseconds: UInt64
        let renders: Int
        let lastMilliseconds: Double
    }

    private let lock = NSLock()
    private var cpuNanoseconds: UInt64 = 0
    private var renders = 0
    private var lastMilliseconds: Double = 0

    func record(cpuNanoseconds: UInt64) {
        lock.lock()
        self.cpuNanoseconds += cpuNanoseconds
        renders += 1
        lastMilliseconds = Double(cpuNanoseconds) / 1_000_000
        lock.unlock()
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(cpuNanoseconds: cpuNanoseconds, renders: renders, lastMilliseconds: lastMilliseconds)
    }
}

enum HTMLProcessUsage {
    static func threadCPUNanoseconds() -> UInt64 {
        return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }

    static func appCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    static func appFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private static func seconds(_ time: timeval) -> Double {
        return Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }
}

final class HTMLBubbleStatsOverlay {
    private struct Sample {
        let time: Double
        let app: Double
        let render: HTMLRenderStats.Snapshot
        let script: Double
        let scriptFrames: Int
        let scene: HTML3DStats?
        let sandbox: Double
        let rendererSeconds: Double?
    }

    static var isEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "HTMLBubbleLiveStats")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "HTMLBubbleLiveStats")
            NotificationCenter.default.post(name: HTMLBubbleStatsOverlay.didChangeNotification, object: nil)
        }
    }
    
    static func isEnabled(for state: HTMLBubbleState?) -> Bool {
        return isEnabled && (state?.showsStats ?? true)
    }

    static let didChangeNotification = Notification.Name("HTMLBubbleStatsOverlayDidChange")

    static let lineHeight: CGFloat = 13
    static let gap: CGFloat = 4
    static let padding: CGFloat = 4

    static func lineCount(_ state: HTMLBubbleState) -> Int {
        if state.engine.usesWidgetSandbox {
            return 4
        }
        return state.scene3D != nil ? 6 : 4
    }

    struct SourceSize: Equatable {
        let total: Int
        let images: Int
        let zlibTotal: Int
        let zlibImages: Int
    }

    static func sourceSize(_ html: String) -> SourceSize {
        let bytes = Array(html.utf8)
        var images = 0
        var imageBytes: [UInt8] = []
        var index = 0
        let dataImage = Array("data:image/".utf8)
        let svgOpen = Array("<svg".utf8)
        let svgClose = Array("</svg>".utf8)
        func matches(_ pattern: [UInt8], at position: Int) -> Bool {
            guard position + pattern.count <= bytes.count else {
                return false
            }
            for offset in 0 ..< pattern.count {
                let byte = bytes[position + offset]
                let folded = byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte
                if folded != pattern[offset] {
                    return false
                }
            }
            return true
        }
        while index < bytes.count {
            if matches(dataImage, at: index) {
                var end = index + dataImage.count
                while end < bytes.count, !(bytes[end] == 0x22 || bytes[end] == 0x27 || bytes[end] == 0x29 || bytes[end] == 0x3C || bytes[end] == 0x20 || bytes[end] == 0x0A || bytes[end] == 0x0D || bytes[end] == 0x09) {
                    end += 1
                }
                images += end - index
                imageBytes.append(contentsOf: bytes[index ..< end])
                index = end
            } else if matches(svgOpen, at: index), index + svgOpen.count < bytes.count, bytes[index + svgOpen.count] == 0x20 || bytes[index + svgOpen.count] == 0x3E || bytes[index + svgOpen.count] == 0x0A || bytes[index + svgOpen.count] == 0x09 {
                var end = index + svgOpen.count
                while end < bytes.count, !matches(svgClose, at: end) {
                    end += 1
                }
                end = min(bytes.count, end + svgClose.count)
                images += end - index
                imageBytes.append(contentsOf: bytes[index ..< end])
                index = end
            } else {
                index += 1
            }
        }
        return SourceSize(total: bytes.count, images: images, zlibTotal: HTMLWidgetPayload.compressedSize(bytes), zlibImages: HTMLWidgetPayload.compressedSize(imageBytes))
    }

    static func kilobytes(_ bytes: Int) -> String {
        let value = Double(bytes) / 1024
        return value < 10 ? String(format: "%.1f KB", value) : String(format: "%.0f KB", value)
    }

    static func sizeLine(_ size: SourceSize) -> String {
        let share = size.zlibTotal > 0 ? min(100, Double(size.zlibImages) / Double(size.zlibTotal) * 100) : 0
        return "zlib \(kilobytes(size.zlibTotal)) (raw \(kilobytes(size.total))) · images \(kilobytes(size.zlibImages)) (\(String(format: "%.0f%%", share)))"
    }

    static func reservedHeight(_ state: HTMLBubbleState) -> CGFloat {
        guard isEnabled(for: state) else {
            return 0
        }
        return gap + padding * 2 + CGFloat(lineCount(state)) * lineHeight
    }

    let layer = CALayer()
    private let textLayer = CATextLayer()
    private var previous: Sample?
    private var cachedSize: (version: Int, size: SourceSize)?

    init() {
        layer.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        layer.cornerRadius = 6
        layer.zPosition = 10
        layer.isHidden = true
        textLayer.isWrapped = false
        layer.addSublayer(textLayer)
    }

    func reset() {
        previous = nil
        if !layer.isHidden {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.isHidden = true
            CATransaction.commit()
        }
    }

    func update(state: HTMLBubbleState, bitmapBytes: Int, bounds: CGRect, scale: CGFloat) {
        let render = state.renderStats.snapshot
        let sandbox = state.twidgetSandboxStats
        let renderer = state.twidgetRendererStats
        let sample = Sample(time: CACurrentMediaTime(), app: HTMLProcessUsage.appCPUSeconds(), render: render, script: state.scriptMilliseconds, scriptFrames: state.scriptFrames, scene: state.scene3D?.stats, sandbox: sandbox?.jsMs ?? 0, rendererSeconds: renderer.map { ($0.update + $0.draw) / 1000 })
        defer {
            previous = sample
        }
        guard let previous = previous, sample.time - previous.time > 0.2 else {
            return
        }
        let elapsed = sample.time - previous.time
        let percent: (Double) -> String = { String(format: "%.1f%%", $0 / elapsed * 100) }
        let megabytes: (UInt64) -> String = { String(format: "%.0f MB", Double($0) / 1_048_576) }
        var lines: [String] = []
        if state.engine.usesWidgetSandbox {
            var line = "\(state.engine.title)  QuickJS \(percent((sample.sandbox - previous.sandbox) / 1000))"
            if let sandbox = sandbox {
                line += " · heap \(megabytes(UInt64(sandbox.memoryBytes)))"
            }
            lines.append(line)
            if state.engine == .webKit {
                lines.append("WebKit pool \(RendererPool.shared.count) ready · \(RendererPool.shared.recycled) reused")
            }
            if let renderer = renderer, let now = sample.rendererSeconds, let before = previous.rendererSeconds {
                lines.append("litehtml \(percent(now - before)) · \(renderer.composited) layers")
            }
        } else {
            let renders = sample.render.renders - previous.render.renders
            let cpu = Double(sample.render.cpuNanoseconds - previous.render.cpuNanoseconds) / 1_000_000_000
            let perFrame = renders > 0 ? cpu * 1000 / Double(renders) : sample.render.lastMilliseconds
            lines.append(String(format: "%@  %.2f ms × %.0f/s = %@", state.engine.title, perFrame, Double(renders) / elapsed, percent(cpu)))
            let scriptSeconds = (sample.script - previous.script) / 1000
            let scriptFrames = sample.scriptFrames - previous.scriptFrames
            var script = "JS \(percent(scriptSeconds))"
            if scriptFrames > 0 {
                script += String(format: " · %.0f/s × %.2f ms", Double(scriptFrames) / elapsed, scriptSeconds * 1000 / Double(scriptFrames))
            }
            lines.append(script + " · bitmaps \(String(format: "%.1f MB", Double(bitmapBytes) / 1_048_576))")
            if let scene = sample.scene, let before = previous.scene {
                let frames = scene.frames - before.frames
                let skipped = max(0, (scene.submitted - before.submitted) - frames)
                var line = String(format: "3D %.0f fps", Double(frames) / elapsed)
                if skipped > 1 {
                    line += String(format: " (%.0f/s skipped)", Double(skipped) / elapsed)
                }
                if !scene.gpuTimed {
                    line += " · GPU –"
                } else if frames > 0 {
                    let gpu = scene.gpuSeconds - before.gpuSeconds
                    line += String(format: " · GPU %.2f ms ", gpu * 1000 / Double(frames)) + "(\(percent(gpu)))"
                }
                if frames > 0 {
                    line += String(format: " · CPU %.2f ms", (scene.cpuSeconds - before.cpuSeconds) * 1000 / Double(frames))
                }
                lines.append(line)
                let triangles = scene.triangles >= 1000 ? String(format: "%.0fk", Double(scene.triangles) / 1000) : "\(scene.triangles)"
                lines.append("3D \(scene.draws) draws · \(triangles) tris · GPU memory \(megabytes(UInt64(scene.memoryBytes)))")
            }
        }
        let sourceSize: SourceSize
        if let cachedSize = cachedSize, cachedSize.version == state.contentVersion {
            sourceSize = cachedSize.size
        } else {
            sourceSize = HTMLBubbleStatsOverlay.sourceSize(state.source)
            cachedSize = (state.contentVersion, sourceSize)
        }
        lines.append(HTMLBubbleStatsOverlay.sizeLine(sourceSize))
        let scope = state.engine == .webKit ? "App only (excludes WebKit)" : "App"
        lines.append("\(scope) \(percent(sample.app - previous.app)) · \(megabytes(HTMLProcessUsage.appFootprint()))")
        let text = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        let size = text.size()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.string = text
        textLayer.contentsScale = scale
        textLayer.frame = CGRect(x: 6, y: 4, width: ceil(size.width), height: ceil(size.height))
        let width = ceil(size.width) + 12
        let reserved = HTMLBubbleStatsOverlay.reservedHeight(state)
        let height = min(ceil(size.height) + HTMLBubbleStatsOverlay.padding * 2, max(0, reserved - HTMLBubbleStatsOverlay.gap))
        layer.frame = CGRect(x: 0, y: max(0, bounds.height - reserved + HTMLBubbleStatsOverlay.gap), width: min(width, bounds.width), height: height)
        layer.isHidden = false
        CATransaction.commit()
    }
}
