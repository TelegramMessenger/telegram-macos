import XCTest
import TelegramCore
import InAppSettings
@testable import TelegramCallsCore

final class CallToneTests: XCTestCase {
    private func tone(_ state: CallState.State, previous: CallSessionState?, reconnecting: Bool = false, hasCallContext: Bool = true, isOutgoing: Bool = false) -> CallTone? {
        return callTone(for: state, isReconnecting: reconnecting, previous: previous, hasCallContext: hasCallContext, isOutgoing: isOutgoing)
    }

    func testIncomingRingingStartsRingtone() {
        XCTAssertEqual(tone(.ringing, previous: nil, hasCallContext: false), .ringing)
    }

    func testOutgoingFirstStateStartsRingback() {
        XCTAssertEqual(tone(.waiting, previous: nil, hasCallContext: false, isOutgoing: true), .ringback)
    }

    func testRepublishingRingingKeepsRingtone() {
        XCTAssertEqual(tone(.ringing, previous: .ringing, hasCallContext: false), .ringing)
    }

    func testAcceptingStopsRingtone() {
        XCTAssertNil(tone(.connecting(nil), previous: .ringing))
    }

    func testDecliningIncomingIsSilent() {
        XCTAssertNil(tone(.terminated(nil, .ended(.hungUp), false), previous: .ringing))
        XCTAssertNil(tone(.terminating(.ended(.hungUp)), previous: .ringing))
    }

    func testOutgoingRingbackWhilePeerRings() {
        XCTAssertEqual(tone(.requesting(true), previous: .requesting(ringing: false)), .ringback)
        XCTAssertEqual(tone(.requesting(true), previous: .requesting(ringing: true)), .ringback)
        XCTAssertNil(tone(.requesting(false), previous: .requesting(ringing: false)))
    }

    func testConnectingAfterRequestKeepsRingback() {
        XCTAssertEqual(tone(.connecting(nil), previous: .requesting(ringing: true)), .ringback)
        XCTAssertEqual(tone(.connecting(nil), previous: .accepting), .connecting)
    }

    func testEndTones() {
        XCTAssertEqual(tone(.terminated(nil, .ended(.busy), false), previous: .requesting(ringing: true)), .busy)
        XCTAssertEqual(tone(.terminated(nil, .ended(.hungUp), false), previous: .accepting), .ended)
        XCTAssertEqual(tone(.terminated(nil, .ended(.missed), false), previous: .requesting(ringing: true)), .ended)
        XCTAssertEqual(tone(.terminated(nil, .error(.generic), false), previous: .accepting), .failed)
        XCTAssertEqual(tone(.terminated(nil, .error(.disconnected), false), previous: .dropping(reason: .error(.disconnected))), .failed)
        XCTAssertNil(tone(.terminated(nil, .ended(.switchedToConference(slug: "x")), false), previous: .accepting))
        XCTAssertNil(tone(.terminated(nil, nil, false), previous: .accepting))
    }

    func testReconnectingAlwaysPlaysConnecting() {
        XCTAssertEqual(tone(.reconnecting(0, nil, Data()), previous: .accepting, reconnecting: true), .connecting)
        XCTAssertEqual(tone(.ringing, previous: .ringing, reconnecting: true), .connecting)
        XCTAssertEqual(tone(.ringing, previous: nil, reconnecting: true), .connecting)
    }

    func testActiveCallIsSilent() {
        XCTAssertNil(tone(.active(0, 4, Data()), previous: .accepting))
        XCTAssertNil(tone(.ringing, previous: nil, hasCallContext: true))
    }

    func testSwitchedToConferenceIsSilent() {
        XCTAssertNil(tone(.terminated(nil, .ended(.switchedToConference(slug: "x")), false), previous: .switchedToConference(slug: "x")))
    }

    func testIncomingRingtoneMutesUntilOneMinuteIdle() {
        XCTAssertTrue(shouldMuteIncomingCallRingtone(isOutgoing: false, muteMode: .whileUsingMac, systemIdleTime: 0))
        XCTAssertTrue(shouldMuteIncomingCallRingtone(isOutgoing: false, muteMode: .whileUsingMac, systemIdleTime: 59.999))
        XCTAssertFalse(shouldMuteIncomingCallRingtone(isOutgoing: false, muteMode: .whileUsingMac, systemIdleTime: 60))
    }

    func testDisabledSettingDoesNotMuteActiveMac() {
        XCTAssertFalse(shouldMuteIncomingCallRingtone(isOutgoing: false, muteMode: .off, systemIdleTime: 0))
    }

    func testOutgoingCallDoesNotMuteActiveMac() {
        for mode in IncomingCallMuteMode.allCases {
            XCTAssertFalse(shouldMuteIncomingCallRingtone(isOutgoing: true, muteMode: mode, systemIdleTime: 0))
        }
    }

    func testUnavailableIdleTimeDoesNotMuteRingtone() {
        for idleTime: TimeInterval in [-1, .infinity, .nan] {
            XCTAssertFalse(shouldMuteIncomingCallRingtone(isOutgoing: false, muteMode: .whileUsingMac, systemIdleTime: idleTime))
        }
    }

    func testAlwaysMutesIncomingRegardlessOfActivity() {
        for idleTime: TimeInterval in [0, 60, 3600, -1, .infinity, .nan] {
            XCTAssertTrue(shouldMuteIncomingCallRingtone(isOutgoing: false, muteMode: .always, systemIdleTime: idleTime))
        }
    }
}
