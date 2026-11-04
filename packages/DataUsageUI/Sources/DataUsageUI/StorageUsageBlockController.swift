import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI



final class SegmentContainerView : View {
    static let height: CGFloat = 56
    private let scrollView = HorizontalScrollView(frame: .zero)
    private let documentView = View()
    private let segmentControl = GlassSegmentView(frame: .zero)
    private var collections: [StorageUsageCollection] = []
    private var selected: StorageUsageCollection?
    private var accessibilityTabs: [StorageUsageCollection: StorageTabAccessibilityElement] = [:]
    var didSelect: ((StorageUsageCollection) -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.documentView = documentView
        scrollView.backgroundColor = .clear
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        documentView.layer?.masksToBounds = false
        documentView.addSubview(segmentControl)
        addSubview(scrollView)
        segmentControl.didSelect = { [weak self] index in
            guard let self, self.collections.indices.contains(index) else {
                return
            }
            self.select(self.collections[index])
        }
        updateLocalizationAndTheme(theme: theme)
    }

    func update(collections: [StorageUsageCollection], selected: StorageUsageCollection?, animated: Bool) {
        self.collections = collections
        self.selected = selected
        segmentControl.set(titles: collections.map { $0.title }, selected: selected.flatMap { collections.firstIndex(of: $0) }, animated: animated)
        accessibilityTabs = accessibilityTabs.filter { collections.contains($0.key) }
        layout()
        revealSelection()
    }

    func contains(_ collection: StorageUsageCollection?) -> Bool {
        return collection.map { collections.contains($0) } ?? false
    }

    fileprivate func select(_ collection: StorageUsageCollection) {
        guard collections.contains(collection) else {
            return
        }
        selected = collection
        revealSelection()
        didSelect?(collection)
    }

    private func revealSelection() {
        guard let selected, let index = collections.firstIndex(of: selected) else {
            return
        }
        let labels = segmentControl.subviews.compactMap { $0 as? TextView }
        guard labels.indices.contains(index) else {
            return
        }
        let rect = segmentControl.convert(labels[index].frame.insetBy(dx: -16, dy: -8), to: documentView)
        documentView.scrollToVisible(rect)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let size = segmentControl.contentSize
        documentView.frame = NSMakeRect(0, 0, max(bounds.width, size.width + 16), bounds.height)
        segmentControl.frame = NSMakeRect(max(8, floorToScreenPixels((bounds.width - size.width) / 2)), (bounds.height - size.height) / 2, size.width, size.height)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        segmentControl.updateLocalizationAndTheme(theme: theme)
        segmentControl.set(titles: collections.map { $0.title }, selected: selected.flatMap { collections.firstIndex(of: $0) }, animated: false)
        backgroundColor = .clear
        needsLayout = true
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }

    override func accessibilityChildren() -> [Any]? {
        guard TGUIKitAccessibility.isEnabled else {
            return super.accessibilityChildren()
        }
        return collections.map { collection in
            let element = accessibilityTabs[collection] ?? StorageTabAccessibilityElement()
            element.owner = self
            element.collection = collection
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityLabel(collection.title)
            element.setAccessibilityEnabled(true)
            accessibilityTabs[collection] = element
            return element
        }
    }

    fileprivate func accessibilityFrame(for collection: StorageUsageCollection) -> NSRect {
        let labels = segmentControl.subviews.compactMap { $0 as? TextView }
        guard let index = collections.firstIndex(of: collection), labels.indices.contains(index) else {
            return .zero
        }
        let rect = segmentControl.convert(labels[index].frame.insetBy(dx: -12, dy: 0), to: self)
        return NSAccessibility.screenRect(fromView: self, rect: NSMakeRect(rect.minX, 8, rect.width, GlassSegmentView.height))
    }

