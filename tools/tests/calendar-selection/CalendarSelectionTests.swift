import AppKit
import CalendarUtils
import XCTest
import SwiftSignalKit

var clockNow=Date()

class View {weak var window:Window?;var frame:NSRect;var bounds:NSRect {NSRect(origin:.zero,size:frame.size)};required init(frame:NSRect) {self.frame=frame};func addSubview(_ view:View) {}}
class CalendarMonthView:View {
    var previewUpdates=0;func updateDayPreviews(animated:Bool) {previewUpdates+=1}
    var layouts=0;func layout(for month:CalendarMonthStruct) {layouts+=1}
    func handler(month:CalendarMonthStruct,current:Int)->(Control)->Void {__DAY_CLICK__}
}
class Control {}
struct NavigationBarStyle {let height:CGFloat}
enum Key {case LeftArrow,RightArrow}
enum Priority {case modal}
enum KeyHandlerResult {case invoked}
final class Window {var handlers:[Key:(Int)->KeyHandlerResult]=[:];func set(handler:@escaping(Int)->KeyHandlerResult,with object:AnyObject,for key:Key,priority:Priority) {handlers[key]=handler};func remove(object:AnyObject,for key:Key) {handlers[key]=nil}}
final class Popover {var hidden=0;var onHide:(()->Void)?;func hide() {hidden+=1;onHide?()}}
final class Modal {var closes=0;var resized=0;var heights=0;var onClose:(()->Void)?;func close() {closes+=1;onClose?()};func setInteractionHeight(height:Int,animated:Bool) {heights+=1};func resize(with size:NSSize,animated:Bool) {resized+=1}}
class ViewController {
    var view:View;weak var window:Window? {didSet {view.window=window}};weak var navigationController:NavigationViewController?;var popover:Popover?;var modal:Modal?;var bar=NavigationBarStyle(height:0);var _frameRect=NSRect.zero
    var frame:NSRect {view.frame}
    init(frame:NSRect = .zero) {view=View(frame:frame)}
    func isLoaded()->Bool {true}
    func viewDidResized(_ size:NSSize) {}
    func viewDidLoad() {};func viewDidAppear(_ animated:Bool) {};func viewWillDisappear(_ animated:Bool) {};func viewDidDisappear(_ animated:Bool) {};func viewWillAppear(_ animated:Bool) {};func readyOnce() {};func addSubview(_ v:View) {view.addSubview(v)};var isAutoclosePopover:Bool {true}
}
class GenericViewController<T:View>:ViewController {override init(frame:NSRect = .zero) {super.init(frame:frame);view=T(frame:frame)};var genericView:T {view as! T}}
enum ViewControllerStyle {case none,push,pop}
class NavigationViewController:ViewController {
    var controller:ViewController;var pushes=0
    init(_ controller:ViewController,_ window:Window) {self.controller=controller;super.init();self.window=window;controller.navigationController=self;controller.window=window}
    func push(_ controller:ViewController,style:ViewControllerStyle) {self.controller=controller;controller.navigationController=self;controller.window=window;pushes+=1}
}
__INTERACTIONS__
__MONTH__
__MONTH_CONTROLLER__
__CONTROLLER__
protocol ChatBirthdayCalendar:ViewController {var date:Date {get};func hideYear()}
extension CalendarController:ChatBirthdayCalendar {}
struct TelegramBirthday:Equatable {let date:Date}
extension Date {var birthday:TelegramBirthday {TelegramBirthday(date:self)}}
enum UpdateBirthdayError {case generic,flood}
final class AccountData {func updateBirthday(birthday:TelegramBirthday?)->Signal<Never,UpdateBirthdayError> {Signal {s in if let birthday {ChatNavigationHooks.shared.submitted.append(birthday.date)};s.putCompletion();return EmptyDisposable}}}
struct Engine {let accountData=AccountData()}
final class Context {var window:Window?;let engine=Engine()}
final class Queue {static let main=Queue();var jobs:[()->Void]=[];static func mainQueue()->Queue {main};func justDispatch(_ f:@escaping()->Void) {jobs.append(f)};func drain() {while !jobs.isEmpty {jobs.removeFirst()()}}}
func deliverOnMainQueue<T,E>(_ signal:Signal<T,E>)->Signal<T,E> {signal}
func showModalProgress<T,E>(signal:Signal<T,E>,for window:Window,shouldPresent:@escaping()->Bool={true})->Signal<T,E> {signal}
struct Strings {let loginFloodWait="Flood",unknownError="Error",birthdayAlertAdded="Added"}
func strings()->Strings {Strings()}
func showModalText(for window:Window,text:String) {}
__SAVE_HELPER__
final class ChatNavigationHooks {static let shared=ChatNavigationHooks();var submitted:[Date]=[];func updateAccountBirthday(_ date:Date,_ context:Context) {submitted.append(date)}}
final class ModalInteractions {var updates=0;func updateBottomText(_ value:Int?) {updates+=1}}
final class Wrap:ViewController {
    let controller:NavigationViewController;let context:Context;var isVisible=true;var hasSubmitted=false;let saveAction=ChatBirthdaySaveAction()
    init(_ controller:NavigationViewController,context:Context=Context()) {self.controller=controller;self.context=context;super.init();self.window=controller.window;self.context.window=controller.window;modal=Modal()}
    __WRAP_LIFECYCLE__
    func accept()->()->Void {let context=self.context;return __ACCEPT__}
    func hide(_ interactions:ModalInteractions)->(String)->Void {return __HIDE_YEAR__}
}
final class CalendarSelectionTests:XCTestCase {
    let window=Window();var oldZone:TimeZone!
    override func setUp() {Queue.mainQueue().drain();oldZone=NSTimeZone.default;NSTimeZone.default=TimeZone(secondsFromGMT:0)!;ChatNavigationHooks.shared.submitted=[];clockNow=date(2026,10,17)}
    override func tearDown() {NSTimeZone.default=oldZone}
    func date(_ year:Int=2000,_ month:Int=6,_ day:Int=15)->Date {Calendar(identifier:.gregorian).date(from:DateComponents(year:year,month:month,day:day,hour:0))!}
    func make(_ date:Date?=nil,autoclose:Bool=false,future:Bool=false,limit:Date?=nil,canBeNoYear:Bool=true,selected:@escaping(Date)->Void={_ in})->CalendarController {let c=CalendarController(.zero,window,current:date ?? self.date(),onlyFuture:future,limitedBy:limit,lowYear:1900,canBeNoYear:canBeNoYear,selectHandler:selected,autoclose:autoclose);c.window=window;return c}
    func click(_ c:CalendarController,_ day:Int) {let current=c.navigation.controller as! CalendarMonthController;current.genericView.handler(month:current.month,current:day)(Control())}
    func current(_ c:CalendarController)->CalendarMonthController {c.navigation.controller as! CalendarMonthController}
    func next(_ c:CalendarController) {c.interactions.nextAction?(current(c).month.month)}
    func previous(_ c:CalendarController) {c.interactions.backAction?(current(c).month.month)}
    func testEmbeddedNavigationFitsInitialCalendarBounds() {
        let controller = CalendarController(NSMakeRect(0, 0, 300, 300), window, current: date(), lowYear: 1900, selectHandler: { _ in })
        controller.view.frame = NSMakeRect(0, 0, 300, 246)
        controller.viewDidLoad()
        XCTAssertEqual(controller.navigation.view.frame, controller.view.bounds)
    }

