import Foundation
import SwiftSignalKit
import XCTest

struct TelegramBirthday:Equatable {let day:Int;let month:Int;let year:Int?}
extension Date {var birthday:TelegramBirthday {let c=Calendar(identifier:.gregorian);return .init(day:c.component(.day,from:self),month:c.component(.month,from:self),year:c.component(.year,from:self))}}
enum UpdateBirthdayError {case generic,flood}
final class Window {var messages:[String]=[]}
final class View {weak var window:Window?;init(_ window:Window) {self.window=window}}
final class Controller {let view:View;var willAppear:((Controller)->Void)?;var willDisappear:((Controller)->Void)?;var onDeinit:(()->Void)?;init(_ window:Window) {view=View(window)};func isLoaded()->Bool {true};deinit {onDeinit?()}}
final class Queue {static let main=Queue();var jobs:[()->Void]=[];static func mainQueue()->Queue {main};func justDispatch(_ f:@escaping()->Void) {jobs.append(f)};func drain() {while !jobs.isEmpty {jobs.removeFirst()()}}}
func deliverOnMainQueue<T,E>(_ s:Signal<T,E>)->Signal<T,E> {s}
final class Progress {static var pending:[MetaDisposable]=[]}
func showModalProgress<T,E>(signal:Signal<T,E>,for window:Window,shouldPresent:@escaping()->Bool={true})->Signal<T,E> {Signal {s in let d=MetaDisposable();Progress.pending.append(d);d.set(signal.start(next:{s.putNext($0)},error:{s.putError($0)},completed:{s.putCompletion()}));return d}}
struct Strings {let loginFloodWait="Flood",unknownError="Error",birthdayAlertAdded="Added"}
func strings()->Strings {Strings()}
func showModalText(for window:Window,text:String) {window.messages.append(text)}
final class Request {let birthday:TelegramBirthday?;let subscriber:Subscriber<Never,UpdateBirthdayError>;var disposed=false;init(_ birthday:TelegramBirthday?,_ subscriber:Subscriber<Never,UpdateBirthdayError>) {self.birthday=birthday;self.subscriber=subscriber};func accept() {subscriber.putCompletion()};func reject(_ error:UpdateBirthdayError = .generic) {subscriber.putError(error)}}
final class AccountData {var requests:[Request]=[];var onStart:((Request)->Void)?;func updateBirthday(birthday:TelegramBirthday?)->Signal<Never,UpdateBirthdayError> {Signal {s in let r=Request(birthday,s);self.requests.append(r);self.onStart?(r);return ActionDisposable {r.disposed=true}}}}
struct Engine {let accountData=AccountData()}
final class Context {var window=Window();let engine=Engine()}
final class CalendarController {let selected:(Date)->Void;init(_ selected:@escaping(Date)->Void) {self.selected=selected}}
final class SettingsNavigationHooks {static let shared=SettingsNavigationHooks();func makeBirthdayCalendarController(_ window:Window,_ selected:@escaping(Date)->Void)->CalendarController {CalendarController(selected)};func makeBirthdayCalendarController(_ window:Window,_ current:Date,_ selected:@escaping(Date)->Void)->CalendarController {CalendarController(selected)}}
extension TelegramBirthday {var dateForPicker:Date? {nil}}
struct PickerState {var birthday:TelegramBirthday? {nil}}
struct PickerStateValue {func with<T>(_ f:(PickerState)->T)->T {f(PickerState())}}
__HELPER__
__GLOBAL__
final class Screen {
    let context=Context();var controller:Controller?;let profileSaveAction=EditAccountProfileSaveAction();let birthdaySaveAction=EditAccountProfileSaveAction();let actionsDisposable=DisposableSet()
    init() {let controller=Controller(context.window);self.controller=controller;let profileSaveAction=self.profileSaveAction;let birthdaySaveAction=self.birthdaySaveAction;let avatarAcquisition=EditAccountProfileSaveAction();let actionsDisposable=self.actionsDisposable;__HOOKS__}
    func makeCalendar()->CalendarController {
        let context=self.context;let birthdaySaveAction=self.birthdaySaveAction;let getController:(()->Controller?)? = {[weak self] in self?.controller};let stateValue=PickerStateValue()
        __UPDATE__
        __CALENDAR__
        return controller
    }
    func remove() {
        let context=self.context;let birthdaySaveAction=self.birthdaySaveAction;let getController:(()->Controller?)? = {[weak self] in self?.controller}
        __UPDATE__
        let remove:()->Void = __REMOVE__
        remove()
    }
    func disappear() {if let c=controller {c.willDisappear?(c);c.view.window=nil}}
    func appear() {if let c=controller {c.view.window=context.window;c.willAppear?(c)}}
}
final class BirthdayUITests:XCTestCase {
    let date=Date(timeIntervalSince1970:946728000)
    override func setUp() {Progress.pending=[];Queue.mainQueue().drain()}
    func select(_ screen:Screen) {screen.makeCalendar().selected(date)}
    func testCalendarSelectionPassesBirthday() {let s=Screen();select(s);XCTAssertEqual(s.context.engine.accountData.requests.count,1);XCTAssertEqual(s.context.engine.accountData.requests[0].birthday,date.birthday);XCTAssertTrue(s.context.window.messages.isEmpty)}
    func testCalendarSuccessWaitsForAcceptance() {let s=Screen();select(s);XCTAssertTrue(s.context.window.messages.isEmpty);s.context.engine.accountData.requests[0].accept();XCTAssertEqual(s.context.window.messages,["Added"])}
    func testCalendarGenericFailureShowsError() {let s=Screen();select(s);s.context.engine.accountData.requests[0].reject();XCTAssertEqual(s.context.window.messages,["Error"])}
    func testCalendarFloodShowsFloodFeedback() {let s=Screen();select(s);s.context.engine.accountData.requests[0].reject(.flood);XCTAssertEqual(s.context.window.messages,["Flood"])}
    func testRemovalUsesNilAndNoAddedToast() {let s=Screen();s.remove();XCTAssertNil(s.context.engine.accountData.requests[0].birthday);s.context.engine.accountData.requests[0].accept();XCTAssertTrue(s.context.window.messages.isEmpty)}
    func testRemovalGenericFailureIsVisible() {let s=Screen();s.remove();s.context.engine.accountData.requests[0].reject();XCTAssertEqual(s.context.window.messages,["Error"])}
    func testRemovalFloodIsVisible() {let s=Screen();s.remove();s.context.engine.accountData.requests[0].reject(.flood);XCTAssertEqual(s.context.window.messages,["Flood"])}
    func testDuplicateSelectionIsCoalesced() {let s=Screen();let c=s.makeCalendar();c.selected(date);c.selected(date);XCTAssertEqual(s.context.engine.accountData.requests.count,1)}
    func testAddAndRemoveSharePendingGate() {let s=Screen();select(s);s.remove();XCTAssertEqual(s.context.engine.accountData.requests.count,1);XCTAssertNotNil(s.context.engine.accountData.requests[0].birthday)}
    func testRemoveAndAddSharePendingGate() {let s=Screen();s.remove();select(s);XCTAssertEqual(s.context.engine.accountData.requests.count,1);XCTAssertNil(s.context.engine.accountData.requests[0].birthday)}
    func testSelectionAfterDisappearanceDoesNotRequest() {let s=Screen();let c=s.makeCalendar();s.disappear();c.selected(date);XCTAssertTrue(s.context.engine.accountData.requests.isEmpty)}
    func testRemovalAfterDisappearanceDoesNotRequest() {let s=Screen();s.disappear();s.remove();XCTAssertTrue(s.context.engine.accountData.requests.isEmpty)}
    func testDisappearanceCancelsInFlightRequest() {let s=Screen();select(s);s.disappear();XCTAssertTrue(s.context.engine.accountData.requests[0].disposed);s.context.engine.accountData.requests[0].accept();XCTAssertTrue(s.context.window.messages.isEmpty)}
    func testRemovalDisappearanceSuppressesLateError() {let s=Screen();s.remove();s.disappear();XCTAssertTrue(s.context.engine.accountData.requests[0].disposed);s.context.engine.accountData.requests[0].reject();XCTAssertTrue(s.context.window.messages.isEmpty)}
    func testWindowChangeSuppressesFeedback() {let s=Screen();select(s);let w=Window();s.controller?.view.window=w;s.context.engine.accountData.requests[0].accept();XCTAssertTrue(s.context.window.messages.isEmpty);XCTAssertTrue(w.messages.isEmpty)}
    func testRetryAfterFlood() {let s=Screen();s.remove();s.context.engine.accountData.requests[0].reject(.flood);s.remove();XCTAssertEqual(s.context.engine.accountData.requests.count,2);s.context.engine.accountData.requests[1].accept();XCTAssertEqual(s.context.window.messages,["Flood"])}
    func testProgressCancellationIsQuietAndAllowsRetry() {let s=Screen();select(s);guard let pending=Progress.pending.last else {return XCTFail("Missing owned progress")};pending.dispose();Queue.mainQueue().drain();XCTAssertTrue(s.context.engine.accountData.requests[0].disposed);XCTAssertTrue(s.context.window.messages.isEmpty);select(s);XCTAssertEqual(s.context.engine.accountData.requests.count,2)}
    func testReappearAllowsNewRequestWithoutOldFeedback() {let s=Screen();select(s);s.disappear();s.appear();select(s);XCTAssertEqual(s.context.engine.accountData.requests.count,2);s.context.engine.accountData.requests[0].accept();XCTAssertTrue(s.context.window.messages.isEmpty);s.context.engine.accountData.requests[1].accept();XCTAssertEqual(s.context.window.messages,["Added"])}
    func testControllerReleaseCancelsRequest() {let s=Screen();select(s);s.controller=nil;XCTAssertTrue(s.context.engine.accountData.requests[0].disposed);s.context.engine.accountData.requests[0].accept();XCTAssertTrue(s.context.window.messages.isEmpty)}
    func testSynchronousAcceptanceClearsPending() {let s=Screen();s.context.engine.accountData.onStart={$0.accept()};select(s);Queue.mainQueue().drain();XCTAssertFalse(s.birthdaySaveAction.isPending);XCTAssertEqual(s.context.window.messages,["Added"])}
    func testGlobalHelperDoesNotRetainContext() {var c:Context?=Context();let data=c!.engine.accountData;let window=c!.window;editAccountUpdateBirthday(date,context:c!);weak var weakContext=c;c=nil;XCTAssertNil(weakContext);data.requests[0].accept();XCTAssertTrue(window.messages.isEmpty)}
    func testGlobalHelperDoesNotRetainOriginalWindow() {let c=Context();weak var window=c.window;editAccountUpdateBirthday(date,context:c);c.window=Window();XCTAssertNil(window);c.engine.accountData.requests[0].accept();XCTAssertTrue(c.window.messages.isEmpty)}
    func testGlobalHelperRejectsReplacedWindowOnError() {let c=Context();let old=c.window;editAccountUpdateBirthday(date,context:c);c.window=Window();c.engine.accountData.requests[0].reject(.flood);XCTAssertTrue(old.messages.isEmpty);XCTAssertTrue(c.window.messages.isEmpty)}
    func testGlobalHelperPreservesFloodAndSuccess() {for failure in [false,true] {let c=Context();editAccountUpdateBirthday(date,context:c);if failure {c.engine.accountData.requests[0].reject(.flood)} else {c.engine.accountData.requests[0].accept()};XCTAssertEqual(c.window.messages,[failure ? "Flood" : "Added"])}}
}
