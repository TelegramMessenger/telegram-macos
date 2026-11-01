import Cocoa
import SwiftSignalKit
import ColorPalette

private var _theme:Atomic<PresentationTheme> = Atomic(value: defaultPresentation)
let presentationThemeUpdates = ValuePipe<PresentationTheme>()

private let defaultPresentation = PresentationTheme(colors: whitePalette, search: SearchTheme(.grayBackground, #imageLiteral(resourceName: "Icon_SearchField").precomposed(), #imageLiteral(resourceName: "Icon_SearchClear").precomposed(), {localizedString("SearchField.Search")}, .text, .grayText), inputTheme: .init(quote: .init(foreground: .init(main: NSColor.accent), icon: NSImage(named: "Icon_Quote")!, collapse: NSImage(named: "Icon_Quote_Collapse")!, expand: NSImage(named: "Icon_Quote_Expand")!), indicatorColor: NSColor.accent, backgroundColor: NSColor.grayBackground, selectingColor: NSColor.selectText, textColor: NSColor.textColor, accentColor: NSColor.accent, grayTextColor: NSColor.grayText, fontSize: 13))



public var presentation:PresentationTheme {
    // Read-only access under the lock: `modify {$0}` would redundantly re-store the value (a
    // retain/release) on every read, and this is read on nearly every cell layout/draw.
    return _theme.with {$0}
}

public func updateTheme(_ theme:PresentationTheme) {
    assertOnMainThread()
    _ = _theme.swap(theme)
    presentationThemeUpdates.putNext(theme)
}

open class PresentationTheme : Equatable {
    
    public let colors:ColorPalette
    public let search: SearchTheme
    public let inputTheme: InputViewTheme
    
    public let resourceCache = PresentationsResourceCache()
    
    public init(colors: ColorPalette, search: SearchTheme, inputTheme: InputViewTheme) {
        self.colors = colors
        self.search = search
        self.inputTheme = inputTheme
    }
    
    public static var current: PresentationTheme {
        return presentation
    }
    
    public static func ==(lhs: PresentationTheme, rhs: PresentationTheme) -> Bool {
        // Dispatch via an overridable instance method so subclasses
        // (TelegramPresentationTheme) can define value-based equality —
        // a `static func ==` on a subclass would only shadow this one and
        // never be called when the call site sees the parent's type.
        return lhs.isEqual(rhs)
    }

    open func isEqual(_ other: PresentationTheme) -> Bool {
        return self === other
    }
}


public extension PresentationTheme {
    var appearance: NSAppearance {
        return colors.appearance
    }
}
