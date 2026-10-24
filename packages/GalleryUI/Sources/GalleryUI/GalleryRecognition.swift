import Foundation
import TextRecognizing
import SwiftSignalKit
import TelegramCore
import Postbox
import Translate
import TGUIKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import ChatModeTypes
import ChatHistoryModel
import GeneralRows
import LocalAnimations
import TelegramMediaUtils
import TelegramMedia
import AvatarUI
import MessageUtils
import InstantPageUI
import SecureIdUtils
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils

public final class GalleryRecognition {
    private let item: MGalleryPhotoItem
    private let disposable = MetaDisposable()
    private let translateDisposable = MetaDisposable()
    private let subjectDisposable = MetaDisposable()
    private let loadedDisposable = MetaDisposable()
    private var isFullImageLoaded: Bool = false
    
    public var openLink: ((String) -> Void)?
    
    private var result: AnyObject?
    private var translation: AnyObject?
    
    public let view:NSView
    public init?(_ item: MGalleryItem) {
        if let item = item as? MGalleryPhotoItem {
            if let message = item.entry.message, message.isCopyProtected() {
                return nil
            }
            self.item = item
            if #available(macOS 10.15, *) {
                self.view = TextRecognizing.ImageTextSelector(frame: .zero)
            } else {
                return nil
            }
        } else {
            return nil
        }
        if #available(macOS 10.15, *) {
            let postbox = item.context.account.postbox
            let mediaId = item.entry.mediaId
            let fullImageLoaded = item.path.get() |> take(1) |> map { _ in Void() }
            let image: Signal<TextRecognizing.Result?, TextRecognizing.Error> = combineLatest(item.image.get(), item.magnify.get(), item.appearValue, fullImageLoaded) |> castError(TextRecognizing.Error.self) |> mapToSignal { image, magnify, visible, _ in
                if magnify == 1, visible {
                    switch image.value {
                    case let .image(image, _):
                        if let image = image {
                            return TextRecognizing.recognize(image._cgImage!, postbox: postbox, stableId: mediaId) |> map(Optional.init)
                        } else {
                            return .single(nil)
                        }
                    default:
                        return .single(nil)
                    }
                } else {
                    return .single(nil)
                }
               
            } |> deliverOnMainQueue
            
            disposable.set(image.start(next: { [weak self] result in
                self?.applyResult(result)
            }))
            
            loadedDisposable.set((fullImageLoaded |> deliverOnMainQueue).start(next: { [weak self] in
                self?.isFullImageLoaded = true
            }))
            
