import Cocoa
import LiteHTML
import TwidgetRenderer

enum HTMLBubbleMagicMove {
    static let attribute = "data-key"
    static let maxElements = 32

    struct Capture {
        let rects: [String: CGRect]
        let parents: [String: String]
        let snapshots: [String: MagicMoveStage.Snapshot]
    }

    struct Plan {
        let items: [MagicMoveStage.Item]
        let baseTiles: [HTMLBubbleTile]
    }

    static func capture(_ document: LHDocument, presented: [String: CGRect], scale: CGFloat) -> Capture? {
        var rects: [String: CGRect] = [:]
        for (key, value) in document.bounds(byAttribute: attribute) {
            rects[key] = value.rectValue
        }
        guard !rects.isEmpty, rects.count <= maxElements * 2 else {
            return nil
        }
        var snapshots: [String: MagicMoveStage.Snapshot] = [:]
        var pixels = 0
        for (key, rect) in rects.sorted(by: { $0.key < $1.key }) where rect.width > 0 && rect.height > 0 {
            pixels += Int(rect.width * scale * rect.height * scale)
            if snapshots.count >= maxElements || pixels > MagicMoveStage.maxPixels / 2 {
                return nil
            }
            if let snapshot = snapshot(document, key: key, scale: scale) {
                snapshots[key] = snapshot
            }
        }
        for (key, frame) in presented {
            rects[key] = frame
        }
        return Capture(rects: rects, parents: document.parents(byAttribute: attribute), snapshots: snapshots)
    }

    static func plan(_ capture: Capture, document: LHDocument, width: CGFloat, scale: CGFloat, tiles: [HTMLBubbleTile]) -> Plan? {
        var rects: [String: CGRect] = [:]
        for (key, value) in document.bounds(byAttribute: attribute) {
            rects[key] = value.rectValue
        }
        let parents = document.parents(byAttribute: attribute)
        func chain(_ key: String, _ parents: [String: String]) -> [String] {
            var result: [String] = []
            var current = parents[key]
            while let value = current, result.count < 64 {
                result.append(value)
                current = parents[value]
            }
            return result
        }
        var animated: [String: (from: CGRect?, rect: CGRect)] = [:]
        var made: [String: MagicMoveStage.Snapshot] = [:]
        for (key, rect) in rects where rect.width > 0 && rect.height > 0 {
            if let old = capture.rects[key] {
                if !MagicMoveStage.close(old, rect) {
                    animated[key] = (old, rect)
                } else if let previous = capture.snapshots[key], let current = snapshot(document, key: key, scale: scale), !same(previous.image, current.image) {
                    made[key] = current
                    animated[key] = (old, rect)
                }
            } else {
                animated[key] = (nil, rect)
            }
        }
        let chosen = Set(animated.keys)
        animated = animated.filter { Set(chain($0.key, parents)).isDisjoint(with: chosen) }
        let gone = Set(capture.rects.keys.filter { rects[$0] == nil })
        let leaving = gone.filter { Set(chain($0, capture.parents)).isDisjoint(with: gone) }
        if animated.isEmpty && leaving.isEmpty {
            return nil
        }
        var items: [MagicMoveStage.Item] = leaving.sorted().compactMap { capture.snapshots[$0].map { .leave($0) } }
        var excluded: Set<String> = []
        for (key, item) in animated.sorted(by: { $0.key < $1.key }) {
            guard items.count < MagicMoveStage.maxLayers, let snapshot = made[key] ?? snapshot(document, key: key, scale: scale) else {
                return nil
            }
            if let from = item.from {
                let previous = capture.snapshots[key].flatMap { same($0.image, snapshot.image) ? nil : $0 }
                items.append(.move(key: key, from: from, to: snapshot, previous: previous))
            } else {
                items.append(.enter(key: key, snapshot))
            }
            excluded.insert(key)
        }
        var baseTiles = tiles
        if !excluded.isEmpty {
            baseTiles = tiles.map { tile in
                document.copyImage(maxWidth: width, rect: tile.rect, scale: scale, excluding: excluded, attribute: attribute).map { HTMLBubbleTile(rect: tile.rect, image: $0) } ?? tile
            }
        }
        return Plan(items: items, baseTiles: baseTiles)
    }

    private static func snapshot(_ document: LHDocument, key: String, scale: CGFloat) -> MagicMoveStage.Snapshot? {
        var ink = CGRect.zero, border = CGRect.zero
        var radii = [CGFloat](repeating: 0, count: 8)
        guard let image = document.copyImageOfElement(attribute: attribute, value: key, scale: scale, inkBounds: &ink, borderBox: &border, radii: &radii) else {
            return nil
        }
        return MagicMoveStage.Snapshot(image: image, ink: ink, border: border, corners: MagicMoveCorners(radii: radii))
    }

    private static func same(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height, a.bytesPerRow == b.bytesPerRow, let da = a.dataProvider?.data, let db = b.dataProvider?.data else {
            return false
        }
        return CFEqual(da, db)
    }
}
