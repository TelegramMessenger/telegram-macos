import XCTest
import Cocoa
import Foundation
import TelegramCore
import WalletContext
@testable import WalletUI
@testable import SceneEffects

private struct SubmoduleTransferStar {
    let angle: Double
    let speed: Double
    let size: Double
    let life: Double
    let delay: Double
    let phase: Double
    let tone: Int
}

private let submoduleTransferStars: [SubmoduleTransferStar] = {
    var seed: UInt64 = 31 &* 0x9E37_79B9_7F4A_7C15 | 1
    func random(_ lower: Double, _ upper: Double) -> Double {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return lower + (upper - lower) * Double(seed % 1_000_000) / 1_000_000.0
    }
    return (0 ..< 34).map { i in
        SubmoduleTransferStar(angle: i % 2 == 0 ? .pi + random(-0.75, 0.75) : random(0.0, 2.0 * .pi),
            speed: random(160.0, 760.0), size: random(2.6, 6.2), life: random(0.6, 1.15),
            delay: random(0.0, 0.09), phase: random(0.0, 2.0 * .pi), tone: Int(random(0.0, 2.99)))
    }
}()

private struct SubmoduleTransferFrame {
    var lift: CGFloat = 0.0
    var dip: CGFloat = 0.0
    var scale: CGFloat = 1.0
    var translationY: CGFloat = 0.0
    var surfaceOpacity: Float = 0.0
    var expansion: CGFloat = 0.0
    var iconAlpha: CGFloat = 0.0
    var iconScale: CGFloat = 0.0
    var clockAlpha: CGFloat = 0.0
    var separatorOpacity: Float = 0.0
    var clockTime: Double = 0.0
    var sheenOpacity: Float = 0.0
    var slot: CGPoint = .zero
    var diamondWidth: CGFloat = 0.0
    var diamondAlpha: CGFloat = 0.0
    var starTime: Double?
    var finished = false
}

private enum SubmodulePendingTransfer {
    static func spring(_ time: Double, damping: Double = 7.0, frequency: Double = 14.0) -> CGFloat {
        guard time > 0.0 else { return 0.0 }
        return CGFloat(1.0 - exp(-damping * time) * (cos(frequency * time) + damping / frequency * sin(frequency * time)))
    }

    static func frame(now: CFTimeInterval, start: CFTimeInterval, completion: CFTimeInterval?, landing: CFTimeInterval?, reduced: Bool, normal: CGPoint, pending: CGPoint, iconWidth: CGFloat) -> SubmoduleTransferFrame {
        var result = SubmoduleTransferFrame()
        let elapsed = max(0.0, now - start)
        let finish = completion.map { max(0.0, now - $0) }
        var lift = reduced ? CGFloat(0.0) : Self.spring(now - start)
        if let finish { lift *= 1.0 - Self.spring(finish, damping: 8.0, frequency: 13.0) }
        let big: CGFloat = reduced ? 0.0 : finish.map { CGFloat(pow(1.0 - min(1.0, $0 / 0.3), 3.0)) } ?? 1.0
        let impact = landing.map { now - $0 } ?? 0.0
        let dip = !reduced && impact > 0.0 && impact < 1.2
            ? CGFloat(5.0 * sin(2.0 * .pi * 2.2 * impact) * exp(-impact / 0.2)) : 0.0
        let scale = 1.0 + 0.035 * lift - 0.004 * dip
        result.lift = lift
        result.dip = dip
        result.scale = scale
        result.translationY = -2.0 * lift + dip
        result.surfaceOpacity = Float(max(0.0, min(1.0, lift)))
        let iconAlpha: CGFloat
        if reduced { iconAlpha = 1.0 }
        else if let finish { iconAlpha = min(1.0, max(0.0, Self.spring(finish - 0.32, damping: 8.0, frequency: 17.0))) }
        else { iconAlpha = 0.0 }
        let clockAlpha = finish.map { 0.5 + 0.5 * CGFloat(cos(.pi * min(1.0, $0 / (reduced ? 0.15 : 0.35)))) } ?? 1.0
        result.separatorOpacity = Float(1.0 - clockAlpha)
        let iconScale = reduced ? 1.0 : finish.map { 0.2 + 0.8 * Self.spring($0 - 0.32, damping: 8.0, frequency: 17.0) } ?? 0.2
        result.expansion = big
        result.iconAlpha = iconAlpha
        result.iconScale = iconScale
        result.clockAlpha = clockAlpha
        result.clockTime = reduced ? 0.0 : elapsed
        result.sheenOpacity = !reduced && finish == nil ? 1.0 : 0.0
        var slot = CGPoint(x: normal.x + (pending.x - normal.x) * big, y: normal.y + (pending.y - normal.y) * big)
        if let finish, finish < 0.34 { slot.y -= CGFloat(sin(.pi * finish / 0.34)) * 11.0 }
        result.slot = slot
        var width: CGFloat = 34.0
        if let finish {
            let pop = CGFloat(sin(.pi * min(1.0, finish / 0.26))) * 0.3
            let shrink = CGFloat(max(0.0, min(1.0, (finish - 0.18) / 0.16)))
            width = 34.0 * (1.0 + pop) * (1.0 - shrink) + iconWidth * shrink
        } else if impact > 0.0 && impact < 0.36 {
            width *= 1.0 + 0.26 * CGFloat(sin(.pi * impact / 0.36) * (1.0 - 0.3 * impact / 0.36))
        }
        result.diamondWidth = width
        result.diamondAlpha = reduced ? 0.0 : finish.map { CGFloat(max(0.0, min(1.0, 1.0 - ($0 - 0.35) / 0.1))) } ?? 1.0
        result.starTime = reduced ? nil : finish
        if let finish, finish >= (reduced ? 0.15 : 1.3) { result.finished = true }
        return result
    }

