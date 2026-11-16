import Cocoa
import TelegramCore
import ApiCredentials
import Postbox
import SwiftSignalKit
import TGUIKit
import libwebp
import GZIP
import Svg
import TelegramMedia
import TelegramMediaPlayer

import AppKit
import FoundationUtils
import TelegramMediaResources
import ThemeSettings
import TelegramUtils
import TelegramContext
import TelegramTheme
import ImageIO
import CoreMedia
import AVFoundation

public func makeLottieImage(from zippedData: Data,
                     key: String,
                     size: NSSize = NSMakeSize(512, 512),
                     scale: CGFloat = 2.0,
                     maxUnzip: UInt32 = 8 * 1024 * 1024) -> NSImage? {
    return autoreleasepool {
        guard let data = TGGUnzipData(zippedData, maxUnzip) else { return nil }
        guard let json = String(data: data, encoding: .utf8), !json.isEmpty else { return nil }
        guard let renderer = LottieRenderHooks.shared.makeRenderer(json) else { return nil }

        let pixelW = max(1, Int(size.width  * scale))
        let pixelH = max(1, Int(size.height * scale))

        let bytesPerRow = DeviceGraphicsContextSettings.shared.bytesPerRow(forWidth: pixelW)
        let bufferSize  = pixelH * bytesPerRow

        guard let memory = malloc(bufferSize) else { return nil }
        defer { free(memory) }

        let frameData = memory.assumingMemoryBound(to: UInt8.self)

        renderer.renderFrame(with: 0,
                            into: frameData,
                            width: Int32(pixelW),
                            height: Int32(pixelH),
                            bytesPerRow: Int32(bytesPerRow))

        // Build NSImage from raw BGRA bytes using your helper
        let image = generateImagePixel(size, scale: scale) { (_, pixelDst, dstBPR) in
            // Fast path when strides match
            if dstBPR == bytesPerRow {
                memcpy(pixelDst, frameData, bufferSize)
            } else {
                // Safe row-by-row copy if generateImagePixel requested different stride
                for row in 0..<pixelH {
                    let src = frameData.advanced(by: row * bytesPerRow)
                    let dst = pixelDst.advanced(by: row * dstBPR)
                    memcpy(dst, src, min(bytesPerRow, dstBPR))
                }
            }
        }
        if let image {
            return NSImage(cgImage: image, size: size)
        } else {
            return nil
        }
    }
}


private let cacheThreadPool = ThreadPool(threadCount: 1, threadPriority: 0.1)