    fileprivate func isSelected(_ collection: StorageUsageCollection) -> Bool {
        return selected == collection
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class StorageTabAccessibilityElement: NSAccessibilityElement {
    weak var owner: SegmentContainerView?
    var collection: StorageUsageCollection = .peers

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityFrame() -> NSRect {
        return owner?.accessibilityFrame(for: collection) ?? .zero
    }

    override func isAccessibilitySelected() -> Bool {
        return owner?.isSelected(collection) ?? false
    }

    override func accessibilityPerformPress() -> Bool {
        guard let owner else {
            return false
        }
        owner.select(collection)
        return true
    }
}

private enum AnimationDirection {
   case leftToRight
   case rightToLeft
}
private let sectionOffset: CGFloat = 30

final class StorageUsageMediaContainerView : View {
   
   
   fileprivate let view: StorageUsageBlockControllerView
   required init(frame frameRect: NSRect) {
       view = StorageUsageBlockControllerView(frame: NSMakeRect(0, sectionOffset, min(600, frameRect.width - sectionOffset * 2), frameRect.height - sectionOffset))
       super.init(frame: frameRect)
       addSubview(view)
       backgroundColor = .clear
       layer?.isOpaque = false
       layout()
   }
   override func updateLocalizationAndTheme(theme: PresentationTheme) {
       super.updateLocalizationAndTheme(theme: theme)
       backgroundColor = .clear
       layer?.isOpaque = false
   }
   
   override func scrollWheel(with event: NSEvent) {
       view.scrollWheel(with: event)
   }
   
   required init?(coder: NSCoder) {
       fatalError("init(coder:) has not been implemented")
   }
   
   override func layout() {
       super.layout()
       
       let blockWidth = min(600, frame.width - sectionOffset * 2)
       view.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - blockWidth) / 2), sectionOffset, blockWidth, frame.height - sectionOffset)
              
   }
   
   var mainView:NSView? {
       return self.view.mainView
   }
   
   var mainTable: TableView? {
       if let tableView = self.view.mainView as? TableView {
           return tableView
       } else if let view = self.view.mainView as? InputDataView {
           return view.tableView
       } else if let view = self.view.mainView as? StorageUsageGifsView {
           return view.tableView
       }
       return nil
   }
   
   func updateInteraction(_ chatInteraction:StorageUsageChatInteraction) {
       self.view.updateInteraction(chatInteraction)
   }
   
   
   fileprivate func updateMainView(with view:NSView, animated:AnimationDirection?) {
       self.view.updateMainView(with: view, animated: animated)
   }
   
   func changeState(selectState:Bool, animated:Bool) {
       self.view.changeState(selectState: selectState, animated: animated)
   }
   
   fileprivate var segmentPanelView: SegmentContainerView {
       return self.view.segmentPanelView
   }
   
   func updateCorners(_ corners: GeneralViewItemCorners, animated: Bool) {
       view.updateCorners(corners, animated: animated)
   }
}

class StorageUsageBlockControllerView : View {
   
   private let contentContainerView = GeneralRowContainerView(frame: .zero)
   fileprivate let segmentPanelView: SegmentContainerView
   
   private(set) weak var mainView:NSView?
   
   override func scrollWheel(with event: NSEvent) {
       mainTable?.scrollWheel(with: event)
   }
   
   var mainTable: TableView? {
       if let tableView = self.mainView as? TableView {
           return tableView
       } else if let view = self.mainView as? InputDataView {
           return view.tableView
       }
       return nil
   }
   
   fileprivate var corners:GeneralViewItemCorners = [.topLeft, .topRight]
   
   fileprivate var isSelectionState:Bool = false
   private var chatInteraction:StorageUsageChatInteraction?
   required init(frame frameRect:NSRect) {
       segmentPanelView = SegmentContainerView(frame: NSMakeRect(0, 0, frameRect.width, SegmentContainerView.height))
       super.init(frame: frameRect)
       addSubview(contentContainerView)
       addSubview(segmentPanelView)
       updateLocalizationAndTheme(theme: theme)
       layout()
   }
   
