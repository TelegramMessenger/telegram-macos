import Foundation
import XCTest

struct PeerId { let secret: Bool }
__POLICY__
extension AnalyticsPrivacy {
    init(peerId: PeerId) { self = peerId.secret ? .excluded : .ordinary }
}
__CONTEXT__
final class Analytics {
    static let shared = Analytics()
    let policy = AnalyticsCollectionPolicy()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(analytics: self, privacy: .unresolved, scope: nil) }
__CAPTURE__
}
final class SubmissionState {
    enum Stage { case ready, submitting }
    var stage: Stage? = .submitting
    let context: AnalyticsContext
    let scope: AnalyticsScope?
    init(_ context: AnalyticsContext) { self.context = context; scope = context.scope }
__SUBMISSION_CONTEXT__
}
final class SubmissionContextTests: XCTestCase {
    let owner = NSObject()
    func hub() -> Analytics {
        let analytics = Analytics()
        analytics.policy.setOwner(owner)
        analytics.policy.isEnabled = true
        return analytics
    }
    func testOnlyLiveSubmissionExposesItsExactOriginalContext() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let state = SubmissionState(origin)
        XCTAssertTrue(state.submissionContext === origin)
        XCTAssertTrue(state.submissionContext === origin)
        state.stage = .ready
        XCTAssertTrue(state.submissionContext.isExcluded)
        XCTAssertNil(state.submissionContext.scope)
        state.stage = nil
        XCTAssertTrue(state.submissionContext.isExcluded)
        XCTAssertTrue(state.submissionContext.policy === origin.policy)
    }
    func testEndedSubmissionCannotGrantFreshContextToLaterBatch() {
        let analytics = hub()
        let state = SubmissionState(analytics.captureContext(owner: owner, privacy: .ordinary))
        state.stage = nil
        let later = analytics.captureContext(owner: owner, privacy: .ordinary, inherited: state.submissionContext)
        XCTAssertTrue(later.isExcluded)
        XCTAssertNil(later.scope)
        XCTAssertTrue(state.scope?.isValid == true)
    }
    func testDisableAccountChangeAndSecretEntryInvalidateEvenSubmittingState() {
        for change in 0..<3 {
            let analytics = hub()
            let state = SubmissionState(analytics.captureContext(owner: owner, privacy: .ordinary))
            switch change {
            case 0:
                analytics.policy.isEnabled = false
                analytics.policy.isEnabled = true
            case 1:
                analytics.policy.setOwner(NSObject())
                analytics.policy.setOwner(owner)
            default:
                let surface = ObjectIdentifier(NSObject())
                analytics.policy.setExcluded(true, owner: surface)
                analytics.policy.setExcluded(false, owner: surface)
            }
            XCTAssertTrue(state.submissionContext.isExcluded)
            XCTAssertNil(state.submissionContext.scope)
            XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary, inherited: state.submissionContext).scope)
        }
    }
    func testUnresolvedAndForeignOwnerContextsDoNotYieldSubmissionGrant() {
        let analytics = hub()
        for origin in [analytics.unresolvedContext(), analytics.captureContext(owner: NSObject(), privacy: .ordinary), analytics.captureContext(owner: owner, privacy: .excluded)] {
            let state = SubmissionState(origin)
            XCTAssertTrue(state.submissionContext.isExcluded)
            XCTAssertNil(state.submissionContext.scope)
        }
    }
    func testReleasedAnalyticsOwnerDoesNotRestoreAnEndedSubmission() {
        var analytics: Analytics? = hub()
        let state = SubmissionState(analytics!.captureContext(owner: owner, privacy: .ordinary))
        state.stage = nil
        weak var released = analytics
        analytics = nil
        XCTAssertNil(released)
        XCTAssertTrue(state.submissionContext.isExcluded)
        XCTAssertNil(state.submissionContext.scope)
    }
}
