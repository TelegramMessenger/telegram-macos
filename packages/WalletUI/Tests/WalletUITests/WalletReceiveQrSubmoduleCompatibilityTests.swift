import XCTest
import Cocoa
import Metal
import TGUIKit
@testable import WalletUI
@testable import SceneEffects

private func repositoryRoot() -> URL {
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func source(_ path: String) throws -> String {
    return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
}

private func collapsed(_ text: String) -> String {
    return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

private let submoduleReceivePath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletReceiveScreen/Sources/WalletReceiveScreen.swift"
private let submoduleRevealPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletReceiveScreen/Sources/WalletReceiveQrRevealView.swift"
private let submoduleIntroPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Premium/PremiumDiamondComponent/Sources/InteractiveDiamondIntro.swift"
private let submoduleQrCodePath = "submodules/telegram-ios/submodules/QrCode/Sources/QrCode.swift"
private let actualReceivePath = "packages/WalletUI/Sources/WalletUI/WalletReceiveController.swift"
private let actualRevealPath = "packages/WalletUI/Sources/WalletUI/WalletReceiveQrRevealView.swift"
private let actualIntroPath = "packages/SceneEffects/Sources/InteractiveDiamond/InteractiveDiamondIntro.swift"

private func submoduleFloorToContextPixels(_ value: CGFloat, scale: CGFloat?) -> CGFloat {
    let scale = scale ?? 2.0
    return floor(value * scale) / scale
}

private func submoduleQrCodeCutout(size: Int, dimensions: CGSize, scale: CGFloat?) -> (Int, CGRect, CGFloat) {
    var cutoutSize = Int(round(CGFloat(size) * 0.297))
    if size == 39 {
        cutoutSize = 11
    } else if cutoutSize % 2 == 0 {
        cutoutSize += 1
    }
    cutoutSize = min(23, cutoutSize)

    let quadSize = submoduleFloorToContextPixels(dimensions.width / CGFloat(size), scale: scale)
    let cutoutSide = quadSize * CGFloat(cutoutSize - 2)
    let cutoutRect = CGRect(x: submoduleFloorToContextPixels((dimensions.width - cutoutSide) / 2.0, scale: scale), y: submoduleFloorToContextPixels((dimensions.height - cutoutSide) / 2.0, scale: scale), width: cutoutSide, height: cutoutSide)

    return (cutoutSize, cutoutRect, quadSize)
}

private struct SubmoduleInteractiveDiamondIntro {
    static let delay = 0.18
    static let duration = 1.2
    private static let omega = 2.0 * Double.pi / 0.9

    let progress: CGFloat
    var lift: CGFloat { -48.0 * 4.0 * self.progress * (1.0 - self.progress) }
    var scale: CGFloat { self.scale(from: 6.0) }

    func scale(from initialScale: CGFloat, allowsOvershoot: Bool = false) -> CGFloat {
        let remaining = 1.0 - self.progress
        let offset: CGFloat
        if allowsOvershoot && remaining < 0.0 {
            offset = -pow(-remaining, 1.25)
        } else {
            offset = pow(max(0.0, remaining), 1.25)
        }
        return 1.0 + (initialScale - 1.0) * offset
    }

    init(progress: CGFloat) {
        self.progress = progress
    }

    init(time: Double?, speed: Double = 1.0, damping: Double = 0.8) {
        let duration = Self.delay + (Self.duration - Self.delay) / speed
        guard let time, time < duration else {
            self.progress = 1.0
            return
        }
        let t = max(time - Self.delay, 0.0) * speed
        let decay = damping * Self.omega
        let frequency = Self.omega * sqrt(1.0 - damping * damping)
        self.progress = CGFloat(1.0 - exp(-decay * t) * (cos(frequency * t) + (decay - 1.2) / frequency * sin(frequency * t)))
    }
}

private enum SubmoduleQrIntro {
    static let introDelay = 0.03
    static let qrRevealDuration = 0.5
    static let diamondIntroSpeed = 1.5
    static var diamondIntroDuration: Double {
        return Self.introDelay + (SubmoduleInteractiveDiamondIntro.duration - SubmoduleInteractiveDiamondIntro.delay) / Self.diamondIntroSpeed
    }

    static func frame(elapsed: Double) -> (lift: CGFloat, openingScale: CGFloat?)? {
        guard elapsed < max(Self.diamondIntroDuration, Self.introDelay + Self.qrRevealDuration) else {
            return nil
        }
        let introTime = elapsed + SubmoduleInteractiveDiamondIntro.delay - Self.introDelay
        let intro = SubmoduleInteractiveDiamondIntro(time: introTime, speed: Self.diamondIntroSpeed, damping: 0.64)
        let bounceAmplitude: CGFloat = intro.progress > 1.0 ? 0.49 : 1.0
        let scale = 1.0 + (intro.scale(from: 5.0, allowsOvershoot: true) - 1.0) * bounceAmplitude
        return (intro.lift * bounceAmplitude, elapsed < Self.diamondIntroDuration ? scale : nil)
    }
}

private func submoduleRevealGeometry(moduleCount: Int, imageSize: CGSize, scale: CGFloat) -> (moduleSide: CGFloat, padding: CGFloat) {
    let (_, _, moduleSide) = submoduleQrCodeCutout(size: moduleCount, dimensions: imageSize, scale: scale)
    let padding = round((imageSize.width - moduleSide * CGFloat(moduleCount)) * 0.5 * scale) / scale
    return (moduleSide, padding)
}

private func submoduleRevealPlan(moduleCount: Int, moduleSide: CGFloat, padding: CGFloat, jitter: () -> Double) -> (batches: [[CGRect]], markers: [CGRect]) {
    let markerModuleCount = 9
    let markerOrigins = [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: CGFloat(moduleCount - markerModuleCount), y: 0.0),
        CGPoint(x: 0.0, y: CGFloat(moduleCount - markerModuleCount))
    ]
    let markerFrames = markerOrigins.map { origin in
        return CGRect(
            x: padding + origin.x * moduleSide,
            y: padding + origin.y * moduleSide,
            width: CGFloat(markerModuleCount) * moduleSide,
            height: CGFloat(markerModuleCount) * moduleSide
        )
    }
    let batchCount = 48
    var batches = Array(repeating: [CGRect](), count: batchCount)
    let center = CGFloat(moduleCount - 1) * 0.5
    for y in 0 ..< moduleCount {
        for x in 0 ..< moduleCount {
            if (y < markerModuleCount && (x < markerModuleCount || x >= moduleCount - markerModuleCount))
                || (y >= moduleCount - markerModuleCount && x < markerModuleCount) {
                continue
            }
            let frame = CGRect(
                x: padding + CGFloat(x) * moduleSide,
                y: padding + CGFloat(y) * moduleSide,
                width: moduleSide,
                height: moduleSide
            )
            let distanceToEdge = min(min(x, y), min(moduleCount - 1 - x, moduleCount - 1 - y))
            let inwardProgress = Double(CGFloat(distanceToEdge) / center)
            let dx = Double(CGFloat(x) - center)
            let dy = Double(CGFloat(y) - center)
            let angle = (atan2(dy, dx) + Double.pi) / (2.0 * Double.pi)
            let radius = hypot(dx, dy) / Double(center)
            let spiralPosition = angle + radius * 1.25
            let spiralPhase = spiralPosition - floor(spiralPosition)
            let phase = inwardProgress * 0.55 + spiralPhase * 0.4 + jitter()
            let batchIndex = min(batchCount - 1, Int(phase * Double(batchCount - 1)))
            batches[batchIndex].append(frame)
        }
    }
    return (batches, markerFrames)
}

private func submoduleRevealBatchDelay(index: Int, delay: Double, duration: Double) -> Double {
    let batchCount = 48
    return delay + Double(index) / Double(batchCount - 1) * max(0.0, duration - 0.12)
}

private func submoduleRefractionPixels(_ bytes: [UInt8]) -> [UInt8] {
    var pixels = bytes
    for offset in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = 255 - pixels[offset + 2]
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = alpha
    }
    return pixels
}

