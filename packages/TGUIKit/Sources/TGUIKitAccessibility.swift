import AppKit

public enum TGUIKitAccessibility {
    public static var isEnabled: Bool = true

    public static func parent(of view: NSView, default fallback: () -> Any?) -> Any? {
        guard isEnabled else {
            return nil
        }
        if let row = view.superview as? NSTableRowView {
            return row
        }
        return fallback()
    }
}

public struct AccessibilityIssue: Equatable, CustomStringConvertible {
    public enum Kind: String {
        case unlabeledControl
        case unlabeledImage
        case emptyText
        case unreachableControl
    }

    public let kind: Kind
    public let path: String

    public var description: String {
        return "\(kind.rawValue): \(path)"
    }
}

public enum AccessibilityAudit {
    private static let interactiveRoles: Set<NSAccessibility.Role> = [
        .button, .checkBox, .radioButton, .popUpButton, .menuButton, .link, .slider, .incrementor, .disclosureTriangle,
        .textField, .textArea, .comboBox,
    ]
    private static let minimumImageSide: CGFloat = 12

    public static func audit(_ window: NSWindow) -> [AccessibilityIssue] {
        guard let contentView = window.contentView else {
            return []
        }
        return audit(contentView)
    }

    public static func audit(_ root: NSView) -> [AccessibilityIssue] {
        var issues: [AccessibilityIssue] = []
        var visited = Set<ObjectIdentifier>()
        walkAccessibility(root, path: name(of: root), issues: &issues, visited: &visited, depth: 0)
        walkViews(root, path: name(of: root), representedByAncestor: false, issues: &issues)
        return issues
    }

    public static func elements(_ root: NSView) -> [NSAccessibilityProtocol] {
        var result: [NSAccessibilityProtocol] = []
        var visited = Set<ObjectIdentifier>()
        collect(root, into: &result, visited: &visited, depth: 0)
        return result
    }

    private static func collect(_ element: NSAccessibilityProtocol, into result: inout [NSAccessibilityProtocol], visited: inout Set<ObjectIdentifier>, depth: Int) {
        guard depth < 64, visited.insert(ObjectIdentifier(element as AnyObject)).inserted else {
            return
        }
        if element.isAccessibilityElement() {
            result.append(element)
        }
        for child in children(of: element) {
            collect(child, into: &result, visited: &visited, depth: depth + 1)
        }
    }

    private static func walkAccessibility(_ element: NSAccessibilityProtocol, path: String, issues: inout [AccessibilityIssue], visited: inout Set<ObjectIdentifier>, depth: Int) {
        guard depth < 64, visited.insert(ObjectIdentifier(element as AnyObject)).inserted else {
            return
        }
        if element.isAccessibilityElement(), let role = element.accessibilityRole() {
            let label = text(element.accessibilityLabel()) ?? text(element.accessibilityTitle())
            if interactiveRoles.contains(role), label == nil {
                issues.append(AccessibilityIssue(kind: .unlabeledControl, path: path))
            } else if role == .image, label == nil {
                issues.append(AccessibilityIssue(kind: .unlabeledImage, path: path))
            } else if role == .staticText, text(element.accessibilityValue() as? String) == nil, label == nil {
                issues.append(AccessibilityIssue(kind: .emptyText, path: path))
            }
        }
        if element.accessibilityRole() == .scrollBar {
            return
        }
        for child in children(of: element) {
            walkAccessibility(child, path: path + " > " + name(of: child), issues: &issues, visited: &visited, depth: depth + 1)
        }
    }

    private static func walkViews(_ view: NSView, path: String, representedByAncestor: Bool, issues: inout [AccessibilityIssue]) {
        guard !view.isHidden, view.alphaValue > 0 else {
            return
        }
        let isElement = view.isAccessibilityElement()
        if !representedByAncestor, !isElement {
            if let control = view as? Control, control.hasHandlers, control.isEnabled, control.userInteractionEnabled, !control.isAccessibilityDecorative {
                issues.append(AccessibilityIssue(kind: .unreachableControl, path: path))
            } else if let imageView = view as? ImageView, imageView.image != nil, !imageView.isAccessibilityDecorative, imageView.frame.width >= minimumImageSide, imageView.frame.height >= minimumImageSide {
                issues.append(AccessibilityIssue(kind: .unlabeledImage, path: path))
            }
        }
        for subview in view.subviews {
            walkViews(subview, path: path + " > " + name(of: subview), representedByAncestor: representedByAncestor || isElement, issues: &issues)
        }
    }

    private static func children(of element: NSAccessibilityProtocol) -> [NSAccessibilityProtocol] {
        let object = element as AnyObject
        let selector = #selector(NSAccessibilityProtocol.accessibilityChildren)
        guard object.responds(to: selector), let array = object.perform(selector)?.takeUnretainedValue() as? NSArray else {
            return []
        }
        return array.compactMap { $0 as? NSAccessibilityProtocol }
    }

    private static func text(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func name(of element: Any) -> String {
        let type = String(describing: Swift.type(of: element as AnyObject))
        if let element = element as? NSAccessibilityProtocol, let label = text(element.accessibilityLabel()) {
            return "\(type)(\(label))"
        }
        return type
    }
}
