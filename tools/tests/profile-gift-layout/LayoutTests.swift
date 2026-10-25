import Cocoa
import QuartzCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

func layout(width: CGFloat = 600, height: CGFloat = 280, avatarSize: CGFloat = 120, titleWidth: CGFloat = 220) -> PositionGenerator {
    PositionGenerator(
        containerSize: CGSize(width: width, height: height),
        centerFrame: CGRect(x: (width - avatarSize) / 2, y: 20, width: avatarSize, height: avatarSize),
        exclusionZones: [
            CGRect(x: (width - titleWidth) / 2, y: avatarSize + 26, width: titleWidth, height: 72),
            CGRect(x: 0, y: height - 36, width: width, height: 36)
        ],
        minimumDistance: 44,
        edgePadding: 8
    )
}

let itemSize = CGSize(width: 44, height: 44)
func coordinates(_ generator: PositionGenerator, count: Int = 6) -> [[CGFloat]] {
    generator.generatePositions(count: count, itemSize: itemSize).map {
        [$0.relativeCartesian.x, $0.relativeCartesian.y, $0.scale]
    }
}

func validate(_ generator: PositionGenerator, count: Int = 6) {
    let positions = generator.generatePositions(count: count, itemSize: itemSize)
    require(positions.count <= count, "Generated too many gifts")
    let bounds = CGRect(origin: .zero, size: generator.containerSize).insetBy(dx: 8, dy: 8)
    let center = CGPoint(x: generator.centerFrame.midX, y: generator.centerFrame.midY)
    var points: [CGPoint] = []
    for position in positions {
        let relative = position.relativeCartesian
        let point = CGPoint(x: center.x + relative.x, y: center.y + relative.y)
        let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
        require(bounds.insetBy(dx: -0.001, dy: -0.001).contains(rect), "Gift clipped by bounds")
        require(!generator.exclusionZones.contains { $0.insetBy(dx: 0.001, dy: 0.001).intersects(rect) }, "Gift overlaps profile content")
        require(position.distance >= generator.centerFrame.width / 2 + hypot(44, 44) / 2 + 7.999, "Gift overlaps avatar")
        require(position.scale >= 0.7 && position.scale <= 1, "Invalid icon scale")
        for previous in points {
            require(hypot(previous.x - point.x, previous.y - point.y) >= 43.999, "Gifts overlap")
        }
        points.append(point)
    }
}

if CommandLine.arguments.contains("--fingerprint") {
    let data = try JSONSerialization.data(withJSONObject: coordinates(layout()), options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

let standard = layout()
require(coordinates(standard) == coordinates(standard), "Repeated layout changes base positions")
require(coordinates(standard) == coordinates(layout()), "Recreated layout changes base positions")
require(coordinates(standard, count: 3) == Array(coordinates(standard).prefix(3)), "Gift count reshuffles existing slots")
require(coordinates(standard).count == 6, "Wide header must fit six gifts")
for width: CGFloat in [280, 320, 360, 400, 600, 1024] {
    let generator = layout(width: width)
    require(coordinates(generator).count >= 6, "Header must fit six gifts at width \(width)")
    validate(generator)
}
let firstSix = coordinates(standard, count: 6)
for index in stride(from: 0, to: firstSix.count, by: 2) {
    require(abs(firstSix[index][0] + firstSix[index + 1][0]) < 0.001, "Orbit is not symmetric")
    require(abs(firstSix[index][1] - firstSix[index + 1][1]) < 0.001, "Paired gifts have different heights")
}
for width: CGFloat in [240, 280, 320, 360, 420, 600, 900] {
    for height: CGFloat in [220, 260, 320] {
        for avatar: CGFloat in [80, 120, 160] {
            for title: CGFloat in [140, 220, 300, 440] {
                for count in 1 ... 6 {
                    validate(layout(width: width, height: height, avatarSize: avatar, titleWidth: title), count: count)
                }
            }
        }
    }
}
require(coordinates(layout(width: 600)) == coordinates(standard), "Resize round trip changes positions")
let changedZones = layout(titleWidth: 440)
require(standard != changedZones, "Cache ignores text geometry")
validate(changedZones)
let movedAvatar = PositionGenerator(containerSize: standard.containerSize, centerFrame: standard.centerFrame.offsetBy(dx: 0, dy: 12), exclusionZones: standard.exclusionZones, minimumDistance: 44, edgePadding: 8)
require(standard != movedAvatar, "Cache ignores avatar geometry")
validate(movedAvatar)
require(standard.generatePositions(count: 0, itemSize: itemSize).isEmpty, "Empty gift list produces positions")
require(layout(width: 0).generatePositions(count: 6, itemSize: itemSize).isEmpty, "Empty header produces positions")
require(standard.generatePositions(count: -1, itemSize: itemSize).isEmpty, "Negative count produces positions")
let blocked = PositionGenerator(containerSize: standard.containerSize, centerFrame: standard.centerFrame, exclusionZones: [CGRect(origin: .zero, size: standard.containerSize)], minimumDistance: 44, edgePadding: 8)
require(blocked.generatePositions(count: 6, itemSize: itemSize).isEmpty, "Blocked header produces positions")

let motion = GiftAnimationProbe()
motion.startAnimations(index: 2)
for (layer, key) in [(motion as CALayer, "hover"), (motion.animationLayer, "wiggle"), (motion.shadowLayer, "glow")] {
    guard let animation = layer.animation(forKey: key) as? CABasicAnimation else {
        fatalError("Missing \(key) animation")
    }
    require(animation.autoreverses && animation.repeatCount == .infinity, "Motion must keep looping")
    require(animation.duration >= 2 && animation.duration <= 4.5, "Motion duration changed")
    let previous = animation.duration
    motion.startAnimations(index: 2)
    require(layer.animation(forKey: key)?.duration == previous, "Layout update restarts motion")
}
print("PASS: stable slots, one to six gifts, 252 geometry combinations, cache inputs, empty/blocked layouts, native hover/wiggle/glow")
