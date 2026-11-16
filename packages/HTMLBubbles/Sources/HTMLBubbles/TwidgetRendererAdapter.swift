import Cocoa
import TwidgetRenderer
import WidgetSandbox

extension LiteHTMLWidgetRenderer: ScheduledRenderer {}

extension LiteHTMLWidgetRenderer: Renderer {
    public func evaluate(_ script: String, completion: @escaping (String?) -> Void) {
        completion(nil)
    }

    public func snapshot(completion: @escaping (NSImage?) -> Void) {
        completion(snapshot())
    }
}
