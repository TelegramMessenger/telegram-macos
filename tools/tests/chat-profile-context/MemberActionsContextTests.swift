struct ChannelParticipant { let peerId: PeerId }
struct RenderedChannelParticipant { let peer: Peer; let participant: ChannelParticipant }
struct TelegramChatAdminRights {}
struct TelegramChatBannedRights {
    enum Flag { case banReadMessages }
    let flags: [Flag]
    let untilDate: Int32
}
extension Peer {
    func _asPeer() -> Peer { self }
    var compactDisplayTitle: String { "member" }
}
extension CommonStrings {
    func peerInfoConfirmRemovePeer(_ name: String) -> String { name }
    var modalRemove: String { "remove" }
    var channelParticipantTagUpdateError: String { "error" }
    var channelParticipantTagUpdated: String { "updated" }
}
typealias ModalViewController = MemberModal
final class MemberModal: ViewController {
    let content: ViewController
    var updated: ((TelegramChatBannedRights) -> Void)?
    var adminUpdated: ((TelegramChatAdminRights?) -> Void)?
    var upgraded: ((PeerId, @escaping () -> Void) -> Void)?
    init(_ content: ViewController) { self.content = content; super.init() }
}
func RestrictedModalController(_ context: any AccountContextProtocol, peerId: PeerId, memberId: PeerId, initialParticipant: ChannelParticipant?, updated: @escaping (TelegramChatBannedRights) -> Void, analyticsContext: AnalyticsContext? = nil) -> MemberModal {
__RESTRICT_PREFIX__
    MemberProbe.check?()
    let controller = ViewController()
__RESTRICT_CONTROLLER__
    let modalController = MemberModal(controller)
__RESTRICT_MODALCONTROLLER__
    modalController.updated = updated
    return modalController
}
func ChannelAdminModalController<C: AccountContextProtocol>(_ context: C, peerId: PeerId, adminId: PeerId, initialParticipant: ChannelParticipant?, updated: @escaping (TelegramChatAdminRights?) -> Void, upgradedToSupergroup: @escaping (PeerId, @escaping () -> Void) -> Void, analyticsContext: AnalyticsContext? = nil) -> MemberModal {
__ADMIN_PREFIX__
    MemberProbe.check?()
    let controller = ViewController()
__ADMIN_CONTROLLER__
    let modalController = MemberModal(controller)
__ADMIN_MODALCONTROLLER__
    modalController.adminUpdated = updated
    modalController.upgraded = upgradedToSupergroup
    return modalController
}
struct FeatureNavigationHooks {
    static var shared = FeatureNavigationHooks()
__ADMIN_HOOK__
}
func installMemberBridge() {
    var hooks = FeatureNavigationHooks()
__ADMIN_BRIDGE__
    FeatureNavigationHooks.shared = hooks
}
__MEMBER_ARGUMENTS__
struct MemberState { var tag = ""; let initialTag = "" }
enum MemberValidation { enum Reason { case none }; case fail(Reason) }
final class MemberHarness: ViewController {
    var actions: MemberArguments!
    var validateData: (Int) -> MemberValidation = { _ in .fail(.none) }
    let disposables: DisposableSet
    init(_ disposables: DisposableSet) { self.disposables = disposables; super.init() }
    deinit { disposables.dispose() }
}
func makeMember(context: AccountContext, peerId: PeerId = 2, participant: RenderedChannelParticipant = RenderedChannelParticipant(peer: Peer(3), participant: ChannelParticipant(peerId: 3)), analyticsContext: AnalyticsContext? = nil) -> MemberHarness {
__MEMBER_PREFIX__
    MemberProbe.check?()
    let actionsDisposable = DisposableSet()
    let stateValue = Atomic(value: MemberState())
    let updateState: ((MemberState) -> MemberState) -> Void = { f in _ = stateValue.modify(f) }
    let close: (() -> Void)? = { MemberProbe.check?(); MemberProbe.closes += 1 }
__MEMBER_ACTIONS__
    let controller = MemberHarness(actionsDisposable)
    controller.actions = arguments
__MEMBER_CONTEXT__
__MEMBER_VALIDATE__
    return controller
}
final class MemberManager {
    func updateMemberBannedRights(peerId: PeerId, memberId: PeerId, bannedRights: TelegramChatBannedRights?) -> Signal<Void, NoError> {
        MemberProbe.check?(); MemberProbe.removals.append((peerId, memberId, bannedRights?.untilDate ?? -1))
        return Signal { sink in
            MemberProbe.check?(); MemberProbe.rightsSink = sink
            return ActionDisposable { MemberProbe.check?(); MemberProbe.disposals += 1 }
        }
    }
    func updateChatRank(peerId: PeerId, memberId: PeerId, rank: String?, participant: RenderedChannelParticipant) -> Signal<Never, MemberFailure> {
        MemberProbe.check?(); MemberProbe.ranks.append(rank)
        return Signal { sink in
            MemberProbe.check?(); MemberProbe.rankSink = sink
            return ActionDisposable { MemberProbe.check?(); MemberProbe.disposals += 1 }
        }
    }
}
enum MemberFailure: Error { case failed }
extension AccountContextProtocol { var peerChannelMemberCategoriesContextsManager: MemberManager { MemberProbe.manager } }
func showModal(with controller: MemberModal, for window: Int, morphSource: (() -> NSView?)? = nil) { MemberProbe.check?(); MemberProbe.modal = controller; TagProbe.morph = morphSource }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Int) -> Signal<T, E> { MemberProbe.check?(); return signal }
func showModalText(for window: Int, text: String) { MemberProbe.check?(); MemberProbe.feedback.append(text) }
func verifyAlert_button(for window: Int, information: String, ok: String, successHandler: @escaping (Int) -> Void, onDeinit: @escaping () -> Void) {
    MemberProbe.check?(); MemberProbe.confirm = successHandler; MemberProbe.dismiss = onDeinit
}
enum MemberProbe {
    static let manager = MemberManager()
    static var check: (() -> Void)?
    static var modal: MemberModal?
    static var confirm: ((Int) -> Void)?
    static var dismiss: (() -> Void)?
    static var rightsSink: Subscriber<Void, NoError>?
    static var rankSink: Subscriber<Never, MemberFailure>?
    static var removals: [(PeerId, PeerId, Int32)] = []
    static var ranks: [String?] = []
    static var feedback: [String] = []
    static var closes = 0
    static var disposals = 0
    static func reset() {
        check = nil; modal = nil; confirm = nil; dismiss = nil; rightsSink = nil; rankSink = nil
        removals = []; ranks = []; feedback = []; closes = 0; disposals = 0
    }
}
final class MemberActionsContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    let selected = ChannelParticipant(peerId: 3)
    override func setUp() {
        MemberProbe.reset(); Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true; installMemberBridge()
    }
    override func tearDown() { MemberProbe.reset(); context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func expectExcluded() { MemberProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testOrdinaryPromotionKeepsExactScopeOnModalAndContent() {
        let source = origin(); let member = makeMember(context: context, analyticsContext: source)
        member.actions.promote(selected)
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.scope === source.scope)
        XCTAssertTrue(MemberProbe.modal?.content.analyticsContext?.scope === source.scope)
        XCTAssertEqual(MemberProbe.closes, 1)
    }
    func testPrivatePromotionAfterParentReleaseProtectsClosingAndConstruction() {
        var member: MemberHarness? = makeMember(context: context, analyticsContext: origin(.excluded))
        let promote = member!.actions.promote; member = nil
        expectExcluded(); promote(selected)
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testBothRestrictionEntriesCarryScopeAndReturnRights() {
        let source = origin(); let member = makeMember(context: context, analyticsContext: source)
        for action in [member.actions.restrict, member.actions.openPermissions] {
            action(selected)
            XCTAssertTrue(MemberProbe.modal?.analyticsContext?.scope === source.scope)
            XCTAssertTrue(MemberProbe.modal?.content.analyticsContext?.scope === source.scope)
            MemberProbe.modal?.updated?(TelegramChatBannedRights(flags: [], untilDate: 9))
            MemberProbe.rightsSink?.putCompletion()
        }
        XCTAssertEqual(MemberProbe.removals.map { $0.2 }, [9, 9])
    }
    func testPrivateRightsCallbackSurvivesBothOwnersAndGuardsProviderDisposal() {
        var member: MemberHarness? = makeMember(context: context, analyticsContext: origin(.excluded))
        member!.actions.restrict(selected)
        let updated = MemberProbe.modal!.updated!; member = nil; MemberProbe.modal = nil
        expectExcluded(); updated(TelegramChatBannedRights(flags: [], untilDate: 9))
        XCTAssertTrue(hub.policy.hasExclusions)
        MemberProbe.rightsSink?.putCompletion()
        XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertEqual(MemberProbe.disposals, 1)
    }
    func testRemovalConfirmationRetainsPrivacyUntilDismissalAndDuringLateDelivery() {
        var member: MemberHarness? = makeMember(context: context, analyticsContext: origin(.excluded))
        expectExcluded(); member!.actions.remove(selected)
        let confirm = MemberProbe.confirm!; member = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        MemberProbe.dismiss?(); MemberProbe.dismiss = nil
        XCTAssertFalse(hub.policy.hasExclusions)
        confirm(0)
        XCTAssertEqual(MemberProbe.removals.count, 1)
        XCTAssertEqual(MemberProbe.removals.first?.2, 0)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRemovalCancellationDoesNotCallProviderAndReleasesPrivacy() {
        let member = makeMember(context: context, analyticsContext: origin(.excluded))
        member.actions.remove(selected)
        XCTAssertTrue(hub.policy.hasExclusions); MemberProbe.dismiss?()
        XCTAssertFalse(hub.policy.hasExclusions); XCTAssertTrue(MemberProbe.removals.isEmpty)
    }
    func testPrivateTagSaveProtectsProgressAndSuccessFeedback() {
        let member = makeMember(context: context, analyticsContext: origin(.excluded))
        member.actions.updateTag("  label  "); expectExcluded(); _ = member.validateData(0)
        XCTAssertEqual(MemberProbe.ranks, ["label"])
        MemberProbe.rankSink?.putCompletion()
        XCTAssertEqual(MemberProbe.feedback, ["updated"])
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testTagFailureRetainsOriginalContextAndDoesNotClose() {
        let member = makeMember(context: context, analyticsContext: origin(.excluded))
        member.actions.updateTag("label"); expectExcluded(); _ = member.validateData(0)
        MemberProbe.rankSink?.putError(.failed)
        XCTAssertEqual(MemberProbe.feedback, ["error"]); XCTAssertEqual(MemberProbe.closes, 0)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testUnchangedTagSkipsProvider() {
        let member = makeMember(context: context, analyticsContext: origin(.excluded))
        expectExcluded(); _ = member.validateData(0)
        XCTAssertTrue(MemberProbe.ranks.isEmpty); XCTAssertEqual(MemberProbe.closes, 1)
    }
    func testSecretSelectedMemberRestrictsOrdinarySourceBeforeClosing() {
        let member = makeMember(context: context, analyticsContext: origin())
        expectExcluded(); member.actions.promote(ChannelParticipant(peerId: -4))
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testPrivateRepresentedMemberRejectsOrdinaryAdmission() {
        expectExcluded()
        let member = makeMember(context: context, participant: RenderedChannelParticipant(peer: Peer(3), participant: ChannelParticipant(peerId: -4)), analyticsContext: origin())
        member.actions.promote(selected)
        XCTAssertTrue(member.analyticsContext?.isExcluded == true)
    }
    func testLegacyAndDisabledEntriesRemainFunctional() {
        for disabled in [false, true] {
            hub.policy.isEnabled = !disabled; expectExcluded()
            let member = makeMember(context: context)
            member.actions.promote(selected)
            XCTAssertNotNil(MemberProbe.modal); XCTAssertNil(MemberProbe.modal?.analyticsContext?.scope)
        }
    }
    func testAccountSwitchAndRevocationCannotRenewAtChildOpening() {
        for switchAccount in [false, true] {
            MemberProbe.check = nil
            hub.policy.setOwner(context.account); hub.policy.isEnabled = true
            let member = makeMember(context: context, analyticsContext: origin())
            let other = AccountContext()
            if switchAccount { hub.policy.setOwner(other.account) } else { hub.policy.isEnabled = false; hub.policy.isEnabled = true }
            expectExcluded(); member.actions.promote(selected)
            XCTAssertNil(MemberProbe.modal?.analyticsContext?.scope)
        }
    }
    func testLegacyAdminHookFallbackDoesNotGrantFreshScope() {
        FeatureNavigationHooks.shared.makeChannelAdminControllerWithContext = nil
        let member = makeMember(context: context, analyticsContext: origin(.excluded))
        expectExcluded(); member.actions.promote(selected)
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testAdminUpgradeReturnRetainsPrivateDestinationContext() {
        var complete: (() -> Void)?
        var delivered = false
        let modal = ChannelAdminModalController(context, peerId: 2, adminId: 3, initialParticipant: selected, updated: { _ in }, upgradedToSupergroup: { _, callback in
            XCTAssertTrue(self.hub.policy.hasExclusions); complete = callback
        }, analyticsContext: origin())
        modal.upgraded?(-5) { XCTAssertTrue(self.hub.policy.hasExclusions); delivered = true }
        XCTAssertFalse(hub.policy.hasExclusions); complete?(); XCTAssertTrue(delivered)
    }
    func testAdminFactoryClassifiesGroupTargetAndRepresentedMember() {
        for (group, target, represented): (PeerId, PeerId, PeerId) in [(-2, 3, 3), (2, -3, 3), (2, 3, -4)] {
            MemberProbe.check = nil
            let source = origin(); expectExcluded()
            let modal = ChannelAdminModalController(context, peerId: group, adminId: target, initialParticipant: ChannelParticipant(peerId: represented), updated: { _ in }, upgradedToSupergroup: { _, _ in }, analyticsContext: source)
            XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
            XCTAssertTrue(modal.content.analyticsContext?.isExcluded == true)
        }
    }
    func testRestrictionFactoryClassifiesGroupTargetAndRepresentedMember() {
        for (group, target, represented): (PeerId, PeerId, PeerId) in [(-2, 3, 3), (2, -3, 3), (2, 3, -4)] {
            MemberProbe.check = nil
            let source = origin(); expectExcluded()
            var delivered = false
            let modal = RestrictedModalController(context, peerId: group, memberId: target, initialParticipant: ChannelParticipant(peerId: represented), updated: { _ in
                XCTAssertTrue(self.hub.policy.hasExclusions); delivered = true
            }, analyticsContext: source)
            XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
            XCTAssertTrue(modal.content.analyticsContext?.isExcluded == true)
            modal.updated?(TelegramChatBannedRights(flags: [], untilDate: 0))
            XCTAssertTrue(delivered)
        }
    }
    func testPrivacyTighteningDuringTagSaveProtectsLateFeedback() {
        let source = origin(); let member = makeMember(context: context, analyticsContext: source)
        member.actions.updateTag("label"); _ = member.validateData(0)
        XCTAssertFalse(hub.policy.hasExclusions)
        source.scope?.exclude(); XCTAssertTrue(hub.policy.hasExclusions)
        expectExcluded(); MemberProbe.rankSink?.putError(.failed)
        XCTAssertEqual(MemberProbe.feedback, ["error"])
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testAdminUpdatedReturnRetainsPrivateOrigin() {
        var delivered = false
        let modal = ChannelAdminModalController(context, peerId: 2, adminId: 3, initialParticipant: selected, updated: { _ in
            XCTAssertTrue(self.hub.policy.hasExclusions); delivered = true
        }, upgradedToSupergroup: { _, _ in }, analyticsContext: origin(.excluded))
        modal.adminUpdated?(nil); XCTAssertTrue(delivered); XCTAssertFalse(hub.policy.hasExclusions)
    }
}
