import Cocoa

import TelegramCore

import TGUIKit
import TelegramTheme
import TelegramUtils
import TelegramContext

public enum InstantPageTextStyle {
    case fontSize(CGFloat)
    case lineSpacingFactor(CGFloat)
    case fontSerif(Bool)
    case fontFixed(Bool)
    case bold
    /// Baseline semibold / medium weights. Used by button pills, whose labels carry their own weight
    /// regardless of the surrounding paragraph.
    case semibold
    case medium
    case italic
    case underline
    case strikethrough
    case textColor(NSColor)
    case `subscript`
    case superscript
    case markerColor(NSColor)
    case marker
    case anchor(String, Bool)
    case linkColor(NSColor)
    case linkMarkerColor(NSColor)
    case link(Bool)
}

extension NSAttributedString.Key {
    public static let instantPageLineSpacingFactorAttribute = NSAttributedString.Key("InstantPageLineSpacingFactorAttribute")
    public static let instantPageMarkerColorAttribute = NSAttributedString.Key("InstantPageMarkerColorAttribute")
    public static let instantPageMediaIdAttribute = NSAttributedString.Key("InstantPageMediaIdAttribute")
    public static let instantPageMediaDimensionsAttribute = NSAttributedString.Key("InstantPageMediaDimensionsAttribute")
    public static let instantPageAnchorAttribute = NSAttributedString.Key("InstantPageAnchorAttribute")
    public static let instantPageFormulaAttribute = NSAttributedString.Key("InstantPageFormulaAttribute")
    public static let instantPageInlineButtonAttribute = NSAttributedString.Key("InstantPageInlineButtonAttribute")
    public static let instantPageStrikethroughAttribute = NSAttributedString.Key("InstantPageStrikethroughAttribute")
}

private func instantPageSansFont(
    size: CGFloat,
    bold: Bool,
    semibold: Bool,
    medium: Bool,
    italic: Bool
) -> NSFont {
    let baseFont: NSFont
    if bold {
        baseFont = NSFont.bold(size)
    } else if semibold {
        baseFont = NSFont.semibold(size)
    } else if medium {
        baseFont = NSFont.medium(size)
    } else {
        baseFont = NSFont.normal(size)
    }

    if italic {
        return NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    } else {
        return baseFont
    }
}


public final class InstantPageTextStyleStack {
    private var items: [InstantPageTextStyle] = []

    public let buttonsEnabled: Bool

    public init(buttonsEnabled: Bool = true) {
        self.buttonsEnabled = buttonsEnabled
    }
    
    public func push(_ item: InstantPageTextStyle) {
        items.append(item)
    }
    
    public func pop() {
        if !items.isEmpty {
            items.removeLast()
        }
    }
    
