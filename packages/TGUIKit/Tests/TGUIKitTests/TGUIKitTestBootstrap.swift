import AppKit
import TGUIKit

enum TGUIKitTestBootstrap {
    private static var retained: [NSImage] = []

    private static let installed: Void = {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        System.liquidGlass = false
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode", "Icon_Menu_More"] {
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                NSColor.black.setFill()
                rect.insetBy(dx: 4, dy: 4).fill()
                return true
            }
            _ = image.setName(name)
            retained.append(image)
        }
    }()

    static func install() {
        _ = installed
    }
}

func testImage(_ size: CGSize) -> CGImage {
    let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    return context.makeImage()!
}
