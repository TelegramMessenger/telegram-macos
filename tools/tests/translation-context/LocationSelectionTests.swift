struct CLLocationCoordinate2D: Equatable { let latitude: Double; let longitude: Double }
struct CLLocation: Equatable { let coordinate: CLLocationCoordinate2D }
struct MapVenue: Equatable { let title: String }
struct TelegramMediaMap: Equatable {
    let latitude: Double
    let longitude: Double
    let venue: MapVenue?
    init(latitude: Double, longitude: Double, heading: Int?, accuracyRadius: Int?, venue: MapVenue?, liveBroadcastingTimeout: Int?, liveProximityNotificationRadius: Int?) {
        self.latitude = latitude; self.longitude = longitude; self.venue = venue
    }
}
__LOCATION_STATES__
__LOCATION_PROTOCOL__
extension ChatInteraction: LocationChatInteraction {
    var locationContext: Context { interactionContext }
    var locationPeerId: PeerId { peerId }
    func sendPickedLocation(_ coordinate: CLLocationCoordinate2D, _ venue: MapVenue?) {
        Probe.check?(); LocationProbe.sent.append((coordinate, venue))
    }
}
__LOCATION_CONFIRM_HOOK__
enum ModalAnimationCloseBehaviour { case common }
enum AnalyticsScreen { case chatAttachLocation, appLocationPicker }
class LocationBase {
    var analyticsContext: AnalyticsContext?
    var analyticsScreen: AnalyticsScreen?
    init(frame: NSRect) { Probe.check?() }
    func close(animationType: ModalAnimationCloseBehaviour = .common) { Probe.check?(); LocationProbe.closes += 1 }
}
final class LocationSelectionHost: LocationBase {
    let chatInteraction: any LocationChatInteraction
    let destination: SelectLocationDestination
    let getAnalyticsContext: () -> AnalyticsContext
    let statePromise = Promise<LocationViewState>()
    let state = ValuePromise<LocationViewState>(.normal(.user(nil)), ignoreRepeated: true)
    let disposable = MetaDisposable()
    let sendDisposable = MetaDisposable()
    let requestDisposable = MetaDisposable()
    var isClosed = false
    var hasSelected = false
    var selectCallback: ((TelegramMediaMap) -> Void)?
__LOCATION_INIT__
__LOCATION_SEND__
__LOCATION_CLOSE__
__LOCATION_DEINIT__
    func start() { statePromise.set(state.get()) }
}
struct ChatNavigationHooks {
    static var shared = ChatNavigationHooks()
__LOCATION_HOOK__
}
func showModal(with controller: LocationSelectionHost, for window: Int) { Probe.check?(); LocationProbe.shown = controller; controller.start() }
func installLocationSelectorFixture() {
    var hooks = ChatNavigationHooks()
__LOCATION_BRIDGE__
    ChatNavigationHooks.shared = hooks
}
final class LocationCache { var media: [String: TelegramMediaMap] = [:] }
enum RichLocationPicker {
__LOCATION_PICKER__
}
enum LocationProbe {
    static var confirmationOrigin: AnalyticsContext?
    static var shown: LocationSelectionHost?
    static var confirmations: [() -> Void] = []
    static var sent: [(CLLocationCoordinate2D, MapVenue?)] = []
    static var closes = 0
    static func reset() { confirmationOrigin = nil; shown = nil; confirmations = []; sent = []; closes = 0 }
}
final class LocationSelectionTests: XCTestCase {
    var context: Context!
    var interaction: ChatInteraction!
    var hub: Analytics { Analytics.shared }
    let coordinate = CLLocationCoordinate2D(latitude: 1.25, longitude: 2.5)
    override func setUp() {
        Analytics.shared = Analytics(); context = Context(); interaction = ChatInteraction(context)
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.check = nil; LocationProbe.reset(); var hooks = LocationHooks(confirmSend: { _, action in LocationProbe.confirmations.append(action) })
        hooks.confirmSendWithContext = { _, origin, action in
            Probe.check?(); LocationProbe.confirmationOrigin = origin; LocationProbe.confirmations.append(action)
        }
        installLocationHooks(hooks)
        installLocationSelectorFixture()
    }
    override func tearDown() { Probe.check = nil; LocationProbe.reset(); ChatNavigationHooks.shared = ChatNavigationHooks() }
    func origin(_ peer: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: peer) }
    func picker(_ source: AnalyticsContext?, destination: SelectLocationDestination = .chat) -> LocationSelectionHost {
        let picker = LocationSelectionHost(interaction, destination: destination, analyticsContext: source); picker.start(); return picker
    }
    func map() -> TelegramMediaMap { TelegramMediaMap(latitude: 3, longitude: 4, heading: nil, accuracyRadius: nil, venue: MapVenue(title: "venue"), liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil) }

    func testOrdinaryEditorHookBridgeAndSelectionKeepExactOrigin() {
        let source = origin(), editor = PickerEditor(), cache = LocationCache()
        Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        RichLocationPicker.presentLocationPicker(editor, context: context, cache: cache, interaction: interaction, analyticsContext: source)
        let picker = LocationProbe.shown!
        XCTAssertTrue(picker.analyticsContext?.scope === source.scope)
        XCTAssertEqual(picker.analyticsScreen, .appLocationPicker)
        picker.state.set(.expanded(nil)); picker.sendLocation(map()); LocationProbe.confirmations[0]()
        XCTAssertEqual(cache.media.values.first, map()); XCTAssertEqual(editor.inserted.first?.0, "map")
        XCTAssertEqual(editor.focuses, 1); XCTAssertEqual(LocationProbe.closes, 1); XCTAssertTrue(LocationProbe.sent.isEmpty)
    }

    func testPrivateSourceSurvivesRetainedConfirmationAndSelection() {
        let source = origin(-1), editor = PickerEditor(), cache = LocationCache()
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        RichLocationPicker.presentLocationPicker(editor, context: context, cache: cache, interaction: interaction, analyticsContext: source)
        let picker = LocationProbe.shown!
        XCTAssertTrue(picker.analyticsContext!.isExcluded)
        picker.state.set(.normal(.custom(CLLocation(coordinate: coordinate), named: "address")))
        picker.sendLocation(); LocationProbe.confirmations[0]()
        XCTAssertEqual(cache.media.values.first?.latitude, coordinate.latitude)
        XCTAssertNil(cache.media.values.first?.venue); XCTAssertEqual(editor.inserted.count, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testChatDestinationRejectsSecretPeerEvenWithOrdinaryParent() {
        let source = origin(); interaction.peerId = -1
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let picker = picker(source)
        XCTAssertEqual(picker.analyticsScreen, .chatAttachLocation); XCTAssertTrue(picker.analyticsContext!.isExcluded)
        picker.state.set(.normal(.user(CLLocation(coordinate: coordinate))))
        picker.sendLocation(); LocationProbe.confirmations[0]()
        XCTAssertEqual(LocationProbe.sent.count, 1); XCTAssertEqual(LocationProbe.sent[0].0, coordinate)
        XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testMissingOriginAndLegacySelectorRemainExcluded() {
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let missing = picker(nil, destination: .select)
        XCTAssertTrue(missing.analyticsContext!.isExcluded)
        missing.close()
        Probe.check = nil
        let source = origin(), editor = PickerEditor(), cache = LocationCache()
        var callback: ((TelegramMediaMap) -> Void)?
        ChatNavigationHooks.shared.showLocationSelectorWithContext = nil
        ChatNavigationHooks.shared.showLocationSelector = { _, selected, _ in
            XCTAssertTrue(self.hub.policy.hasExclusions); callback = selected
        }
        RichLocationPicker.presentLocationPicker(editor, context: context, cache: cache, interaction: interaction, analyticsContext: source)
        XCTAssertTrue(source.isExcluded)
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        callback?(map()); XCTAssertEqual(editor.inserted.count, 1)
    }

    func testAccountChangeAndRevocationBeforeConfirmationDoNotRenewAdmission() {
        for changedOwner in [false, true] {
            setUp()
            let source = origin(), editor = PickerEditor(), cache = LocationCache()
            RichLocationPicker.presentLocationPicker(editor, context: context, cache: cache, interaction: interaction, analyticsContext: source)
            let picker = LocationProbe.shown!
            picker.state.set(.expanded(CLLocation(coordinate: coordinate))); picker.sendLocation()
            if changedOwner { hub.policy.setOwner(Account()) } else { source.scope?.exclude() }
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            LocationProbe.confirmations[0]()
            XCTAssertEqual(editor.inserted.count, 1); XCTAssertFalse(hub.policy.hasExclusions)
            tearDown()
        }
    }

    func testWaitsForLocationThenDeliversOnlyOnce() {
        let picker = picker(origin())
        picker.sendLocation(); LocationProbe.confirmations[0]()
        XCTAssertTrue(LocationProbe.sent.isEmpty)
        picker.state.set(.normal(.user(CLLocation(coordinate: coordinate))))
        picker.state.set(.expanded(CLLocation(coordinate: .init(latitude: 9, longitude: 8))))
        LocationProbe.confirmations[0](); picker.sendLocation()
        XCTAssertEqual(LocationProbe.sent.count, 1); XCTAssertEqual(LocationProbe.sent[0].0, coordinate)
        XCTAssertEqual(LocationProbe.closes, 1); XCTAssertEqual(LocationProbe.confirmations.count, 1)
    }

    func testDelayedPrivateLocationResultStaysGuardedAfterConfirmationReturns() {
        let picker = picker(origin(-1))
        picker.sendLocation(); LocationProbe.confirmations[0]()
        XCTAssertTrue(hub.policy.hasExclusions)
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        picker.state.set(.normal(.user(CLLocation(coordinate: coordinate))))
        XCTAssertEqual(LocationProbe.sent.count, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testNormalSelectionUsesCurrentCoordinateInsteadOfStaleVenue() {
        let picker = picker(origin())
        picker.state.set(.normal(.custom(CLLocation(coordinate: coordinate), named: "address")))
        picker.sendLocation(map()); LocationProbe.confirmations[0]()
        XCTAssertEqual(LocationProbe.sent.first?.0, coordinate); XCTAssertNil(LocationProbe.sent.first?.1)
    }

    func testCloseBeforeConfirmationAndBeforeLocationRejectLateSelection() {
        for confirmFirst in [false, true] {
            let picker = picker(origin())
            picker.sendLocation(); let confirmation = LocationProbe.confirmations.last!
            if confirmFirst { confirmation() }
            picker.close(); confirmation()
            picker.state.set(.normal(.user(CLLocation(coordinate: coordinate))))
            XCTAssertTrue(LocationProbe.sent.isEmpty)
        }
    }

    func testReentrantSelectionAndRepeatedConfirmationDoNotInsertTwice() {
        let picker = picker(origin(), destination: .select)
        var selections = 0
        picker.selectCallback = { _ in selections += 1; picker.sendLocation(); LocationProbe.confirmations[0]() }
        picker.state.set(.expanded(nil)); picker.sendLocation(map()); LocationProbe.confirmations[0]()
        XCTAssertEqual(selections, 1); XCTAssertEqual(LocationProbe.closes, 1)
        picker.selectCallback = nil
    }

    func testClosedPickerDisposesPendingProvidersUnderItsContext() {
        let picker = picker(origin(-1))
        var disposals = 0
        let cleanup = { XCTAssertTrue(self.hub.policy.hasExclusions); disposals += 1 }
        picker.disposable.set(ActionDisposable(action: cleanup)); picker.requestDisposable.set(ActionDisposable(action: cleanup))
        picker.sendLocation(); LocationProbe.confirmations[0](); picker.close()
        XCTAssertEqual(disposals, 2); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testDisabledCollectionAndReleasedEditorStillCompleteSelection() {
        hub.policy.isEnabled = false
        var editor: PickerEditor? = PickerEditor()
        let cache = LocationCache()
        RichLocationPicker.presentLocationPicker(editor!, context: context, cache: cache, interaction: interaction, analyticsContext: origin())
        let picker = LocationProbe.shown!
        editor = nil
        picker.state.set(.expanded(nil)); picker.sendLocation(map()); LocationProbe.confirmations[0]()
        XCTAssertTrue(cache.media.isEmpty); XCTAssertEqual(LocationProbe.closes, 1)
    }
}

struct LocationPaidPeer { let id: PeerId = 1; let displayTitle = "recipient" }
struct LocationStars { let value: Int64 }
struct LocationStarsState { let balance: LocationStars }
struct LocationPaidState {
    var sendPaidMessageStars: LocationStars? = LocationStars(value: 10)
    var peer: LocationPaidPeer? = LocationPaidPeer()
    var starsState: LocationStarsState? = LocationStarsState(balance: LocationStars(value: 20))
    var alwaysPaidMessage = false
    func withUpdatedAlwaysPaidMessage(_ value: Bool) -> LocationPaidState { var result = self; result.alwaysPaidMessage = value; return result }
}
extension ChatInteraction {
    var locationPresentation: LocationPaidState { LocationPaidProbe.state }
    func update(_ transform: (LocationPaidState) -> LocationPaidState) { Probe.check?(); LocationPaidProbe.state = transform(LocationPaidProbe.state) }
}
enum FastSettings {
    static func toggleCofirmPaid(_ peer: PeerId, price: Int) { Probe.check?(); LocationPaidProbe.preferences.append((peer, price)) }
}
extension Strings {
    func starListItemCountOther(_ count: Int) -> String { "\(count)" }
    func chatPayStarsConfirmMessagesOther(_ count: Int) -> String { "\(count)" }
    var chatPayStarsConfirmTitle: String { "confirm" }
    func chatPayStarsConfirmText(_ peer: String, _ a: String, _ b: String, _ c: String) -> String { peer }
    func chatPayStarsConfirmPayOther(_ count: Int) -> String { "pay" }
    var chatPayStarsConfirmCheckbox: String { "remember" }
}
enum LocationPurchaseSource { case buy(suffix: String?, amount: Int64) }
struct LocationPurchase {}
func Star_ListScreen(context: Context, source: LocationPurchaseSource, analyticsContext: AnalyticsContext?) -> LocationPurchase {
    Probe.check?(); LocationPaidProbe.purchaseOrigin = analyticsContext
    if case let .buy(_, amount) = source { LocationPaidProbe.price = amount }
    return LocationPurchase()
}
func showModal(with controller: LocationPurchase, for window: Int) { Probe.check?(); LocationPaidProbe.purchases += 1 }
func verifyAlert(for window: Int, header: String, information: String, ok: String, option: String, optionIsSelected: Bool, successHandler: @escaping (ConfirmResult) -> Void, onDeinit: @escaping () -> Void) {
    Probe.check?(); XCTAssertFalse(optionIsSelected); LocationPaidProbe.success = successHandler; LocationPaidProbe.release = onDeinit
}
enum LocationPaidProbe {
    static var state = LocationPaidState()
    static var success: ((ConfirmResult) -> Void)?
    static var release: (() -> Void)?
    static var preferences: [(PeerId, Int)] = []
    static var purchaseOrigin: AnalyticsContext?
    static var price: Int64?
    static var purchases = 0
    static func reset() { success = nil; release?(); release = nil; state = LocationPaidState(); preferences = []; purchaseOrigin = nil; price = nil; purchases = 0 }
}
__LOCATION_CONFIRM_INSTALLER__
extension LocationSelectionTests {
    func testPaidConfirmationHoldsPrivateOriginThroughPreferenceAndSend() {
        LocationPaidProbe.reset(); defer { LocationPaidProbe.reset() }
        installLocationUIHooks()
        let source = origin(-1), picker = picker(source)
        picker.state.set(.normal(.user(CLLocation(coordinate: coordinate))))
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        picker.sendLocation()
        XCTAssertTrue(hub.policy.hasExclusions)
        LocationPaidProbe.success?(.thrid)
        XCTAssertEqual(LocationProbe.sent.count, 1); XCTAssertTrue(LocationPaidProbe.state.alwaysPaidMessage)
        XCTAssertEqual(LocationPaidProbe.preferences.first?.1, 10)
        LocationPaidProbe.reset(); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testPaidConfirmationAccountSwitchGuardsDeferredTopUp() {
        LocationPaidProbe.reset(); defer { LocationPaidProbe.reset() }
        installLocationUIHooks(); LocationPaidProbe.state.starsState = LocationStarsState(balance: LocationStars(value: 0))
        let picker = picker(origin()); picker.sendLocation()
        hub.policy.setOwner(Account())
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        LocationPaidProbe.success?(.basic)
        XCTAssertTrue(LocationProbe.sent.isEmpty); XCTAssertEqual(LocationPaidProbe.purchases, 1)
        XCTAssertEqual(LocationPaidProbe.price, 10)
        let presentation = LocationPaidProbe.purchaseOrigin!.beginPresentation()
        XCTAssertTrue(hub.policy.hasExclusions); presentation.end()
    }

    func testPaidAlwaysAndUnpaidRoutesKeepOrdinaryScope() {
        LocationPaidProbe.reset(); defer { LocationPaidProbe.reset() }
        installLocationUIHooks()
        for paid in [false, true] {
            LocationPaidProbe.state.alwaysPaidMessage = true
            LocationPaidProbe.state.sendPaidMessageStars = paid ? LocationStars(value: 10) : nil
            let source = origin(), picker = picker(source)
            picker.state.set(.expanded(nil))
            Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
            picker.sendLocation(map())
            XCTAssertTrue(picker.analyticsContext?.scope === source.scope)
        }
        XCTAssertEqual(LocationProbe.sent.count, 2); XCTAssertNil(LocationPaidProbe.success)
    }

    func testLegacyConfirmationRetainsExclusionUntilCallbackReleased() {
        var retained: (() -> Void)?
        installLocationHooks(LocationHooks(confirmSend: { _, action in retained = action }))
        let source = origin(), picker = picker(source)
        picker.state.set(.expanded(nil)); picker.sendLocation(map())
        XCTAssertTrue(source.isExcluded); XCTAssertTrue(hub.policy.hasExclusions)
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        retained?(); XCTAssertEqual(LocationProbe.sent.count, 1)
        retained = nil; XCTAssertFalse(hub.policy.hasExclusions)
    }
}
