import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import TelegramUtils

private let customWallpaperMaxFileSize: Int32 = 10 * 1024 * 1024
private let customWallpaperMinPixelSide: CGFloat = 500
let customWallpaperMaxPixelSide: CGFloat = 4096
private let customWallpaperDownscaledQuality: Float = 0.9

func customWallpaperRepresentations(path: String, postbox: Postbox) -> [TelegramMediaImageRepresentation]? {
    guard let (image, data) = loadCustomWallpaperImage(path: path) else {
        return nil
    }

    var representations: [TelegramMediaImageRepresentation] = []

    let options = NSMutableDictionary()
    options.setValue(90 as NSNumber, forKey: kCGImageDestinationImageMaxPixelSize as String)
    let colorQuality: Float = 0.1
    options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
    let mutableData: CFMutableData = NSMutableData() as CFMutableData

    if let colorDestination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil) {
        CGImageDestinationAddImage(colorDestination, image, options as CFDictionary)
        if CGImageDestinationFinalize(colorDestination) {
            let thumbResource = LocalFileMediaResource(fileId: arc4random64())
            postbox.mediaBox.storeResourceData(thumbResource.id, data: mutableData as Data)
            representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(image.size.aspectFitted(NSMakeSize(90, 90))), resource: thumbResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
        }
    }

    let resource = LocalFileMediaResource(fileId: arc4random64(), size: Int64(data.count))
    postbox.mediaBox.storeResourceData(resource.id, data: data)
    representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(image.size), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))

    return representations
}

private func loadCustomWallpaperImage(path: String) -> (CGImage, Data)? {
    let url = URL(fileURLWithPath: path)
    let image: CGImage
    let data: Data
    if let size = fs(path), size < customWallpaperMaxFileSize, let pixelSize = imagePixelSize(url: url), max(pixelSize.width, pixelSize.height) <= customWallpaperMaxPixelSide {
        guard let original = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil), let originalData = try? Data(contentsOf: url) else {
            return nil
        }
        image = original
        data = originalData
    } else {
        guard let downscaled = downsampledImage(contentsOfFile: path, maxPixelSize: customWallpaperMaxPixelSide)?.cgImage(forProposedRect: nil, context: nil, hints: nil), max(downscaled.size.width, downscaled.size.height) <= customWallpaperMaxPixelSide, let downscaledData = compressImageToJPEG(downscaled, quality: customWallpaperDownscaledQuality), downscaledData.count < Int(customWallpaperMaxFileSize) else {
            return nil
        }
        image = downscaled
        data = downscaledData
    }
    guard image.size.width > customWallpaperMinPixelSide, image.size.height > customWallpaperMinPixelSide else {
        return nil
    }
    return (image, data)
}

private func imagePixelSize(url: URL) -> NSSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue, let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
        return nil
    }
    return NSMakeSize(CGFloat(width), CGFloat(height))
}