   override func updateLocalizationAndTheme(theme: PresentationTheme) {
       backgroundColor = .clear
       layer?.isOpaque = false
       contentContainerView.backgroundColor = .clear
       contentContainerView.layer?.isOpaque = false
       segmentPanelView.updateLocalizationAndTheme(theme: theme)
   }
   
   func updateInteraction(_ chatInteraction:StorageUsageChatInteraction) {
       self.chatInteraction = chatInteraction
   }
   
   func updateCorners(_ corners: GeneralViewItemCorners, animated: Bool) {
       self.corners = corners
       self.contentContainerView.setCorners(corners, animated: animated)
   }
   
   fileprivate func updateMainView(with view:NSView, animated:AnimationDirection?) {
       view.frame = contentContainerView.bounds
       contentContainerView.addSubview(view)
       
       let timingFunction: CAMediaTimingFunctionName = .spring
       let duration: TimeInterval = 0.35
       
       if let animated = animated {
           if let mainView = mainView {
               switch animated {
               case .leftToRight:
                   mainView._change(pos: NSMakePoint(-mainView.frame.width, mainView.frame.minY), animated: true, duration: duration, timingFunction: timingFunction, completion: { [weak mainView] completed in
                       if completed {
                           mainView?.removeFromSuperview()
                       }
                   })
                   view.layer?.animatePosition(from: NSMakePoint(view.frame.width, mainView.frame.minY), to: NSMakePoint(0, mainView.frame.minY), duration: duration, timingFunction: timingFunction)
               case .rightToLeft:
                   mainView._change(pos: NSMakePoint(mainView.frame.width, mainView.frame.minY), animated: true, duration: duration, timingFunction: timingFunction, completion: { [weak mainView] completed in
                       if completed {
                           mainView?.removeFromSuperview()
                       }
                   })
                   view.layer?.animatePosition(from: NSMakePoint(-view.frame.width, mainView.frame.minY), to: NSMakePoint(0, mainView.frame.minY), duration: duration, timingFunction: timingFunction)
               }
           }
           self.mainView = view
       } else {
           mainView?.removeFromSuperview()
           self.mainView = view
       }
       needsLayout = true
   }
   
   func changeState(selectState:Bool, animated:Bool) {
       assert(mainView != nil)
       
       self.isSelectionState = selectState
       
   }
   
   
   override func layout() {
       
       super.layout()
       let inset:CGFloat = isSelectionState ? 40 : 0
       segmentPanelView.frame = NSMakeRect(0, 0, frame.width, SegmentContainerView.height)
       contentContainerView.frame = NSMakeRect(0, segmentPanelView.frame.maxY, frame.width, max(0, frame.height - inset - segmentPanelView.frame.maxY))
       contentContainerView.setCorners(self.corners)
       mainView?.frame = contentContainerView.bounds
       

   }
   
   required init?(coder: NSCoder) {
       fatalError("init(coder:) has not been implemented")
   }
   
}


enum StorageUsageCollection : Int32 {
    case peers
    case media
    case files
    case music
    case voice
    
    var title: String {
        switch self {
        case .peers:
            return strings().storageUsageSegmentChats
        case .media:
            return strings().storageUsageSegmentMedia
        case .files:
            return strings().storageUsageSegmentFiles
        case .music:
            return strings().storageUsageSegmentMusic
        case .voice:
            return strings().storageUsageSegmentVoice
        }
    }
}



class StorageUsageBlockController<Context: AccountContextProtocol>: TelegramGenericViewController<StorageUsageMediaContainerView, Context>, StorageUsageBlockControlling {
    var mediaView: View { genericView }
    var mainTable: TableView? { genericView.mainTable }
   
    
    private let members: ViewController
    private let media: ViewController
    private let files: ViewController
    private let music: ViewController
    private let voice: ViewController

    private var currentController: ViewController?