    static func flight(now: CFTimeInterval, start: CFTimeInterval, sourceCenter: CGPoint, sourceWidth: CGFloat, target: CGPoint, targetWidth: CGFloat) -> (t: CGFloat, center: CGPoint, width: CGFloat, speed: Float) {
        let t = min(1.0, max(0.0, now - start) / 0.5)
        let d = target.y - sourceCenter.y
        let rise = 44.0 + max(0.0, -d)
        let b = -2.0 * rise - 2.0 * sqrt(max(0.0, rise * rise + rise * d))
        let center = CGPoint(x: sourceCenter.x + (target.x - sourceCenter.x) * t,
            y: sourceCenter.y + b * t + (d - b) * t * t)
        let width = (sourceWidth + (targetWidth - sourceWidth) * t) * (1.0 + 0.28 * sin(.pi * min(1.0, t / 0.75)))
        let speed = Float(2.0 * .pi / 26.0 + (6.5 - 2.0 * .pi / 26.0) * min(1.0, t / 0.6))
        return (CGFloat(t), center, width, speed)
    }

    static func sheen(elapsed: Double, size: CGSize, opacity: Float) -> (opacity: Float, bands: [(CGPoint, CGPoint)]?) {
        let u = (elapsed + 0.2).truncatingRemainder(dividingBy: 2.5) / 1.5
        let sheenOpacity = u <= 1.0 ? opacity * Float(sin(.pi * u)) : 0.0
        guard u <= 1.0, size.width > 0.0, size.height > 0.0 else { return (sheenOpacity, nil) }
        let x = (-0.25 + 1.5 * (0.5 - 0.5 * cos(.pi * u))) * size.width
        return (sheenOpacity, [150.0, 60.0, 120.0, 90.0].map { width in
            (CGPoint(x: (x - width) / size.width, y: 0.0), CGPoint(x: (x + width) / size.width, y: width * 0.55 / size.height))
        })
    }

    static func star(_ star: SubmoduleTransferStar, time: Double, origin: CGPoint) -> (position: CGPoint, opacity: Float, transform: CGAffineTransform)? {
        let age = time - star.delay
        guard age > 0.0 && age < star.life else { return nil }
        let u = age / star.life
        let distance = star.speed * (1.0 - exp(-2.6 * age)) / 2.6
        let position = CGPoint(x: origin.x + cos(star.angle) * distance, y: origin.y + sin(star.angle) * distance * 0.45)
        let opacity = Float(min(1.0, u / 0.12) * (1.0 - u * u))
        let scale = (0.55 + 0.45 * (1.0 - u)) * (0.72 + 0.28 * sin(age * 19.0 + star.phase))
        return (position, opacity, CGAffineTransform(rotationAngle: star.phase + age * 2.4).scaledBy(x: scale, y: scale))
    }

    static func amount(expansion: CGFloat, width: CGFloat) -> (scale: CGFloat, tx: CGFloat, ty: CGFloat) {
        let scale = 1.0 + 0.33 * expansion
        return (scale, -23.0 * expansion - (scale - 1.0) * width * 0.5, 20.35 * expansion)
    }

    static func clockHands(time: Double) -> (minute: CGFloat, hour: CGFloat) {
        return (CGFloat(time * 4.2), CGFloat(time * 4.2 / 12.0 - .pi / 2.0))
    }

    static func showsAnimation(_ transaction: WalletContext.Transaction) -> Bool {
        return transaction.status == .pending && transaction.currency == .ton
            && transaction.direction == .outgoing && transaction.kind != .deployContract && transaction.kind != .keyChange
            && transaction.isVisibleInWalletHistory
    }

    static func observe(_ transaction: WalletContext.Transaction?, isFlying: Bool, isVisible: Bool, transferScreenVisible: Bool, transferApplicationActive: Bool) -> WalletPendingTransferObservation {
        guard let transaction = transaction, transaction.status != .failed else {
            return .remove
        }
        let isPending = transaction.status == .pending
        if !isPending && !isFlying && (!isVisible || !transferScreenVisible || !transferApplicationActive) {
            return .remove
        }
        return .keep(isPending: isPending)
    }

    static func accepts(_ transaction: WalletContext.Transaction?, transferApplicationActive: Bool, hasSource: Bool, sourceHasWindow: Bool) -> Bool {
        guard transferApplicationActive,
              let transaction = transaction,
              transaction.status != .failed, transaction.isVisibleInWalletHistory else { return false }
        if hasSource && !sourceHasWindow { return false }
        return true
    }

    static func recipient(hasPeer: Bool, address: String?) -> (passesTransferAnimation: Bool, opensChat: Bool) {
        if hasPeer {
            return (address == nil, address != nil)
        }
        return (true, false)
    }
}

private func mirroredValue<T>(_ subject: Any, _ label: String) -> T? {
    var mirror: Mirror? = Mirror(reflecting: subject)
    while let current = mirror {
        if let child = current.children.first(where: { $0.label == label }) {
            return child.value as? T
        }
        mirror = current.superclassMirror
    }
    return nil
}