public func fetchCachedResourceRepresentation(account: Account, resource: MediaResource, representation: CachedMediaResourceRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    if let representation = representation as? CachedStickerAJpegRepresentation {
        return fetchCachedStickerAJpegRepresentation(account: account, resource: resource, representation: representation)
    } else if let representation = representation as? CachedAnimatedStickerRepresentation {
        return fetchCachedAnimatedStickerRepresentation(account: account, resource: resource, representation: representation)
    } else if let representation = representation as? CachedScaledImageRepresentation {
        return fetchCachedScaledImageRepresentation(account: account, resource: resource, representation: representation)
    } else if representation is CachedVideoFirstFrameRepresentation {
        let fromResource = account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> mapToSignal { data -> Signal<CachedMediaResourceRepresentationResult, NoError> in
                if data.complete {
                    return fetchCachedVideoFirstFrameRepresentation(account: account, resource: resource, resourceData: data)
                        |> `catch` { _ -> Signal<CachedMediaResourceRepresentationResult, NoError> in
                            return .complete()
                    }
                } else if let size = resource.size {
                    return videoFirstFrameData(account: account, resource: resource, chunkSize: min(size, 192 * 1024))
                } else {
                    return .complete()
                }
        }
        if let resource = resource as? LocalFileVideoMediaResource, let info = PendingVideoRenders.shared.info(for: resource.path) {
            return Signal<Data?, NoError> { subscriber in
                subscriber.putNext(info.frame)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(cacheThreadPool)
            |> mapToSignal { frame -> Signal<CachedMediaResourceRepresentationResult, NoError> in
                let file = TempBox.shared.tempFile(fileName: "frame.jpg")
                if let frame = frame, (try? frame.write(to: URL(fileURLWithPath: file.path))) != nil {
                    return .single(.tempFile(file))
                }
                return fromResource
            }
        }
        return fromResource
    } else if let representation = representation as? CachedScaledVideoFirstFrameRepresentation {
        return fetchCachedScaledVideoFirstFrameRepresentation(account: account, resource: resource, representation: representation)
    } else if let representation = representation as? CachedDiceRepresentation {
        if let diceCache = MediaRenderHooks.shared.diceCache() {
            return diceCache.interactiveSymbolData(baseSymbol: representation.emoji, synchronous: false) |> map { values -> (String, Data?, TelegramMediaFile)? in
                for value in values {
                    if value.0.withoutColorizer == representation.value {
                        return value
                    }
                }
                return nil
            } |> filter { $0?.1 != nil } |> mapToSignal { data in
                return fetchCachedDiceRepresentation(account: account, data: data!.1!, representation: representation)
            }
        } else {
            return .complete()
        }
    } else if let representation = representation as? CachedSlotMachineRepresentation {
        if let diceCache = MediaRenderHooks.shared.diceCache() {
            return diceCache.interactiveSymbolData(baseSymbol: slotsEmoji, synchronous: false) |> filter { $0.count >= 21 } |> map { values -> [(Data?, Int32)] in
                var required: [(Data?, Int32)] = []
                required.append((values[1].1, 1))
                switch representation.value.left {
                case .rolling:
                    required.append((values[representation.value.packIndex[0]].1, 1))
                default:
                    required.append((values[representation.value.packIndex[0]].1, .max))
                }
                switch representation.value.center {
                case .rolling:
                    required.append((values[representation.value.packIndex[1]].1, 1))
                default:
                    required.append((values[representation.value.packIndex[1]].1, .max))
                }
                switch representation.value.right {
                case .rolling:
                    required.append((values[representation.value.packIndex[2]].1, 1))
                default:
                    required.append((values[representation.value.packIndex[2]].1, .max))
                }
                required.append((values[2].1, 1))
                return required
                } |> filter { !$0.contains(where: { $0.0 == nil} ) } |> map { $0.map { ($0.0!, $0.1) }} |> mapToSignal { data in
                return fetchCachedSlotRepresentation(account: account, data: data, representation: representation)
            }
        } else {
            return .complete()
        }
    } else if let representation = representation as? CachedBlurredWallpaperRepresentation {
        return account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> mapToSignal { data -> Signal<CachedMediaResourceRepresentationResult, NoError> in
                if !data.complete {
                    return .complete()
                }
                return fetchCachedBlurredWallpaperRepresentation(account: account, resource: resource, resourceData: data, representation: representation)
        }
    } else if let representation = representation as? CachedPatternWallpaperMaskRepresentation {
        
        let patternSignal = representation.pattern.flatMap {
            return account.postbox.mediaBox.resourceData($0.resource, option: .complete(waitUntilFetchStatus: false)) |> map(Optional.init)
        } ?? .single(nil)
        
        let modelSignal = representation.model.flatMap {
            return account.postbox.mediaBox.resourceData($0.resource, option: .complete(waitUntilFetchStatus: false)) |> map(Optional.init)
        } ?? .single(nil)
        
        let resourceSignal = account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        
        return combineLatest(resourceSignal, modelSignal, patternSignal)
            |> mapToSignal { data, modelData, patternData -> Signal<CachedMediaResourceRepresentationResult, NoError> in
                if !data.complete {
                    return .complete()
                }
                if let modelData, !modelData.complete {
                    return .complete()
                }
                if let patternData, !patternData.complete {
                    return .complete()
                }
                return fetchCachedPatternWallpaperMaskRepresentation(account: account, resource: resource, resourceData: data, representation: representation, modelData: modelData, patternData: patternData)
        }
    } else if let resource = resource as? MapSnapshotMediaResource, let _ = representation as? MapSnapshotMediaResourceRepresentation {
        return fetchMapSnapshotResource(resource: resource)
    }




    return .never()
}


public func fetchCachedSharedResourceRepresentation(accountManager: AccountManager<TelegramAccountManagerTypes>, resource: MediaResource, representation: CachedMediaResourceRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    fatalError()
}


private func fetchCachedPatternWallpaperMaskRepresentation(account: Account, resource: MediaResource, resourceData: MediaResourceData, representation: CachedPatternWallpaperMaskRepresentation, modelData: MediaResourceData?, patternData: MediaResourceData?) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    return Signal({ subscriber in
        if let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: [.mappedIfSafe]) {
            
            var svgPath: String?
            
            let path = NSTemporaryDirectory() + "\(arc4random64())"
            let url = URL(fileURLWithPath: path)
            
            var fillSlot: Array<[String:Any]> = Array()
            
            if let data = TGGUnzipData(data, 8 * 1024 * 1024), data.count > 5, let string = String(data: data.subdata(in: 0 ..< 5), encoding: .utf8), string == "<?xml" {
                
                let size = NSMakeSize(400, 800)
                
                if let patternData = patternData, let pattern = representation.pattern {
                    let data = try? Data(contentsOf: URL(fileURLWithPath: patternData.path), options: [.mappedIfSafe])
                    let size = pattern.dimensions?.size ?? NSMakeSize(512, 512)

                    if let data, let patternImage = makeLottieImage(from: data, key: patternData.path, size: size) {
                        fillSlot.append(["image": patternImage,
                                         "pattern": NSNumber(value: true)])
                    }
                }

                if let nsImage = drawSvgImageNano(data, size, fillSlot), let drawn = nsImage._cgImage {
                    let image = imageWithEightBitChannels(drawn) ?? drawn
                    
                    
                    if let alphaDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
                        CGImageDestinationSetProperties(alphaDestination, [:] as CFDictionary)
                        
                        let colorQuality: Float = 0.6
                        
                        let options = NSMutableDictionary()
                        options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                        
                        CGImageDestinationAddImage(alphaDestination, image, options as CFDictionary)
                        if CGImageDestinationFinalize(alphaDestination) {
                           svgPath = path
                        }
                    }
                }
            } else if let decoded = NSImage(data: data)?._cgImage {
                let image = imageWithEightBitChannels(decoded) ?? decoded
                
              
                if let alphaDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
                    CGImageDestinationSetProperties(alphaDestination, [:] as CFDictionary)
                    
                    let colorQuality: Float = 0.6
                    
                    let options = NSMutableDictionary()
                    options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                    
                    CGImageDestinationAddImage(alphaDestination, image, options as CFDictionary)
                    if CGImageDestinationFinalize(alphaDestination) {
                        svgPath = path
                    }
                }
            }
            
            if let path = svgPath {
                if let image = NSImage(contentsOfFile: path)?._cgImage {

                    let finalPath = NSTemporaryDirectory() + "\(arc4random64())"
                    let url = URL(fileURLWithPath: finalPath)
                    
                    if let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
                        CGImageDestinationSetProperties(dest, [:] as CFDictionary)
                        
                        let colorQuality: Float = 0.6
                        
                        let options = NSMutableDictionary()
                        options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                        
                        CGImageDestinationAddImage(dest, image, options as CFDictionary)
                        if CGImageDestinationFinalize(dest) {
                            try? FileManager.default.removeItem(atPath: path)
                            subscriber.putNext(.temporaryPath(finalPath))
                            subscriber.putCompletion()
                        }
                    }
                }
            }
            
        }
        return EmptyDisposable
    }) |> runOn(Queue.concurrentDefaultQueue())
}