    private var mode: StorageUsageCollection?
   
    private let toggleDisposable = MetaDisposable()
    private let disposable = MetaDisposable()

    
    var currentMainTableView:((TableView?, Bool, Bool)->Void)? = nil {
        didSet {
            if isLoaded() {
                currentMainTableView?(genericView.mainTable, false, false)
            }
        }
    }
    
    private let stateSignal:Signal<StorageUsageUIState, NoError>
    private let updateState:((StorageUsageUIState)->StorageUsageUIState)->StorageUsageUIState
   
    init(context: Context, storageArguments: StorageUsageArguments<Context>, state: Signal<StorageUsageUIState, NoError>, updateState:@escaping((StorageUsageUIState)->StorageUsageUIState)->StorageUsageUIState) {
        self.updateState = updateState
        self.stateSignal = state
        
        self.members = StorageUsage_Block_Chats(context: context, storageArguments: storageArguments, state: state, updateState: updateState)
        self.files = StorageUsage_Block_MediaList(context: context, storageArguments: storageArguments, tag: .files, state: state, updateState: updateState)
        self.media = StorageUsage_Block_MediaList(context: context, storageArguments: storageArguments, tag: .media, state: state, updateState: updateState)
        self.music = StorageUsage_Block_MediaList(context: context, storageArguments: storageArguments, tag: .music, state: state, updateState: updateState)
        self.voice = StorageUsage_Block_MediaList(context: context, storageArguments: storageArguments, tag: .voice, state: state, updateState: updateState)
        super.init(context)
        
        self.navigationController = context.bindings.rootNavigation()
   }

   var unableToHide: Bool {
       return !onTheTop
   }
   
   override func viewDidAppear(_ animated: Bool) {
       super.viewDidAppear(animated)
       
       if let mode = self.mode {
           self.controller(for: mode).viewDidAppear(animated)
       }
   }
    
   
   override func viewDidDisappear(_ animated: Bool) {
       super.viewDidDisappear(animated)
       
       if let mode = mode {
           let controller = self.controller(for: mode)
           controller.viewDidDisappear(animated)
       }
       
   }
   
   override func viewWillAppear(_ animated: Bool) {
       super.viewWillAppear(animated)
       
       if let mode = mode {
           let controller = self.controller(for: mode)
           controller.viewWillAppear(animated)
       }
   }
   
   override func viewWillDisappear(_ animated: Bool) {
       super.viewWillDisappear(animated)
       window?.removeAllHandlers(for: self)
       
       if let mode = mode {
           let controller = self.controller(for: mode)
           controller.viewWillDisappear(animated)
       }
   }
   
   
   func isEqual(to other: Notifable) -> Bool {
       if let other = other as? StorageUsagePeerMediaController {
           return self == other
       }
       return false
   }
   