            selectorView.openBarcode = { [weak self] barcode in
                self?.open(barcode)
            }
            selectorView.barcodeMenu = { [weak self] barcode in
                return self?.menu(for: barcode)
            }
        }
    }
    deinit {
        disposable.dispose()
        translateDisposable.dispose()
        subjectDisposable.dispose()
        loadedDisposable.dispose()
    }
    
    @available(macOS 10.15, *)
    private func open(_ barcode: TextRecognizing.Result.Barcode) {
        if let link = barcode.link {
            openLink?(link)
        } else {
            copy(barcode.payload)
        }
    }
    
    private func copy(_ text: String) {
        copyToClipboard(text)
        if let window = view.window as? Window {
            showModalText(for: window, text: strings().contextAlertCopied)
        }
    }
    
    @available(macOS 10.15, *)
    private func menu(for barcode: TextRecognizing.Result.Barcode) -> ContextMenu {
        let menu = ContextMenu(presentation: .current(darkPalette), betterInside: true)
        if let link = barcode.link {
            menu.addItem(ContextMenuItem(strings().chatMessageOpenLink, handler: { [weak self] in
                self?.openLink?(link)
            }, itemImage: MenuAnimation.menu_open_with.value))
            menu.addItem(ContextMenuItem(strings().textContextCopyLink, handler: { [weak self] in
                self?.copy(link)
            }, itemImage: MenuAnimation.menu_copy_link.value))
        } else {
            menu.addItem(ContextMenuItem(strings().contextCopy, handler: { [weak self] in
                self?.copy(barcode.payload)
            }, itemImage: MenuAnimation.menu_copy.value))
        }
        return menu
    }
    
    public var canLiftSubject: Bool {
        if #available(macOS 14.0, *) {
            return isFullImageLoaded
        } else {
            return false
        }
    }
    
    @available(macOS 14.0, *)
    private func liftSubject(at windowPoint: NSPoint?, completion: @escaping (TextRecognizing.Subject) -> Void) {
        let point = windowPoint.flatMap { selectorView.normalizedPoint(fromWindow: $0) }
        let signal = item.image.get()
        |> take(1)
        |> mapToSignal { value -> Signal<TextRecognizing.Subject?, NoError> in
            switch value.value {
            case let .image(image, _):
                if let image = image?._cgImage {
                    return TextRecognizing.liftSubject(image, at: point)
                }
                return .single(nil)
            default:
                return .single(nil)
            }
        }
        |> deliverOnMainQueue
        
        subjectDisposable.set(signal.start(next: { [weak self] subject in
            guard let self else {
                return
            }
            if let subject {
                self.selectorView.showLiftedSubject(subject.image, rect: subject.rect, completion: {
                    completion(subject)
                })
            } else if let window = self.view.window as? Window {
                showModalText(for: window, text: strings().gallerySubjectNotFound)
            }
        }))
    }
    
    public func copySubject(at windowPoint: NSPoint?) {
        guard #available(macOS 14.0, *) else {
            return
        }
        liftSubject(at: windowPoint, completion: { [weak self] subject in
            let representation = NSBitmapImageRep(cgImage: subject.image)
            guard let png = representation.representation(using: .png, properties: [:]) else {
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            if let tiff = representation.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            if let window = self?.view.window as? Window {
                showModalText(for: window, text: strings().contextAlertCopied)
            }
        })
    }
    
    public func sendSubjectAsSticker(at windowPoint: NSPoint?, send: @escaping (String) -> Void) {
        guard #available(macOS 14.0, *) else {
            return
        }
        liftSubject(at: windowPoint, completion: { subject in
            let signal: Signal<String?, NoError> = Signal { subscriber in
                subscriber.putNext(GalleryRecognition.writeSticker(subject))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(.concurrentDefaultQueue())
            |> deliverOnMainQueue
            
            _ = signal.start(next: { path in
                if let path {
                    send(path)
                }
            })
        })
    }
    
    @available(macOS 14.0, *)
    private static func writeSticker(_ subject: TextRecognizing.Subject) -> String? {
        guard let data = subject.stickerData() else {
            return nil
        }
        let path = NSTemporaryDirectory() + "subject_sticker_\(arc4random64()).webp"
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            return nil
        }
        return path
    }
    @available(macOS 10.15, *)
    public func canTranslate() -> Bool {
        guard let result = result as? TextRecognizing.Result else {
            return false
        }
        
        switch result {
        case let .finish(_, text, _):
            let text = text.map { $0.text }.joined(separator: "\n")
            let fromLang = Translate.detectLanguage(for: text)
            let toLang = item.context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
            
            if fromLang == nil || !toLang.contains(fromLang!) {
                return true
            }
        default:
            break
        }
        
        return false
        
    }
    
    @available(macOS 10.15, *)
    public func toggleTranslate(to: String) {
        
        if let result = result as? TextRecognizing.Result {
            guard translation == nil else {
                self.applyResult(result)
                return
            }
            
            switch result {
            case let .finish(image, text, _):
                var entities: [MessageTextEntity] = []
                var length = 0
                var currentText: String = ""
                let toLang = Translate.normalizeLanguageCode(appAppearance.languageCode)
                for text in text {
                    entities.append(.init(range: length ..< length + text.text.length, type: .BlockQuote(isCollapsed: false)))
                    currentText += text.text
                    length += text.text.length
                }
                
                let signal:Signal<(result: String, entities: [MessageTextEntity])?, TranslationError>
                signal = item.context.engine.messages.translate(text: currentText, toLang: toLang, entities: entities) |> mapToSignal { value in
                    if let value = value {
                        return .single((result: value.0, entities: value.1.filter { value in
                            switch value.type {
                            case .BlockQuote:
                                return true
                            default:
                                return false
                            }
                        }))
                    } else {
                        return .single(nil)
                    }
                } |> deliverOnMainQueue
                
                translateDisposable.set(signal.startStrict(next: { [weak self] translated in
                    var texts: [TextRecognizing.TranslateResult.Value] = []
                    var toRemove: [Int] = []
                    var filtered = text
                    if let result = translated {
                        for (i, entity) in result.1.enumerated() {
                            let t = result.0.nsstring.substring(with: NSMakeRange(entity.range.lowerBound, entity.range.upperBound - entity.range.lowerBound))
                            let onlyText = !text[i].text.trimmingCharacters(in: CharacterSet.decimalDigits).isEmpty
                            if text[i].text != t, onlyText {
                                texts.append(.init(text: t, detected: text[i]))
                            } else {
                                toRemove.append(i)
                            }
                        }
                    }
                    for idx in toRemove.reversed() {
                        filtered.remove(at: idx)
                    }
                    if translated == nil || translated?.result.isEmpty == true || translated?.1.isEmpty == true {
                        self?.applyResult(result, translate: nil)
                        return
                    } else {
                        self?.applyResult(result, translate: .success(translated: texts, original: .finish(image: image, text: filtered, barcodes: [])))
                    }
                }, error: { [weak self] _ in
                    self?.applyResult(result)
                }))
            default:
                break
            }
            self.applyResult(result, translate: .progress(result))
        }
    }
    
    public func hasTranslation() -> Bool {
        return translation != nil
    }
    
    
    @available(macOS 10.15, *)
    private func applyResult(_ result: TextRecognizing.Result?, translate: TextRecognizing.TranslateResult? = nil) {
        self.result = result as AnyObject?
        self.translation = translate as AnyObject?
        
        self.selectorView.set(result, translate: translate)
        
        if translate == nil {
            self.translateDisposable.set(nil)
        }
    }
    
    @available(macOS 10.15, *)
    private var selectorView: TextRecognizing.ImageTextSelector {
        return self.view as! TextRecognizing.ImageTextSelector
    }
    
    public var hasRecognition: Bool {
        if #available(macOS 10.15, *) {
            return self.selectorView.result != nil
        } else {
            return false
        }
       
    }
    public var hasSelectedText: Bool {
        if #available(macOS 10.15, *) {
            return self.selectorView.hasSelectedText
        } else {
            return false
        }
    }
    public func cancelSelection() {
        if #available(macOS 10.15, *) {
            self.selectorView.cancelSelection()
        }
    }
    
    public func copySelectedText() -> Bool {
        if #available(macOS 10.15, *) {
            return self.selectorView.copySelectedText()
        } else {
            return false
        }
    }
    public var selectedText: String? {
        if #available(macOS 10.15, *) {
            return self.selectorView.selectedText
        } else {
            return nil
        }
    }
}
