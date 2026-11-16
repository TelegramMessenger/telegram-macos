import Foundation
import AppAnalytics
import AppKit
import ImageIO
import TGUIKit
import FilePanels

func qrStudioWriteTemporaryImage(_ image: CGImage, name: String = "qr-code.jpg") -> URL? {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
        return nil
    }
    let options = [kCGImageDestinationLossyCompressionQuality as String: 0.92] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    return url
}

func qrStudioSaveImage(_ image: CGImage, window: NSWindow, suggestedName: String, analyticsContext: AnalyticsContext, completion: @escaping (Bool) -> Void) {
    guard let window = window as? Window, let url = qrStudioWriteTemporaryImage(image) else {
        completion(false)
        return
    }
    let name = (suggestedName as NSString).pathExtension.isEmpty ? suggestedName + ".jpg" : suggestedName
    savePanel(file: url.path, ext: "jpg", for: window, defaultName: name, analyticsContext: analyticsContext, completion: { path in
        guard let path = path else {
            return
        }
        completion(FileManager.default.fileExists(atPath: path))
    })
}
