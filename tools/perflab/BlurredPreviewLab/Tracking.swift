import Cocoa
import TGUIKit

private let allocationLock = NSLock()
private var allocationLengths: [Int] = []

public func resetCanvasAllocations() {
    allocationLock.lock()
    allocationLengths = []
    allocationLock.unlock()
}

public func canvasAllocations() -> [Int] {
    allocationLock.lock()
    defer { allocationLock.unlock() }
    return allocationLengths
}

func trackedDrawingContext(size: CGSize, scale: CGFloat, clear: Bool = false) -> DrawingContext {
    let context = DrawingContext(size: size, scale: scale, clear: clear)
    allocationLock.lock()
    allocationLengths.append(context.length)
    allocationLock.unlock()
    return context
}
