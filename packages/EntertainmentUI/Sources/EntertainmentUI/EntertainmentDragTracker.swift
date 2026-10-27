import Cocoa

final class EntertainmentDragTracker {
    private var start: NSPoint?
    private(set) var isDragging = false

    func down(in window: NSWindow?) {
        start = window?.mouseLocationOutsideOfEventStream
        isDragging = false
    }

    func dragged(in window: NSWindow?, begin: (NSPoint) -> Bool, move: (NSPoint) -> Void) -> Bool {
        guard let window = window else {
            return false
        }
        let location = window.mouseLocationOutsideOfEventStream
        if isDragging {
            move(location)
            return true
        }
        guard let start = start, hypot(location.x - start.x, location.y - start.y) > 6 else {
            return false
        }
        self.start = nil
        isDragging = begin(location)
        return isDragging
    }

    func up(in window: NSWindow?, end: (NSPoint) -> Void) -> Bool {
        start = nil
        guard isDragging else {
            return false
        }
        isDragging = false
        if let window = window {
            end(window.mouseLocationOutsideOfEventStream)
        }
        return true
    }
}
