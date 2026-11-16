import Foundation

@objc public protocol WidgetEngineServiceXPC {
    func open(features: String, reply: @escaping (String?) -> Void)
    func prewarm()
    func start(html: String, config: Data)
    func event(_ json: String)
    func activationEvent(_ json: String, gesture: Int)
    func frame(_ time: Double)
    func viewport(width: Double, height: Double, dpr: Double)
    func resize(_ json: String)
    func theme(_ theme: String, params: Data)
    func contentSafeArea(_ area: Data)
    func setData(_ data: Data)
    func setVisible(_ visible: Bool)
    func press(began: Bool)
    func stop(_ reason: String)
    func answer(request id: Int, outcome: Data)
    func morph(_ html: String, reply: @escaping (Bool) -> Void)
    func evaluate(_ code: String, reply: @escaping (String?) -> Void)
    func collectGarbage()
}

@objc public protocol WidgetEngineClientXPC {
    func taskStarted()
    func taskCompleted()
    func ops(_ json: String, canvas: Data?)
    func binaryOps(words: Data, strings: Data, canvas: Data?)
    func query(_ json: String, reply: @escaping (String, Data?) -> Void)
    func listen(_ json: String)
    func preventDefault(_ json: String)
    func anim(_ json: String)
    func requestsFrame()
    func log(_ level: String, text: String)
    func diag(_ kind: String, detail: String)
    func bridge(_ method: String, args: String)
    func copyText(_ text: String)
    func request(_ id: Int, data: String, wallet: Bool)
    func wallet(_ id: Int, payload: Data)
    func storage(_ json: String)
    func resizeAnchor(_ edge: String)
    func watchesPublicData(_ on: Bool)
    func loaded()
    func stats(_ values: Data)
    func died(_ reason: String)
}

public enum WidgetEngineXPCInterface {
    public static let bundleName = "WidgetEngineService.xpc"
    public static let openTimeout: TimeInterval = 15

    public static func service() -> NSXPCInterface {
        return NSXPCInterface(with: WidgetEngineServiceXPC.self)
    }

    public static func client() -> NSXPCInterface {
        return NSXPCInterface(with: WidgetEngineClientXPC.self)
    }

    public static func encode(doubles: [Double]) -> Data {
        return doubles.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decode(doubles data: Data, max: Int) -> [Double]? {
        guard data.count % 8 == 0, data.count / 8 <= max else {
            return nil
        }
        let count = data.count / 8
        return [Double](unsafeUninitializedCapacity: count) { buffer, initialized in
            _ = data.copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
            initialized = count
        }
    }

    public static func encode(strings: [String: String]) -> Data {
        return (try? JSONSerialization.data(withJSONObject: strings)) ?? Data()
    }

    public static func decode(strings data: Data) -> [String: String] {
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: String]) ?? [:]
    }

    public static func encode(features: Set<String>) -> String {
        return Array(features).sorted().joined(separator: ",")
    }

    public static func decode(features: String) -> Set<String> {
        return Set(features.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }
}
