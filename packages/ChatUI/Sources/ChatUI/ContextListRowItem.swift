import Cocoa
import HTMLBubbles
import TGUIKit
import TelegramCore

import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import AudioPlayerCore



public class ContextListRowItem: TableRowItem {

    fileprivate var widgetState: HTMLBubbleState?
    public let result:ChatContextResult
    public let results:ChatContextResultCollection
    private let _index1:Int64
    public let context: any AccountContextProtocol
    public let iconSignal:Signal<ImageDataTransformation, NoError>
    public let arguments:TransformImageArguments?
    public var textLayout:(TextNodeLayout, TextNode)?
    public let capImage:CGImage?
    public var fileResource:TelegramMediaResource?
    public let chatInteraction:ChatInteraction
    public var audioWrapper:APSingleWrapper?
    public private(set) var file: TelegramMediaFile?
    private var vClass:AnyClass = ContextListImageView.self
    private let text:NSAttributedString
    public override var stableId: AnyHashable {
        return Int64(_index1)
    }
    
    public init(_ initialSize: NSSize, _ results:ChatContextResultCollection, _ result:ChatContextResult, _ index:Int64, _ context: any AccountContextProtocol, _ chatInteraction:ChatInteraction) {
        self.result = result
        self.results = results
        self.chatInteraction = chatInteraction
        self._index1 = index
        self.context = context
        var representation: TelegramMediaImageRepresentation?
        var iconText:NSAttributedString? = nil
        switch result {
        case let .externalReference(values):
            if let thumbnail = values.thumbnail {
                representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(NSMakeSize(50, 50)), resource: thumbnail.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
            }
            if let content = values.content {
                if content.mimeType.hasPrefix("audio") {
                    vClass = ContextListAudioView.self
                    audioWrapper = APSingleWrapper(resource: content.resource, name: values.title, performer: values.description, duration: content.duration, id: result.maybeId)
                } else if content.mimeType == "video/mp4" {
                    vClass = ContextListGIFView.self
                }
            }
            var selectedUrl: String?
            if let url = values.url {
                selectedUrl = url
            }
            if let selectedUrl = selectedUrl, let parsedUrl = URL(string: selectedUrl) {
                if let host = parsedUrl.host, !host.isEmpty {
                    iconText = NSAttributedString.initialize(string: host[..<host.index(after: host.startIndex)].uppercased(), color: .white, font: .medium(25.0))
                }
            }
        case let .internalReference(values):
            if let file = values.file {
                self.file = file
                fileResource = file.resource
                if file.isMusic || file.isVoice {
                    vClass = ContextListAudioView.self
                    audioWrapper = APSingleWrapper(resource: fileResource!, name: values.title, performer: values.description, duration: file.duration, id: result.maybeId)
                } else if file.isVideo && file.isAnimated {
                    vClass = ContextListGIFView.self
                }
            }
            if let image = values.image {
                representation = firstImageRepresentation(image.representations)
            } else if let file = file {
                representation = firstImageRepresentation(file.previewRepresentations)
            }
        }
        
        
        
        if let representation = representation {
            let tmpImage = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
            iconSignal = chatWebpageSnippetPhoto(account: context.account, imageReference: ImageMediaReference.standalone(media: tmpImage), scale: System.backingScale, small:true)
            
            let iconSize = representation.dimensions.size.aspectFilled(CGSize(width: 50, height: 50))
            
            let imageCorners = ImageCorners(topLeft: .Corner(2.0), topRight: .Corner(2.0), bottomLeft: .Corner(2.0), bottomRight: .Corner(2.0))
            arguments = TransformImageArguments(corners: imageCorners, imageSize: iconSize, boundingSize: NSMakeSize(50, 50), intrinsicInsets: NSEdgeInsets())
            iconText = nil
        } else {
            arguments = nil
            iconSignal = .complete()
            
            if iconText == nil {
                if let title = result.title, !title.isEmpty {
                    let titleText = title[..<title.index(after: title.startIndex)].uppercased()
                    iconText = .initialize(string: titleText, color: .white, font: .medium(25.0))
                }
            }
        }

        if let iconText = iconText {
            capImage = capIcon(for: iconText)
        } else {
            capImage = nil
        }
        
        

        let attr:NSMutableAttributedString = NSMutableAttributedString()
        var title:String = "Untitled"
        if let t = result.title {
            title = t
        }
        _ = attr.append(string: title , color: theme.colors.text, font: .medium(.text))
        if let description = result.description {
            _ = attr.append(string:"\n")
            _ = attr.append(string: description, color: theme.colors.grayText, font: NSFont.normal(FontSize.text))
        }
        attr.addAttribute(.selectedColor, value: NSColor.white, range: attr.range)

        self.text = attr.copy() as! NSAttributedString
        super.init(initialSize)
        if case let .widget(media, _, _, _) = result.message {
            widgetState = HTMLWidgetStore.preview(widget: media, locale: appCurrentLanguage.languageCode)
            vClass = ContextListWidgetView.self
        }
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        prepare(isSelected)
        return success
    }
    
