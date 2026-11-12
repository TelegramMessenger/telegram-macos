import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import MapKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramIconsTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI
import LocationUI
import AlertsUI
import ColorPalette
import FoundationUtils
import AvatarUI
import TelegramMediaResources
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public let presentaiton: TelegramPresentationTheme
    public let loadMore: () -> Void
    public let openStory:(StoryInitialIndex?)->Void
    public init(context: any AccountContextProtocol, presentaiton: TelegramPresentationTheme, openStory:@escaping(StoryInitialIndex?)->Void, loadMore: @escaping () -> Void) {
        self.context = context
        self.presentaiton = presentaiton
        self.openStory = openStory
        self.loadMore = loadMore
    }
}


private class MapRowItem: GeneralRowItem {
    public let context: any AccountContextProtocol
    fileprivate let location: State.Location
    fileprivate let presentation: TelegramPresentationTheme
    fileprivate let userLocation: CLLocation?
    fileprivate let geocodedPlacemark: ReverseGeocodedPlacemark?
    fileprivate let userLocationError: UserLocationError?
    public init(_ initialSize: NSSize, height: CGFloat, stableId: AnyHashable, context: any AccountContextProtocol, location: State.Location, userLocation: CLLocation?, geocodedPlacemark: ReverseGeocodedPlacemark?, userLocationError: UserLocationError?, presentation: TelegramPresentationTheme, viewType: GeneralViewType, action: @escaping()->Void) {
        self.context = context
        self.location = location
        self.userLocation = userLocation
        self.presentation = presentation
        self.geocodedPlacemark = geocodedPlacemark
        self.userLocationError = userLocationError
        super.init(initialSize, height: height + 60, stableId: stableId, viewType: viewType, action: action, inset: NSEdgeInsets())
    }
    
    deinit {
       
    }
    
    public override func viewClass() -> AnyClass {
        return MapRowItemView.self
    }

    public override var accessibilityLabel: String? {
        return geocodedPlacemark?.city ?? strings().locationPreviewLocation
    }

    public override var accessibilityValue: String? {
        return geocodedPlacemark?.street
    }
}

private final class MapRowItemView : GeneralContainableRowView, MKMapViewDelegate {
    
    public final class VenueView : View {
        private let imageView = ImageView()
        private let titleView = TextView()
        private let textView = TextView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(imageView)
            imageView.isAccessibilityDecorative = true
            
            addSubview(titleView)
            addSubview(textView)
            
            titleView.userInteractionEnabled = false
            titleView.isSelectable = false
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
        }
        
        override func layout() {
            super.layout()
            imageView.centerY(x: 10)
            titleView.setFrameOrigin(NSMakePoint(imageView.frame.maxX + 10, 12))
            textView.setFrameOrigin(NSMakePoint(imageView.frame.maxX + 10, frame.height - textView.frame.height - 12))
        }
        
        func update(item: MapRowItem, animated: Bool) {
            
            self.backgroundColor = item.presentation.colors.background
            imageView.image = item.presentation.icons.locationPin
            imageView.sizeToFit()
            
            let name = TextViewLayout(.initialize(string: item.geocodedPlacemark?.city ?? strings().locationPreviewLocation, color: item.presentation.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
            
            
            var distance: String = ""
            if let address = item.geocodedPlacemark?.street {
                distance += address
                distance += " \(strings().bullet) "
            }
            if let userLocation = item.userLocation {
                let loc1 = CLLocation(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
                let loc2 = CLLocation(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude)
                let dis = loc1.distance(from: loc2)
                distance += strings().locationPreviewDistanceAway(stringForDistance(distance: dis))
            } else {
                distance += "\(item.location.coordinate.latitude), \(item.location.coordinate.longitude)"
            }
            
            let info = TextViewLayout(.initialize(string: distance, color: item.presentation.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
            
            
            name.measure(width: frame.width - imageView.frame.width - 30)
            info.measure(width: frame.width - imageView.frame.width - 30)
            
            self.titleView.update(name)
            self.textView.update(info)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    
    private let mapView: MKMapView = MKMapView()
    
    
    private let venueView: VenueView = .init(frame: .zero)
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(mapView)
        mapView.register(LocationPinAnnotationView.self, forAnnotationViewWithReuseIdentifier: LocationPinAnnotationView.reuseIdentifier)
        mapView.delegate = self
        
        mapView.showsZoomControls = true
        mapView.showsUserLocation = true
        
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        
        mapView.showsBuildings = false
        
        addSubview(venueView)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        mapView.delegate = nil
    }
    
    public override func layout() {
        super.layout()
        mapView.frame = CGRect(origin: .zero, size: NSMakeSize(containerView.frame.width, containerView.frame.height - 60))
        venueView.frame = NSMakeRect(0, mapView.frame.maxY, mapView.frame.width, 60)
    }

    
    public func focusVenue() {
        guard let item = item as? MapRowItem else {
            return
        }
        mapView.focusVenue(at: item.location.coordinate)
    }
    
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        switch annotation {
        case is State.Location:
            return mapView.dequeueReusableAnnotationView(withIdentifier: LocationPinAnnotationView.reuseIdentifier, for: annotation)
        default:
            return nil
        }
    }
    
    public func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        
    }
    
    public func mapViewDidStopLocatingUser(_ mapView: MKMapView) {
        
    }
    
        
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        
    }

    private var location: NSPoint? = nil
    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        location = nil
       
    }
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        location = event.locationInWindow
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        layout()
        
        guard let item = item as? MapRowItem else {
            return
        }

        mapView.appearance = item.presentation.appearance
        
        venueView.update(item: item, animated: animated)
        
    
        if !mapView.annotations.contains(where: { ($0 as? State.Location) === item.location }) {
            mapView.removeAnnotations(mapView.annotations.compactMap { $0 as? State.Location })
            mapView.addAnnotation(item.location)
            focusVenue()
        }

    }
}



