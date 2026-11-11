import Cocoa
import TGUIKit
import WidgetSandbox

public protocol HTMLTwidgetRow: AnyObject {
    var htmlTwidgetState: HTMLBubbleState { get }
    var htmlTwidgetAppearance: HTMLBubbleAppearance { get }
    var htmlTwidgetWidth: CGFloat { get }
}

public let pauseWhileScrollingKey = "HTMLBubbles.pauseWidgetsWhileScrolling"

final class HTMLTwidgetTableSpace: WidgetFeedSpace {
    private weak var table: TableView?
    private var observer: NSObjectProtocol?
    private struct Key: Hashable {
        let table: ObjectIdentifier
        let webKit: Bool
    }
    private static var spaces: [Key: HTMLTwidgetTableSpace] = [:]
    private let webKit: Bool
    private let feed: WidgetFeed
    private static let webKitFeed: WidgetFeed = {
        let feed = WidgetFeed()
        feed.policy.liveBudget = 8
        feed.policy.keepScreens = 1.5
        feed.policy.prefetchScreens = 0.75
        feed.policy.maxPrefetchScreens = 1.5
        feed.policy.pressureLiveBudget = 4
        feed.policy.pressureKeepScreens = 0.5
        return feed
    }()

    static func feed(for engine: HTMLRenderEngine) -> WidgetFeed {
        return engine == .webKit ? webKitFeed : .shared
    }

    static func space(for table: TableView, engine: HTMLRenderEngine) -> HTMLTwidgetTableSpace {
        let key = Key(table: ObjectIdentifier(table), webKit: engine == .webKit)
        if let space = spaces[key], space.table === table {
            return space
        }
        spaces = spaces.filter { $0.value.table != nil }
        let space = HTMLTwidgetTableSpace(table, engine: engine)
        spaces[key] = space
        space.feed.policy.pauseVelocity = UserDefaults.standard.bool(forKey: pauseWhileScrollingKey) ? 900 : 0
        space.feed.watchMemoryPressure()
        space.feed.attach(space)
        return space
    }

    private init(_ table: TableView, engine: HTMLRenderEngine) {
        self.webKit = engine == .webKit
        let feed = Self.feed(for: engine)
        self.feed = feed
        self.table = table
        let clip = table.clipView
        clip.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: nil) { _ in
            feed.setNeedsUpdate()
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var feedViewport: CGRect {
        return table?.clipView.bounds ?? .zero
    }

    var feedOnScreen: Bool {
        guard let window = table?.window else {
            return false
        }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] {
        guard let table = table, table.count > 0 else {
            return []
        }
        let viewport = table.clipView.bounds
        let inset = max(0, viewport.minY - rect.minY, rect.maxY - viewport.maxY)
        let range = table.visibleRows(inset)
        guard range.location != NSNotFound, range.length > 0 else {
            return []
        }
        var slots: [WidgetFeedSlot] = []
        let end = min(table.count, range.location + range.length)
        var index = max(0, range.location)
        while index < end {
            let item = table.item(at: index)
            if let row = item as? HTMLTwidgetRow, (row.htmlTwidgetState.engine == .webKit) == webKit, let slot = row.htmlTwidgetState.twidgetSlot(appearance: row.htmlTwidgetAppearance, width: row.htmlTwidgetWidth, locate: { [weak item, weak table, weak state = row.htmlTwidgetState] in
                guard let item = item, let table = table else {
                    return nil
                }
                if let document = table.clipView.documentView, let rect = state?.twidgetAttachedRect(in: document) {
                    return rect
                }
                let rect = table.rectOf(item: item)
                return rect.isEmpty ? nil : rect
            }) {
                slot.space = self
                slots.append(slot)
            }
            index += 1
        }
        return slots
    }
}

final class HTMLTwidgetSnapshot {
    private let tiles: [(frame: CGRect, contents: Any, scale: CGFloat)]

    private init(tiles: [(frame: CGRect, contents: Any, scale: CGFloat)]) {
        self.tiles = tiles
    }

    static func capture(_ view: NSView) -> (snapshot: AnyObject, bytes: Int)? {
        guard let window = view.window, let layer = view.layer else {
            return nil
        }
        CATransaction.lock()
        let layers = (layer.sublayers ?? []).flatMap { $0.delegate == nil ? ($0.sublayers ?? []) : [$0] }.filter { $0.delegate != nil && !($0.delegate is NSView) }
        CATransaction.unlock()
        guard !layers.isEmpty, layers.allSatisfy({ $0.contents != nil }) else {
            return nil
        }
        let scale = window.backingScaleFactor
        let bytes = layers.reduce(0) { $0 + Int($1.bounds.width * scale) * Int($1.bounds.height * scale) * 4 }
        return (HTMLTwidgetSnapshot(tiles: layers.map { ($0.frame, $0.contents!, $0.contentsScale) }), bytes)
    }

    static func capture(_ image: NSImage) -> (snapshot: AnyObject, bytes: Int)? {
        guard image.size.width > 0, image.size.height > 0,
              let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let tile = (CGRect(origin: .zero, size: image.size), bitmap as Any, CGFloat(bitmap.width) / image.size.width)
        return (HTMLTwidgetSnapshot(tiles: [tile]), bitmap.bytesPerRow * bitmap.height)
    }

    func install(in host: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        for tile in tiles {
            let layer = CALayer()
            layer.anchorPoint = .zero
            layer.contentsGravity = .topLeft
            layer.frame = tile.frame
            layer.contentsScale = tile.scale
            layer.contents = tile.contents
            host.addSublayer(layer)
        }
        CATransaction.commit()
    }
}
