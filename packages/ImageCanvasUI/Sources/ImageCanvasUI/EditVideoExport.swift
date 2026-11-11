import Foundation
import AVFoundation
import AudioToolbox
import CoreImage
import SwiftSignalKit
import Localization
import TelegramMediaUtils

public enum EditVideoTool: String, CaseIterable, Equatable {
    case enhance
    case exposure
    case contrast
    case saturation
    case warmth
    case fade
    case highlights
    case shadows
    case vignette

    public var title: String {
        switch self {
        case .enhance:
            return strings().editVideoExportEnhance
        case .exposure:
            return strings().editVideoExportBrightness
        case .contrast:
            return strings().editVideoExportContrast
        case .saturation:
            return strings().editVideoExportSaturation
        case .warmth:
            return strings().editVideoExportWarmth
        case .fade:
            return strings().editVideoExportFade
        case .highlights:
            return strings().editVideoExportHighlights
        case .shadows:
            return strings().editVideoExportShadows
        case .vignette:
            return strings().editVideoExportVignette
        }
    }

    public var minimum: Int {
        switch self {
        case .enhance, .fade, .vignette:
            return 0
        default:
            return -100
        }
    }

    public var maximum: Int {
        return 100
    }

    public var isBipolar: Bool {
        return minimum < 0
    }
}

public struct EditVideoTint: Equatable {
    public static let shadowsColors: [UInt32] = [0xff4d4d, 0xf48022, 0xffcd00, 0x81d281, 0x71c5d6, 0x0072bc, 0x662d91]
    public static let highlightsColors: [UInt32] = [0xef9286, 0xeacea2, 0xf2e17c, 0xa4edae, 0x89dce5, 0x2e8bc8, 0xcd98e5]

    public var shadowsColor: UInt32?
    public var shadowsIntensity: Int
    public var highlightsColor: UInt32?
    public var highlightsIntensity: Int

    public init(shadowsColor: UInt32? = nil, shadowsIntensity: Int = 50, highlightsColor: UInt32? = nil, highlightsIntensity: Int = 50) {
        self.shadowsColor = shadowsColor
        self.shadowsIntensity = shadowsIntensity
        self.highlightsColor = highlightsColor
        self.highlightsIntensity = highlightsIntensity
    }

    public var isDefault: Bool {
        return shadowsColor == nil && highlightsColor == nil
    }
}

public enum EditVideoQuality: Int, CaseIterable, Equatable {
    case veryLow = 1
    case low
    case medium
    case high
    case veryHigh

    public var maxSide: CGFloat {
        switch self {
        case .veryLow:
            return 480
        case .low:
            return 640
        case .medium:
            return 848
        case .high:
            return 1280
        case .veryHigh:
            return 1920
        }
    }

    public var videoBitrate: Int {
        switch self {
        case .veryLow:
            return 400_000
        case .low:
            return 700_000
        case .medium:
            return 1_600_000
        case .high:
            return 3_000_000
        case .veryHigh:
            return 6_600_000
        }
    }

    public var audioBitrate: Int {
        switch self {
        case .veryLow, .low:
            return 32_000
        default:
            return 64_000
        }
    }

    public var audioChannels: Int {
        switch self {
        case .veryLow, .low:
            return 1
        default:
            return 2
        }
    }

    public var title: String {
        switch self {
        case .veryLow:
            return "240p"
        case .low:
            return "360p"
        case .medium:
            return "480p"
        case .high:
            return "720p"
        case .veryHigh:
            return "1080p"
        }
    }

    public var shortTitle: String {
        switch self {
        case .veryLow:
            return "240"
        case .low:
            return "360"
        case .medium:
            return "480"
        case .high:
            return "720"
        case .veryHigh:
            return "HD"
        }
    }

    public static func bestAvailable(for size: CGSize) -> EditVideoQuality {
        let side = max(size.width, size.height)
        for quality in EditVideoQuality.allCases.reversed() where quality != .veryLow {
            if quality.maxSide <= side {
                return quality
            }
        }
        return .low
    }
}

public struct EditVideoOrientation: Equatable {
    public var degrees: Int
    public var mirrored: Bool