private struct State : Equatable {
    public class Location : NSObject, MKAnnotation {
        var coordinate: CLLocationCoordinate2D
        var venue: MapVenue?
        init(coordinate: CLLocationCoordinate2D, venue: MapVenue?) {
            self.coordinate = coordinate
            self.venue = venue
        }
    }
    
    public var location: Location?
    public var userLocation: CLLocation?
    public var geocodedPlacemark: ReverseGeocodedPlacemark?
    public var userLocationError: UserLocationError?
    
    public var listState: StoryListContext.State?
}

private let _id_map_map = InputDataIdentifier("_id_map_map")
private let _id_separator = InputDataIdentifier("_id_separator")
private let _id_search_empty = InputDataIdentifier("_id_search_empty")

private func _id_block(_ item: StoryListContextState.Item) -> InputDataIdentifier {
    return .init("_id_\(item.storyItem.id)_\(String(describing: item.peer?.id.toInt64()))")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    let sectionId:Int32 = 0
    let index: Int32 = 0
    
  
    if let location = state.location {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_map_map, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return MapRowItem(initialSize, height: 200, stableId: stableId, context: arguments.context, location: location, userLocation: state.userLocation, geocodedPlacemark: state.geocodedPlacemark, userLocationError: state.userLocationError, presentation: arguments.presentaiton, viewType: .legacy, action: { })
        }))
    }
    
    if let listState = state.listState {
        if state.location != nil {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_separator, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return SeparatorRowItem(initialSize, stableId, string: strings().storiesFoundListFromLocationOther(listState.totalCount), customTheme: .initialize(arguments.presentaiton))
            }))
        }
        
        let items = listState.items.filter { item in
            guard let peer = item.peer, peer.id == item.id.peerId else {
                return false
            }
            return PeerReference(peer._asPeer()) != nil
        }
        for chunk in items.chunks(3) {
            guard let item = chunk.first, let peer = item.peer, let peerReference = PeerReference(peer._asPeer()) else {
                continue
            }
            let viewType: GeneralViewType = .modern(position: .inner, insets: NSEdgeInsetsMake(0, 0, 0, 0))
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_block(item), equatable: .init(chunk), comparable: nil, item: { initialSize, stableId in
                return StoriesHooks.shared.makeStoryMonthRowItem(initialSize, stableId, arguments.context, false, item.id.peerId, peerReference, chunk, nil, [], 3, viewType, arguments.openStory, { _ in }, { _ in return [] }, arguments.presentaiton)
            }))
        }
        if items.isEmpty || listState.isLoading || listState.loadMoreToken != nil {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_search_empty, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                let action: SearchEmptyRowItem.Action?
                if !listState.isLoading && listState.loadMoreToken != nil {
                    action = .init(click: arguments.loadMore, title: listState.hasCache ? strings().chatRichTextShowMore : strings().voiceOverCommonRetry)
                } else {
                    action = nil
                }
                let text: String
                if !listState.hasCache && !listState.isLoading {
                    text = strings().unknownError
                } else if items.isEmpty && listState.loadMoreToken == nil {
                    text = strings().storiesFoundListNotFound
                } else {
                    text = ""
                }
                return SearchEmptyRowItem(initialSize, stableId: stableId, height: items.isEmpty ? 160 : 120, isLoading: listState.isLoading, text: text, customTheme: .initialize(arguments.presentaiton), action: action)
            }))
        }
        
    }
    
    
    
    return entries
}

