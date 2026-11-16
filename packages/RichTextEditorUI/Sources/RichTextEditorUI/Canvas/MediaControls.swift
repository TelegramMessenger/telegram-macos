#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
public enum MediaControlsKind: Equatable { case singleImage, singleVideo, collage, slider }

@available(macOS 12, *)
public struct MediaControlsContext: Equatable {
    public let blockID: String
    public let kind: MediaControlsKind
    public let areaSize: CGSize
    public let tileFrames: [CGRect]
}

@available(macOS 12, *)
public protocol MediaGroupSliderSelectionProviding: AnyObject {
    var currentMediaIndex: Int? { get }
}

@available(macOS 12, *)
protocol MediaControlsProviding: CanvasBlock {
    var mediaControlsKind: MediaControlsKind? { get }
    var mediaAreaFrame: CGRect { get }
    func mediaTileFrames() -> [CGRect]
    /// Horizontal content margin, set by the canvas so a media block bleeds to the CURRENT canvas edge
    /// rather than a fixed page margin (lets a compact host use a small margin without clipping images).
    var contentMargin: CGFloat { get set }
}

@available(macOS 12, *)
extension ImageBlockBox: MediaControlsProviding {
    var mediaControlsKind: MediaControlsKind? { .singleImage }
    var mediaAreaFrame: CGRect { imageRect() }
    func mediaTileFrames() -> [CGRect] { [mediaAreaFrame] }
}

@available(macOS 12, *)
extension MediaBlockBox: MediaControlsProviding {
    var mediaControlsKind: MediaControlsKind? {
        switch kind {
        case .image: return .singleImage
        case .video: return .singleVideo
        default:     return nil
        }
    }
    var mediaAreaFrame: CGRect {
        let x = mediaBleeds ? frame.minX - contentMargin : frame.minX
        let w = mediaBleeds ? layoutWidth + contentMargin * 2 : layoutWidth
        return CGRect(x: x, y: mediaOrigin.y, width: w, height: mediaAreaHeight)
    }
    func mediaTileFrames() -> [CGRect] { [mediaAreaFrame] }
}

@available(macOS 12, *)
extension MediaGroupBlockBox: MediaControlsProviding {
    var mediaControlsKind: MediaControlsKind? { kind == .collage ? .collage : .slider }
    var mediaAreaFrame: CGRect {
        CGRect(origin: mediaOrigin, size: CGSize(width: canvasWidth, height: mediaAreaHeight))
    }
    func mediaTileFrames() -> [CGRect] {
        switch kind {
        case .collage:
            let o = mediaOrigin
            return tileFrames().map { $0.offsetBy(dx: o.x, dy: o.y) }
        case .slideshow:
            return [mediaAreaFrame]
        }
    }
}
#endif
