import Cocoa
import TGUIKit
import MapKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import ObjcUtils
import AppAnalytics

private enum PickLocationState : Equatable {
    case user(CLLocation?)
    case custom(CLLocation?, named: String?)
    var location: CLLocation? {
        switch self {
        case let .user(location):
            return location
        case let .custom(location, _):
            return location
        }
    }
}

private enum LocationViewState : Equatable {
    case normal(PickLocationState)
    case expanded(CLLocation?)
}


private final class LocationPinView : View {
    private let locationPin: ImageView = ImageView()
    private let dotView: View = View(frame: NSMakeRect(0, 0, 4, 4))
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(locationPin)
        addSubview(dotView)
        locationPin.isAccessibilityDecorative = true
        dotView.layer?.cornerRadius = 2
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        locationPin.image = theme.icons.locationMapPin
        locationPin.sizeToFit()
        dotView.backgroundColor = theme.colors.accentIcon
    }
    
    override func layout() {
        super.layout()
        dotView.centerX(y: frame.height - dotView.frame.height)
    }
    
    func updateState(_ state: PickLocationState, animated: Bool) -> Void {
        
        switch state {
        case .user:
            dotView.change(opacity: 0, animated: animated)
            locationPin.change(pos: NSMakePoint(locationPin.frame.minX, frame.height - dotView.frame.height - locationPin.frame.height - 6), animated: animated, duration: 0.3, timingFunction: CAMediaTimingFunctionName.spring)
        case let .custom(location, _):
            dotView.change(opacity: 1, animated: animated)
            locationPin.change(pos: NSMakePoint(locationPin.frame.minX, location == nil ? 0 : frame.height - dotView.frame.height - locationPin.frame.height - 6), animated: animated, duration: 0.3, timingFunction: CAMediaTimingFunctionName.spring)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class LocationMapView : View {
    fileprivate let mapView: MKMapView = MKMapView()
    private let expandContainer: Control = Control(frame: NSMakeRect(0, 0, 0, 50))
    private let expandButton: TextButton = TextButton()
    private var state: LocationViewState = .normal(.user(nil))
    private var hasExpand: Bool = true
    private let loadingView: ProgressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))
    fileprivate let dismiss: ImageButton = ImageButton()
    fileprivate let tableView: TableView = TableView(frame: NSZeroRect)
    fileprivate let locateButton: ImageButton = ImageButton()
    private var zoomControl: NSView?

    private let locationPinView = LocationPinView(frame: NSMakeRect(0, 0, 40, 70))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(mapView)

        mapView.mapType = .standard
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        if #available(macOS 11.0, *) {
            mapView.showsZoomControls = false
            let zoomControl = MKZoomControl(mapView: mapView)
            addSubview(zoomControl)
            self.zoomControl = zoomControl
        } else {
            mapView.showsZoomControls = true
        }
        mapView.wantsLayer = true
        addSubview(dismiss)
        addSubview(locateButton)
        addSubview(tableView)
        updateLocalizationAndTheme(theme: theme)

        expandButton.isEventLess = true
        expandButton.userInteractionEnabled = false

        expandContainer.addSubview(loadingView)
        expandContainer.addSubview(expandButton)
        addSubview(expandContainer)
        locateButton.autohighlight = false
        addSubview(locationPinView)

        locateButton.scaleOnClick = true

        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        locateButton.setAccessibilityLabel(strings().voiceOverCommonLocation)
    }
    
    fileprivate func getSelectedLocation() -> CLLocation? {
        let windowLocation = locationPinView.convert(NSMakePoint(locationPinView.frame.width / 2, locationPinView.frame.height - 2), to: nil)
        let coordinate = mapView.convert(windowLocation, toCoordinateFrom: nil)
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    
    fileprivate func hitsMapWhileExpanded(_ event: NSEvent) -> Bool {
        guard case .expanded = state, let contentView = window?.contentView else {
            return false
        }
        return contentView.hitTest(event.locationInWindow)?.isDescendant(of: mapView) == true
    }
    
    private func zoomControlOrigin(_ zoomControl: NSView) -> NSPoint {
        let bottomInset = 60 + (hasExpand ? expandContainer.frame.height : 0)
        return NSMakePoint(frame.width - 10 - zoomControl.frame.width, frame.height - bottomInset - 10 - zoomControl.frame.height)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        locationPinView.updateLocalizationAndTheme(theme: theme)
        expandButton.set(font: .medium(.title), for: .Normal)
        expandButton.set(color: theme.colors.accent, for: .Normal)
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        _ = dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        _ = locateButton.sizeToFit()
        loadingView.progressColor = theme.colors.accent
        expandContainer.border = [.Top]
        expandContainer.backgroundColor = theme.colors.background
    }
    
    fileprivate func updateExpandState(_ state: LocationViewState, loading: Bool, hasVenues: Bool, animated: Bool, toggleExpand:@escaping(LocationViewState)->Void, destination: SelectLocationDestination) {
        loadingView.isHidden = !loading && hasVenues
        expandButton.isHidden = loading || !hasVenues
        hasExpand = (loading || hasVenues) && destination == .chat
        self.state = state
        
        let duration: Double = 0.3
        let timingFunction: CAMediaTimingFunctionName = CAMediaTimingFunctionName.spring
        
        
        CATransaction.begin()
        let mapY: CGFloat
        switch state {
        case let .normal(pickState):
            switch pickState {
            case .custom:
                hasExpand = false
                locateButton.set(image: theme.icons.locationMapLocate, for: .Normal)
            case let .user(location):
                locateButton.set(image: theme.icons.locationMapLocated, for: .Normal)
                locateButton.isHidden = location == nil
            }
            locationPinView.change(opacity: 1, animated: animated)
            locationPinView.updateState(pickState, animated: animated)
            expandButton.set(text: strings().locationSendShowNearby, for: .Normal)
            expandContainer.setAccessibilityLabel(strings().locationSendShowNearby)
            tableView.change(size: NSMakeSize(frame.width, 60), animated: animated, timingFunction: CAMediaTimingFunctionName.spring)
            tableView.change(pos: NSMakePoint(0, frame.height - 60 - (hasExpand ? expandContainer.frame.height : 0)), animated: animated, duration: duration, timingFunction: timingFunction)
            mapY = 0
            locateButton.userInteractionEnabled = true
            zoomControl?.isHidden = false
            zoomControl?._change(opacity: 1, animated: animated)
        case .expanded:
            locateButton.userInteractionEnabled = false
            zoomControl?._change(opacity: 0, animated: animated, completion: { [weak self] completed in
                if completed, let self, case .expanded = self.state {
                    self.zoomControl?.isHidden = true
                }
            })
            locateButton.set(image: theme.icons.locationMapLocate, for: .Normal)
            locationPinView.change(opacity: 0, animated: animated)
            expandButton.set(text: strings().locationSendHideNearby, for: .Normal)
            expandContainer.setAccessibilityLabel(strings().locationSendHideNearby)
            let tableHeight = min(tableView.listHeight, frame.height - (hasExpand ? expandContainer.frame.height : 0) - 50)
            tableView.change(size: NSMakeSize(frame.width, tableHeight), animated: animated, duration: duration, timingFunction: timingFunction)
            tableView.change(pos: NSMakePoint(0, frame.height - (hasExpand ? expandContainer.frame.height : 0) - tableHeight), animated: animated, duration: duration, timingFunction: timingFunction)
            mapY = -(mapView.frame.height / 2) + 50 / 2
        }
        expandContainer.change(pos: NSMakePoint(0, hasExpand ? frame.height - expandContainer.frame.height : frame.height), animated: animated, duration: duration, timingFunction: timingFunction)
        if let zoomControl {
            zoomControl._change(pos: zoomControlOrigin(zoomControl), animated: animated, duration: duration, timingFunction: timingFunction)
        }
        _ = locateButton.sizeToFit()
        
        
        mapView._change(pos: NSMakePoint(0, mapY), animated: animated, duration: duration, timingFunction: timingFunction)
        let finalMapFrame = NSMakeRect(0, mapY, frame.width, mapView.frame.height)
        let pinPoint = finalMapFrame.focus(NSMakeSize(locationPinView.frame.width, 4))
        locationPinView.change(pos: NSMakePoint(pinPoint.minX, pinPoint.midY - locationPinView.frame.height), animated: animated, duration: 0.2, timingFunction: CAMediaTimingFunctionName.linear)


        CATransaction.commit()
        
        expandContainer.removeAllHandlers()
        if !loading {
            expandContainer.set(handler: { [weak self] _ in
                guard let `self` = self else {return}
                switch state {
                case .normal:
                    toggleExpand(.expanded(self.mapView.userLocation.location))
                case .expanded:
                    toggleExpand(.normal(.user(self.mapView.userLocation.location)))
                }
            }, for: .Click)
        }
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        let overlayInset: CGFloat = 10
        dismiss.setFrameOrigin(NSMakePoint(overlayInset, overlayInset))
        locateButton.setFrameOrigin(NSMakePoint(frame.width - overlayInset - locateButton.frame.width, overlayInset))
        if let zoomControl {
            zoomControl.setFrameOrigin(zoomControlOrigin(zoomControl))
        }
        expandContainer.frame = NSMakeRect(0, hasExpand ? frame.height - expandContainer.frame.height : frame.height, frame.width, expandContainer.frame.height)
        let mapY: CGFloat
        let mapHeight: CGFloat = frame.height
        switch state {
        case .normal:
            tableView.frame = NSMakeRect(0, frame.height - 60 - (hasExpand ? expandContainer.frame.height : 0), frame.width, 60)
            mapY = 0
        case .expanded:
            let tableHeight = min(tableView.listHeight, frame.height - (hasExpand ? expandContainer.frame.height : 0) - 50)
            tableView.frame = NSMakeRect(0, frame.height - (hasExpand ? expandContainer.frame.height : 0) - tableHeight, frame.width, tableHeight)
            mapY = -(mapHeight / 2) + 50 / 2
        }
        let delegate = mapView.delegate
        mapView.delegate = nil
        mapView.frame = NSMakeRect(0, mapY, frame.width, mapHeight)
        mapView.delegate = delegate
        
        let pinPoint = mapView.frame.focus(NSMakeSize(4, 4))
        locationPinView.centerX(y: pinPoint.midY - locationPinView.frame.height)

        
        expandButton.center()
        loadingView.center()
        
        let zoomControls = ObjcUtils.findElements(byClass: "MKZoomSegmentedControl", in: mapView).first
        if let zoomControls = zoomControls {
            zoomControls.setFrameOrigin(20, 20)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



private final class MapItemsArguments {
    let context: (any AccountContextProtocol)
    let destination: SelectLocationDestination
    let sendCurrent:()->Void
    let sendVenue:(TelegramMediaMap)->Void
    let searchVenues:(String)->Void
    init(context: (any AccountContextProtocol), destination: SelectLocationDestination, sendCurrent:@escaping()->Void, sendVenue:@escaping(TelegramMediaMap)->Void, searchVenues: @escaping(String)->Void) {
        self.context = context
        self.destination = destination
        self.sendCurrent = sendCurrent
        self.sendVenue = sendVenue
        self.searchVenues = searchVenues
    }
}

private enum MapItemEntryId : Hashable {
    case currentLocation
    case expandNearby
    case nearby(Int32)
    case search
    case searchEmptyId
}

private enum MapItemEntry : TableItemListNodeEntry {
    case currentLocation(index:Int32, state: LocationSelectCurrentState)
    case expandNearby(index: Int32, expand: Bool, loading: Bool)
    case nearby(index: Int32, result: ChatContextResult)
    case search(index: Int32)
    case searchEmpty(index: Int32, loading: Bool)
    var index: Int32 {
        switch self {
        case let .currentLocation(index, _):
            return index
        case let .expandNearby(index, _, _):
            return index
        case let .nearby(index, _):
            return index
        case let .search(index):
            return index
        case let .searchEmpty(index, _):
            return index
        }
    }
    
    var stableId: MapItemEntryId {
        switch self {
        case .currentLocation:
            return .currentLocation
        case .expandNearby:
            return .expandNearby
        case .search:
            return .search
        case .searchEmpty:
            return .searchEmptyId
        case let .nearby(index, _):
            return .nearby(index)
        }
    }
    
    func item(_ arguments: MapItemsArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .nearby(_, result):
            return LocationPlaceSuggestionRowItem(initialSize, stableId: stableId, account: arguments.context.account, result: result, action: {
                switch result.message {
                case let .mapLocation(media, _):
                    arguments.sendVenue(media)
                default:
                    break
                }
            })
        case .search:
            return SearchRowItem(initialSize, stableId: stableId, searchInteractions: SearchInteractions({ state, _ in
                arguments.searchVenues(state.request)
            }, { state in
                arguments.searchVenues(state.request)
            }), inset: NSEdgeInsets(left: 10,right: 10, top: 0, bottom: 0))
        case let .currentLocation(_, state):
            return LocationSendCurrentItem(initialSize, stableId: stableId, state: state, destination: arguments.destination, action: {
                arguments.sendCurrent()
            })
        case let .searchEmpty(_, loading):
            return SearchEmptyRowItem(initialSize, stableId: stableId, isLoading: loading)
        default:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId)
        }
    }
}

private func < (lhs: MapItemEntry, rhs: MapItemEntry) -> Bool {
    return lhs.index < rhs.index
}

private func mapEntries(result: [ChatContextResult], loading: Bool, location: CLLocation?, state: LocationViewState) -> [MapItemEntry] {
    var entries: [MapItemEntry] = []
    

    
    var index: Int32 = 0
    
    let selectState: LocationSelectCurrentState
    switch state {
    case .expanded:
        selectState = .accurate(location: location, expanded: true)
    case let .normal(pickState):
        switch pickState {
        case .user:
            selectState = .accurate(location: location, expanded: false)
        case let .custom(_, name):
            let text: String
            if let name = name {
                text = name.isEmpty ? strings().locationSendThisLocationUnknown : name
            } else {
                text = strings().locationSendLocating
            }
            selectState = .selected(location: text)
        }
    }
    
    entries.append(.currentLocation(index: index, state: selectState))
    index += 1
    switch state {
    case .expanded:
        entries.append(.search(index: index))
        index += 1
        if !result.isEmpty {
            for value in result {
                entries.append(.nearby(index: index, result: value))
                index += 1
            }
        } else {
            entries.append(MapItemEntry.searchEmpty(index: index, loading: false))
            index += 1
        }
       
    case .normal:
        break
    }
    
    return entries
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<MapItemEntry>], right: [AppearanceWrapperEntry<MapItemEntry>], initialSize:NSSize, arguments:MapItemsArguments) -> TableUpdateTransition {
    
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

private class MapDelegate : NSObject, MKMapViewDelegate {
    
    fileprivate var isPinRaised: Bool = false
    private var animated: Bool = false
    let location:Promise<MKUserLocation?> = Promise()
    fileprivate var willChangeRegion:()->Void = {}
    fileprivate var didChangeRegion:()->Void = {}
    
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        self.location.set(.single(userLocation))
        
        guard !isPinRaised else {return}
        focusUserLocation(mapView)
    }
        
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        willChangeRegion()

    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        didChangeRegion()
    }
    
    func mapView(_ mapView: MKMapView, didFailToLocateUserWithError error: Error) {
        if "\(error)".contains("Code=1") {
            cancelRequestLocation()
        }
    }

    func cancelRequestLocation() {
        self.location.set(.single(nil))
        isPinRaised = true
        didChangeRegion()
    }
    
    
    fileprivate func focusUserLocation(_ mapView: MKMapView) {
        let userLocation = mapView.userLocation
        
        var region = MKCoordinateRegion()
        var span = MKCoordinateSpan()
        span.latitudeDelta = CLLocationDegrees(0.005)
        span.longitudeDelta = CLLocationDegrees(0.005)
        var location = CLLocationCoordinate2D()
        location.latitude = userLocation.coordinate.latitude
        location.longitude = userLocation.coordinate.longitude
        region.span = span
        region.center = location
        mapView.setRegion(region, animated: animated)
        animated = true
    }
    
    func focusVenue(mapView: MKMapView, _ location: CLLocationCoordinate2D) {
        let userLocation = location
        var region = MKCoordinateRegion()
        var span = MKCoordinateSpan()
        span.latitudeDelta = CLLocationDegrees(0.005)
        span.longitudeDelta = CLLocationDegrees(0.005)
        var location = CLLocationCoordinate2D()
        location.latitude = userLocation.latitude
        location.longitude = userLocation.longitude
        region.span = span
        region.center = location
        mapView.setRegion(region, animated: true)
    }
}