    public override func prepare(_ selected: Bool) {
        textLayout = TextNode.layoutText(maybeNode: nil,  text, nil, 3, .end, NSMakeSize(width - textInset.left - textInset.right, height), nil, selected, .left)
    }
    
    public override var height: CGFloat {
        return 60
    }
    
    public var textInset:NSEdgeInsets {
        var insets = NSEdgeInsets(left:70, right:10, top:10)
        
        if vClass == ContextListAudioView.self {
            insets.left = 60
        }
        
        return insets
    }
    
    public override func viewClass() -> AnyClass {
        return vClass
    }

    public override var accessibilityLabel: String? {
        let string = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

public class ContextListRowView : TableRowView {

    public override var backdorColor: NSColor {
        return item?.isSelected ?? false ? theme.colors.accentSelect : theme.colors.background
    }
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        if let item = item as? ContextListRowItem {
            
            if !item.isSelected && item.index != item.table!.count - 1 {
                ctx.setFillColor(theme.colors.border.cgColor)
                ctx.fill(NSMakeRect(item.textInset.left, frame.height - .borderSize, frame.width - item.textInset.left, .borderSize))
            }
            
            if let layout = item.textLayout {
                let f = focus(layout.0.size)
                layout.1.draw(NSMakeRect(item.textInset.left, f.minY, layout.0.size.width, layout.0.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
            }
            
        }
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        needsDisplay = true
        needsLayout = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
}

public class ContextListImageView : TableRowView {
    public let image:TransformImageView = TransformImageView()
    public required init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        image.setFrameSize(NSMakeSize(50, 50))
        addSubview(image)
    }
    
    public override var backdorColor: NSColor {
        return item?.isSelected ?? false ? theme.colors.accentSelect : theme.colors.background
    }
    
    public override func layout() {
        super.layout()
        image.centerY(x:10)
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        if let item = item as? ContextListRowItem {
            
            if !item.isSelected && item.index != item.table!.count - 1 {
                ctx.setFillColor(theme.colors.border.cgColor)
                ctx.fill(NSMakeRect(item.textInset.left, frame.height - .borderSize, frame.width - item.textInset.left, .borderSize))
            }
            
            if let layout = item.textLayout {
                let f = focus(layout.0.size)
                layout.1.draw(NSMakeRect(item.textInset.left, f.minY, layout.0.size.width, layout.0.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
            }
            needsLayout = true
        }
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        let updated = self.item != item
        super.set(item: item)
        
        if let item = item as? ContextListRowItem, let arguments = item.arguments {
            image.set(arguments: arguments)
        }
        
        if let item = item as? ContextListRowItem, updated {
            if let capImage = item.capImage {
                self.image.layer?.contents = capImage
            } else {
                image.setSignal( item.iconSignal)
            }
        }
        needsDisplay = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class ContextListGIFView : ContextListRowView {
    private let player:GIFContainerView = GIFContainerView()
 
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        player.setFrameSize(NSMakeSize(50, 50))
        addSubview(player)
    }
    
    public override func layout() {
        super.layout()
        player.centerY(x:10)
    }
    

    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        let updated = self.item != item
        super.set(item: item, animated: animated)
        
        if let item = item as? ContextListRowItem, updated, let file = item.file {
            player.update(with: FileMediaReference.standalone(media: file), size: NSMakeSize(50,50), viewSize: NSMakeSize(50,50), context: item.context, table: item.table)
            player.needsLayout = true
        }
    }
}



public class ContextListAudioView : ContextListRowView, APDelegate {
    public let progressView:RadialProgressView = RadialProgressView()
    private let statusDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private var fetchStatus:MediaResourceStatus?
    private var fetchStatusResource: MediaResourceId?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        progressView.state = .Icon(image: theme.icons.chatMusicPlay)
        progressView.setAccessibilityLabel(strings().voiceOverCommonPlay)
        progressView.fetchControls = FetchControls(fetch: { [weak self] in
            self?.checkOperation()
        })
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        addSubview(progressView)
        

    }
    
    public func checkOperation() {
        
        if let item = item as? ContextListRowItem, let status = fetchStatus {
            switch status {
            case .Fetching, .Paused:
                break
            case .Local, .Remote:
                if let wrapper = item.audioWrapper {
                    if let controller = ChatInputUIHooks.shared.getAudioPlayer(item.context), controller.playOrPause(wrapper) {
                        
                    } else {
                        let controller = APSingleResourceController(context: item.context, wrapper: wrapper, streamable: false)
                        controller.add(listener: self)
                        item.chatInteraction.inlineAudioPlayer(controller)
                        controller.start()
                    }
                }
               
                break
                
            }
        }
    }
    
    public func songDidChanged(song: APSongItem, for controller: APController, animated: Bool) {
        checkState()
    }
    public func songDidChangedState(song: APSongItem, for controller: APController, animated: Bool) {
        checkState()
    }
    
    public func songDidStartPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        checkState()
    }
    public func songDidStopPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        checkState()
    }
    public func playerDidChangedTimebase(song:APSongItem, for controller:APController, animated: Bool) {
        checkState()
    }
    
    public func audioDidCompleteQueue(for controller:APController, animated: Bool) {
        checkState()
    }
    
    public func checkState(animated: Bool = false) {
        
        progressView.theme = RadialProgressTheme(backgroundColor: theme.colors.accent, foregroundColor: .white, icon: theme.icons.chatMusicPlay, iconInset:NSEdgeInsets(left:1))
        
        switch fetchStatus {
        case let .Fetching(_, progress), let .Paused(progress):
            self.progressView.setState(.Fetching(progress: progress, force: false), animated: animated)
            progressView.setAccessibilityLabel(strings().voiceOverCommonLoading)
        default:
            if let item = item as? ContextListRowItem, let wrapper = item.audioWrapper, let controller = ChatInputUIHooks.shared.getAudioPlayer(item.context), let song = controller.currentSong {
                if song.entry.isEqual(to: wrapper), case .playing = song.state {
                    progressView.setState(.Icon(image: theme.icons.chatMusicPause), animated: animated)
                    progressView.setAccessibilityLabel(strings().voiceOverCommonPause)
                } else {
                    progressView.setState(.Icon(image: theme.icons.chatMusicPlay), animated: animated)
                    progressView.setAccessibilityLabel(strings().voiceOverCommonPlay)
                }
            } else {
                progressView.setState(.Icon(image: theme.icons.chatMusicPlay), animated: animated)
                progressView.setAccessibilityLabel(strings().voiceOverCommonPlay)
            }
        }
        
    }
    
    public override func layout() {
        super.layout()
        progressView.centerY(x:10)
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        _ = self.item != item
        super.set(item: item, animated: animated)
        
        if let item = item as? ContextListRowItem, let resource = item.fileResource {
            
            let updatedStatusSignal = item.context.account.postbox.mediaBox.resourceStatus(resource) |> deliverOnMainQueue

            let resourceId = resource.id
            statusDisposable.set(updatedStatusSignal.start(next: { [weak self] status in
                if let strongSelf = self {
                    let animated = strongSelf.fetchStatus != nil && strongSelf.fetchStatusResource == resourceId
                    strongSelf.fetchStatus = status
                    strongSelf.fetchStatusResource = resourceId
                    strongSelf.checkState(animated: animated)
                }
            }))

        }
        checkState()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    deinit {
        if let item = item as? ContextListRowItem {
            ChatInputUIHooks.shared.getAudioPlayer(item.context)?.remove(listener: self)
        }
        statusDisposable.dispose()
        fetchDisposable.dispose()
    }
}


final class ContextWidgetRowItem: ContextListRowItem, HTMLTwidgetRow {
    fileprivate private(set) var titleLayout: TextViewLayout?
    private var reportedHeight: CGFloat?

    var htmlTwidgetState: HTMLBubbleState { widgetState! }
    var htmlTwidgetAppearance: HTMLBubbleAppearance { HTMLBubbleStyle.appearance(theme: theme, incoming: false) }
    var htmlTwidgetWidth: CGFloat { previewLayout.contentSize.width }

    fileprivate var previewLayout: HTMLWidgetPreviewLayout {
        guard case let .widget(media, _, _, _) = result.message else {
            preconditionFailure()
        }
        return HTMLWidgetPreviewLayout(width: media.width, height: media.height, availableWidth: width - 24, reportedHeight: reportedHeight)
    }

    fileprivate var previewFrame: CGRect {
        return CGRect(origin: CGPoint(x: 12, y: titleLayout.map { $0.layoutSize.height + 15 } ?? 9), size: previewLayout.displaySize)
    }

    override var height: CGFloat { previewFrame.maxY + 9 }

    override func prepare(_ selected: Bool) {
        if let title = result.title, !title.isEmpty {
            let layout = TextViewLayout(.initialize(string: title, color: selected ? theme.colors.underSelectedColor : theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 2, truncationType: .end)
            layout.measure(width: max(1, width - 24))
            titleLayout = layout
        } else {
            titleLayout = nil
        }
    }

    fileprivate func updatePreviewHeight(_ height: CGFloat) {
        guard case let .widget(media, _, _, _) = result.message, media.height == 0, reportedHeight != height else {
            return
        }
        let oldHeight = self.height
        reportedHeight = height
        if abs(oldHeight - self.height) > 0.5 {
            noteHeightOfRow()
            (table?.delegate as? InputContextViewController)?.layout(false)
        }
        (view as? ContextListWidgetView)?.needsLayout = true
    }

    override var accessibilityLabel: String? {
        if let title = result.title, !title.isEmpty { return title }
        if case let .widget(_, caption, _, _) = result.message, !caption.isEmpty { return caption }
        return strings().contextListRowItemWidget
    }
}

private final class ContextListWidgetView: TableRowView {
    private let titleView = TextView()
    private let previewContainer = View(frame: .zero)
    private let preview = HTMLBubbleView(frame: .zero)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleView.userInteractionEnabled = false
        addSubview(titleView)
        addSubview(previewContainer)
        previewContainer.addSubview(preview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? ContextWidgetRowItem else { return }
        preview.onContentChanged = { [weak self, weak item] size, _ in
            DispatchQueue.main.async {
                guard self?.item === item else { return }
                item?.updatePreviewHeight(size.height)
            }
        }
        updateFrames(item)
        preview.update(state: item.htmlTwidgetState, appearance: item.htmlTwidgetAppearance, maxWidth: item.htmlTwidgetWidth, rendering: nil)
    }

    override func layout() {
        super.layout()
        if let item = item as? ContextWidgetRowItem {
            updateFrames(item)
        }
    }

    private func updateFrames(_ item: ContextWidgetRowItem) {
        titleView.isHidden = item.titleLayout == nil
        if let title = item.titleLayout {
            titleView.update(title, origin: NSMakePoint(12, 9))
        }
        let layout = item.previewLayout
        previewContainer.frame = item.previewFrame
        previewContainer.setBoundsSize(layout.contentSize)
        preview.frame = CGRect(origin: .zero, size: layout.contentSize)
    }

    override var backdorColor: NSColor {
        return item?.isSelected == true ? theme.colors.accentSelect : theme.colors.background
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }
}