   override func viewDidLoad() {
       super.viewDidLoad()
       
       
       
       _ = self.context
       
       
       let data: Signal<StorageUsageUIState, NoError> = stateSignal |> deliverOnMainQueue |> mapToSignal { [weak self] state in
           guard let `self` = self else {
               return .complete()
           }
           var list:[StorageUsageCollection : ViewController] = [:]
           list[.peers] = self.members
           list[.files] = self.files
           list[.media] = self.media
           list[.music] = self.music
           list[.voice] = self.voice

           if let collection = state.effectiveCollection {
               let controller = list[collection]!
               if !controller.isLoaded() {
                   controller.loadViewIfNeeded(self.genericView.view.bounds)
               }
               return controller.ready.get() |> map { ready in
                   return state
               }
           } else {
               return .complete()
           }
           
       } |> distinctUntilChanged(isEqual: { lhs, rhs in
           if lhs.messages != rhs.messages {
               return false
           } else if lhs.segments != rhs.segments {
               return false
           } else if lhs.collection != rhs.collection {
               return false
           } else {
               return true
           }
       }) |> deliverOnMainQueue
       
       let ready = data |> map { _ in return true } |> take(1)
       
       self.ready.set(ready)
       
       genericView.segmentPanelView.didSelect = { [weak self] newMode in
           
           if newMode == self?.mode, let mainTable = self?.genericView.mainTable {
               self?.currentMainTableView?(mainTable, true, true)
           }
           _ = self?.updateState { current in
               var current = current
               current.collection = newMode
               return current
           }
       }
       
       var first = true

       disposable.set(data.start(next: { [weak self] state in
           guard let `self` = self else {
               return
           }
           self.genericView.segmentPanelView.update(collections: state.segments, selected: state.effectiveCollection, animated: !first)
           
           if let collection = state.effectiveCollection {
               self.toggle(with: collection, animated: !first)
           }
           
           first = false
           
           if state.segments.isEmpty {
               if self.genericView.superview != nil {
                   self.viewWillDisappear(true)
                   self.genericView.removeFromSuperview()
                   self.viewDidDisappear(true)
               }
           }
       }))

   }
   
   
   private func applyReadyController(mode: StorageUsageCollection, animated: Bool) {
       genericView.mainTable?.updatedItems = nil
       let oldMode = self.mode
       
       let previous = self.currentController
       
       let controller = self.controller(for: mode)
       
       self.currentController = controller
       controller.viewWillAppear(animated)
       previous?.viewWillDisappear(animated)
       let animation: AnimationDirection?
       
       if animated, let oldMode = oldMode {
           if oldMode.rawValue > mode.rawValue {
               animation = .rightToLeft
           } else {
               animation = .leftToRight
           }
       } else {
           animation = nil
       }
       
       genericView.updateMainView(with: controller.view, animated: animation)
       controller.viewDidAppear(animated)
       previous?.viewDidDisappear(animated)
       
       var firstUpdate: Bool = true
       genericView.mainTable?.updatedItems = { [weak self] items in
           let filter = items.filter {
               !($0 is StorageUsageEmptyRowItem) && !($0.className == "Telegram.GeneralRowItem") && !($0 is SearchEmptyRowItem)
           }
           self?.genericView.updateCorners(filter.isEmpty ? .all : [.topLeft, .topRight], animated: !firstUpdate)
           firstUpdate = false
       }
       self.currentMainTableView?(genericView.mainTable, animated, previous != controller && genericView.segmentPanelView.contains(oldMode))
       
   }
   
   private func controller(for mode: StorageUsageCollection) -> ViewController {
       switch mode {
       case .media:
           return self.media
       case .music:
           return self.music
       case .files:
           return self.files
       case .peers:
           return self.members
       case .voice:
           return self.voice
       }
   }
   
   private func toggle(with mode:StorageUsageCollection, animated:Bool = false) {
       let isUpdated = self.mode != mode
       if isUpdated {
           let controller: ViewController = self.controller(for: mode)

           let ready = controller.ready.get() |> take(1)
           
           toggleDisposable.set(ready.start(next: { [weak self] _ in
               self?.applyReadyController(mode: mode, animated: animated)
           }))
       } else {
           self.currentMainTableView?(genericView.mainTable, animated, true)
       }
       self.mode = mode
   }
   
   deinit {
       disposable.dispose()
       toggleDisposable.dispose()
   }
   
   override func updateLocalizationAndTheme(theme: PresentationTheme) {
       super.updateLocalizationAndTheme(theme: theme)
       
   }
   
   override func escapeKeyAction() -> KeyHandlerResult {
       return super.escapeKeyAction()
   }
    
    var onTheTop: Bool {
        return true
    }
   
   
   override var defaultBarTitle: String {
       return localizedString("Telegram.StorageUsageBlockController")
   }
   
   override func backSettings() -> (String, CGImage?) {
       return super.backSettings()
   }
   
   override func didRemovedFromStack() {
       super.didRemovedFromStack()
   }
   
}