    public init(degrees: Int, mirrored: Bool) {
        self.degrees = degrees
        self.mirrored = mirrored
    }

    public static let up = EditVideoOrientation(degrees: 0, mirrored: false)

    var swapsSides: Bool {
        return degrees == 90 || degrees == -90
    }
}

public struct EditVideoRenderSpec {
    public var url: URL
    public var trimStart: Double
    public var trimEnd: Double
    public var isMuted: Bool
    public var tools: [EditVideoTool: Int]
    public var tint: EditVideoTint
    public var orientation: EditVideoOrientation
    public var crop: CGRect?
    public var overlay: CGImage?
    public var quality: EditVideoQuality?

    public init(url: URL, trimStart: Double, trimEnd: Double, isMuted: Bool, tools: [EditVideoTool: Int] = [:], tint: EditVideoTint = EditVideoTint(), orientation: EditVideoOrientation = .up, crop: CGRect? = nil, overlay: CGImage? = nil, quality: EditVideoQuality? = nil) {
        self.url = url
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.isMuted = isMuted
        self.tools = tools
        self.tint = tint
        self.orientation = orientation
        self.crop = crop
        self.overlay = overlay
        self.quality = quality
    }

    public var hasAdjustments: Bool {
        return tools.values.contains(where: { $0 != 0 }) || !tint.isDefault
    }

    public var needsRender: Bool {
        return hasAdjustments || orientation != .up || crop != nil || overlay != nil || quality != nil
    }
}

public enum EditVideoRenderer {
    private static let source = """
    float editSigmoid(float value, float strength) {
        float t = 1.0 / (1.0 - strength);
        if (value > 0.5) {
            return 1.0 - pow(2.0 - 2.0 * value, t) * 0.5;
        }
        return pow(2.0 * value, t) * 0.5;
    }
    vec3 editRaiseShadows(vec3 c) {
        return -0.003671 * c * c * c + 0.3842 * c * c + 0.3764 * c + 0.2515;
    }
    kernel vec4 editAdjustments(__sample s, vec4 a, vec4 b, vec4 tint, vec3 shadowsTint, vec3 highlightsTint, vec2 size) {
        float shadows = a.x;
        float highlights = a.y;
        float contrast = a.z;
        float fade = a.w;
        float saturation = b.x;
        float exposure = b.y;
        float warmth = b.z;
        float vignette = b.w;
        float epsilon = 0.005;
        vec3 result = clamp(s.rgb, 0.0, 1.0);
        if (abs(highlights) > epsilon || abs(shadows) > epsilon) {
            float mappedHighlights = highlights * 0.75 + 1.0;
            float mappedShadows = shadows * 0.55 + 1.0;
            float l = dot(result, vec3(0.3, 0.3, 0.3));
            float shadow = clamp((pow(l, 1.0 / mappedShadows) - 0.76 * pow(l, 2.0 / mappedShadows)) - l, 0.0, 1.0);
            float highlight = clamp((1.0 - (pow(1.0 - l, 1.0 / (2.0 - mappedHighlights)) - 0.8 * pow(1.0 - l, 2.0 / (2.0 - mappedHighlights)))) - l, -1.0, 0.0);
            vec3 hs = l > 0.00001 ? (l + shadow + highlight) * (result / l) : result;
            float cl = (l - 0.5) * 1.5 + 0.5;
            hs = mix(hs, vec3(1.0), cl * cl * cl * (clamp(mappedHighlights, 1.0, 2.0) - 1.0));
            float icl = 1.0 - cl;
            result = mix(hs, vec3(0.0), icl * icl * icl * (1.0 - clamp(mappedShadows, 0.0, 1.0)));
        }
        if (abs(contrast) > epsilon) {
            result = clamp((result - vec3(0.5)) * (contrast * 0.3 + 1.0) + vec3(0.5), 0.0, 1.0);
        }
        if (abs(fade) > epsilon) {
            vec3 curve = -0.9772 * result * result * result + 1.708 * result * result - 0.1603 * result + 0.2878;
            vec3 faded = result + (curve - result) * 0.9;
            result = result * (1.0 - fade) + faded * fade;
        }
        if (abs(saturation) > epsilon) {
            float mapped = saturation > 0.0 ? saturation * 1.05 : saturation;
            mapped += 1.0;
            float luminance = dot(result, vec3(0.2126, 0.7152, 0.0722));
            result = clamp(mix(vec3(luminance), result, mapped), 0.0, 1.0);
        }
        if (abs(tint.x) > epsilon) {
            vec3 raised = editRaiseShadows(result);
            vec3 tinted = mix(result, raised, shadowsTint);
            result = clamp(mix(result, tinted, tint.x * 2.0), 0.0, 1.0);
        }
        if (abs(tint.y) > epsilon) {
            vec3 lowered = vec3(1.0) - editRaiseShadows(vec3(1.0) - result);
            vec3 tinted = mix(result, lowered, vec3(1.0) - highlightsTint);
            result = clamp(mix(result, tinted, tint.y * 2.0), 0.0, 1.0);
        }
        if (abs(exposure) > epsilon) {
            float mag = exposure * 1.045;
            float power = 1.0 + abs(mag);
            if (mag < 0.0) {
                power = 1.0 / power;
            }
            result = vec3(1.0) - pow(max(vec3(1.0) - result, vec3(0.0)), vec3(power));
        }
        if (abs(warmth) > epsilon) {
            vec3 yuvVector = warmth > 0.0 ? vec3(0.1765, -0.1255, 0.0902) : -vec3(0.0588, 0.1569, -0.1255);
            float y = 0.299 * result.r + 0.587 * result.g + 0.114 * result.b;
            vec3 yuv = vec3(y, (result.b - y) / 1.772, (result.r - y) / 1.402);
            yuv += 0.375 * warmth * sin(y * 3.14159) * yuvVector;
            result = vec3(1.402 * yuv.z + yuv.x, yuv.x - (0.299 * 1.402 / 0.587) * yuv.z - (0.114 * 1.772 / 0.587) * yuv.y, 1.772 * yuv.y + yuv.x);
        }
        if (abs(vignette) > epsilon) {
            vec2 uv = destCoord() / size;
            float distance = length(uv - vec2(0.5)) / sqrt(0.5);
            float mag = editSigmoid(distance * 0.7, 0.62) * vignette * 0.645;
            result = mix(pow(max(result, vec3(0.0)), vec3(1.0 / (1.0 - mag))), vec3(0.0), mag * mag);
        }
        return vec4(result, s.a);
    }
    """