    func testEmbeddedNavigationFollowsResizeAcrossMonthAndYearChanges() {
        let controller = make()
        controller.viewDidLoad()
        for size in [NSMakeSize(300, 246), NSMakeSize(380, 344), NSMakeSize(300, 310)] {
            next(controller)
            controller.interactions.changeYear(2024, current(controller).month.month)
            controller.view.frame.size = size
            controller.viewDidResized(size)
            XCTAssertEqual(controller.navigation.view.frame, controller.view.bounds)
        }
    }

    func testDayPreviewsFollowMonthNavigationWithoutChangingSelection() {
        let controller = make()
        let preview = NSView()
        var timestamps: [Int] = []
        controller.dayPreview = { timestamp in
            timestamps.append(timestamp)
            return preview
        }
        let june = Int(date(2000, 6, 20).timeIntervalSince1970)
        XCTAssertTrue(current(controller).month.dayPreview(june) === preview)
        next(controller)
        let july = Int(date(2000, 7, 20).timeIntervalSince1970)
        XCTAssertTrue(current(controller).month.dayPreview(july) === preview)
        XCTAssertEqual(timestamps, [june, july])
        XCTAssertEqual(controller.date, date())
        XCTAssertEqual(current(controller).month.mode, .normal)
    }

    func testPreviewRefreshKeepsTheExistingMonthAndSelectedDay() {
        let controller = make()
        let month = current(controller)
        controller.updateDayPreviews()
        XCTAssertTrue(current(controller) === month)
        XCTAssertEqual(month.genericView.previewUpdates, 1)
        XCTAssertEqual(month.month.selectedDay, 15)
        XCTAssertEqual(controller.date, date())
    }

