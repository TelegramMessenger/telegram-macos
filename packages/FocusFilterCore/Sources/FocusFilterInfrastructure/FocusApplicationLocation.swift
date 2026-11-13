import Foundation

struct FocusApplicationLocation {
    static func applicationURL(containing bundleURL: URL) -> URL? {
        var url = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        while url.pathExtension != "app" && url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url.pathExtension == "app" ? url : nil
    }

    static func executableURL(in applicationURL: URL) -> URL? {
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: infoURL.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576,
              let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = info["CFBundleExecutable"] as? String,
              !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
        return applicationURL.appendingPathComponent("Contents/MacOS/\(name)")
    }
}