    private static let kernel: CIColorKernel? = CIColorKernel(source: source)

    public static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    static func components(_ hex: UInt32?) -> CIVector {
        guard let hex = hex else {
            return CIVector(x: 0, y: 0, z: 0)
        }
        return CIVector(x: CGFloat((hex >> 16) & 0xff) / 255.0, y: CGFloat((hex >> 8) & 0xff) / 255.0, z: CGFloat(hex & 0xff) / 255.0)
    }

    static func value(_ tool: EditVideoTool, in tools: [EditVideoTool: Int]) -> CGFloat {
        return CGFloat(tools[tool] ?? 0) / 100.0
    }

    public static func adjust(_ image: CIImage, tools: [EditVideoTool: Int], tint: EditVideoTint, enhance: [CIFilter]) -> CIImage {
        var result = image
        let extent = image.extent
        let enhanceValue = value(.enhance, in: tools)
        if enhanceValue > 0.005, !enhance.isEmpty {
            var enhanced = image
            for filter in enhance {
                filter.setValue(enhanced, forKey: kCIInputImageKey)
                if let output = filter.outputImage {
                    enhanced = output
                }
            }
            result = image.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: enhanced.cropped(to: extent), "inputTime": enhanceValue]).cropped(to: extent)
        }
        let others = EditVideoTool.allCases.filter { $0 != .enhance }
        guard let kernel = kernel, others.contains(where: { (tools[$0] ?? 0) != 0 }) || !tint.isDefault else {
            return result
        }
        let a = CIVector(x: value(.shadows, in: tools), y: value(.highlights, in: tools), z: value(.contrast, in: tools), w: value(.fade, in: tools))
        let b = CIVector(x: value(.saturation, in: tools), y: value(.exposure, in: tools), z: value(.warmth, in: tools), w: value(.vignette, in: tools))
        let shadowsIntensity = tint.shadowsColor == nil ? 0 : CGFloat(tint.shadowsIntensity) / 100.0
        let highlightsIntensity = tint.highlightsColor == nil ? 0 : CGFloat(tint.highlightsIntensity) / 100.0
        let tintVector = CIVector(x: shadowsIntensity, y: highlightsIntensity, z: 0, w: 0)
        let size = CIVector(x: extent.width, y: extent.height)
        let shifted = result.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        guard let output = kernel.apply(extent: shifted.extent, arguments: [shifted, a, b, tintVector, components(tint.shadowsColor), components(tint.highlightsColor), size]) else {
            return result
        }
        return output.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    public static func orient(_ image: CIImage, _ orientation: EditVideoOrientation) -> CIImage {
        let extent = image.extent
        let width = extent.width
        let height = extent.height
        let outWidth = orientation.swapsSides ? height : width
        let outHeight = orientation.swapsSides ? width : height
        var transform = CGAffineTransform(translationX: outWidth / 2.0, y: outHeight / 2.0)
        if orientation.mirrored {
            transform = transform.scaledBy(x: -1.0, y: 1.0)
        }
        transform = transform.rotated(by: CGFloat(orientation.degrees) * .pi / 180.0)
        transform = transform.translatedBy(x: -width / 2.0, y: -height / 2.0)
        let moved = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        return moved.transformed(by: transform).cropped(to: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
    }

    public static func cropRect(_ crop: CGRect?, in size: CGSize) -> CGRect {
        guard let crop = crop else {
            return CGRect(origin: .zero, size: size)
        }
        let width = (crop.width * size.width).rounded()
        let height = (crop.height * size.height).rounded()
        let rect = CGRect(x: (crop.minX * size.width).rounded(), y: ((1.0 - crop.maxY) * size.height).rounded(), width: width, height: height)
        return rect.intersection(CGRect(origin: .zero, size: size))
    }

    public static func croppedSize(display: CGSize, spec: EditVideoRenderSpec) -> CGSize {
        let oriented = spec.orientation.swapsSides ? CGSize(width: display.height, height: display.width) : display
        let rect = cropRect(spec.crop, in: oriented)
        return CGSize(width: max(1, rect.width), height: max(1, rect.height))
    }

    public static func outputSize(display: CGSize, spec: EditVideoRenderSpec) -> CGSize {
        let cropped = croppedSize(display: display, spec: spec)
        let quality = spec.quality ?? EditVideoQuality.bestAvailable(for: display)
        let scale = min(1.0, quality.maxSide / max(cropped.width, cropped.height))
        let width = max(16, floor(cropped.width * scale / 16.0) * 16.0)
        let height = max(2, (width * cropped.height / cropped.width / 2.0).rounded() * 2.0)
        return CGSize(width: width, height: height)
    }

    public static func render(_ source: CIImage, spec: EditVideoRenderSpec, enhance: [CIFilter], outputSize: CGSize?) -> CIImage {
        var image = adjust(source, tools: spec.tools, tint: spec.tint, enhance: enhance)
        if let overlay = spec.overlay {
            let extent = image.extent
            let overlayImage = CIImage(cgImage: overlay)
            let scaled = overlayImage.transformed(by: CGAffineTransform(scaleX: extent.width / overlayImage.extent.width, y: extent.height / overlayImage.extent.height).concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
            image = scaled.composited(over: image).cropped(to: extent)
        }
        image = orient(image, spec.orientation)
        let oriented = image.extent.size
        let rect = cropRect(spec.crop, in: oriented)
        image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        if let outputSize = outputSize, rect.width > 0, rect.height > 0 {
            image = image.transformed(by: CGAffineTransform(scaleX: outputSize.width / rect.width, y: outputSize.height / rect.height))
            image = image.cropped(to: CGRect(origin: .zero, size: outputSize))
        }
        return image
    }

    public static func enhanceFilters(for asset: AVAsset, at seconds: Double) -> [CIFilter] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        guard let frame = try? generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil) else {
            return []
        }
        return CIImage(cgImage: frame).autoAdjustmentFilters(options: [.redEye: false])
    }

    public static func videoComposition(for asset: AVAsset, spec: EditVideoRenderSpec, outputSize: CGSize?, enhanceAt seconds: Double = 0) -> AVMutableVideoComposition {
        let enhance = (spec.tools[.enhance] ?? 0) > 0 ? enhanceFilters(for: asset, at: seconds) : []
        let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let output = render(request.sourceImage, spec: spec, enhance: enhance, outputSize: outputSize)
            request.finish(with: output, context: context)
        })
        let display = composition.renderSize
        composition.renderSize = outputSize ?? croppedSize(display: display, spec: spec)
        if outputSize != nil, spec.hasAdjustments || spec.overlay != nil {
            composition.frameDuration = CMTime(value: 1, timescale: 30)
        }
        return composition
    }
}

