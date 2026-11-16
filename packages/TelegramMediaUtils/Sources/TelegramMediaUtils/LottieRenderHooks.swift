import Foundation

public protocol LottieFrameRenderer: AnyObject {
    func renderFrame(with index: Int32, into buffer: UnsafeMutablePointer<UInt8>, width: Int32, height: Int32, bytesPerRow: Int32)
    func endFrame() -> Int32
}

public struct LottieRenderHooks {
    public let makeRenderer: (String) -> LottieFrameRenderer?

    public init(makeRenderer: @escaping (String) -> LottieFrameRenderer?) {
        self.makeRenderer = makeRenderer
    }

    private static var installed: LottieRenderHooks?

    public static var shared: LottieRenderHooks {
        guard let hooks = installed else {
            fatalError("LottieRenderHooks.install must be called before lottie rendering is used")
        }
        return hooks
    }

    public static func install(_ hooks: LottieRenderHooks) {
        installed = hooks
    }
}
