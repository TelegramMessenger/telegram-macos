import Foundation

public extension ApiEnvironment {
    static let deviceModelMaxLength = 32
    static let deviceModelDidChange = Notification.Name("ApiEnvironmentDeviceModelDidChange")
    static var systemDeviceModel: String?

    private static var deviceModelURL: URL? {
        return containerURL?.appendingPathComponent("device-model")
    }

    static var customDeviceModel: String? {
        get {
            guard let url = deviceModelURL, let value = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            return normalizedDeviceModel(value)
        }
        set {
            guard let url = deviceModelURL else {
                return
            }
            if let value = newValue.flatMap(normalizedDeviceModel) {
                try? value.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            NotificationCenter.default.post(name: deviceModelDidChange, object: nil)
        }
    }

    static func normalizedDeviceModel(_ value: String) -> String? {
        let words = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let result = String(words.joined(separator: " ").prefix(deviceModelMaxLength)).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }
}