private func accountRecordIdPathName(_ id: AccountRecordId) -> String {
    return "account-\(UInt64(bitPattern: id.int64))"
}


public enum FetchVideoFirstFrameError {
    case generic
}


private func videoFirstFrameData(account: Account, resource: MediaResource, chunkSize: Int64) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    if let size = resource.size {
        return account.postbox.mediaBox.resourceData(resource, size: size, in: 0 ..< min(size, chunkSize))
            |> mapToSignal { _ -> Signal<CachedMediaResourceRepresentationResult, NoError> in
                 return account.postbox.mediaBox.resourceData(resource, option: .incremental(waitUntilFetchStatus: false), attemptSynchronously: false)
                    |> mapToSignal { data -> Signal<CachedMediaResourceRepresentationResult, NoError> in
                        return fetchCachedVideoFirstFrameRepresentation(account: account, resource: resource, resourceData: data)
                            |> `catch` { _ -> Signal<CachedMediaResourceRepresentationResult, NoError> in
                                if chunkSize >= size {
                                    return .complete()
                                } else {
                                    return videoFirstFrameData(account: account, resource: resource, chunkSize: chunkSize + chunkSize)
                                }
                        }
                }
        }
    } else {
        return .complete()
    }
}



private func fetchCachedVideoFirstFrameRepresentation(account: Account, resource: MediaResource, resourceData: MediaResourceData) -> Signal<CachedMediaResourceRepresentationResult, FetchVideoFirstFrameError> {
    return Signal { subscriber in
        let tempFilePath = NSTemporaryDirectory() + "\(arc4random()).mov"
        do {
            let _ = try? FileManager.default.removeItem(atPath: tempFilePath)
            try FileManager.default.createSymbolicLink(atPath: tempFilePath, withDestinationPath: resourceData.path)
            
            let asset = AVAsset(url: URL(fileURLWithPath: tempFilePath))
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.maximumSize = CGSize(width: 800.0, height: 800.0)
            imageGenerator.appliesPreferredTrackTransform = true
            
            let fullSizeImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 0.0, preferredTimescale: asset.duration.timescale), actualTime: nil)
            
            
            var randomId: Int64 = 0
            arc4random_buf(&randomId, 8)
            let path = NSTemporaryDirectory() + "\(randomId)"
            let url = URL(fileURLWithPath: path)
            
            if let colorDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) {
                CGImageDestinationSetProperties(colorDestination, [:] as CFDictionary)
                
                let colorQuality: Float = 0.6
                
                let options = NSMutableDictionary()
                options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                
                CGImageDestinationAddImage(colorDestination, fullSizeImage, options as CFDictionary)
                if CGImageDestinationFinalize(colorDestination) {
                    subscriber.putNext(.tempFile(TempBox.shared.tempFile(fileName: path.nsstring.lastPathComponent)))
                    subscriber.putCompletion()
                }
            }
        } catch {
            subscriber.putError(.generic)
            subscriber.putCompletion()
        }
        let _ = try? FileManager.default.removeItem(atPath: tempFilePath)
        return EmptyDisposable
    } |> runOn(cacheThreadPool)
}