private extension SearchStoryListContext.Source {
    var title: String {
        switch self {
        case .hashtag(_, let string):
            return string
        case .mediaArea:
            return strings().storyLocationTitle
        }
    }
    
    var coordinates: CLLocationCoordinate2D? {
        switch self {
        case .hashtag:
            return nil
        case let .mediaArea(area):
            switch area {
            case .venue(_, let venue):
                return .init(latitude: venue.latitude, longitude: venue.longitude)
            default:
                return nil
            }
        }
    }
}

public func StoryFoundListController(context: any AccountContextProtocol, source: SearchStoryListContext.Source, presentation: TelegramPresentationTheme, existingsContext: SearchStoryListContext? = nil, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {
    var origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    if case let .hashtag(peerId, _) = source, let peerId {
        origin = origin.restricting(peerId: peerId)
    }
    let lifetime = origin.beginPresentation()
    defer { lifetime.end() }

    let actionsDisposable = DisposableSet()

    let initialState = State(location: source.coordinates.map { .init(coordinate: $0, venue: nil) })
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    
    
    if let location = initialState.location {
        actionsDisposable.add(requestUserLocation().start(next: { location in
            switch location {
            case let .success(location):
                updateState { current in
                    var current = current
                    current.userLocation = location
                    return current
                }
            }
        }, error: { error in
            updateState { current in
                var current = current
                current.userLocationError = error
                return current
            }
        }))

        actionsDisposable.add(reverseGeocodeLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude).start(next: { mark in
            updateState { current in
                var current = current
                current.geocodedPlacemark = mark
                return current
            }
        }))
    }
    
    let contextObject = existingsContext ?? SearchStoryListContext(account: context.account, source: source)


    let arguments = Arguments(context: context, presentaiton: presentation, openStory: { [weak contextObject] initialId in
        if let contextObject {
            StoriesHooks.shared.showListStoryObserved(context, contextObject, context.peerId, initialId, analyticsContext: origin)
        }
    }, loadMore: { [weak contextObject] in
        contextObject?.loadMore()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: source.title)
    controller.analyticsContext = origin
    controller.analyticsScreen = .storiesSearchResults
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    controller.contextObject = contextObject
   
    
    contextObject.loadMore()
    
    actionsDisposable.add(contextObject.state.start(next: { state in
        updateState { current in
            var current = current
            current.listState = state
            return current
        }
    }))
    
    controller.getBackgroundColor = {
        presentation.colors.background
    }

    
    let modalController = InputDataModalController(controller, modalInteractions: nil, size: NSMakeSize(350, 300), presentation: presentation)
    modalController.analyticsContext = origin
    
   
    
    modalController.getModalTheme = {
        .init(text: presentation.colors.text, grayText: presentation.colors.grayText, background: presentation.colors.background, border: .clear, activeBorder: presentation.colors.border)
    }
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    
    controller.centerModalHeader = ModalHeaderData(title: source.title, subtitle: "")
    
    
    switch source {
    case let .mediaArea(area):
        switch area {
        case let .venue(_, venue):
            
            let shareImage = TelegramThemeHooks.shared.image(.iconStoryShare).precomposed(presentation.colors.accent)
            
            controller.rightModalHeader = ModalHeaderData(image: shareImage, handler: {
                verifyAlert(for: context.window, information: strings().locationPreviewOpenInMaps, ok: strings().inAppLinksConfirmOpenExternalOK, successHandler: { _ in
                    StoriesHooks.shared.executeInApp(.external(link: "https://maps.google.com/maps?q=\(String(format:"%f", venue.latitude)),\(String(format:"%f", venue.longitude))", false))
                }, presentation: presentation)
            })
        default:
            break
        }
        
    default:
        break
    }
    
    controller.didLoad = { [weak contextObject] controller, _ in
        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                contextObject?.loadMore()
            default:
                break
            }
        }
    }
    
    controller.afterTransaction = { [weak modalController] controller in
        controller.centerModalHeader = ModalHeaderData(title: source.title, subtitle: strings().storySearchSubtitleOther(stateValue.with { $0.listState?.totalCount ?? 0 }))
        modalController?.updateLocalizationAndTheme(theme: presentation)
    }
    
    return modalController
}