private final class SeededJitter {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    func next() -> Double {
        self.state = self.state &* 6364136223846793005 &+ 1442695040888963407
        return Double(self.state >> 11) / Double(1 << 53) * 0.05
    }
}

final class WalletReceiveQrSubmoduleCompatibilityTests: XCTestCase {
    func testDiamondIntroIsTheSubmoduleFile() throws {
        XCTAssertEqual(try source(actualIntroPath), try source(submoduleIntroPath))
    }

    func testDiamondIntroValuesMatchSubmodule() {
        for speed in [1.0, 1.5, 2.0] {
            for damping in [0.64, 0.8] {
                var time = -0.05
                while time < 1.4 {
                    let actual = InteractiveDiamondIntro(time: time, speed: speed, damping: damping)
                    let submodule = SubmoduleInteractiveDiamondIntro(time: time, speed: speed, damping: damping)
                    XCTAssertEqual(actual.progress, submodule.progress, accuracy: 1e-12, "t=\(time) speed=\(speed) damping=\(damping)")
                    XCTAssertEqual(actual.lift, submodule.lift, accuracy: 1e-12)
                    XCTAssertEqual(actual.scale, submodule.scale, accuracy: 1e-12)
                    XCTAssertEqual(actual.scale(from: 5.0, allowsOvershoot: true), submodule.scale(from: 5.0, allowsOvershoot: true), accuracy: 1e-12)
                    time += 1.0 / 240.0
                }
            }
        }
        XCTAssertEqual(InteractiveDiamondIntro(time: nil).progress, 1.0)
    }