private func fetchCachedAnimatedStickerRepresentation(account: Account, resource: MediaResource, representation: CachedAnimatedStickerRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
   
    let data: Signal<MediaResourceData, NoError>
    if let resource = resource as? LocalBundleResource {
        data = Signal { subscriber in
            if let path = Bundle.main.path(forResource: resource.name, ofType: resource.ext), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedRead]) {
                subscriber.putNext(MediaResourceData(path: path, offset: 0, size: Int64(data.count), complete: true))
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    } else {
        data = account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
    }

    return data |> deliverOn(lottieThreadPool) |> map { resourceData -> (CGImage?, Data?, MediaResourceData) in
        if resourceData.complete {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: [.mappedIfSafe]) {
                return (nil, data, resourceData)
            }
        }
        return (nil, nil, resourceData)
    } |> runOn(cacheThreadPool) |> mapToSignal { frame, data, resourceData in
        if resourceData.complete {
            if let data = data {
                
                let path = NSTemporaryDirectory() + "\(arc4random64())"
                let url = URL(fileURLWithPath: path)
                
                let colorData = NSMutableData()
                
                var image: CGImage?
                if representation.isVideo {
                    let decoder = SoftwareVideoSource(path: resourceData.path, hintVP9: true, unpremultiplyAlpha: true)
                    image = decoder.preview(size: representation.size, backingScale: 2)
                } else {
                    image = convertFromWebP(data)?._cgImage ?? NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    
                    if image == nil, let data = TGGUnzipData(data, 8 * 1024 * 1024) {
                        if let json = String(data: transformedWithFitzModifier(data: data, fitzModifier: representation.fitzModifier), encoding: .utf8), json.length > 0 {
                            let renderer = LottieRenderHooks.shared.makeRenderer(json)
                            
                            let s:(w: Int, h: Int) = (w: Int(representation.size.width) * 2, h: Int(representation.size.height) * 2)

                            let bytesPerRow = DeviceGraphicsContextSettings.shared.bytesPerRow(forWidth: s.w)
                            let bufferSize = s.h * bytesPerRow
                            let memoryData = malloc(bufferSize)!
                            let frameData = memoryData.assumingMemoryBound(to: UInt8.self)
                            
                            renderer?.renderFrame(with: 0, into: frameData, width: Int32(s.w), height: Int32(s.h), bytesPerRow: Int32(bytesPerRow))
                            
                            image = generateImagePixel(representation.size, scale: 2, pixelGenerator: { (_, pixelData, bytesPerRow) in
                                memcpy(pixelData, frameData, bufferSize)
                            })
                            free(memoryData)
                        }
                    } else if image != nil {
                        let webp = WebPImageDecoder(data: data, scale: 2.0)
                        let fullSizeWebp = webp?.frame(at: 0, decodeForDisplay: true)?.image?._cgImage
                        image = fullSizeWebp ?? image
                    }
                }
               
                
                if let image = image, let colorDestination = CGImageDestinationCreateWithData(colorData as CFMutableData, kUTTypePNG, 1, nil) {
                    CGImageDestinationSetProperties(colorDestination, [:] as CFDictionary)
                    
                    let colorQuality: Float
                    colorQuality = 0.4
                    
                    let options = NSMutableDictionary()
                    options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                    CGImageDestinationAddImage(colorDestination, image, options as CFDictionary)
                    if CGImageDestinationFinalize(colorDestination)  {
                        try? colorData.write(to: url, options: .atomic)
                        return .single(.temporaryPath(path))
                    }
                } else {
                    return .complete()
                }
            }
        }
        return .never()
    }
}