    func testClickedDayBecomesConfirmedDate() {let c=make();click(c,25);XCTAssertEqual(c.date,date(2000,6,25))}
    func testSelectionCallbackSeesUpdatedDate() {var seen:Date?;weak var weakController:CalendarController?;let c=make(selected:{_ in seen=weakController?.date});weakController=c;click(c,25);XCTAssertEqual(seen,date(2000,6,25))}
    func testMultipleClicksKeepLatestDate() {let c=make();click(c,25);click(c,3);XCTAssertEqual(c.date,date(2000,6,3))}
    func testRangeSelectionFollowsTheIOSRules() {
        var picked: [Date] = []
        let c = make(selected: { picked.append($0) })
        c.setSelecting(true)
        click(c, 10)
        XCTAssertEqual(c.selectedRange, date(2000, 6, 10) ... date(2000, 6, 10))
        XCTAssertEqual(c.selectedDaysCount, 1)
        click(c, 14)
        XCTAssertEqual(c.selectedRange, date(2000, 6, 10) ... date(2000, 6, 14))
        XCTAssertEqual(c.selectedDaysCount, 5)
        XCTAssertEqual(current(c).month.selectedRange, 10 ... 14)
        click(c, 12)
        XCTAssertEqual(c.selectedRange, date(2000, 6, 12) ... date(2000, 6, 12))
        click(c, 5)
        XCTAssertEqual(c.selectedRange, date(2000, 6, 5) ... date(2000, 6, 12))
        click(c, 12)
        XCTAssertNil(c.selectedRange)
        XCTAssertTrue(picked.isEmpty, "selecting days must not pick a date")
    }
    func testRangeSpansMonthsAndClearsWhenSelectionEnds() {
        let c = make()
        c.setSelecting(true)
        click(c, 28)
        next(c)
        click(c, 2)
        XCTAssertEqual(c.selectedDaysCount, 5)
        XCTAssertEqual(current(c).month.selectedRange, 1 ... 2)
        previous(c)
        XCTAssertEqual(current(c).month.selectedRange, 28 ... 30)
        XCTAssertTrue(current(c).month.isSelecting)
        c.setSelecting(false)
        XCTAssertNil(c.selectedRange)
        XCTAssertNil(current(c).month.selectedRange)
        XCTAssertFalse(current(c).month.isSelecting)
    }
    func testFittedMonthsReportTheirWeekCount() {
        let c = make(date(2026, 10, 17))
        var reported: [Int] = []
        c.weeksChanged = { reported.append($0) }
        XCTAssertEqual(c.weeksCount, 6)
        c.fitsWeeks = true
        XCTAssertEqual(c.weeksCount, 5)
        previous(c)
        XCTAssertEqual(c.weeksCount, 5)
        c.interactions.changeYear(2021, date(2021, 2, 1))
        XCTAssertEqual(c.weeksCount, 4)
        c.interactions.changeYear(2026, date(2026, 8, 1))
        XCTAssertEqual(c.weeksCount, 6)
        XCTAssertEqual(reported, [5, 4, 6])
    }
    func testMonthBrowsingDoesNotChangeSelection() {let c=make();next(c);XCTAssertEqual(c.date,date());previous(c);previous(c);XCTAssertEqual(c.date,date())}
    func testSelectedDayRestoredWhenReturningToMonth() {let c=make();next(c);previous(c);XCTAssertEqual(current(c).month.selectedDay,15)}
    func testNewSelectionRestoredWhenReturningToMonth() {let c=make();next(c);click(c,23);next(c);previous(c);XCTAssertEqual(current(c).month.selectedDay,23);XCTAssertEqual(c.date,date(2000,7,23))}
    func testBrowsingDifferentMonthDoesNotHighlightUnselectedDay() {let c=make();next(c);XCTAssertNil(current(c).month.selectedDay)}
    func testChangingYearPreservesSelectedDay() {let c=make();click(c,25);c.interactions.changeYear(1999,current(c).month.month);XCTAssertEqual(c.date,date(1999,6,25));XCTAssertEqual(current(c).month.selectedDay,25)}
    func testChangingLeapYearClampsWithinFebruary() {let c=make(date(2000,2,29));c.interactions.changeYear(2001,current(c).month.month);XCTAssertEqual(c.date,date(2001,2,28));XCTAssertEqual(current(c).month.selectedDay,28)}
    func testYearChangeInBrowsedMonthClampsSelectedDay() {let c=make(date(2000,1,31));next(c);c.interactions.changeYear(2001,current(c).month.month);XCTAssertEqual(c.date,date(2001,2,28))}
    func testYearChangeToNoYearPreservesLeapDay() {let c=make(date(2000,2,29));c.interactions.changeYear(Int32(CalendarUtils.yearForNoYear),current(c).month.month);XCTAssertEqual(c.date,date(CalendarUtils.yearForNoYear,2,29));XCTAssertEqual(current(c).month.selectedDay,29)}
    func testHideYearUsesClickedDay() {let c=make();click(c,25);c.hideYear();XCTAssertEqual(c.date,date(CalendarUtils.yearForNoYear,6,25))}
    func testHideYearDoesNotCommitBrowsedMonth() {let c=make();next(c);c.hideYear();XCTAssertEqual(c.date,date(CalendarUtils.yearForNoYear,6,15))}
    func testHideYearPreservesLeapDay() {let c=make(date(2000,2,29));c.hideYear();XCTAssertEqual(c.date,date(CalendarUtils.yearForNoYear,2,29))}
    func testSelectionAfterDisappearanceIsIgnored() {var values:[Date]=[];let c=make(selected:{values.append($0)});let action=c.interactions.selectAction;c.viewWillDisappear(false);action(date(2000,6,20));XCTAssertTrue(values.isEmpty);XCTAssertEqual(c.date,date())}
    func testNavigationAfterDisappearanceIsIgnored() {let c=make();c.viewWillDisappear(false);let old=current(c);next(c);previous(c);c.interactions.changeYear(1999,old.month.month);c.hideYear();XCTAssertTrue(current(c) === old);XCTAssertEqual(c.date,date())}
    func testReappearanceAllowsFreshSelection() {var values:[Date]=[];let c=make(selected:{values.append($0)});c.viewWillDisappear(false);c.interactions.selectAction(date(2000,6,20));c.viewWillAppear(false);click(c,22);XCTAssertEqual(values,[date(2000,6,22)]);XCTAssertEqual(c.date,date(2000,6,22))}
    func testRetainedActionCannotFireAfterControllerDeinit() {var values:[Date]=[];var c:CalendarController?=make(selected:{values.append($0)});let action=c!.interactions.selectAction;weak var weakController=c;c=nil;XCTAssertNil(weakController);action(date());XCTAssertTrue(values.isEmpty)}
    func testRetainedDayClickCannotFireAfterControllerDeinit() {var values:[Date]=[];var c:CalendarController?=make(selected:{values.append($0)});let m=current(c!);let action=m.genericView.handler(month:m.month,current:25);weak var weakController=c;c=nil;XCTAssertNil(weakController);action(Control());XCTAssertTrue(values.isEmpty)}
    func testAutocloseCommitsBeforeClosing() {var values:[Date]=[];let c=make(autoclose:true,selected:{values.append($0)});let nav=NavigationViewController(c,window);let modal=Modal();nav.modal=modal;var dateAtClose:Date?;modal.onClose={[weak c] in dateAtClose=c?.date};click(c,25);XCTAssertEqual(dateAtClose,date(2000,6,25));XCTAssertEqual(values,[date(2000,6,25)]);XCTAssertEqual(modal.closes,1)}
    func testAutocloseSuppressesReentrantAndRepeatedClick() {var values:[Date]=[];let c=make(autoclose:true,selected:{values.append($0)});let popover=Popover();c.popover=popover;popover.onHide={[weak c, weak popover] in if popover?.hidden == 1 {c?.interactions.selectAction(self.date(2000,6,26))}};click(c,25);click(c,27);XCTAssertEqual(values,[date(2000,6,25)]);XCTAssertEqual(popover.hidden,1);XCTAssertEqual(c.date,date(2000,6,25))}
    func testNonAutocloseKeepsPickerActive() {var values:[Date]=[];let c=make(selected:{values.append($0)});let p=Popover();c.popover=p;click(c,25);click(c,26);XCTAssertEqual(values,[date(2000,6,25),date(2000,6,26)]);XCTAssertEqual(p.hidden,0)}
    func testDateGetterDoesNotDependOnNavigationControllerType() {let c=make();c.navigation.controller=ViewController();XCTAssertEqual(c.date,date())}
    func testWrapperSaveUsesClickedDate() {let c=make();let w=Wrap(NavigationViewController(c,window));click(c,25);w.accept()();XCTAssertEqual(ChatNavigationHooks.shared.submitted,[date(2000,6,25)]);XCTAssertEqual(w.modal?.closes,1)}
    func testWrapperDuplicateAcceptSubmitsOnce() {let c=make();let w=Wrap(NavigationViewController(c,window));let accept=w.accept();accept();accept();XCTAssertEqual(ChatNavigationHooks.shared.submitted.count,1);XCTAssertEqual(w.modal?.closes,1)}
    func testWrapperCancelledAcceptDoesNotSubmit() {let c=make();let w=Wrap(NavigationViewController(c,window));let accept=w.accept();w.viewWillDisappear(false);accept();XCTAssertTrue(ChatNavigationHooks.shared.submitted.isEmpty);XCTAssertEqual(w.modal?.closes,0)}
    func testWrapperReappearanceAllowsUnsubmittedAccept() {let c=make();let w=Wrap(NavigationViewController(c,window));w.viewWillDisappear(false);w.viewWillAppear(false);w.accept()();XCTAssertEqual(ChatNavigationHooks.shared.submitted.count,1)}
    func testWrapperReappearanceDoesNotRepeatAcceptedSave() {let c=make();let w=Wrap(NavigationViewController(c,window));let accept=w.accept();accept();w.viewWillDisappear(false);w.viewWillAppear(false);accept();XCTAssertEqual(ChatNavigationHooks.shared.submitted.count,1)}
    func testRetainedWrapperAcceptDoesNotRetainContext() {let c=make();var w:Wrap?=Wrap(NavigationViewController(c,window));weak var context=w!.context;let accept=w!.accept();w=nil;XCTAssertNil(context);accept();XCTAssertTrue(ChatNavigationHooks.shared.submitted.isEmpty)}
    func testHideYearLinkUsesClickedDay() {let c=make();let w=Wrap(NavigationViewController(c,window));let i=ModalInteractions();click(c,25);w.hide(i)("");XCTAssertEqual(c.date,date(CalendarUtils.yearForNoYear,6,25));XCTAssertEqual(i.updates,1);XCTAssertEqual(w.modal?.resized,1)}
    func testHideYearLinkAfterCancelDoesNothing() {let c=make();let w=Wrap(NavigationViewController(c,window));let i=ModalInteractions();let hide=w.hide(i);w.viewWillDisappear(false);hide("");XCTAssertEqual(c.date,date());XCTAssertEqual(i.updates,0)}
    func testHideYearLinkAfterSubmissionDoesNothing() {let c=make();let w=Wrap(NavigationViewController(c,window));let i=ModalInteractions();w.accept()();w.hide(i)("");XCTAssertEqual(c.date,date());XCTAssertEqual(i.updates,0)}
    func testYearChangeCannotSelectFutureBirthday() {let c=make(date(2000,12,31));c.interactions.changeYear(2026,current(c).month.month);XCTAssertEqual(c.date,date(2026,10,17));XCTAssertEqual(current(c).month.selectedDay,17)}
    func testYearChangeRespectsExplicitUpperLimit() {let c=make(date(2000,6,15),limit:date(2001,3,10));c.interactions.changeYear(2001,current(c).month.month);XCTAssertEqual(c.date,date(2001,3,10))}
    func testHiddenYearIsUnavailableWhenDisabled() {let c=make(canBeNoYear:false);c.hideYear();XCTAssertEqual(c.date,date())}
    func testYearBelowPickerMinimumDoesNotChangeSelection() {let c=make();c.interactions.changeYear(1800,current(c).month.month);XCTAssertEqual(c.date,date())}
    func testFuturePickerYearChangeClampsToAllowedRange() {let c=make(date(2027,1,1),future:true);c.interactions.changeYear(2026,current(c).month.month);XCTAssertEqual(c.date,date(2026,10,17));c.interactions.changeYear(2028,date(2028,12,1));XCTAssertEqual(c.date,date(2027,10,17))}
    func testFuturePickerCannotHideYear() {let c=make(date(2026,10,20),future:true);c.hideYear();XCTAssertEqual(c.date,date(2026,10,20))}

}