    func testDiamondDropInMatchesSubmodule() {
        var sawOvershoot = false
        var sawSettled = false
        var elapsed = 0.0
        while elapsed < 1.0 {
            let actual = walletReceiveQrDiamondIntroFrame(elapsed: elapsed)
            let submodule = SubmoduleQrIntro.frame(elapsed: elapsed)
            XCTAssertEqual(actual == nil, submodule == nil, "elapsed \(elapsed)")
            if let actual, let submodule {
                XCTAssertEqual(actual.lift, submodule.lift, accuracy: 1e-12, "elapsed \(elapsed)")
                XCTAssertEqual(actual.openingScale == nil, submodule.openingScale == nil, "elapsed \(elapsed)")
                if let actualScale = actual.openingScale, let submoduleScale = submodule.openingScale {
                    XCTAssertEqual(actualScale, submoduleScale, accuracy: 1e-12, "elapsed \(elapsed)")
                    sawOvershoot = sawOvershoot || actualScale < 1.0
                }
            } else {
                sawSettled = true
            }
            elapsed += 1.0 / 240.0
        }
        XCTAssertTrue(sawOvershoot)
        XCTAssertTrue(sawSettled)
        XCTAssertEqual(walletReceiveQrDiamondIntroDuration, SubmoduleQrIntro.diamondIntroDuration, accuracy: 1e-12)
        XCTAssertEqual(walletReceiveQrIntroDelay, SubmoduleQrIntro.introDelay)
        XCTAssertEqual(walletReceiveQrRevealDuration, SubmoduleQrIntro.qrRevealDuration)
        XCTAssertEqual(walletReceiveQrDiamondIntroSpeed, SubmoduleQrIntro.diamondIntroSpeed)
        XCTAssertEqual(walletReceiveQrDiamondIntroFrame(elapsed: 0.0)?.openingScale ?? 0, 5.0, accuracy: 1e-9)
    }

    func testNativeDropInAndReviewedIOSRevealVariant() throws {
        let screen = collapsed(try source(submoduleReceivePath))
        for line in [
            "private static let introDelay = 0.03",
            "private static let qrRevealDuration = WalletReceiveQrRevealView.revealTime",
            "private static let diamondIntroSpeed = 1.5",
            "return Self.introDelay + (InteractiveDiamondIntro.duration - InteractiveDiamondIntro.delay) / Self.diamondIntroSpeed",
            "guard elapsed < max(Self.diamondIntroDuration, Self.introDelay + Self.qrRevealDuration),",
            "let introTime = elapsed + InteractiveDiamondIntro.delay - Self.introDelay",
            "let intro = InteractiveDiamondIntro(time: introTime, speed: Self.diamondIntroSpeed, damping: 0.64)",
            "let bounceAmplitude: CGFloat = intro.progress > 1.0 ? 0.49 : 1.0",
            "let scale = 1.0 + (intro.scale(from: 5.0, allowsOvershoot: true) - 1.0) * bounceAmplitude",
            "diamondView.center = CGPoint(x: self.diamondFrame.midX, y: self.diamondFrame.midY + intro.lift * bounceAmplitude)",
            "diamondView.updateOpeningScale(elapsed < Self.diamondIntroDuration ? scale : nil)"
        ] {
            XCTAssertTrue(screen.contains(collapsed(line)), line)
        }
        let receive = collapsed(try source(actualReceivePath))
        for line in [
            "qrDiamondView.setFrameOrigin(NSMakePoint(qrDiamondFrame.minX, qrDiamondFrame.minY + frame.lift))",
            "qrDiamondView.updateOpeningScale(frame.openingScale)",
            "revealView.animateIn(image: image, moduleCount: qrModuleCount, delay: walletReceiveQrIntroDelay, duration: walletReceiveQrRevealDuration)"
        ] {
            XCTAssertTrue(receive.contains(collapsed(line)), line)
        }
    }