private func fetchCachedStickerAJpegRepresentation(account: Account, resource: MediaResource, representation: CachedStickerAJpegRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    
    let signal: Signal<MediaResourceData?, NoError>
    
    if resource is LocalFileReferenceMediaResource {
        signal = .single(nil)
    } else {
        signal = account.postbox.mediaBox.resourceData(resource) |> map(Optional.init)
    }
    
    return signal |> mapToSignal { resourceData in
        return Signal { subscriber in
            
            let complete: Bool
            let resourcePath: String?
            if let resourceData = resourceData {
                resourcePath = resourceData.path
                complete = resourceData.complete
            } else if let resource = resource as? LocalFileReferenceMediaResource {
                resourcePath = resource.localFilePath
                complete = true
            } else {
                resourcePath = nil
                complete = false
            }
            
            if let resourcePath = resourcePath, let data = try? Data(contentsOf: URL(fileURLWithPath: resourcePath), options: [.mappedIfSafe]), complete {
                let image = convertFromWebP(data)?._cgImage ?? NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                if let image = image, let containerUrl = ApiEnvironment.containerURL {
                    var randomId: Int64 = 0
                    arc4random_buf(&randomId, 8)
                    let directory = "\(containerUrl.path)/\(accountRecordIdPathName(account.id))/cached/"
                    try? FileManager.default.createDirectory(at: URL(fileURLWithPath: directory), withIntermediateDirectories: true, attributes: nil)
                    let path: String = directory + "\(randomId)"
                    let url = URL(fileURLWithPath: path)
                    
                    let colorData = NSMutableData()
                    
                    
                    let size:CGSize
                    if let s = representation.size {
                        size = s
                    } else {
                        size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
                    }
                    
                    let colorImage: CGImage
                    if let _ = representation.size {
                        colorImage = generateImage(size, contextGenerator: { size, context in
                            context.setBlendMode(.copy)
                            context.draw(image, in: CGRect(origin: CGPoint(), size: size))
                        })!
                    } else {
                        colorImage = image
                    }
                    if let colorDestination = CGImageDestinationCreateWithData(colorData as CFMutableData, kUTTypePNG, 1, nil) {
                        CGImageDestinationSetProperties(colorDestination, [:] as CFDictionary)
                        
                        let colorQuality: Float
                        if representation.size == nil {
                            colorQuality = 0.6
                        } else {
                            colorQuality = 0.3
                        }
                        
                        let options = NSMutableDictionary()
                        options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                        
                        CGImageDestinationAddImage(colorDestination, colorImage, options as CFDictionary)
                        if CGImageDestinationFinalize(colorDestination) {
                            let _ = try? colorData.write(to: url, options: [.atomic])
                            subscriber.putNext(.temporaryPath(path))
                            subscriber.putCompletion()
                        }
                    } else {
                        subscriber.putCompletion()
                    }
                } else {
                    subscriber.putCompletion()
                }
            }
            return EmptyDisposable
        } |> runOn(cacheThreadPool)
    }
}

