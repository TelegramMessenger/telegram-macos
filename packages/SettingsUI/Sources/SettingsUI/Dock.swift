import AppKit

public final class Dock {
    private static let iconQueue = DispatchQueue(label: "org.telegram.custom-app-icon", qos: .utility)
    private static var iconUpdate: DispatchWorkItem?
    private static var appliedPath: String?
    private static var hasAppliedIcon = false

    public static func setCustomAppIcon(path: String?) {
        assert(Thread.isMainThread)

        if hasAppliedIcon && appliedPath == path {
            return
        }

        let image: NSImage?
        if let path {
            guard let customIcon = NSImage(contentsOfFile: path), customIcon.isValid else {
                return
            }
            image = customIcon
        } else {
            image = nil
        }

        NSApplication.shared.applicationIconImage = image
        appliedPath = path
        hasAppliedIcon = true

        iconUpdate?.cancel()
        let bundlePath = Bundle.main.bundlePath
        let persistentImage = image?.copy() as? NSImage
        let update = DispatchWorkItem {
            if !NSWorkspace.shared.setIcon(persistentImage, forFile: bundlePath, options: []) {
                NSLog("Failed to persist the custom application icon at %@", bundlePath)
            }
        }
        iconUpdate = update
        iconQueue.async(execute: update)
    }
}
