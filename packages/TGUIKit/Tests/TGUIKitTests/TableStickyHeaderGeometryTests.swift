import Foundation
import XCTest
@testable import TGUIKit

final class TableStickyHeaderGeometryTests: XCTestCase {
    private func header(_ id: Int, _ start: CGFloat, _ end: CGFloat, height: CGFloat = 30, inset: CGFloat = 10) -> TableStickyHeaderLayout {
        return TableStickyHeaderLayout(id: id, naturalY: start, sectionEnd: end, height: height, inset: inset)
    }

    func testDateIsAbovePinnedTopic() {
        let date = header(0, -200, 500)
        var topic = header(1, -100, 400, height: 28)
        topic.yield(to: [date])
        XCTAssertEqual(date.y, 10)
        XCTAssertEqual(topic.y, 40)
    }

    func testIncomingTopicPushesOutgoingTopicWithoutCrossingItsSection() {
        let date = header(0, -200, 500)
        for boundary in stride(from: CGFloat(90), through: -30, by: -0.25) {
            var outgoing = header(1, -100, boundary, height: 28)
            var incoming = header(2, boundary, 400, height: 28)
            outgoing.yield(to: [date])
            incoming.yield(to: [date])
            XCTAssertLessThanOrEqual(outgoing.y + outgoing.height, incoming.y)
            XCTAssertLessThanOrEqual(outgoing.y + outgoing.height, boundary)
        }
    }

    func testDateBoundaryPushesOutgoingDateAndTopicYieldsToIncomingDate() {
        var previousTopicY: CGFloat?
        var previousPartner: AnyHashable?
        var handoffs = 0
        for boundary in stride(from: CGFloat(100), through: -40, by: -0.125) {
            let outgoing = header(0, -200, boundary)
            let incoming = header(1, boundary, 500)
            var topic = header(2, -100, 400, height: 28)
            topic.yield(to: [outgoing, incoming])
            XCTAssertLessThanOrEqual(outgoing.y + outgoing.height, incoming.y)
            for date in [outgoing, incoming] {
                XCTAssertFalse(topic.y < date.y + date.height && topic.y + topic.height > date.y)
            }
            if let previousTopicY, previousPartner == topic.offsetBy {
                XCTAssertLessThanOrEqual(abs(topic.y - previousTopicY), 0.125)
            } else if previousTopicY != nil {
                handoffs += 1
            }
            previousTopicY = topic.y
            previousPartner = topic.offsetBy
        }
        XCTAssertEqual(handoffs, 1)
    }

    func testTopicEndsAtDateThatLeadsNextTopic() {
        var previousTopicY: CGFloat?
        for offset in stride(from: CGFloat(0), through: 120, by: 0.25) {
            let outgoing = header(0, -200, 100 - offset)
            let incoming = header(1, 100 - offset, 500)
            var topic = header(2, -100, 130 - offset, height: 28)
            topic.end(beforeLeading: [outgoing, incoming])
            topic.yield(to: [outgoing, incoming])
            XCTAssertEqual(topic.sectionEnd, incoming.naturalY)
            XCTAssertLessThanOrEqual(topic.y + topic.height, incoming.naturalY)
            XCTAssertEqual(topic.offsetBy, AnyHashable(0))
            if let previousTopicY {
                XCTAssertLessThanOrEqual(abs(topic.y - previousTopicY), 0.25)
            }
            previousTopicY = topic.y
        }
    }

    func testTopicContinuingPastDateKeepsItsSection() {
        var topic = header(0, -100, 400, height: 28)
        topic.end(beforeLeading: [header(1, 200, 500)])
        XCTAssertEqual(topic.sectionEnd, 400)
    }

    func testFractionalScrollAndDirectionReversalAreContinuous() {
        func positions(_ offset: CGFloat) -> [CGFloat] {
            let date = header(0, 50 - offset, 500 - offset)
            var topic = header(1, 80 - offset, 450 - offset, height: 28)
            topic.yield(to: [date])
            return [date.y, topic.y]
        }
        let offsets = stride(from: CGFloat(0), through: 350, by: 0.25).map { $0 }
        let forward = offsets.map(positions)
        XCTAssertEqual(forward, offsets.reversed().map(positions).reversed())
        for index in 1 ..< forward.count {
            for pill in 0 ..< 2 {
                XCTAssertLessThanOrEqual(abs(forward[index][pill] - forward[index - 1][pill]), 0.25)
            }
        }
    }

    func testUnrelatedDateDoesNotMoveTopic() {
        var topic = header(0, -100, 500, height: 28)
        topic.yield(to: [header(1, 200, 600)])
        XCTAssertEqual(topic.y, 10)
    }

    func testStackingIsIndependentOfDateEnumerationOrder() {
        let dates = [header(0, -100, 20), header(1, 20, 500)]
        var first = header(2, -80, 400, height: 28)
        var second = first
        first.yield(to: dates)
        second.yield(to: dates.reversed())
        XCTAssertEqual(first.y, second.y)
    }

    func testShortSectionUsesFarEdgeLikeIOS() {
        let date = header(0, 20, 25)
        XCTAssertEqual(date.y, -5)
    }

    func testInsetChangesMoveBothPinnedPillsTogether() {
        for inset in [CGFloat(0), 10, 44, 120] {
            let date = header(0, -200, 500, inset: inset)
            var topic = header(1, -100, 500, height: 28, inset: inset)
            topic.yield(to: [date])
            XCTAssertEqual(date.y, inset)
            XCTAssertEqual(topic.y, inset + date.height)
        }
    }

    func testLayoutMatchesRotatedIOSHeaderSolve() {
        let viewportHeight: CGFloat = 800
        let height: CGFloat = 34
        let spacing: CGFloat = 27
        for inset in [CGFloat(0), 10, 90] {
            for offset in stride(from: CGFloat(-100), through: 600, by: 0.5) {
                let date = header(0, -200 - offset, 200 - offset, height: height, inset: inset)
                let nextDate = header(1, 200 - offset, 900 - offset, height: height, inset: inset)
                var topic = header(2, -100 - offset, 700 - offset, height: height, inset: inset)
                let upperBound = viewportHeight - topic.sectionEnd
                let lowerBound = viewportHeight - topic.naturalY
                let lowerDisplayBound = viewportHeight - inset
                var referenceY = max(upperBound, min(lowerBound, lowerDisplayBound) - height)
                var referencePartner: AnyHashable?
                let partners = [date, nextDate].map { layout in
                    (layout.id, CGRect(x: 0, y: viewportHeight - layout.y - height, width: 320, height: height))
                }
                for _ in 0 ..< 2 {
                    let frame = CGRect(x: 0, y: referenceY, width: 320, height: height)
                    var mostOverlap: (AnyHashable, CGRect)?
                    for partner in partners where frame.intersects(partner.1) && frame.intersection(partner.1).height > 0 {
                        if mostOverlap == nil || partner.1.minY < mostOverlap!.1.minY {
                            mostOverlap = partner
                        }
                    }
                    if let partner = mostOverlap {
                        referenceY = max(upperBound, min(referenceY, partner.1.minY - spacing))
                        referencePartner = partner.0
                    }
                }
                topic.yield(to: [date, nextDate], spacing: spacing)
                XCTAssertEqual(topic.y, viewportHeight - referenceY - height, accuracy: 0.0001)
                XCTAssertEqual(topic.offsetBy, referencePartner)
            }
        }
    }
}