public enum EditVideoExport {
    public static let minimumTrimDuration: Double = 1.0
    public static let minimumTrimmableDuration: Double = 1.5
    static let epsilon: Double = 0.01

    public static func duration(of url: URL) -> Double {
        let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    public static func hasAudio(_ url: URL) -> Bool {
        return !AVURLAsset(url: url).tracks(withMediaType: .audio).isEmpty
    }

    public static func displaySize(of url: URL) -> CGSize {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: .video).first else {
            return CGSize(width: 16, height: 9)
        }
        let size = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    public static func estimatedSize(duration: Double, quality: EditVideoQuality, muted: Bool) -> Int64 {
        let audio = muted ? 0 : quality.audioBitrate * quality.audioChannels
        return Int64(Double(quality.videoBitrate + audio) * duration / 8.0)
    }

    static func preferredAudioTrack(in asset: AVAsset) -> AVAssetTrack? {
        let tracks = asset.tracks(withMediaType: .audio)
        return tracks.first(where: { track in
            guard let description = track.formatDescriptions.first else { return false }
            return CMFormatDescriptionGetMediaSubType(description as! CMFormatDescription) == kAudioFormatMPEG4AAC
        }) ?? tracks.first
    }

    static func linearPCMAudioSettings(channelCount: Int) -> [String: Any] {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channelCount == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        return [AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: channelCount,
                AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)]
    }