private func fetchCachedScaledImageRepresentation(account: Account, resource: MediaResource, representation: CachedScaledImageRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    return account.postbox.mediaBox.resourceData(resource) |> mapToSignal { resourceData in
        return Signal { subscriber in
            if let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: [.mappedIfSafe]) {
                if let image = NSImage(data: data) {
                    var randomId: Int64 = 0
                    arc4random_buf(&randomId, 8)
                    let path = NSTemporaryDirectory() + "\(randomId)"
                    let url = URL(fileURLWithPath: path)
                    
                    let size = representation.size
                    
                    let colorImage = generateImage(size, contextGenerator: { size, context in
                        context.setBlendMode(.copy)
                        if let image = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            context.draw(image, in: CGRect(origin: CGPoint(), size: size))
                        }
                    })!
                    
                    if let colorDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) {
                        CGImageDestinationSetProperties(colorDestination, nil)
                        
                        let colorQuality: Float = 0.5
                        
                        let options = NSMutableDictionary()
                        options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                        
                        CGImageDestinationAddImage(colorDestination, colorImage, options as CFDictionary)
                        if CGImageDestinationFinalize(colorDestination) {
                            subscriber.putNext(.temporaryPath(path))
                            subscriber.putCompletion()
                        }
                    }
                }
            }
            return EmptyDisposable
        } |> runOn(cacheThreadPool)
    }
}

private func fetchCachedVideoFirstFrameRepresentation(account: Account, resource: MediaResource, representation: CachedVideoFirstFrameRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    return account.postbox.mediaBox.resourceRangesStatus(resource) |> mapToSignal { _ in
        return account.postbox.mediaBox.resourceData(resource) |> take(1)
    } |> runOn(cacheThreadPool) |> mapToSignal { resourceData in
        let tempFilePath = NSTemporaryDirectory() + "\(resourceData.path.nsstring.lastPathComponent).mp4"
        let _ = try? FileManager.default.removeItem(atPath: tempFilePath)
        try? FileManager.default.createSymbolicLink(atPath: resourceData.path, withDestinationPath: tempFilePath)
        
        let asset = AVAsset(url: URL(fileURLWithPath: tempFilePath))
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.maximumSize = CGSize(width: 800.0, height: 800.0)
        imageGenerator.appliesPreferredTrackTransform = true
        let fullSizeImage = try? imageGenerator.copyCGImage(at: CMTime(seconds: 0.0, preferredTimescale: asset.duration.timescale), actualTime: nil)
        
        var randomId: Int64 = 0
        arc4random_buf(&randomId, 8)
        let path = NSTemporaryDirectory() + "\(randomId)"
        let url = URL(fileURLWithPath: path)
        
        if let fullSizeImage = fullSizeImage, let colorDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) {
            CGImageDestinationSetProperties(colorDestination, nil)
            
            let colorQuality: Float = 0.6
            
            let options = NSMutableDictionary()
            options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
            
            CGImageDestinationAddImage(colorDestination, fullSizeImage, options as CFDictionary)
            if CGImageDestinationFinalize(colorDestination) {
                return .single(.temporaryPath(path))
            }
        }
        return .never()
    }
}


private func fetchCachedScaledVideoFirstFrameRepresentation(account: Account, resource: MediaResource, representation: CachedScaledVideoFirstFrameRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    return account.postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedVideoFirstFrameRepresentation(), complete: true) |> mapToSignal { firstFrame -> Signal<CachedMediaResourceRepresentationResult, NoError> in
        return Signal({ subscriber in
            if let data = try? Data(contentsOf: URL(fileURLWithPath: firstFrame.path), options: [.mappedIfSafe]) {
                if let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    var randomId: Int64 = 0
                    arc4random_buf(&randomId, 8)
                    let path = NSTemporaryDirectory() + "\(randomId)"
                    let url = URL(fileURLWithPath: path)
                    
                    let size = representation.size
                    
                    let colorImage = generateImage(size, contextGenerator: { size, context in
                        context.setBlendMode(.copy)
                        context.draw(image, in: CGRect(origin: CGPoint(), size: size))
                    })!
                    
                    if let colorDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) {
                        CGImageDestinationSetProperties(colorDestination, nil)
                        
                        let colorQuality: Float = 0.5
                        
                        let options = NSMutableDictionary()
                        options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                        
                        CGImageDestinationAddImage(colorDestination, colorImage, options as CFDictionary)
                        if CGImageDestinationFinalize(colorDestination) {
                            subscriber.putNext(.temporaryPath(path))
                            subscriber.putCompletion()
                        }
                    }
                }
            }
            return EmptyDisposable
        }) |> runOn(cacheThreadPool)
    }
}



