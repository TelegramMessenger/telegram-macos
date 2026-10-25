import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import InlineStickerLayer



public struct PositionGenerator: Equatable {
    public struct Position {
        public let distance: CGFloat
        public let angle: CGFloat
        public let scale: CGFloat
        
        public init(distance: CGFloat, angle: CGFloat, scale: CGFloat) {
            self.distance = distance
            self.angle = angle
            self.scale = scale
        }
        
        public var relativeCartesian: CGPoint {
            return CGPoint(
                x: self.distance * cos(self.angle),
                y: self.distance * sin(self.angle)
            )
        }
    }
    
    let containerSize: CGSize
    let centerFrame: CGRect
    let exclusionZones: [CGRect]
    let minimumDistance: CGFloat
    let edgePadding: CGFloat

    public init(
        containerSize: CGSize,
        centerFrame: CGRect,
        exclusionZones: [CGRect],
        minimumDistance: CGFloat,
        edgePadding: CGFloat
    ) {
        self.containerSize = containerSize
        self.centerFrame = centerFrame
        self.exclusionZones = exclusionZones
        self.minimumDistance = minimumDistance
        self.edgePadding = edgePadding
    }

    public func generatePositions(count: Int, itemSize: CGSize) -> [Position] {
        guard count > 0, minimumDistance > 0, !centerFrame.isEmpty, itemSize.width > 0, itemSize.height > 0 else {
            return []
        }
        let bounds = CGRect(origin: .zero, size: containerSize).insetBy(dx: edgePadding, dy: edgePadding)
        guard bounds.width >= itemSize.width, bounds.height >= itemSize.height else {
            return []
        }

        let center = CGPoint(x: centerFrame.midX, y: centerFrame.midY)
        let innerDistance = max(centerFrame.width, centerFrame.height) / 2 + hypot(itemSize.width, itemSize.height) / 2 + 8
        let maxDistance = hypot(containerSize.width, containerSize.height)
        var positions: [Position] = []
        var points: [CGPoint] = []
        var distance = innerDistance
        var orbit = 0

        while distance <= maxDistance {
            for row in 0 ... Int(distance / minimumDistance) {
                let offsets: [CGFloat] = row == 0 ? [0] : [-CGFloat(row) * minimumDistance, CGFloat(row) * minimumDistance]
                for y in offsets {
                    let x = sqrt(max(0, distance * distance - y * y))
                    for side: CGFloat in [-1, 1] {
                        let point = CGPoint(x: center.x + side * x, y: center.y + y)
                        let rect = CGRect(x: point.x - itemSize.width / 2, y: point.y - itemSize.height / 2, width: itemSize.width, height: itemSize.height)
                        guard bounds.contains(rect), !exclusionZones.contains(where: { $0.intersects(rect) }) else {
                            continue
                        }
                        guard !points.contains(where: { hypot($0.x - point.x, $0.y - point.y) < minimumDistance }) else {
                            continue
                        }
                        points.append(point)
                        positions.append(Position(distance: distance, angle: atan2(y, side * x), scale: max(0.7, 1 - CGFloat(orbit) * 0.1)))
                        if positions.count == count {
                            return positions
                        }
                    }
                }
            }
            orbit += 1
            distance += minimumDistance + 6
        }
        return positions
    }
}

extension PeerInfoSpawnEmojiView {
    public func set(fileId: Int64, color: NSColor, context: any AccountContextProtocol, animated: Bool) {
        set(fileId: fileId, color: color, context: context, inlinePacksContext: context.inlinePacksContext, animated: animated)
    }
}