    func testCutoutAndRevealGeometryMatchSubmodule() {
        for moduleCount in stride(from: 21, through: 177, by: 2) {
            for side in [200.0, 236.0, 256.0, 244.0] as [CGFloat] {
                for scale in [1.0, 2.0, 3.0] as [CGFloat] {
                    let size = CGSize(width: side, height: side)
                    XCTAssertEqual(walletReceiveQrCutoutFrame(moduleCount: moduleCount, qrSize: size, scale: scale), submoduleQrCodeCutout(size: moduleCount, dimensions: size, scale: scale).1, "\(moduleCount) \(side) \(scale)")
                    let actual = walletReceiveQrRevealGeometry(moduleCount: moduleCount, imageSize: size, scale: scale)
                    let submodule = submoduleRevealGeometry(moduleCount: moduleCount, imageSize: size, scale: scale)
                    XCTAssertEqual(actual.moduleSide, submodule.moduleSide, "\(moduleCount) \(side) \(scale)")
                    XCTAssertEqual(actual.padding, submodule.padding, "\(moduleCount) \(side) \(scale)")
                }
            }
        }
    }

    func testSubmoduleCutoutIsStillTheCopiedOne() throws {
        let qrCode = collapsed(try source(submoduleQrCodePath))
        for line in [
            "var cutoutSize = Int(round(CGFloat(size) * 0.297))",
            "if size == 39 { cutoutSize = 11 } else if cutoutSize % 2 == 0 { cutoutSize += 1 }",
            "cutoutSize = min(23, cutoutSize)",
            "let quadSize = floorToContextPixels(dimensions.width / CGFloat(size), scale: scale)",
            "let cutoutSide = quadSize * CGFloat(cutoutSize - 2)"
        ] {
            XCTAssertTrue(qrCode.contains(collapsed(line)), line)
        }
        let reveal = collapsed(try source(submoduleRevealPath))
        XCTAssertTrue(reveal.contains(collapsed("let padding = round((imageSize.width - moduleSide * CGFloat(n)) * 0.5 * self.image.scale) / self.image.scale")))
    }

    func testRevealPlanMatchesSubmodule() {
        for moduleCount in [21, 25, 29, 33, 37, 41, 45, 49, 53, 57] {
            let geometry = walletReceiveQrRevealGeometry(moduleCount: moduleCount, imageSize: CGSize(width: 236.0, height: 236.0), scale: 2.0)
            for seed in [1, 7, 42] as [UInt64] {
                let actualJitter = SeededJitter(seed: seed)
                let submoduleJitter = SeededJitter(seed: seed)
                let actual = walletReceiveQrRevealPlan(moduleCount: moduleCount, moduleSide: geometry.moduleSide, padding: geometry.padding, jitter: { actualJitter.next() })
                let submodule = submoduleRevealPlan(moduleCount: moduleCount, moduleSide: geometry.moduleSide, padding: geometry.padding, jitter: { submoduleJitter.next() })
                XCTAssertEqual(actual.markers, submodule.markers, "\(moduleCount)")
                XCTAssertEqual(actual.batches, submodule.batches, "\(moduleCount) seed \(seed)")
                XCTAssertEqual(actual.batches.reduce(0) { $0 + $1.count }, moduleCount * moduleCount - 3 * 81)
            }
        }
    }

    func testRevealRevealsInwardLikeSubmodule() {
        let geometry = walletReceiveQrRevealGeometry(moduleCount: 33, imageSize: CGSize(width: 236.0, height: 236.0), scale: 2.0)
        let plan = walletReceiveQrRevealPlan(moduleCount: 33, moduleSide: geometry.moduleSide, padding: geometry.padding, jitter: { 0.0 })
        let center = CGPoint(x: 118.0, y: 118.0)
        func meanDistance(_ frames: [CGRect]) -> CGFloat {
            return frames.reduce(0.0) { $0 + hypot($1.midX - center.x, $1.midY - center.y) } / CGFloat(max(1, frames.count))
        }
        let nonEmpty = plan.batches.filter { !$0.isEmpty }
        XCTAssertGreaterThan(meanDistance(Array(nonEmpty.prefix(6)).flatMap { $0 }), meanDistance(Array(nonEmpty.suffix(6)).flatMap { $0 }))
    }

