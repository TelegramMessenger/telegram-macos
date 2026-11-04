import AppKit
import TGUIKit
import SwiftSignalKit

class ChatInputControllerView: View {let inputView=View()}
class ContextClueRowItem: TableRowItem {}
final class ResultRowItem: TableRowItem {
 let message: Message
 let action: ()->Void
 init(_ message:Message, width:CGFloat, action:@escaping()->Void) { self.message=message;self.action=action;super.init(NSMakeSize(width,44),stableId:message.id.value) }
 override var accessibilityLabel:String? {message.text}
 override var accessibilityRole:NSAccessibility.Role? {.button}
 override func accessibilityPerformPress()->Bool {action();return true}
 override var height:CGFloat {44}
 override func viewClass()->AnyClass {ResultRowView.self}
}
final class ResultRowView:TableRowView {
 let label=TextView()
 required init(frame:NSRect) {super.init(frame:frame);addSubview(label);label.isSelectable=false;label.userInteractionEnabled=false}
 required init?(coder:NSCoder){fatalError()}
 override func set(item:TableRowItem,animated:Bool=false) {super.set(item:item,animated:animated);guard let row=item as? ResultRowItem else {return};let layout=TextViewLayout(.initialize(string:row.message.text,color:theme.colors.text,font:.normal(.text)),maximumNumberOfLines:1);layout.measure(width:row.width-30);label.update(layout)}
 override func layout(){super.layout();label.centerY(x:15)}
 override func mouseUp(with event:NSEvent) {(item as? ResultRowItem)?.action()}
}
final class ContextController {
 var fullWidthInset: CGFloat?
 __ANCHOR_FRAME__
 var _frameRect=NSRect.zero
 var atomicSize=Atomic(value:NSSize.zero)
 var superview:NSView?
 var getBackground:(()->NSColor)?
 var getHeight:(()->CGFloat)?
 var updatedSize:((NSSize,Bool)->Void)?
 var onDisappear:(()->Void)?
 var markAsNeedShown=false
 let genericView=InputContextView(frame:.zero)
 var view:InputContextView {genericView}
 var frame:NSRect {get {view.frame} set {view.frame=newValue}}
 func loadViewIfNeeded(){if frame == .zero {frame=_frameRect}}
 func viewWillAppear(_ animated:Bool){}
 func viewDidAppear(_ animated:Bool){}
 func viewWillDisappear(_ animated:Bool){}
 func viewDidDisappear(_ animated:Bool){}
 func make(with messages:[Message],animated:Bool,selectIndex:Int?,result:ChatPresentationInputQueryResult?) {
  genericView.tableView.removeAll()
  for message in messages { _ = genericView.tableView.addItem(item:ResultRowItem(message,width:_frameRect.width,action:{ [weak self] in self?.selected?(message)})) }
  layout(animated)
 }
 var onSearchMessageSelected:((Message)->Void)?
 var selected:((Message)->Void)?
 __CONTEXT_LAYOUT__
}
final class InputContextHelper {
 var fullWidthInset: CGFloat? { get { controller.fullWidthInset } set { controller.fullWidthInset = newValue } }
 static let containerCornerRadius:CGFloat=20
 let controller=ContextController()
 let accessoryContainerView=View()
 var accessoryView:NSView? {accessoryContainerView.superview == nil ? nil:accessoryContainerView}
 let chatInteraction:ChatInteraction
 var results:[Message]=[]
 var updatedSize:((NSSize,Bool)->Void)?
 var getBackground:(()->NSColor)?
 var getHeight:(()->CGFloat)?
 var onDisappear:(()->Void)?
 var previosEntries=Atomic<[Message]?>(value:nil)
 init(chatInteraction:ChatInteraction,highlightInsteadOfSelect:Bool){self.chatInteraction=chatInteraction;controller.selected={ [weak self] message in self?.controller.onSearchMessageSelected?(message);self?.chatInteraction.focusMessageId(nil,.init(messageId:message.id),nil) }}
 __LAYOUT_CONTAINER__
 __HELPER_LAYOUT__
 func context(with result:ChatPresentationInputQueryResult?,for parent:NSView,relativeView anchor:NSView,position:InputContextPosition,selectIndex:Int?,animated:Bool,inset:CGFloat) {
  do {
   let view = parent
   let relativeView = anchor
   __CONTEXT_PREPARE__
  }
  if case let .searchMessages(messages,_,_) = result {
   results=messages.0
   controller.selected={ [weak self] message in self?.controller.onSearchMessageSelected?(message);self?.chatInteraction.focusMessageId(nil,.init(messageId:message.id),nil) }
  } else if case let .mentions(peers) = result {
   results=peers.map {Message(id:.init(value:$0.id.value),text:$0.compactDisplayTitle)}
   controller.selected={ [weak self] message in if let peer=peers.first(where:{$0.id.value==message.id.value}) {self?.chatInteraction.movePeerToInput(peer)} }
  } else {results=[]}
  let transition=results
  let show = !results.isEmpty
  let previousIsEmpty = accessoryView == nil
  let container=accessoryContainerView
  let gap:CGFloat=10
  let view:NSView?=parent
  let relativeView:NSView?=anchor
  __CONTEXT_ATTACH__
 }
}
typealias InputContextViewController = ContextController
public enum InputContextPosition {case below,above}
