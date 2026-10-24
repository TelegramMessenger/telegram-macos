import Cocoa
import AppKit

private class TabBarViewController : View {
    let tabView:TabBarView
    let pocketArea: ScrollPocketArea?
    var contentExtendsUnderTabBar: Bool = false
    var pocketTopExtension: CGFloat = 0 {
        didSet {
            if pocketTopExtension != oldValue {
                needsLayout = true
            }
        }
    }

    
    required init(frame frameRect: NSRect) {
        tabView = TabBarView(frame: NSMakeRect(0, frameRect.height - 50, frameRect.width, 50))
        pocketArea = System.edgeToEdgeSidebar ? ScrollPocketArea(frame: tabView.frame, style: .soft) : nil
        super.init(frame: frameRect)
        if let pocketArea {
            addSubview(pocketArea)
        }
        addSubview(tabView)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.background = .clear
    }

    var tabBarHeight: CGFloat {
        return tabView.isHidden ? 0 : tabView.frame.height
    }

    func contentFrame(_ size: NSSize) -> NSRect {
        if tabView.isHidden || contentExtendsUnderTabBar {
            return NSMakeRect(0, 0, size.width, size.height)
        }
        return NSMakeRect(0, 0, size.width, size.height - tabView.frame.height)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        for subview in subviews {
            if subview is TabBarView {
                transition.updateFrame(view: subview, frame: NSMakeRect(0, frame.height - 50, frame.width, 50))
            } else if subview === pocketArea {
                let extensionHeight = tabView.isHidden ? 0 : pocketTopExtension
                transition.updateFrame(view: subview, frame: NSMakeRect(0, frame.height - 50 - extensionHeight, frame.width, 50 + extensionHeight))
            } else {
                transition.updateFrame(view: subview, frame: contentFrame(frame.size))
            }
        }
    }
    
    override func layout() {
        super.layout()
        updateFrame(frame, transition: .immediate)
    }
}

public class TabBarController: ViewController, TabViewDelegate {

    
    public var didChangedIndex:(Int)->Void = {_ in}
    
    public weak var current:ViewController? {
        didSet {
            current?.navigationController = self.navigationController
        }
    }
    
    public override var navigationController: NavigationViewController? {
        didSet {
            current?.navigationController = self.navigationController
        }
    }
    
    public override var redirectUserInterfaceCalls: Bool {
        return true
    }

    public var extendsContentUnderTabBar: (ViewController) -> Bool = { _ in false }

    public var tabBarHeight: CGFloat {
        return genericView.tabBarHeight
    }

    public var tabBarView: NSView {
        return genericView.pocketArea ?? genericView.tabView
    }

    public var pocketTopExtension: CGFloat {
        get {
            return genericView.pocketTopExtension
        }
        set {
            genericView.pocketTopExtension = newValue
        }
    }
    
    private var genericView:TabBarViewController {
        return view as! TabBarViewController
    }
    
    public override func viewClass() -> AnyClass {
        return TabBarViewController.self
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        genericView.tabView.enumerateItems({ item in
            if item.controller.isLoaded() {
                item.controller.updateLocalizationAndTheme(theme: theme)
            }
            return false
        })
    }
    
    public override func loadView() {
        super.loadView()
        genericView.tabView.delegate = self
        genericView.autoresizingMask = []
    }
    
    public func didChange(selected item: TabItem, index: Int) {
        
        let animated = current != nil
        
        if current != item.controller {
            if let current = current {
                _ = current.window?.makeFirstResponder(nil)
                current.viewWillDisappear(false)
                if animated {
                    current.view.layer?.animateAlpha(from: 1, to: 0, duration: 0.15, removeOnCompletion: false, completion: { [weak current] _ in
                        current?.view.removeFromSuperview()
                    })
                } else {
                    current.view.removeFromSuperview()
                }
                current.viewDidDisappear(false)
            }
            genericView.contentExtendsUnderTabBar = extendsContentUnderTabBar(item.controller)
            item.controller._frameRect = genericView.contentFrame(bounds.size)
            item.controller.view.frame = item.controller._frameRect
            item.controller.viewWillAppear(false)
            view.addSubview(item.controller.view, positioned: .below, relativeTo: genericView.tabView)
            if animated {
                item.controller.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.15)
            }
            item.controller.viewDidAppear(false)
            current = item.controller
            didChangedIndex(index)
        }
    }
    
    public func scrollup() {
        current?.scrollup()
    }
    
    public func control(for index: Int) -> Control {
        return self.genericView.tabView.control(for: index)
    }
    
    public func hideTabView(_ hide:Bool) {
        genericView.tabView.isHidden = hide
        current?.view.frame = genericView.contentFrame(bounds.size)
        
    }
    
    public override func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        super.updateFrame(frame, transition: transition)
        self.genericView.updateFrame(frame, transition: transition)
    }
    
    public func select(index:Int) -> Void {
        if index != self.genericView.tabView.selectedIndex {
            genericView.tabView.setSelectedIndex(index, respondToDelegate: true, animated: false)
        }
    }
    
    public var count: Int {
        return genericView.tabView.count
    }
    
    public func add(tab:TabItem) -> Void {
        genericView.tabView.addTab(tab)
    }
    public func tab(at index:Int) -> TabItem {
        return genericView.tabView.tab(at: index)
    }
    public func replace(tab: TabItem, at index:Int) -> Void {
        genericView.tabView.replaceTab(tab, at: index)
    }
    public func insert(tab: TabItem, at index: Int) -> Void {
        genericView.tabView.insertTab(tab, at: index)
    }
    public func remove(at index: Int) -> Void {
        genericView.tabView.removeTab(at: index)
    }
    public var isEmpty:Bool {
        return genericView.tabView.isEmpty
    }
    public func showTooltip(text: String, for index: Int) -> Void {
        genericView.tabView.showTooltip(text: text, for: index)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.current?.viewWillAppear(animated)
    }
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.current?.viewDidAppear(animated)
    }
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.current?.viewWillDisappear(animated)
    }
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.current?.viewDidDisappear(animated)
    }
}
