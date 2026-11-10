import Foundation
import KeyboardKey
import AppKit

open class CodeEntryControl : View {
    
    public class CodeEntryElement : Control {
        private var textView: TextView? = nil
        private var current: UInt16? = nil
        
        
        
        public var prev:((Control, Bool)->Void)?
        public var next:((Control, Bool)->Void)?
        public var invoke:(()->Void)?

        public var insertAll:(([Int])->Void)?
        
        public var locked: Bool = false

        public var accessibilityPosition: Int = 0
        public var accessibilityTotal: Int = 0
        public var accessibilityLabelProvider: ((Int, Int) -> String?)?

        public override func accessibilityRole() -> NSAccessibility.Role? {
            return .textField
        }

        public override func accessibilityLabel() -> String? {
            if let provider = accessibilityLabelProvider, let label = provider(accessibilityPosition + 1, accessibilityTotal), !label.isEmpty {
                return label
            }
            return super.accessibilityLabel()
        }

        public override func accessibilityValue() -> Any? {
            guard let current = current else {
                return nil
            }
            return "\(current)"
        }

        public override func accessibilityPerformPress() -> Bool {
            guard !locked, userInteractionEnabled else {
                return false
            }
            return window?.makeFirstResponder(self) ?? false
        }

        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            layer?.cornerRadius = 10
            updateLocalizationAndTheme(theme: presentation)
            self.set(handler: { control in
                control.window?.makeFirstResponder(control)
            }, for: .Click)
        }
        
        public var value: String {
            if let current = current {
                return "\(current)"
            } else {
                return ""
            }
        }
        
        @objc public func paste(_ id: Any) {
            let pasteboard = NSPasteboard.general
            guard let items = pasteboard.pasteboardItems else {
                return
            }
            for item in items {
                let string = item.string(forType: .string)?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let string = string, !string.isEmpty {
                    let chars = Array(string).map { String($0) }
                    self.insertAll?(chars.compactMap { Int($0) })
                    break
                }
            }
        }
        
        public override func keyUp(with event: NSEvent) {
            super.keyUp(with: event)
        }
        
        public override func keyDown(with event: NSEvent) {
            super.keyDown(with: event)
            
            guard !locked else {
                return
            }
            
            if let keyCode = KeyboardKey(rawValue: event.keyCode) {
                switch keyCode {
                case .Delete:
                    self.inputKey(nil, animated: true)
                    prev?(self, false)
                case .Tab:
                    next?(self, true)
                case .LeftArrow:
                    prev?(self, true)
                case .RightArrow:
                    next?(self, true)
                case .Return:
                    invoke?()
                default:
                    self.inputKey(event.keyCode, animated: true)
                }
            }
        }
        
        private func updateTextView() {
            if let textView = textView, let current = self.current {
                let layout = TextViewLayout(.initialize(string: "\(current)", color: locked ? presentation.colors.grayText : presentation.colors.text, font: .code(24)))
                layout.measure(width: .greatestFiniteMagnitude)
                textView.update(layout)
            }
        }
        
        public func inputKey(_ keyCode: UInt16?, animated: Bool) {
            if let keyCode = keyCode {
                if let number = KeyboardKey(rawValue: keyCode)?.number {
                    if self.current != number {
                        if let view = textView {
                            performSubviewRemoval(view, animated: animated, duration: 0.2, scale: true)
                        }
                        let textView = TextView()
                        self.textView = textView
                        addSubview(textView)
                        let layout = TextViewLayout(.initialize(string: "\(number)", color: presentation.colors.text, font: .code(24)))
                        layout.measure(width: .greatestFiniteMagnitude)
                        textView.update(layout)
                        textView.centerX(y: 7)
                        textView.userInteractionEnabled = false
                        textView.isSelectable = false
                        textView.isEventLess = true
                        if animated {
                            textView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                            textView.layer?.animatePosition(from: NSMakePoint(textView.frame.minX, textView.frame.minY + 5), to: textView.frame.origin)
                            textView.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
                        }
                    }
                    self.current = number
                    NSAccessibility.post(element: self, notification: .valueChanged)
                    self.next?(self, false)
                } else {
                    self.shake(beep: true)
                }
            } else {
                if let view = textView {
                    performSubviewRemoval(view, animated: animated, duration: 0.2, scale: true)
                }
                self.textView = nil
                self.current = nil
                NSAccessibility.post(element: self, notification: .valueChanged)
            }
        }
        
        public override func layout() {
            super.layout()
            textView?.centerX(y: 7)
        }
        
        public override func updateLocalizationAndTheme(theme: PresentationTheme) {
            super.updateLocalizationAndTheme(theme: theme)
            layer?.borderWidth = .borderSize
            background = presentation.colors.grayBackground
        }
        
        public var isFirstResponder: Bool {
            return window?.firstResponder == self
        }
        