    func testNativeRevealTimingAndReviewedIOSCenteredVariant() throws {
        for index in 0 ..< 48 {
            XCTAssertEqual(walletReceiveQrRevealBatchDelay(index: index, delay: 0.03, duration: 0.5), submoduleRevealBatchDelay(index: index, delay: 0.03, duration: 0.5), accuracy: 1e-12)
        }
        XCTAssertEqual(walletReceiveQrRevealBatchCount, 48)
        let submodule = collapsed(try source(submoduleRevealPath))
        for line in [
            "static let revealTime: Double = 0.6",
            "let k = Self.clamp01(time / Self.revealTime)",
            "let center = Double(n - 1) / 2.0",
            "let reach = hypot(center, center)",
            "width: 7.0 * moduleSide,"
        ] {
            XCTAssertTrue(submodule.contains(collapsed(line)), line)
        }
        let actual = try source(actualRevealPath)
        let compact = collapsed(actual)
        for line in [
            "let plan = walletReceiveQrRevealPlan(moduleCount: moduleCount, moduleSide: moduleSide, padding: padding, jitter: { Double.random(in: 0.0 ... 0.05) })",
            "fade.beginTime = batchLayer.convertTime(now, from: nil) + walletReceiveQrRevealBatchDelay(index: index, delay: delay, duration: duration)",
            "let grow = makeSpringAnimation(\"transform.scale\") grow.fromValue = 0.01 grow.toValue = 1.0 grow.beginTime = markerLayer.convertTime(now, from: nil) + delay",
            "fade.beginTime = markerLayer.convertTime(now, from: nil) + delay",
            "guard moduleSide > 0.0, moduleCount >= 21 else {"
        ] {
            XCTAssertTrue(compact.contains(collapsed(line)), line)
        }
        XCTAssertEqual(actual.components(separatedBy: "fade.duration = 0.12").count - 1, 2)
        XCTAssertEqual(actual.components(separatedBy: "fade.timingFunction = CAMediaTimingFunction(name: .easeOut)").count - 1, 2)
        XCTAssertEqual(actual.components(separatedBy: "fade.fillMode = .backwards").count - 1, 2)
        let spring = makeSpringAnimation("transform.scale")
        XCTAssertEqual(spring.duration, 0.5)
    }

    func testDiamondSitsInTheCutoutLikeSubmodule() throws {
        XCTAssertEqual(walletReceiveQrDiamondWidthRatio, 0.72)
        let submodule = collapsed(try source(submoduleReceivePath))
        for line in [
            "icon: .cutout,",
            "ecl: \"Q\"",
            "let (_, cutoutFrame, _) = qrCodeCutout(size: qrCodeSize, dimensions: imageSize, scale: nil)",
            "size: cutoutFrame.size, diamondWidth: cutoutFrame.width * 0.72, isVisible: component.isVisible, theme: component.theme, animationMode: .continuous"
        ] {
            XCTAssertTrue(submodule.contains(collapsed(line)), line)
        }
        let component = collapsed(try source("submodules/telegram-ios/submodules/TelegramUI/Components/Premium/PremiumDiamondComponent/Sources/PremiumDiamondComponent.swift"))
        XCTAssertTrue(component.contains(collapsed("self.diamondLayer.lightBackground = component.expansionStyle == .centered && !component.theme.overallDarkAppearance")))
        let actual = try source(actualReceivePath)
        let compact = collapsed(actual)
        for line in [
            "let icon: QrCodeIcon = .cutout",
            "icon: icon, ecl: \"Q\")",
            "let cutoutFrame = walletReceiveQrCutoutFrame(moduleCount: qrModuleCount, qrSize: qrView.frame.size, scale: backingScaleFactor)",
            "qrDiamondView.update(size: cutoutFrame.size, diamondWidth: cutoutFrame.width * walletReceiveQrDiamondWidthRatio, isVisible: window != nil && !item.displaysAddress, lightBackground: !theme.colors.isDark, animationMode: .continuous)"
        ] {
            XCTAssertTrue(compact.contains(collapsed(line)), line)
        }
        XCTAssertEqual(actual.components(separatedBy: "#if arch(arm64)\n        let icon: QrCodeIcon = .cutout").count - 1, 1)
    }