    public func textAttributes() -> [NSAttributedString.Key: Any] {
        var fontSize: CGFloat?
        var fontSerif: Bool?
        var fontFixed: Bool?
        var bold: Bool?
        var semibold: Bool?
        var medium: Bool?
        var italic: Bool?
        var strikethrough: Bool?
        var underline: Bool?
        var color: NSColor?
        var lineSpacingFactor: CGFloat?
        var baselineOffset: CGFloat?
        var markerColor: NSColor?
        var marker: Bool?
        var anchor: Dictionary<String, Any>?
        var linkColor: NSColor?
        var linkMarkerColor: NSColor?
        var link: Bool?
        
        for item in self.items.reversed() {
            switch item {
            case let .fontSize(value):
                if fontSize == nil {
                    fontSize = value
                }
            case let .fontSerif(value):
                if fontSerif == nil {
                    fontSerif = value
                }
            case let .fontFixed(value):
                if fontFixed == nil {
                    fontFixed = value
                }
            case .bold:
                if bold == nil {
                    bold = true
                }
            case .semibold:
                if semibold == nil {
                    semibold = true
                }
            case .medium:
                if medium == nil {
                    medium = true
                }
            case .italic:
                if italic == nil {
                    italic = true
                }
            case .strikethrough:
                if strikethrough == nil {
                    strikethrough = true
                }
            case .underline:
                if underline == nil {
                    underline = true
                }
            case let .textColor(value):
                if color == nil {
                    color = value
                }
            case let .lineSpacingFactor(value):
                if lineSpacingFactor == nil {
                    lineSpacingFactor = value
                }
            case .subscript:
                if baselineOffset == nil {
                    baselineOffset = 0.35
                    underline = false
                }
            case .superscript:
                if baselineOffset == nil {
                    baselineOffset = -0.35
                }
            case let .markerColor(color):
                if markerColor == nil {
                    markerColor = color
                }
            case .marker:
                if marker == nil {
                    marker = true
                }
            case let .anchor(name, empty):
                if anchor == nil {
                    anchor = ["name": name, "empty": empty]
                }
            case let .linkColor(color):
                if linkColor == nil {
                    linkColor = color
                }
            case let .linkMarkerColor(color):
                if linkMarkerColor == nil {
                    linkMarkerColor = color
                }
            case let .link(instant):
                if link == nil {
                    link = instant
                }
            }
        }
        
        var attributes: [NSAttributedString.Key: Any] = [:]
        
        var parsedFontSize: CGFloat
        if let fontSize = fontSize {
            parsedFontSize = fontSize
        } else {
            parsedFontSize = 16.0
        }
        
        if let baselineOffset = baselineOffset {
            attributes[.baselineOffset] = round(parsedFontSize * baselineOffset);
            parsedFontSize = round(parsedFontSize * 0.85)
        }
        
        let isBold = bold == true
        let isSemibold = semibold == true
        let isMedium = medium == true
        let isItalic = italic == true

        if fontSerif == true, isSemibold || isMedium {
            // Georgia ships only Regular and Bold, so a weighted serif run resolves to the system
            // serif design (New York), which has real Medium and Semibold faces. Bold and italic
            // inside such a run stay in the same family — falling through to the Georgia arms below
            // would mix two serif families mid-line inside a single heading.
            let weightedFace: NSFont.Weight = isSemibold ? .semibold : .medium
            attributes[.font] = NSFont.serif(parsedFontSize, weight: isBold ? .bold : weightedFace, italic: isItalic)
        } else if fontSerif == true {
            if isBold && isItalic {
                attributes[.font] = NSFont(name: "Georgia-BoldItalic", size: parsedFontSize)
            } else if isBold {
                attributes[.font] = NSFont(name: "Georgia-Bold", size: parsedFontSize)
            } else if isItalic {
                attributes[.font] = NSFont(name: "Georgia-Italic", size: parsedFontSize)
            } else {
                attributes[.font] = NSFont(name: "Georgia", size: parsedFontSize)
            }
        } else if fontFixed == true {
            if isBold && isItalic {
                attributes[.font] = NSFont(name: "Menlo-BoldItalic", size: parsedFontSize)
            } else if isBold {
                attributes[.font] = NSFont(name: "Menlo-Bold", size: parsedFontSize)
            } else if isItalic {
                attributes[.font] = NSFont(name: "Menlo-Italic", size: parsedFontSize)
            } else {
                attributes[.font] = NSFont(name: "Menlo", size: parsedFontSize)
            }
        } else {
            attributes[.font] = instantPageSansFont(
                size: parsedFontSize,
                bold: isBold,
                semibold: isSemibold,
                medium: isMedium,
                italic: isItalic
            )
        }
        
        if strikethrough != nil && strikethrough! {
            attributes[.instantPageStrikethroughAttribute] = NSNumber(value: true)
        }
        
        if underline != nil && underline! {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue as NSNumber
        }
        
        if let link = link, let linkColor = linkColor {
            attributes[.foregroundColor] = linkColor
            if link, let linkMarkerColor = linkMarkerColor {
                attributes[.instantPageMarkerColorAttribute] = linkMarkerColor
            }
        } else {
            if let color = color {
                attributes[.foregroundColor] = color
            } else {
                attributes[.foregroundColor] = NSColor.black
            }
        }
        
        if let lineSpacingFactor = lineSpacingFactor {
            attributes[.instantPageLineSpacingFactorAttribute] = lineSpacingFactor as NSNumber
        }
        
        if marker != nil && marker!, let markerColor = markerColor {
            attributes[.instantPageMarkerColorAttribute] = markerColor
        }
        
        if let anchor = anchor {
            attributes[.instantPageAnchorAttribute] = anchor
        }
        
        return attributes
    }
}