        private func updateResponder(animated: Bool) {
            layer?.borderColor = isFirstResponder && !locked ? presentation.colors.accent.cgColor : .clear
            if animated {
                layer?.animateBorder()
            }
        }
        
        public override func resignFirstResponder() -> Bool {
            DispatchQueue.main.async {
                self.updateResponder(animated: true)
            }
            return true
        }
        
        public override func becomeFirstResponder() -> Bool {
            DispatchQueue.main.async {
                self.updateResponder(animated: true)
            }
            return true
        }
        
        public func set(locked: Bool, animated: Bool) {
            self.locked = locked
            updateResponder(animated: animated)
            updateTextView()
        }
        
        public func clear() {
            inputKey(nil, animated: true)
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    
    public var takeNext:((String)->Void)?
    public var takeError:(()->Void)?
    public var accessibilityElementLabel: ((Int, Int) -> String?)?

    public var locked: Bool = false
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    
    public func moveToStart() {
        let subviews = self.subviews.compactMap { $0 as? CodeEntryElement }
        for subview in subviews {
            subview.clear()
        }
        let subview = self.subviews.compactMap { $0 as? CodeEntryElement }.first
        window?.makeFirstResponder(subview)
    }
    
    public func set(locked: Bool, animated: Bool) {
        self.locked = locked
        let subviews = self.subviews.compactMap { $0 as? CodeEntryElement }
        for subview in subviews {
            subview.set(locked: locked, animated: animated)
        }
    }
    
    public func update(count: Int) -> NSSize {
        while subviews.count > count {
            subviews.removeLast()
        }
        while subviews.count < count {
            let element = CodeEntryElement(frame: NSMakeRect(0, 0, 40, 40))
            
            element.next = { [weak self] control, flip in
                self?.next(control, flip)
            }
            element.prev = { [weak self] control, flip in
                self?.prev(control, flip)
            }
            element.invoke = { [weak self] in
                self?.invoke()
            }
            element.insertAll = { [weak self] values in
                self?.insertAll(values)
            }
            
            subviews.append(element)
        }
        needsLayout = true
        return NSMakeSize(subviewsSize.width + (CGFloat(subviews.count - 1) * 8) + 20, 40)
    }
    
    public func insertAll(_ values: [Int]) {
        let subviews = self.subviews.compactMap { $0 as? CodeEntryElement }
        if values.count == subviews.count {
            for (i, subview) in subviews.enumerated() {
                let value = values[i]
                if let keyboardKey = KeyboardKey.keyboardKey(value)?.rawValue {
                    subview.inputKey(keyboardKey, animated: true)
                }
            }
            window?.makeFirstResponder(subviews.last)
            self.invoke()
        }
    }
    
    public var value: String {
        let values = self.subviews.compactMap { $0 as? CodeEntryElement }
        return values.reduce("", { current, value in
            return current + value.value
        })
    }
  
    public override func layout() {
        super.layout()
        var x: CGFloat = 10
        let elements = subviews.compactMap { $0 as? CodeEntryElement }
        for (index, subview) in elements.enumerated() {
            subview.setFrameOrigin(NSMakePoint(x, 0))
            subview.accessibilityPosition = index
            subview.accessibilityTotal = elements.count
            subview.accessibilityLabelProvider = accessibilityElementLabel
            x += subview.frame.width + 8
        }
    }
    
    public func firstResponder() -> NSResponder? {
        for subview in subviews {
            if window?.firstResponder == subview {
                return subview
            }
        }
        return subviews.first
    }
    public func prev(_ current: Control, _ flip: Bool) {
        let subviews = self.subviews.compactMap { $0 as? CodeEntryElement }
        if let index = subviews.firstIndex(where: { $0 == current }) {
            if index > 0 {
                let view = subviews[index - 1]
                window?.makeFirstResponder(view)
            } else if flip {
                let view = subviews[subviews.count - 1]
                window?.makeFirstResponder(view)
            }
        }
    }
    public func next(_ current: Control, _ flip: Bool) {
        if !flip {
            takeError?()
        }
        let subviews = self.subviews.compactMap { $0 as? CodeEntryElement }
        if let index = subviews.firstIndex(where: { $0 == current }) {
            if index < subviews.count - 1 {
                let view = subviews[index + 1]
                window?.makeFirstResponder(view)
            } else if flip {
                let view = subviews[0]
                window?.makeFirstResponder(view)
            } else if let index = subviews.firstIndex(where: { $0.value.isEmpty }) {
                let view = subviews[index]
                window?.makeFirstResponder(view)
            }
            if value.length == subviews.count, index == subviews.count - 1 {
                self.takeNext?(value)
            }
        }
    }
    public func invoke() {
        guard !locked else {
            return
        }
        let subviews = self.subviews.compactMap { $0 as? CodeEntryElement }
        if value.count == subviews.count {
            self.takeNext?(value)
        } else if let view = subviews.first(where: { $0.value.isEmpty }) {
            window?.makeFirstResponder(view)
            view.shake(beep: false)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