    func testRevealLifecycleMatchesSubmodule() throws {
        let submodule = collapsed(try source(submoduleReceivePath))
        for line in [
            "if UIAccessibility.isReduceMotionEnabled { self.didAnimateIn = true self.finishRevealAnimation() return }",
            "guard !self.didAnimateIn, let image = self.imageNode.image, let qrCodeSize = self.qrCodeSize,",
            "self.didAnimateIn = true let revealView = WalletReceiveQrRevealView(image: image, moduleCount: qrCodeSize)",
            "self.insertSubview(revealView, aboveSubview: self.imageNode.view) self.imageNode.isHidden = true",
            "if previousComponent?.address != component.address { self.finishRevealAnimation() self.didAnimateIn = false",
            "if expanded, self.revealStartTime != nil { self.finishRevealAnimation() } self.updateDiamondRefraction()",
            "self.imageNode.isHidden = false if let diamondView = self.diamond.view as? InteractiveDiamondComponent.View { diamondView.updateOpeningScale(nil) diamondView.frame = self.diamondFrame }"
        ] {
            XCTAssertTrue(submodule.contains(collapsed(line)), line)
        }
        let actual = collapsed(try source(actualReceivePath))
        for line in [
            "if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { qrDidAnimateIn = true finishQrReveal() return }",
            "guard !qrDidAnimateIn, let image = qrView.image, let qrModuleCount, qrView.frame.width > 0 else { return } qrDidAnimateIn = true",
            "qrContainer.addSubview(revealView, positioned: .above, relativeTo: qrView) qrRevealView = revealView qrView.isHidden = true",
            "qrModuleCount = nil #if arch(arm64) finishQrReveal() qrDidAnimateIn = false",
            "if expanded, self.qrRevealStartTime != nil { self.finishQrReveal() } self.updateQrDiamondRefraction()",
            "qrView.isHidden = false qrDiamondView.updateOpeningScale(nil) qrDiamondView.frame = qrDiamondFrame",
            "qrDiamondView.layer?.masksToBounds = false qrContainer.layer?.masksToBounds = false"
        ] {
            XCTAssertTrue(actual.contains(collapsed(line)), line)
        }
    }

    func testRefractionUsesTheQrRectLikeSubmodule() throws {
        let submodule = collapsed(try source(submoduleReceivePath))
        for line in [
            "guard diamondView.isExpanded, let image = self.imageNode.image, let cgImage = image.cgImage else { diamondView.updateRefractionSource(nil) return }",
            "let rect = self.imageNode.view.convert(self.imageNode.bounds, to: diamondView) .offsetBy(dx: -diamondView.bounds.midX, dy: -diamondView.bounds.midY)",
            "texture: texture, uv: SIMD4(0.0, 0.0, 1.0, 1.0), rect: rect, preservesColors: true"
        ] {
            XCTAssertTrue(submodule.contains(collapsed(line)), line)
        }
        let actual = collapsed(try source(actualReceivePath))
        for line in [
            "guard qrDiamondView.isExpanded, let image = qrView.image else { qrDiamondView.updateRefractionSource(nil) return }",
            "let rect = qrView.frame.offsetBy(dx: -qrDiamondView.frame.midX, dy: -qrDiamondView.frame.midY)",
            "InteractiveDiamondView.RefractionSource(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: rect, preservesColors: true)"
        ] {
            XCTAssertTrue(actual.contains(collapsed(line)), line)
        }
    }

    #if arch(arm64)
    func testRefractionTextureMatchesSubmodulePixels() throws {
        let width = 12
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 6, width: 4, height: 2))
        context.setFillColor(NSColor(white: 0.5, alpha: 1.0).cgColor)
        context.fill(CGRect(x: 6, y: 0, width: 3, height: 3))
        context.setFillColor(NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1.0).cgColor)
        context.fill(CGRect(x: 9, y: 4, width: 3, height: 2))
        let image = try XCTUnwrap(context.makeImage())

        let texture = try XCTUnwrap(walletReceiveQrRefractionTexture(image))
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm)
        XCTAssertEqual(texture.width, width)
        XCTAssertEqual(texture.height, height)
        var actual = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&actual, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        var drawn = [UInt8](repeating: 0, count: width * height * 4)
        drawn.withUnsafeMutableBytes { storage in
            let bitmap = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            bitmap?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        XCTAssertEqual(actual, submoduleRefractionPixels(drawn))
        XCTAssertEqual(actual[3], 255, "the top-left black square stays opaque in the first row")
        XCTAssertEqual(actual[(height - 1) * width * 4 + 3], 0, "white backing becomes transparent")
    }
    #endif
}