    static func trimmedComposition(_ spec: EditVideoRenderSpec) -> AVMutableComposition? {
        let asset = AVURLAsset(url: spec.url)
        let duration = asset.duration
        guard let videoTrack = asset.tracks(withMediaType: .video).first, duration.seconds > 0 else {
            return nil
        }
        let start = CMTime(seconds: max(0, spec.trimStart), preferredTimescale: 600)
        let end = CMTimeMinimum(CMTime(seconds: spec.trimEnd, preferredTimescale: 600), duration)
        guard end > start else {
            return nil
        }
        let range = CMTimeRange(start: start, end: end)
        let composition = AVMutableComposition()
        do {
            guard let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return nil
            }
            try compositionVideo.insertTimeRange(range, of: videoTrack, at: .zero)
            compositionVideo.preferredTransform = videoTrack.preferredTransform
            if !spec.isMuted, let audioTrack = preferredAudioTrack(in: asset),
               let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compositionAudio.insertTimeRange(CMTimeRangeGetIntersection(range, otherRange: audioTrack.timeRange), of: audioTrack, at: .zero)
            }
        } catch {
            return nil
        }
        return composition
    }

    public static func outputDimensions(_ spec: EditVideoRenderSpec, display: CGSize) -> CGSize {
        if spec.needsRender {
            return EditVideoRenderer.outputSize(display: display, spec: spec)
        }
        return CGSize(width: floor(display.width), height: floor(display.height))
    }

    public static func frame(_ spec: EditVideoRenderSpec, maxSide: CGFloat) -> CGImage? {
        let asset = AVURLAsset(url: spec.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        guard let still = try? generator.copyCGImage(at: CMTime(seconds: spec.trimStart, preferredTimescale: 600), actualTime: nil) else {
            return nil
        }
        let enhance = (spec.tools[.enhance] ?? 0) > 0 ? EditVideoRenderer.enhanceFilters(for: asset, at: spec.trimStart) : []
        var image = EditVideoRenderer.render(CIImage(cgImage: still), spec: spec, enhance: enhance, outputSize: nil)
        let size = image.extent.size
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let scale = min(1.0, maxSide / max(size.width, size.height))
        let target = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
        image = image.transformed(by: CGAffineTransform(scaleX: target.width / size.width, y: target.height / size.height))
        return EditVideoRenderer.context.createCGImage(image, from: CGRect(origin: .zero, size: target))
    }

    public static func export(_ spec: EditVideoRenderSpec, to url: URL) -> Signal<Bool, NoError> {
        return export(spec) |> map { result in
            guard let result = result else {
                return false
            }
            try? FileManager.default.removeItem(at: url)
            if (try? FileManager.default.moveItem(at: result, to: url)) != nil {
                return true
            }
            try? FileManager.default.removeItem(at: result)
            return false
        }
    }

    public static func exportProgressively(_ spec: EditVideoRenderSpec, to url: URL, useStreamingWriter: Bool = true) -> Signal<PendingVideoRenderEvent, NoError> {
        return Signal { subscriber in
            guard url.standardizedFileURL != spec.url.standardizedFileURL else {
                subscriber.putNext(.completed(false))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            try? FileManager.default.removeItem(at: url)
            let cancelled = Atomic<Bool>(value: false)
            let exposedBody = Atomic<Bool>(value: false)
            let result: Signal<URL?, NoError>
            if useStreamingWriter, spec.needsRender {
                result = streamingReencode(spec, fileGrowth: { path, size, headerSize in
                    if size > PendingVideoRenderEvent.minimumStreamingSize {
                        _ = exposedBody.swap(true)
                    }
                    subscriber.putNext(.progress(path: path, size: size, headerSize: headerSize))
                }) |> mapToSignal { value -> Signal<URL?, NoError> in
                    if value == nil && !exposedBody.with({ $0 }) {
                        return reencode(spec)
                    }
                    return .single(value)
                }
            } else {
                result = export(spec)
            }
            let disposable = result.start(next: { result in
                guard !cancelled.with({ $0 }) else {
                    if let result { try? FileManager.default.removeItem(at: result) }
                    return
                }
                guard let result else {
                    subscriber.putNext(.completed(false))
                    subscriber.putCompletion()
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: url)
                    try FileManager.default.moveItem(at: result, to: url)
                    if cancelled.with({ $0 }) {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    subscriber.putNext(.completed(true))
                } catch {
                    try? FileManager.default.removeItem(at: result)
                    subscriber.putNext(.completed(false))
                }
                subscriber.putCompletion()
            })
            return ActionDisposable {
                _ = cancelled.swap(true)
                disposable.dispose()
            }
        }
    }

    static func export(_ spec: EditVideoRenderSpec) -> Signal<URL?, NoError> {
        if spec.needsRender {
            return reencode(spec)
        }
        return passthrough(spec)
    }

    static func passthrough(_ spec: EditVideoRenderSpec) -> Signal<URL?, NoError> {
        return Signal { subscriber in
            guard let composition = trimmedComposition(spec), let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let fileType: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
            let path = NSTemporaryDirectory() + "edited_video_\(Int64.random(in: 0 ... Int64.max))." + (fileType == .mp4 ? "mp4" : "mov")
            session.outputURL = URL(fileURLWithPath: path)
            session.outputFileType = fileType
            session.shouldOptimizeForNetworkUse = true
            session.exportAsynchronously {
                if session.status == .completed {
                    subscriber.putNext(URL(fileURLWithPath: path))
                } else {
                    try? FileManager.default.removeItem(atPath: path)
                    subscriber.putNext(nil)
                }
                subscriber.putCompletion()
            }
            return ActionDisposable {
                if session.status == .waiting || session.status == .exporting {
                    session.cancelExport()
                }
            }
        } |> runOn(.concurrentDefaultQueue())
    }

    static func streamingReencode(_ spec: EditVideoRenderSpec, fileGrowth: @escaping (String, Int64, Int64) -> Void) -> Signal<URL?, NoError> {
        return Signal { subscriber in
            let url = URL(fileURLWithPath: NSTemporaryDirectory() + "edited_video_stream_\(Int64.random(in: 0 ... Int64.max)).mp4")
            let stopped = Atomic<Bool>(value: false)
            let finished = Atomic<Bool>(value: false)
            let fail: () -> Void = {
                guard !finished.swap(true) else { return }
                try? FileManager.default.removeItem(at: url)
                subscriber.putNext(nil)
                subscriber.putCompletion()
            }
            guard let composition = trimmedComposition(spec), let reader = try? AVAssetReader(asset: composition) else {
                fail()
                return EmptyDisposable
            }
            let display = displaySize(of: spec.url)
            let outputSize = EditVideoRenderer.outputSize(display: display, spec: spec)
            let quality = spec.quality ?? EditVideoQuality.bestAvailable(for: display)
            let videoComposition = EditVideoRenderer.videoComposition(for: composition, spec: spec, outputSize: outputSize)
            let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: composition.tracks(withMediaType: .video), videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            videoOutput.videoComposition = videoComposition
            videoOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(videoOutput) else { fail(); return EmptyDisposable }
            reader.add(videoOutput)
            let audioTracks = composition.tracks(withMediaType: .audio)
            let audioOutput: AVAssetReaderAudioMixOutput?
            var audioSettings: [String: Any] = [:]
            if !spec.isMuted, !audioTracks.isEmpty {
                let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: linearPCMAudioSettings(channelCount: quality.audioChannels))
                guard reader.canAdd(output) else { fail(); return EmptyDisposable }
                reader.add(output)
                audioOutput = output
                audioSettings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: quality.audioChannels, AVEncoderBitRateKey: quality.audioBitrate]
            } else {
                audioOutput = nil
            }
            let sourceRate = composition.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30
            let configuration = EditVideoStreamingConfiguration(videoSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(outputSize.width), AVVideoHeightKey: Int(outputSize.height), AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: quality.videoBitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC]], audioSettings: audioSettings, dimensions: outputSize, frameRate: Int32(max(1, sourceRate.rounded())))
            let writer = EditVideoStreamingWriter(expectedDuration: composition.duration.seconds)
            writer.setup(configuration: configuration, outputPath: url.path)
            writer.setupVideoInput(configuration: configuration, preferredTransform: nil, sourceFrameRate: sourceRate)
            if audioOutput != nil { writer.setupAudioInput(configuration: configuration) }
            writer.onFileGrowth = { size, headerSize in
                if !stopped.with({ $0 }), !finished.with({ $0 }) {
                    fileGrowth(url.path, size, headerSize)
                }
            }
            guard reader.startReading(), writer.startWriting() else {
                reader.cancelReading()
                writer.cancelWriting()
                fail()
                return EmptyDisposable
            }
            writer.startSession(atSourceTime: .zero)
            let queue = DispatchQueue(label: "org.telegram.editVideo.streaming")
            let remaining = Atomic<Int>(value: audioOutput == nil ? 1 : 2)
            let finish: () -> Void = {
                guard !stopped.with({ $0 }), reader.status != .failed, reader.status != .cancelled else {
                    reader.cancelReading()
                    writer.cancelWriting()
                    fail()
                    return
                }
                writer.finishWriting {
                    guard !stopped.with({ $0 }), writer.status == .completed, !writer.wroteMoovAtEnd else { fail(); return }
                    guard !finished.swap(true) else { return }
                    subscriber.putNext(url)
                    subscriber.putCompletion()
                }
            }
            writer.requestVideoDataWhenReady(on: queue) {
                while writer.isReadyForMoreVideoData {
                    if !stopped.with({ $0 }), reader.status == .reading, let buffer = videoOutput.copyNextSampleBuffer() {
                        if !writer.appendVideoBuffer(buffer) {
                            _ = stopped.swap(true)
                            reader.cancelReading()
                            writer.cancelWriting()
                            fail()
                            return
                        }
                    } else {
                        writer.markVideoAsFinished()
                        if remaining.modify({ $0 - 1 }) == 0 { finish() }
                        return
                    }
                }
            }
            if let audioOutput {
                writer.requestAudioDataWhenReady(on: queue) {
                    while writer.isReadyForMoreAudioData {
                        if !stopped.with({ $0 }), reader.status == .reading, let buffer = audioOutput.copyNextSampleBuffer() {
                            if !writer.appendAudioBuffer(buffer) {
                                _ = stopped.swap(true)
                                reader.cancelReading()
                                writer.cancelWriting()
                                fail()
                                return
                            }
                        } else {
                            writer.markAudioAsFinished()
                            if remaining.modify({ $0 - 1 }) == 0 { finish() }
                            return
                        }
                    }
                }
            }
            return ActionDisposable {
                if !finished.swap(true) {
                    _ = stopped.swap(true)
                    reader.cancelReading()
                    writer.cancelWriting()
                    writer.onFileGrowth = nil
                    try? FileManager.default.removeItem(at: url)
                }
            }
        } |> runOn(.concurrentDefaultQueue())
    }

    static func reencode(_ spec: EditVideoRenderSpec) -> Signal<URL?, NoError> {
        return Signal { subscriber in
            let url = URL(fileURLWithPath: NSTemporaryDirectory() + "edited_video_\(Int64.random(in: 0 ... Int64.max)).mp4")
            let fail: () -> Void = {
                try? FileManager.default.removeItem(at: url)
                subscriber.putNext(nil)
                subscriber.putCompletion()
            }
            guard let composition = trimmedComposition(spec), let reader = try? AVAssetReader(asset: composition), let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
                fail()
                return EmptyDisposable
            }
            let display = displaySize(of: spec.url)
            let outputSize = EditVideoRenderer.outputSize(display: display, spec: spec)
            let quality = spec.quality ?? EditVideoQuality.bestAvailable(for: display)
            let videoComposition = EditVideoRenderer.videoComposition(for: composition, spec: spec, outputSize: outputSize)

            let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: composition.tracks(withMediaType: .video), videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            videoOutput.videoComposition = videoComposition
            videoOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(videoOutput) else {
                fail()
                return EmptyDisposable
            }
            reader.add(videoOutput)

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(outputSize.width),
                AVVideoHeightKey: Int(outputSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: quality.videoBitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC
                ]
            ])
            videoInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(videoInput) else {
                fail()
                return EmptyDisposable
            }
            writer.add(videoInput)

            var pairs: [(AVAssetReaderOutput, AVAssetWriterInput, String)] = [(videoOutput, videoInput, "video")]
            let audioTracks = composition.tracks(withMediaType: .audio)
            if !spec.isMuted, !audioTracks.isEmpty {
                let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: linearPCMAudioSettings(channelCount: quality.audioChannels))
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: quality.audioChannels,
                    AVEncoderBitRateKey: quality.audioBitrate
                ])
                input.expectsMediaDataInRealTime = false
                if reader.canAdd(output), writer.canAdd(input) {
                    reader.add(output)
                    writer.add(input)
                    pairs.append((output, input, "audio"))
                }
            }

            writer.shouldOptimizeForNetworkUse = true
            guard reader.startReading(), writer.startWriting() else {
                fail()
                return EmptyDisposable
            }
            writer.startSession(atSourceTime: .zero)

            let remaining = Atomic<Int>(value: pairs.count)
            let stopped = Atomic<Bool>(value: false)
            let finish: () -> Void = {
                if stopped.with({ $0 }) || reader.status == .failed || reader.status == .cancelled {
                    if reader.status == .reading {
                        reader.cancelReading()
                    }
                    if writer.status == .writing {
                        writer.cancelWriting()
                    }
                    fail()
                    return
                }
                writer.finishWriting {
                    if writer.status == .completed {
                        subscriber.putNext(url)
                        subscriber.putCompletion()
                    } else {
                        fail()
                    }
                }
            }
            for (output, input, label) in pairs {
                let queue = DispatchQueue(label: "org.telegram.editVideo.\(label)")
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        var done = false
                        if !stopped.with({ $0 }), reader.status == .reading, let buffer = output.copyNextSampleBuffer() {
                            if !input.append(buffer) {
                                _ = stopped.swap(true)
                                done = true
                            }
                        } else {
                            done = true
                        }
                        if done {
                            input.markAsFinished()
                            if remaining.modify({ $0 - 1 }) == 0 {
                                finish()
                            }
                            return
                        }
                    }
                }
            }
            return ActionDisposable {
                _ = stopped.swap(true)
            }
        } |> runOn(.concurrentDefaultQueue())
    }
}