private func fetchCachedBlurredWallpaperRepresentation(account: Account, resource: MediaResource, resourceData: MediaResourceData, representation: CachedBlurredWallpaperRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    return Signal({ subscriber in
        if let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: [.mappedIfSafe]) {
            if let image = NSImage(data: data)?.jpegCGImage {
                var randomId: Int64 = 0
                arc4random_buf(&randomId, 8)
                let path = NSTemporaryDirectory() + "\(randomId)"
                let url = URL(fileURLWithPath: path)
                
                if let colorImage = blurredImage(image, radius: 70), let colorDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) {
                    CGImageDestinationSetProperties(colorDestination, [:] as CFDictionary)
                    
                    let colorQuality: Float = 0.5
                    
                    let options = NSMutableDictionary()
                    options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                    
                    CGImageDestinationAddImage(colorDestination, colorImage, options as CFDictionary)
                    if CGImageDestinationFinalize(colorDestination) {
                        subscriber.putNext(.temporaryPath(path))
                        subscriber.putCompletion()
                    }
                }
            }
        }
        return EmptyDisposable
    }) |> runOn(cacheThreadPool)
}

private func fetchCachedSlotRepresentation(account: Account, data: [(Data, Int32)], representation: CachedSlotMachineRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    return Signal { subscriber in
        
        var images: [CGImage] = []
        for (data, frame) in data {
            var dataValue: Data! = TGGUnzipData(data, 8 * 1024 * 1024)
            if dataValue == nil {
                dataValue = data
            }
            if let json = String(data: dataValue, encoding: .utf8) {
                let renderer = LottieRenderHooks.shared.makeRenderer(json)
                if let renderer = renderer {
                    
                    let s:(w: Int, h: Int) = (w: Int(representation.size.width) * 2, h: Int(representation.size.height) * 2)

                    let bytesPerRow = DeviceGraphicsContextSettings.shared.bytesPerRow(forWidth: s.w)
                    let bufferSize = s.h * bytesPerRow
                    let memoryData = malloc(bufferSize)!
                    let frameData = memoryData.assumingMemoryBound(to: UInt8.self)
                    
                    renderer.renderFrame(with: Int32.max == frame ? renderer.endFrame() - 1 : frame, into: frameData, width: Int32(s.w), height: Int32(s.h), bytesPerRow: Int32(bytesPerRow))
                    
                    let image = generateImagePixel(representation.size, scale: 2, pixelGenerator: { (_, pixelData, bytesPerRow) in
                        memcpy(pixelData, frameData, bufferSize)
                    })
                    free(memoryData)
                    if let image = image {
                        images.append(image)
                    }
                }
            }
        }
        
        let colorImage = generateImage(NSMakeSize(representation.size.width * 2, representation.size.height * 2), contextGenerator: { size, ctx in
            ctx.clear(CGRect(origin: .zero, size: size))
            for image in images {
                ctx.draw(image, in: CGRect(origin: .zero, size: size))
            }
        }, scale: 1.0)!
        
        
        let path = NSTemporaryDirectory() + "\(arc4random64())"
        let url = URL(fileURLWithPath: path)
        
        let colorData = NSMutableData()
        if let colorDestination = CGImageDestinationCreateWithData(colorData as CFMutableData, kUTTypePNG, 1, nil){
            CGImageDestinationSetProperties(colorDestination, [:] as CFDictionary)
            let colorQuality: Float
            colorQuality = 0.4
            let options = NSMutableDictionary()
            options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
            CGImageDestinationAddImage(colorDestination, colorImage, options as CFDictionary)
            if CGImageDestinationFinalize(colorDestination)  {
                try? colorData.write(to: url, options: .atomic)
                subscriber.putNext(.temporaryPath(path))
                subscriber.putCompletion()
            }
        } else {
            subscriber.putCompletion()
        }
        
        
        return ActionDisposable {
            
        }
    } |> runOn(lottieThreadPool)
}