final class WalletPendingTransferSubmoduleCompatibilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        applyMacEnglishStrings()
    }

    override func tearDown() {
        applyMacEnglishStrings([:])
        super.tearDown()
    }

    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func submoduleSource(_ path: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components").appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func assertSubmodule(_ path: String, contains snippets: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try submoduleSource(path)
        for snippet in snippets {
            let normalized = snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            XCTAssertTrue(source.contains(normalized), "\(path) no longer contains: \(snippet)", file: file, line: line)
        }
    }

    private func transaction(status: WalletContext.Transaction.Status = .pending, direction: WalletContext.Transaction.Direction = .outgoing, currency: WalletContext.Transaction.Currency = .ton, kind: WalletContext.Transaction.Kind = .transfer, collectible: Bool = false, amount: Int64 = 1_000_000_000) -> WalletContext.Transaction {
        return WalletContext.Transaction(
            id: "pending:1",
            logicalTime: "1",
            timestamp: 0,
            direction: direction,
            amount: amount,
            fee: 0,
            peer: .address("UQAREREREREREREREREREREREREREREREREREREREREREbvW", domain: nil),
            comment: nil,
            currency: currency,
            collectible: collectible ? WalletContext.Transaction.CollectibleTransfer(address: "nft", name: "Gift", image: nil, kind: .gift) : nil,
            status: status,
            kind: kind
        )
    }

    private func transactionMatrix() -> [WalletContext.Transaction] {
        var result: [WalletContext.Transaction] = []
        for status in [WalletContext.Transaction.Status.pending, .completed, .failed] {
            for direction in [WalletContext.Transaction.Direction.outgoing, .incoming, .unknown] {
                for currency in [WalletContext.Transaction.Currency.ton, .usdt] {
                    for kind in [WalletContext.Transaction.Kind.transfer, .deployContract, .keyChange] {
                        for collectible in [false, true] {
                            for amount in [Int64(1_000), 1_000_000_000] {
                                result.append(transaction(status: status, direction: direction, currency: currency, kind: kind, collectible: collectible, amount: amount))
                            }
                        }
                    }
                }
            }
        }
        return result
    }

    func testSubmoduleTimelineIsStillTheCopiedOne() throws {
        try assertSubmodule("Wallet/WalletScreen/Sources/WalletPendingTransferAnimation.swift", contains: [
            "var lift = reduced ? CGFloat(0.0) : Self.spring(now - (self.start ?? now))",
            "if let finish { lift *= 1.0 - Self.spring(finish, damping: 8.0, frequency: 13.0) }",
            "let big: CGFloat = reduced ? 0.0 : finish.map { CGFloat(pow(1.0 - min(1.0, $0 / 0.3), 3.0)) } ?? 1.0",
            "let dip = !reduced && impact > 0.0 && impact < 1.2 ? CGFloat(5.0 * sin(2.0 * .pi * 2.2 * impact) * exp(-impact / 0.2)) : 0.0",
            "let scale = 1.0 + 0.035 * lift - 0.004 * dip",
            "row.transform = CGAffineTransform(translationX: 0.0, y: -2.0 * lift + dip).scaledBy(x: scale, y: scale)",
            "self.surface.opacity = Float(max(0.0, min(1.0, lift)))",
            "self.surface.shadowOpacity = 0.13",
            "else if let finish { iconAlpha = min(1.0, max(0.0, Self.spring(finish - 0.32, damping: 8.0, frequency: 17.0))) }",
            "let clockAlpha = finish.map { 0.5 + 0.5 * CGFloat(cos(.pi * min(1.0, $0 / (reduced ? 0.15 : 0.35)))) } ?? 1.0",
            "self.separatorMask.opacity = Float(1.0 - clockAlpha)",
            "let iconScale = reduced ? 1.0 : finish.map { 0.2 + 0.8 * Self.spring($0 - 0.32, damping: 8.0, frequency: 17.0) } ?? 0.2",
            "content.applyTransferPresentation(expansion: big, iconAlpha: iconAlpha, iconScale: iconScale, clockAlpha: clockAlpha, time: reduced ? 0.0 : elapsed)",
            "self.updateSheen(elapsed: elapsed, opacity: !reduced && finish == nil ? 1.0 : 0.0)",
            "var pending = CGPoint(x: row.bounds.width - 34.5, y: row.bounds.height * 0.5)",
            "if let finish, finish < 0.34 { slot.y -= CGFloat(sin(.pi * finish / 0.34)) * 11.0 }",
            "let t = min(1.0, max(0.0, now - start) / 0.5)",
            "let rise = 44.0 + max(0.0, -d)",
            "let b = -2.0 * rise - 2.0 * sqrt(max(0.0, rise * rise + rise * d))",
            "y: source.center.y + b * t + (d - b) * t * t)",
            "let width = (source.width + (targetWidth - source.width) * t) * (1.0 + 0.28 * sin(.pi * min(1.0, t / 0.75)))",
            "let speed = Float(2.0 * .pi / 26.0 + (6.5 - 2.0 * .pi / 26.0) * min(1.0, t / 0.6))",
            "diamond.updateWalletTransfer(width: 34.0, rotationSpeed: 6.5, completion: false, isDark: self.isDark)",
            "diamond.spin(7.0, decay: 0.7)",
            "let pop = CGFloat(sin(.pi * min(1.0, finish / 0.26))) * 0.3",
            "let shrink = CGFloat(max(0.0, min(1.0, (finish - 0.18) / 0.16)))",
            "width = 34.0 * (1.0 + pop) * (1.0 - shrink) + icon.width * shrink",
            "width *= 1.0 + 0.26 * CGFloat(sin(.pi * impact / 0.36) * (1.0 - 0.3 * impact / 0.36))",
            "diamond.alpha = reduced ? 0.0 : finish.map { CGFloat(max(0.0, min(1.0, 1.0 - ($0 - 0.35) / 0.1))) } ?? 1.0",
            "diamond.updateWalletTransfer(width: width, rotationSpeed: 6.5, completion: finish != nil, isDark: self.isDark)",
            "self.updateStars(time: reduced ? nil : finish, origin: pending)",
            "if let finish, finish >= (reduced ? 0.15 : 1.3) { self.finished = true }",
            "let u = (elapsed + 0.2).truncatingRemainder(dividingBy: 2.5) / 1.5",
            "self.sheen.opacity = u <= 1.0 ? opacity * Float(sin(.pi * u)) : 0.0",
            "let x = (-0.25 + 1.5 * (0.5 - 0.5 * cos(.pi * u))) * self.laidOutSize.width",
            "for (band, width) in zip(self.bands, [150.0, 60.0, 120.0, 90.0]) {",
            "band.endPoint = CGPoint(x: (x + width) / self.laidOutSize.width, y: width * 0.55 / self.laidOutSize.height)",
            "for (index, specification) in [(150.0, 0.07, 0.0), (60.0, 0.07, 0.0), (120.0, 0.22, 5.0), (90.0, 0.85, 1.2)].enumerated() {",
            "guard let time, time < 1.25 else { self.particles.isHidden = true; return }",
            "let distance = star.speed * (1.0 - exp(-2.6 * age)) / 2.6",
            "layer.opacity = Float(min(1.0, u / 0.12) * (1.0 - u * u))",
            "let scale = (0.55 + 0.45 * (1.0 - u)) * (0.72 + 0.28 * sin(age * 19.0 + star.phase))",
            "self.surface.cornerRadius = 22.0",
            "self.surface.shadowRadius = 14.0",
            "self.surface.shadowOffset = CGSize(width: 0.0, height: 6.0)",
            "source.diamond.updateWalletTransfer(width: source.width, rotationSpeed: 2.0 * .pi / 26.0, completion: false, isDark: self.isDark)",
            "self.start = now + 0.1",
            "guard let flightStart = self.flightStart, time - flightStart < 0.5 else {"
        ])
        try assertSubmodule("Wallet/WalletTransactionItemComponent/Sources/WalletTransactionItemComponent.swift", contains: [
            "let scale = 1.0 + 0.33 * expansion",
            "tx: offset * expansion - (scale - 1.0) * view.bounds.width * 0.5, ty: 20.35 * expansion)",
            "self.clockMinute.setAffineTransform(CGAffineTransform(rotationAngle: time * 4.2))",
            "self.clockHour.setAffineTransform(CGAffineTransform(rotationAngle: time * 4.2 / 12.0 - .pi / 2.0))",
            "if isPending && !component.animatesPendingTransfer {",
            "isPending: isPending && !component.animatesPendingTransfer,"
        ])
    }

    func testTimelineMatchesSubmodule() {
        let normal = CGPoint(x: 290.0, y: 20.0)
        let pending = CGPoint(x: 301.5, y: 37.0)
        for reduced in [false, true] {
            for completion in [nil, 1.4] as [CFTimeInterval?] {
                for landing in [nil, 0.6] as [CFTimeInterval?] {
                    var now: CFTimeInterval = -0.1
                    while now <= 3.5 {
                        let completionNow: CFTimeInterval? = completion.flatMap { $0 > now ? nil : $0 }
                        let expected = SubmodulePendingTransfer.frame(now: now, start: 0.1, completion: completionNow, landing: landing, reduced: reduced, normal: normal, pending: pending, iconWidth: 18.0)
                        let actual = WalletPendingTransferMotion(now: now, start: 0.1, completion: completionNow, landing: landing, reduced: reduced)
                        let label = "now \(now) reduced \(reduced) completion \(String(describing: completion)) landing \(String(describing: landing))"
                        XCTAssertEqual(actual.lift, expected.lift, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.dip, expected.dip, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.scale, expected.scale, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.translationY, expected.translationY, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.surfaceOpacity, expected.surfaceOpacity, accuracy: 1e-6, label)
                        XCTAssertEqual(actual.expansion, expected.expansion, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.iconAlpha, expected.iconAlpha, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.iconScale, expected.iconScale, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.clockAlpha, expected.clockAlpha, accuracy: 1e-12, label)
                        XCTAssertEqual(Float(1.0 - actual.clockAlpha), expected.separatorOpacity, accuracy: 1e-6, label)
                        XCTAssertEqual(actual.clockTime, expected.clockTime, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.showsSheen ? Float(1.0) : 0.0, expected.sheenOpacity, label)
                        let slot = actual.slot(normal: normal, pending: pending)
                        XCTAssertEqual(slot.x, expected.slot.x, accuracy: 1e-9, label)
                        XCTAssertEqual(slot.y, expected.slot.y, accuracy: 1e-9, label)
                        XCTAssertEqual(actual.diamondWidth(iconWidth: 18.0), expected.diamondWidth, accuracy: 1e-9, label)
                        XCTAssertEqual(actual.diamondAlpha, expected.diamondAlpha, accuracy: 1e-12, label)
                        XCTAssertEqual(actual.starTime, expected.starTime, label)
                        XCTAssertEqual(actual.finished, expected.finished, label)
                        now += 0.01
                    }
                }
            }
        }
    }

    func testTimelineKeyMomentsMatchSubmodule() {
        let sending = WalletPendingTransferMotion(now: 2.0, start: 0.0, completion: nil, landing: nil, reduced: false)
        XCTAssertEqual(sending.expansion, 1.0)
        XCTAssertEqual(sending.iconAlpha, 0.0)
        XCTAssertEqual(sending.iconScale, 0.2, accuracy: 1e-12)
        XCTAssertEqual(sending.clockAlpha, 1.0)
        XCTAssertEqual(sending.diamondAlpha, 1.0)
        XCTAssertTrue(sending.showsSheen)
        XCTAssertFalse(sending.finished)
        let done = WalletPendingTransferMotion(now: 3.31, start: 0.0, completion: 2.0, landing: nil, reduced: false)
        XCTAssertTrue(done.finished)
        XCTAssertEqual(done.expansion, 0.0)
        XCTAssertEqual(done.clockAlpha, 0.0, accuracy: 1e-12)
        XCTAssertEqual(done.diamondAlpha, 0.0)
        let reduced = WalletPendingTransferMotion(now: 0.16, start: 0.0, completion: 0.0, landing: nil, reduced: true)
        XCTAssertTrue(reduced.finished)
        XCTAssertEqual(reduced.iconAlpha, 1.0)
        XCTAssertEqual(reduced.iconScale, 1.0)
        XCTAssertNil(reduced.starTime)
    }

    func testFlightMatchesSubmodule() {
        let sources: [(CGPoint, CGFloat)] = [(CGPoint(x: 200.0, y: 500.0), 24.0), (CGPoint(x: 600.0, y: 120.0), 51.6), (CGPoint(x: 410.0, y: 300.0), 34.0)]
        let targets: [(CGPoint, CGFloat)] = [(CGPoint(x: 700.0, y: 240.0), 34.0), (CGPoint(x: 300.0, y: 640.0), 34.0), (CGPoint(x: 410.0, y: 300.0), 40.0)]
        for (sourceCenter, sourceWidth) in sources {
            for (target, targetWidth) in targets {
                var now: CFTimeInterval = 9.95
                while now <= 10.6 {
                    let expected = SubmodulePendingTransfer.flight(now: now, start: 10.0, sourceCenter: sourceCenter, sourceWidth: sourceWidth, target: target, targetWidth: targetWidth)
                    let t = WalletPendingTransferFlight.progress(now: now, start: 10.0)
                    let center = WalletPendingTransferFlight.center(origin: sourceCenter, target: target, t: t)
                    XCTAssertEqual(t, expected.t, accuracy: 1e-12)
                    XCTAssertEqual(center.x, expected.center.x, accuracy: 1e-9)
                    XCTAssertEqual(center.y, expected.center.y, accuracy: 1e-9)
                    XCTAssertEqual(WalletPendingTransferFlight.width(sourceWidth: sourceWidth, targetWidth: targetWidth, t: t), expected.width, accuracy: 1e-9)
                    XCTAssertEqual(WalletPendingTransferFlight.rotationSpeed(t: t), expected.speed, accuracy: 1e-6)
                    now += 0.01
                }
                let landed = WalletPendingTransferFlight.center(origin: sourceCenter, target: target, t: 1.0)
                XCTAssertEqual(landed.x, target.x, accuracy: 1e-9)
                XCTAssertEqual(landed.y, target.y, accuracy: 1e-9)
            }
        }
    }

    func testFlightArcRisesAboveBothEnds() {
        let origin = CGPoint(x: 200.0, y: 500.0)
        let target = CGPoint(x: 700.0, y: 240.0)
        let top = stride(from: 0.0, through: 1.0, by: 0.01).map { WalletPendingTransferFlight.center(origin: origin, target: target, t: CGFloat($0)).y }.min()!
        XCTAssertEqual(top, target.y - 44.0, accuracy: 0.1)
    }

    func testSheenMatchesSubmodule() {
        for size in [CGSize(width: 320.0, height: 58.0), CGSize(width: 400.0, height: 74.0), CGSize(width: 0.0, height: 58.0)] {
            for opacity in [Float(1.0), 0.0] {
                var elapsed = 0.0
                while elapsed <= 6.0 {
                    let expected = SubmodulePendingTransfer.sheen(elapsed: elapsed, size: size, opacity: opacity)
                    let actual = walletPendingTransferSheen(elapsed: elapsed, size: size, opacity: opacity)
                    XCTAssertEqual(actual.opacity, expected.opacity, accuracy: 1e-6)
                    XCTAssertEqual(actual.bands == nil, expected.bands == nil)
                    if let actualBands = actual.bands, let expectedBands = expected.bands {
                        XCTAssertEqual(actualBands.count, expectedBands.count)
                        for (a, e) in zip(actualBands, expectedBands) {
                            XCTAssertEqual(a.start.x, e.0.x, accuracy: 1e-12)
                            XCTAssertEqual(a.start.y, e.0.y, accuracy: 1e-12)
                            XCTAssertEqual(a.end.x, e.1.x, accuracy: 1e-12)
                            XCTAssertEqual(a.end.y, e.1.y, accuracy: 1e-12)
                        }
                    }
                    elapsed += 0.013
                }
            }
        }
        XCTAssertEqual(walletPendingTransferSheenBands.map { $0.width }, [150.0, 60.0, 120.0, 90.0])
        XCTAssertEqual(walletPendingTransferSheenBands.map { $0.peak }, [0.07, 0.07, 0.22, 0.85])
        XCTAssertEqual(walletPendingTransferSheenBands.map { $0.lineWidth }, [0.0, 0.0, 5.0, 1.2])
    }

    func testStarsMatchSubmodule() {
        XCTAssertEqual(walletPendingTransferStars.count, submoduleTransferStars.count)
        for (actual, expected) in zip(walletPendingTransferStars, submoduleTransferStars) {
            XCTAssertEqual(actual.angle, expected.angle)
            XCTAssertEqual(actual.speed, expected.speed)
            XCTAssertEqual(actual.size, expected.size)
            XCTAssertEqual(actual.life, expected.life)
            XCTAssertEqual(actual.delay, expected.delay)
            XCTAssertEqual(actual.phase, expected.phase)
            XCTAssertEqual(actual.tone, expected.tone)
        }
        let origin = CGPoint(x: 301.5, y: 37.0)
        var time = 0.0
        while time < 1.3 {
            for (actualStar, expectedStar) in zip(walletPendingTransferStars, submoduleTransferStars) {
                let actual = walletPendingTransferStarFrame(actualStar, time: time, origin: origin)
                let expected = SubmodulePendingTransfer.star(expectedStar, time: time, origin: origin)
                XCTAssertEqual(actual == nil, expected == nil)
                if let actual, let expected {
                    XCTAssertEqual(actual.position.x, expected.position.x, accuracy: 1e-9)
                    XCTAssertEqual(actual.position.y, expected.position.y, accuracy: 1e-9)
                    XCTAssertEqual(actual.opacity, expected.opacity, accuracy: 1e-6)
                    XCTAssertEqual(actual.transform.a, expected.transform.a, accuracy: 1e-9)
                    XCTAssertEqual(actual.transform.b, expected.transform.b, accuracy: 1e-9)
                    XCTAssertEqual(actual.transform.c, expected.transform.c, accuracy: 1e-9)
                    XCTAssertEqual(actual.transform.d, expected.transform.d, accuracy: 1e-9)
                }
            }
            time += 0.017
        }
    }

    func testRowPresentationMatchesSubmodule() {
        for expansion in stride(from: 0.0, through: 1.0, by: 0.05) {
            for width in [CGFloat(40.0), 72.5, 118.0] {
                let expected = SubmodulePendingTransfer.amount(expansion: CGFloat(expansion), width: width)
                let actual = walletPendingTransferAmountTransform(expansion: CGFloat(expansion), width: width, verticalOffset: 20.35)
                XCTAssertEqual(actual.scale, expected.scale, accuracy: 1e-12)
                XCTAssertEqual(actual.translation.x, expected.tx, accuracy: 1e-12)
                XCTAssertEqual(actual.translation.y, expected.ty, accuracy: 1e-12)
            }
        }
        for time in stride(from: 0.0, through: 30.0, by: 0.37) {
            let expected = SubmodulePendingTransfer.clockHands(time: time)
            let actual = walletPendingTransferClockHandAngles(time: time)
            XCTAssertEqual(actual.minute, expected.minute, accuracy: 1e-12)
            XCTAssertEqual(actual.hour, expected.hour, accuracy: 1e-12)
        }
    }

    func testWhichTransfersAnimateMatchesSubmodule() throws {
        try assertSubmodule("Wallet/WalletScreen/Sources/WalletScreen.swift", contains: [
            "for transaction in state.transactions.items where transaction.status == .pending && transaction.currency == .ton && transaction.direction == .outgoing && transaction.kind != .deployContract && transaction.kind != .keyChange && transaction.isVisibleInWalletHistory {",
            "guard let transaction = transactions[id], transaction.status != .failed else {",
            "animation.isPending = transaction.status == .pending",
            "if !animation.isPending && !animation.isFlying && (!animation.isVisible || !self.transferScreenVisible || !self.transferApplicationInForeground) {",
            "transaction.status != .failed, transaction.isVisibleInWalletHistory else { return false }",
            "if let source, source.window == nil { return false }",
            "animatesPendingTransfer: self?.pendingTransferAnimations[transaction.presentationId] != nil"
        ])
        for transaction in transactionMatrix() {
            XCTAssertEqual(walletShowsTransferAnimation(transaction), SubmodulePendingTransfer.showsAnimation(transaction), "\(transaction)")
        }
    }

    func testPendingTransferObservationMatchesSubmodule() {
        var transactions: [WalletContext.Transaction?] = [nil]
        for status in [WalletContext.Transaction.Status.pending, .completed, .failed] {
            transactions.append(transaction(status: status))
        }
        for transaction in transactions {
            for isFlying in [false, true] {
                for isVisible in [false, true] {
                    let expected = SubmodulePendingTransfer.observe(transaction, isFlying: isFlying, isVisible: isVisible, transferScreenVisible: true, transferApplicationActive: true)
                    XCTAssertEqual(walletObservePendingTransfer(transaction, isFlying: isFlying, isVisible: isVisible), expected, "\(String(describing: transaction?.status)) flying \(isFlying) visible \(isVisible)")
                }
            }
        }
    }

    func testWalletAcceptsTheSameTransferAnimationsAsSubmodule() {
        var transactions: [WalletContext.Transaction?] = [nil]
        transactions.append(contentsOf: transactionMatrix())
        for transaction in transactions {
            for (hasSource, sourceHasWindow) in [(false, false), (true, true), (true, false)] {
                let expected = SubmodulePendingTransfer.accepts(transaction, transferApplicationActive: true, hasSource: hasSource, sourceHasWindow: sourceHasWindow)
                let actual = walletAcceptsTransferAnimation(transaction, sourceWindowMissing: hasSource && !sourceHasWindow)
                XCTAssertEqual(actual, expected)
            }
        }
    }

    func testRecipientRoutingMatchesSubmodule() throws {
        try assertSubmodule("Wallet/WalletPeerSelectionScreen/Sources/WalletPeerSelectionScreen.swift", contains: [
            "transferAnimation: address == nil ? component.transferAnimation : nil,",
            "if address == nil { component.returnedToWallet?() }",
            "if address != nil, let navigationController {",
            "transferAnimation: component.transferAnimation, completed: { dismissSelectionScreen() component.returnedToWallet?() }"
        ])
        for hasPeer in [false, true] {
            for address in [nil, "UQAREREREREREREREREREREREREREREREREREREREREREbvW"] as [String?] {
                guard hasPeer || address != nil else {
                    continue
                }
                let expected = SubmodulePendingTransfer.recipient(hasPeer: hasPeer, address: address)
                let opensChat = walletRecipientSendOpensChat(hasPeer: hasPeer, address: address)
                XCTAssertEqual(opensChat, expected.opensChat)
                XCTAssertEqual(!opensChat, expected.passesTransferAnimation)
            }
        }
    }

    func testSendsToPeopleOutsideTheWalletOpenTheChat() throws {
        try assertSubmodule("PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift", contains: [
            "allowOpenRecipientChat: false, completed: { [weak self] in guard let self, let navigationController = self.controller?.navigationController as? NavigationController else { return } self.context.sharedContext.navigateToChatController("
        ])
        let resolvedUrl = try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Sources/OpenResolvedUrl.swift"), encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        XCTAssertTrue(resolvedUrl.contains("case let .peer(peer, resolvedAddress): controller = WalletSendScreen( context: context, peer: peer, walletContext: walletContext, resolvedAddress: resolvedAddress, initialAmountNanograms: transfer.amountNanograms, completed: { [weak navigationController] in guard let navigationController else { return } context.sharedContext.navigateToChatController("))
        try assertSubmodule("Wallet/WalletScreen/Sources/WalletScreen.swift", contains: [
            "initialAddress: address, refreshBalanceOnOpen: false, completed: { [weak controller] in guard let navigationController = controller?.navigationController as? NavigationController else { return } component.context.sharedContext.navigateToChatController("
        ])
    }

    func testOnlyCollectibleTransfersShowASuccessToast() throws {
        let sendScreen = try submoduleSource("Wallet/WalletSendScreen/Sources/WalletSendScreen.swift")
        XCTAssertFalse(sendScreen.contains("Wallet_Transfer_Success("))
        XCTAssertFalse(sendScreen.contains("displaySuccessToast"))
        let transactionScreen = try submoduleSource("Wallet/WalletTransactionScreen/Sources/WalletTransactionScreen.swift")
        XCTAssertFalse(transactionScreen.contains("Wallet_Transfer_Success("))
        XCTAssertTrue(transactionScreen.contains("if pendingTransfer.collectibleAddress != nil { self.showCollectibleSuccessIfNeeded(address: pendingTransfer.recipient) }"))
        XCTAssertNil(walletTransferSuccessText(isCollectible: false, recipient: "Alice"))
        XCTAssertEqual(walletTransferSuccessText(isCollectible: true, recipient: "Alice"), "The collectible has been sent to Alice.")
    }

    func testPreviewFliesBackOnlyForAListedTransferLikeSubmodule() throws {
        try assertSubmodule("Wallet/WalletTransactionScreen/Sources/WalletTransactionScreen.swift", contains: [
            "let presentationId = \"pending:\\(id)\" guard walletContext.stateValue.transactions.items.contains(where: { $0.presentationId == presentationId && $0.status != .failed }) else { return } self.isReturningToWallet = true",
            "self.returnToWalletWithPendingTransfer(id: pendingTransfer.id) if self.isReturningToWallet { return } self.dismissSendScreenIfNeeded() self.previewOperation = .confirmed",
            "if !transferAnimation(presentationId, source) {"
        ])
        let url = repositoryRoot().appendingPathComponent("packages/WalletUI/Sources/WalletUI/WalletTransactionController.swift")
        let actual = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        XCTAssertTrue(actual.contains("returnedToWallet = true returnToWalletDisposable.set(nil) let presentationId = \"pending:\\(preparedTransfer.id)\" guard walletContext.stateValue.transactions.items.contains(where: { $0.presentationId == presentationId && $0.status != .failed }) else { updateState { current in var current = current current.previewOperation = .confirmed return current } close?() return }"), "a transfer missing from the list ends in the confirmed state instead of flying")
        XCTAssertTrue(actual.contains("if !transferAnimation(presentationId, source) { source?.diamond.isRenderingEnabled = false source?.diamond.removeFromSuperview() } close?() }"), "the flight closes the preview without marking it confirmed")
        XCTAssertTrue(actual.contains("return state.pendingTransfers.contains(where: { $0.id == preparedTransfer.id }) && state.transactions.items.contains(where: { $0.presentationId == \"pending:\\(preparedTransfer.id)\" && $0.status != .failed })"), "the preview waits for the listed pending row before flying back")
    }

    func testSendFormHandOffTimingMatchesSubmodule() throws {
        try assertSubmodule("Wallet/WalletSendScreen/Sources/WalletSendScreen.swift", contains: [
            "DispatchQueue.main.asyncAfter(deadline: .now() + (switchedFromFiat ? 0.54 : 0.0)) {",
            "(self.amountField as? WalletSendAnimatedAmountField)?.spinForTransfer() DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: launch)",
            "self.requestUpdate(transition: .easeInOut(duration: 0.25))",
            "let presentationId = \"pending:\\(transferId)\"",
            "$0.presentationId == presentationId && $0.status != .failed",
            "let animate = self.commentSessionAvailable && UIApplication.shared.applicationState != .background && !UIAccessibility.isReduceMotionEnabled let source = animate ? (self.amountField as? WalletSendAnimatedAmountField)?.takeTransferDiamond(spinStartedAt: spinStartedAt) : nil",
            "displaysProgress: self.isResolvingSigningAccess || self.isPreparingTransfer || self.isSubmittingTransfer,"
        ])
        XCTAssertEqual(walletSendTransferFiatSwitchDelay, 0.54)
        XCTAssertEqual(walletSendTransferSpinLead, 0.18)
        try assertSubmodule("Wallet/WalletSendScreen/Sources/WalletSendAnimatedAmountField.swift", contains: [
            "guard !self.hasTransferredDiamond, self.isApplicationInForeground, let diamond = self.gramIcon.view as? InteractiveDiamondComponent.View, diamond.window != nil else { return }",
            "diamond.spin(-10.0, decay: 0.9)",
            "func takeTransferDiamond(spinStartedAt: CFTimeInterval?) -> WalletSendTransferAnimationSource? {",
            "let source = WalletSendTransferAnimationSource.capture(diamond: diamond, width: 34.0, spinStartedAt: spinStartedAt) else { return nil }",
            "guard !self.hasTransferredDiamond, self.mode == .gram,"
        ])
        try assertSubmodule("Wallet/WalletTransactionScreen/Sources/WalletTransactionScreen.swift", contains: [
            "source = WalletSendTransferAnimationSource.capture(diamond: diamond, width: 78.0, spinStartedAt: CACurrentMediaTime())",
            "source.diamond.spin(-10.0, decay: 0.9)",
            "if self.previewOperation == .submitting, let preparedTransfer = self.preparedTransfer, state.pendingTransfers.contains(where: { $0.id == preparedTransfer.id }) { self.returnToWalletWithPendingTransfer(id: preparedTransfer.id) }",
            "guard !self.isReturningToWallet, let animationView = self.gramAnimation.view as? InteractiveDiamondComponent.View, !animationView.isPlaying else {"
        ])
        XCTAssertEqual(walletSendTransferSpin.velocity, -10.0)
        XCTAssertEqual(walletSendTransferSpin.decay, 0.9)
    }

    func testDiamondHandOverMatchesSubmodule() throws {
        let view = InteractiveDiamondView(frame: NSRect(x: 10.0, y: 20.0, width: 96.0, height: 96.0))
        view.update(size: NSSize(width: 96.0, height: 96.0), diamondWidth: 34.0, isVisible: true, lightBackground: true)
        view.diamondLayer.isInHierarchy = true
        defer { view.diamondLayer.isInHierarchy = false }
        view.onExpansionChanged = { _ in }
        view.onLanding = { _ in }
        view.onMotionUpdated = { _ in }
        view.prepareForWalletTransfer()
        XCTAssertEqual(view.frame, NSRect(x: 10.0 + 48.0 - 75.0, y: 20.0 + 48.0 - 75.0, width: 150.0, height: 150.0))
        XCTAssertFalse(view.isInteractionEnabled)
        XCTAssertNil(view.onExpansionChanged)
        XCTAssertNil(view.onLanding)
        XCTAssertNil(view.onMotionUpdated)
        XCTAssertTrue(view.diamondLayer.usesHighFrameRate)
        XCTAssertEqual(view.diamondLayer.interactionScale, 1.0)
        XCTAssertEqual(view.diamondLayer.refractionStrength, 0.0)
        XCTAssertEqual(view.diamondLayer.renderSize, CGSize(width: 150.0, height: 150.0))
        XCTAssertEqual(view.diamondLayer.position, CGPoint(x: 75.0, y: 75.0))

        view.updateWalletTransfer(width: 40.0, rotationSpeed: 2.0 * .pi / 26.0, completion: false, isDark: true)
        var style = view.diamondLayer.diamondStyle
        XCTAssertEqual(style.animationMode, .continuous)
        XCTAssertEqual(style.appearance, .blue)
        XCTAssertEqual(style.widthPoints, 40.0)
        XCTAssertEqual(style.rotationSpeed, Float(2.0 * .pi / 26.0))
        XCTAssertEqual(style.swayScale, 2.4)
        XCTAssertEqual(style.floatAmplitude, 0.0)
        XCTAssertFalse(style.backgroundStars)
        XCTAssertFalse(style.steadyStars)
        XCTAssertEqual(style.starZoom, 0.55)
        XCTAssertEqual(style.starEmission, 0.3)
        XCTAssertEqual(style.burstSize, 0.7)
        XCTAssertEqual(style.burstFadeInDuration, 0.0)
        XCTAssertFalse(view.diamondLayer.lightBackground)
        XCTAssertEqual(view.diamondLayer.renderSize, CGSize(width: 150.0, height: 150.0))

        view.updateWalletTransfer(width: 34.0, rotationSpeed: 6.5, completion: true, isDark: false)
        style = view.diamondLayer.diamondStyle
        XCTAssertTrue(style.backgroundStars)
        XCTAssertTrue(view.diamondLayer.lightBackground)
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns the star burst off")
        let bursts: [DiamondStarBurst] = mirroredValue(view.diamondLayer, "starBursts") ?? []
        XCTAssertEqual(bursts.count, 1)
        view.updateWalletTransfer(width: 30.0, rotationSpeed: 6.5, completion: true, isDark: false)
        let burstsAfter: [DiamondStarBurst] = mirroredValue(view.diamondLayer, "starBursts") ?? []
        XCTAssertEqual(burstsAfter.count, 1)
    }

    func testHandedOverDiamondKeepsSpinningAcrossTheModeChange() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion turns spin off")
        let view = InteractiveDiamondView(frame: NSRect(x: 0.0, y: 0.0, width: 118.0, height: 118.0))
        view.update(size: NSSize(width: 118.0, height: 118.0), diamondWidth: 78.0, isVisible: true, lightBackground: true, animationMode: .lottie(loop: false), animateOnAppear: true)
        view.diamondLayer.isInHierarchy = true
        defer { view.diamondLayer.isInHierarchy = false }
        view.spin(-10.0, decay: 0.9)
        let before: Float = mirroredValue(mirroredValue(view.diamondLayer, "motion")! as DiamondMotion, "spinVelocity")!
        XCTAssertNotEqual(before, 0.0)
        view.prepareForWalletTransfer()
        view.updateWalletTransfer(width: 78.0, rotationSpeed: 2.0 * .pi / 26.0, completion: false, isDark: false)
        XCTAssertEqual(view.diamondLayer.diamondStyle.animationMode, .continuous)
        let after: Float = mirroredValue(mirroredValue(view.diamondLayer, "motion")! as DiamondMotion, "spinVelocity")!
        XCTAssertEqual(after, before, accuracy: abs(before) * 0.05)

        var style = view.diamondLayer.diamondStyle
        style.animationMode = .entrance
        view.diamondLayer.update(style: style)
        let reset: Float = mirroredValue(mirroredValue(view.diamondLayer, "motion")! as DiamondMotion, "spinVelocity")!
        XCTAssertEqual(reset, 0.0)
    }
}