public enum SelectLocationDestination : Equatable {
    case chat
    case business(CLLocationCoordinate2D?)
    case select
}

extension CLLocationCoordinate2D : @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

public class LocationModalController: ModalViewController {
    
    

    private let chatInteraction: any LocationChatInteraction
    private let delegate: MapDelegate = MapDelegate()
    private let disposable = MetaDisposable()
    private let sendDisposable = MetaDisposable()
    private let requestDisposable = MetaDisposable()
    private let statePromise:Promise<LocationViewState> = Promise()
    private let destination: SelectLocationDestination
    private let getAnalyticsContext: () -> AnalyticsContext
    private var isClosed = false
    private var hasSelected = false
    public var selectCallback: ((TelegramMediaMap) -> Void)?
    private var collapseNearby: (() -> Void)?
    public init(_ chatInteraction: any LocationChatInteraction, destination: SelectLocationDestination = .chat, analyticsContext: AnalyticsContext? = nil) {
        let context = chatInteraction.locationContext
        let peerId = destination == .chat ? chatInteraction.locationPeerId : context.peerId
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
        self.getAnalyticsContext = {
            Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: origin)
        }
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        self.chatInteraction = chatInteraction
        self.destination = destination
        super.init(frame: NSMakeRect(0, 0, 360, 380))
        self.analyticsContext = origin
        self.analyticsScreen = destination == .chat ? AnalyticsScreen.chatAttachLocation : AnalyticsScreen.appLocationPicker
    }
    
    public override var dynamicSize: Bool {
        return true
    }
    
    public override func measure(size: NSSize) {
        self.modal?.resize(with:NSMakeSize(360, min(size.height - 70, 500)), animated: false)
    }
    
    public func updateSize(_ animated: Bool) {
        if let contentSize = self.modal?.window.contentView?.frame.size {
            self.modal?.resize(with:NSMakeSize(360, min(contentSize.height - 70, 500)), animated: animated)
        }
    }
    
    public override func viewClass() -> AnyClass {
        return LocationMapView.self
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        super.viewWillDisappear(animated)
        genericView.mapView.showsUserLocation = false
        window?.removeAllHandlers(for: self)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        super.viewDidAppear(animated)
        window?.set(mouseHandler: { [weak self] _ -> KeyHandlerResult in
            guard let self else { return .rejected }
            let presentation = self.getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            self.delegate.isPinRaised = true
            return .rejected
        }, with: self, for: .leftMouseDragged, priority: .modal)
        
        let collapseOnMapEvent: (NSEvent) -> KeyHandlerResult = { [weak self] event in
            guard let self else { return .rejected }
            let presentation = self.getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            if self.genericView.hitsMapWhileExpanded(event) {
                self.collapseNearby?()
            }
            return .rejected
        }
        window?.set(mouseHandler: collapseOnMapEvent, with: self, for: .leftMouseDown, priority: .modal)
        window?.set(mouseHandler: collapseOnMapEvent, with: self, for: .scrollWheel, priority: .modal)
    }
    
    public override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        isClosed = true
        disposable.set(nil)
        sendDisposable.set(nil)
        requestDisposable.set(nil)
        super.close(animationType: animationType)
    }

    private func sendLocation(_ media: TelegramMediaMap? = nil) {
        guard !isClosed, !hasSelected else { return }
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        let invoke: () -> Void = { [weak self] in
            guard let self, !self.isClosed, !self.hasSelected else { return }
            let origin = self.getAnalyticsContext()
            let presentation = origin.beginPresentation()
            defer { presentation.end() }
            let selection = self.statePromise.get() |> map { state -> TelegramMediaMap? in
                switch state {
                case let .normal(picked):
                    guard let location = picked.location else { return nil }
                    return TelegramMediaMap(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, heading: nil, accuracyRadius: nil, venue: nil, liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil)
                case let .expanded(location):
                    if let media { return media }
                    guard let location else { return nil }
                    return TelegramMediaMap(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, heading: nil, accuracyRadius: nil, venue: nil, liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil)
                }
            } |> filter { $0 != nil } |> take(1) |> deliverOnMainQueue
            self.sendDisposable.set(origin.preservingPresentation(selection).start(next: { [weak self] media in
                guard let self, let media, !self.isClosed, !self.hasSelected else { return }
                self.hasSelected = true
                if let selectCallback = self.selectCallback {
                    selectCallback(media)
                } else {
                    self.chatInteraction.sendPickedLocation(CLLocationCoordinate2D(latitude: media.latitude, longitude: media.longitude), media.venue)
                }
                self.close()
            }))
        }
        LocationHooks.shared.confirmSendObserved(self.chatInteraction, analyticsContext: getAnalyticsContext(), invoke: invoke)
    }

    public override func returnKeyAction() -> KeyHandlerResult {
        sendLocation()
        return .invoked
    }
    
    public override func viewDidLoad() {
        let getAnalyticsContext = self.getAnalyticsContext
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        super.viewDidLoad()
                
        genericView.mapView.delegate = delegate
        genericView.dismiss.set(handler: { [weak self] _ in
            self?.close()
        }, for: .Click)
        
        let state: ValuePromise<LocationViewState> = ValuePromise(.normal(.user(genericView.mapView.userLocation.location)), ignoreRepeated: true)
        statePromise.set(state.get())
        
        genericView.locateButton.set(handler: { [weak self] _ in
            guard let `self` = self else {return}
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            self.delegate.focusUserLocation(self.genericView.mapView)
            self.delegate.isPinRaised = false
        }, for: .Click)
        
        if let _ = genericView.mapView.userLocation.location {
            delegate.location.set(.single(genericView.mapView.userLocation))
            delegate.focusUserLocation(genericView.mapView)
        }
        
        switch destination {
        case let .business(coordinate):
            if let coordinate = coordinate {
                delegate.focusVenue(mapView: genericView.mapView, coordinate)
                self.delegate.isPinRaised = true
            }
        default:
            break
        }
        
        var handleRegion: Bool = true
        
        delegate.willChangeRegion = { [weak self] in
            guard let `self` = self, handleRegion else {return}
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            if self.delegate.isPinRaised {
                state.set(.normal(.custom(nil, named: nil)))
            } else {
                state.set(.normal(.user(self.genericView.mapView.userLocation.location)))
            }
        }
        delegate.didChangeRegion = { [weak self] in
            guard let `self` = self, handleRegion else {return}
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            if self.delegate.isPinRaised {
                state.set(.normal(.custom(self.genericView.getSelectedLocation(), named: nil)))
            } else {
                state.set(.normal(.user(self.genericView.mapView.userLocation.location)))
            }
        }
        
        let peerId = chatInteraction.locationPeerId
        let context = self.chatInteraction.locationContext
        
        let search:Promise<String> = Promise("")
        
        var cachedData:[String : ChatContextResultCollection] = [:]
        let previousResult:Atomic<ChatContextResultCollection?> = Atomic(value: nil)
        
        
        
        let peerSignal: Signal<PeerId?, NoError> = .single(nil) |> then(context.engine.peers.resolvePeerByName(name: "foursquare", referrer: nil) |> mapToSignal { result in
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            switch result {
            case .progress:
                return .never()
            case let .result(peer):
                return .single(peer?._asPeer().id)
            }
        })
        let requestSignal = combineLatest(peerSignal |> deliverOnPrepareQueue, delegate.location.get() |> take(1) |> deliverOnPrepareQueue, search.get() |> distinctUntilChanged |> deliverOnPrepareQueue)
            |> mapToSignal { botId, location, query -> Signal<(ChatContextResultCollection?, CLLocation?, Bool, Bool), NoError> in
                let presentation = getAnalyticsContext().beginPresentation()
                defer { presentation.end() }
                if let botId = botId, let location = location {
                    let first = Signal<(ChatContextResultCollection?, CLLocation?, Bool, Bool), NoError>.single((cachedData[query] ?? previousResult.modify {$0}, location.location, cachedData[query] == nil, !query.isEmpty))
                    if cachedData[query] == nil {
                        return first |> then(context.engine.messages.requestChatContextResults(botId: botId, peerId: peerId, query: query, location: .single((location.coordinate.latitude, location.coordinate.longitude)), offset: "")
                            |> `catch` { _ in return .complete() }
                            |> deliverOnPrepareQueue |> map { result in
                                let presentation = getAnalyticsContext().beginPresentation()
                                defer { presentation.end() }
                                var value = result?.results
                                if let result = result {
                                    cachedData[query] = result.results
                                }
                                value = previousResult.modify { _ in result?.results }
                                
                                return (value, location.location, false, !query.isEmpty)
                            })
                    } else {
                        return first
                    }
                    
                } else {
                    return .single((nil, location?.location, botId == nil, false))
                }
        }
        
        let signal: Signal<(ChatContextResultCollection?, CLLocation?, Bool, Bool), NoError> = .single((nil, nil, true, false)) |> then(requestSignal)
        
        let previous: Atomic<[AppearanceWrapperEntry<MapItemEntry>]> = Atomic(value: [])
        
        let initialSize = self.atomicSize
        let arguments = MapItemsArguments(context: context, destination: self.destination, sendCurrent: { [weak self] in
            self?.sendLocation()
        }, sendVenue: { [weak self] venue in
            self?.sendLocation(venue)
        }, searchVenues: { query in
            prepareQueue.async {
                let presentation = getAnalyticsContext().beginPresentation()
                defer { presentation.end() }
                if cachedData[query] != nil {
                    search.set(.single(query))
                } else {
                    search.set(.single(query) |> delay(0.2, queue: prepareQueue))
                }
            }
        })
        
        let stateModified = state.get() |> mapToSignal { state -> Signal<LocationViewState, NoError> in
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            switch state {
            case let .normal(pick):
                switch pick {
                case let .custom(location, _):
                    if let location = location {
                        return .single(state) |> then(reverseGeocodeLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) |> map { value in
                            let presentation = getAnalyticsContext().beginPresentation()
                            defer { presentation.end() }
                            return .normal(.custom(location, named: value?.fullAddress))
                        })
                    }
                default:
                    break
                }
            default:
                break
            }
            return .single(state)
        } |> distinctUntilChanged
        
        let transition:Signal<(TableUpdateTransition, Bool, LocationViewState, Bool), NoError> = combineLatest(queue: prepareQueue, signal, appearanceSignal, stateModified) |> map { data, appearance, state in
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            let results:[ChatContextResult] = data.0?.results ?? []
            let entries = mapEntries(result: results, loading: data.2, location: data.1, state: state).map{AppearanceWrapperEntry(entry: $0, appearance: appearance)}
            return (prepareTransition(left: previous.swap(entries), right: entries, initialSize: initialSize.modify{$0}, arguments: arguments), data.2, state, !results.isEmpty || data.3)
        } |> deliverOnMainQueue
        
        let animated:Atomic<Bool> = Atomic(value: false)
        
        let toggleExpand: (LocationViewState) -> Void = { [weak self] viewState in
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            self?.genericView.tableView.clipView.scroll(to: NSMakePoint(0, 0), animated: false)
            search.set(.single(""))
            state.set(viewState)
        }
        
        collapseNearby = { [weak self] in
            guard let self else {
                return
            }
            toggleExpand(.normal(.user(self.genericView.mapView.userLocation.location)))
        }
        
        disposable.set(getAnalyticsContext().preservingPresentation(transition).start(next: { [weak self] transition, loading, expanded, hasVenues in
            guard let `self` = self else {return}
            self.genericView.tableView.merge(with: transition)
            switch expanded {
            case .expanded:
                handleRegion = false
            default:
                handleRegion = true
            }
            self.genericView.updateExpandState(expanded, loading: loading, hasVenues: hasVenues, animated: animated.swap(true), toggleExpand: toggleExpand, destination: self.destination)
            self.readyOnce()
        }))

        let request = requestUserLocation() |> deliverOnMainQueue
        requestDisposable.set(getAnalyticsContext().preservingPresentation(request).start(next: { [weak self] result in
            self?.genericView.mapView.showsUserLocation = true
        }, error: { [weak self] error in
            self?.delegate.cancelRequestLocation()
        }))

    }
    
    deinit {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        disposable.dispose()
        sendDisposable.dispose()
        requestDisposable.dispose()
    }
    
    private var genericView: LocationMapView {
        return view as! LocationMapView
    }
}