private func fetchCachedDiceRepresentation(account: Account, data: Data, representation: CachedDiceRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError> {
    return Signal { subscriber in
        
        var dataValue: Data! = TGGUnzipData(data, 8 * 1024 * 1024)
        if dataValue == nil {
            dataValue = data
        }
        if let json = String(data: dataValue, encoding: .utf8) {
            let renderer = LottieRenderHooks.shared.makeRenderer(json)
            if let renderer = renderer {
                
                let s:(w: Int, h: Int) = (w: Int(representation.size.width) * 2, h: Int(representation.size.height) * 2)

                let bytesPerRow = DeviceGraphicsContextSettings.shared.bytesPerRow(forWidth: s.w)
                let bufferSize = s.h * bytesPerRow
                let memoryData = malloc(bufferSize)!
                let frameData = memoryData.assumingMemoryBound(to: UInt8.self)
                
                renderer.renderFrame(with: representation.value == diceIdle ? 0 : renderer.endFrame() - 1, into: frameData, width: Int32(s.w), height: Int32(s.h), bytesPerRow: Int32(bytesPerRow))
                
                let colorImage = generateImagePixel(representation.size, scale: 2, pixelGenerator: { (_, pixelData, bytesPerRow) in
                    memcpy(pixelData, frameData, bufferSize)
                })!
                free(memoryData)
                
                
                let path = NSTemporaryDirectory() + "\(arc4random64())"
                let url = URL(fileURLWithPath: path)
                
                let colorData = NSMutableData()
                if let colorDestination = CGImageDestinationCreateWithData(colorData as CFMutableData, kUTTypePNG, 1, nil){
                    CGImageDestinationSetProperties(colorDestination, [:] as CFDictionary)
                    let colorQuality: Float
                    colorQuality = 0.4
                    let options = NSMutableDictionary()
                    options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                    CGImageDestinationAddImage(colorDestination, colorImage, options as CFDictionary)
                    if CGImageDestinationFinalize(colorDestination)  {
                        try? colorData.write(to: url, options: .atomic)
                        subscriber.putNext(.temporaryPath(path))
                        subscriber.putCompletion()
                    }
                } else {
                    subscriber.putCompletion()
                }
            } else {
                subscriber.putCompletion()
            }
            
        }
        
        return ActionDisposable {
            
        }
    } |> runOn(lottieThreadPool)
}

public func getAnimatedStickerThumb(data: Data, size: NSSize = NSMakeSize(512, 512)) -> Signal<String?, NoError> {
    
    return .single(data) |> deliverOn(lottieThreadPool) |> map { data -> String? in
        var dataValue: Data! = TGGUnzipData(data, 8 * 1024 * 1024)
        if dataValue == nil {
            dataValue = data
        }
        if let json = String(data: transformedWithFitzModifier(data: dataValue, fitzModifier: nil), encoding: .utf8), json.length > 0 {
            let renderer = LottieRenderHooks.shared.makeRenderer(json)
            
            let s:(w: Int, h: Int) = (w: Int(size.width) * 2, h: Int(size.height) * 2)

            let bytesPerRow = DeviceGraphicsContextSettings.shared.bytesPerRow(forWidth: s.w)
            let bufferSize = s.h * bytesPerRow
            let memoryData = malloc(bufferSize)!
            let frameData = memoryData.assumingMemoryBound(to: UInt8.self)
            
            renderer?.renderFrame(with: 0, into: frameData, width: Int32(s.w), height: Int32(s.h), bytesPerRow: Int32(bytesPerRow))
            
            let image = generateImagePixel(size, scale: 2, pixelGenerator: { (_, pixelData, bytesPerRow) in
                memcpy(pixelData, frameData, bufferSize)
            })
            free(memoryData)
            
            if let image = image {
                let rep = NSBitmapImageRep(cgImage: image)
                let data = rep.representation(using: .png, properties: [:])
                let path = NSTemporaryDirectory() + "temp_as_\(arc4random64()).png"
                try? data?.write(to: URL(fileURLWithPath: path))
                return path
            }
        } else {
            if let image = convertFromWebP(dataValue)?._cgImage {
                let rep = NSBitmapImageRep(cgImage: image)
                let data = rep.representation(using: .png, properties: [:])
                let path = NSTemporaryDirectory() + "temp_as_\(arc4random64()).png"
                try? data?.write(to: URL(fileURLWithPath: path))
                return path
            }
        }
        return nil
    } |> deliverOnMainQueue
}
