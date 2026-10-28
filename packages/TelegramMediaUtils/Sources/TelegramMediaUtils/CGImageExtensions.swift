import Cocoa
import CoreVideo
import ImageIO
import CoreServices
import TGUIKit
import FastBlur

public extension CVImageBuffer {
    var cgImage: CGImage?
    {
        let imageBuffer: CVImageBuffer = self
        
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags.readOnly)
        
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer);
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
        let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        let quartzImage = context?.makeImage()
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags.readOnly);
        
        return quartzImage
    }
}

public extension CGImage {
    func saveToFile(_ path:String) -> Bool {
//        var randomId: Int64 = 0
//        arc4random_buf(&randomId, 8)
//        let path = NSTemporaryDirectory() + "\(randomId)"
        let url = URL(fileURLWithPath: path)
        
        
        
        if let colorDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
            
                        
            let colorQuality: Float = 0.8
            
            let options = NSMutableDictionary()
            options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
            
            
            
            CGImageDestinationAddImage(colorDestination, self, nil)
            if CGImageDestinationFinalize(colorDestination) {
                return true
            }
        }
        return false
    }
    
    var blurred: CGImage {
        
        let thumbnailImage: CGImage = self
        
        let thumbnailContextSize = thumbnailImage.size.multipliedByScreenScale()
        
        let thumbnailContextSmallSize = thumbnailContextSize.aspectFitted(NSMakeSize(50, 50))
        
        let thumbnailContext = DrawingContext(size: thumbnailContextSmallSize, scale: 1.0)
        
        
        
        thumbnailContext.withContext { ctx in
            ctx.interpolationQuality = .none
            ctx.draw(thumbnailImage, in: CGRect(origin: CGPoint(), size: thumbnailContextSize))
        }
        
        telegramFastBlurMore(Int32(thumbnailContextSmallSize.width), Int32(thumbnailContextSmallSize.height), Int32(thumbnailContext.bytesPerRow), thumbnailContext.bytes)
        
        return thumbnailContext.generateImage()!
    }

    
    static func loadFromFile(_ path:String) -> CGImage? {
        
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            if let dataProvider = CGDataProvider(data: data as CFData) {
                return CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            }
        }

        return nil
    }
}
