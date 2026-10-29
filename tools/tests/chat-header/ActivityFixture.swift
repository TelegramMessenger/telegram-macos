import AppKit

enum ActivityMode { case history, scheduled, pinned }
struct ActivityInteraction { var mode: ActivityMode = .history }
struct ActivityTheme {
    struct Colors { let accent = NSColor.systemBlue }
    let colors = Colors()
    func activity(key: Int, foregroundColor: NSColor, backgroundColor: NSColor) -> Int { 0 }
}
final class ActivityStatusView: NSView { var textLayout: Int? = 1 }
final class ActivityRecorder {
    var view: NSView? = NSView()
    var widths: [CGFloat] = []
    var cleanCount = 0
    func update(with value: Int, for width: CGFloat, theme: Int, layout: @escaping (Bool) -> Void) {
        widths.append(width)
        view?.frame.size = CGSize(width: width, height: 14)
        layout(true)
    }
    func clean() { cleanCount += 1 }
}
final class ActivityFixture {
    var inputActivities: Int? = 1
    var inputActivitiesWidth: CGFloat?
    var chatInteraction = ActivityInteraction()
    let theme = ActivityTheme()
    let centerBubble = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 40))
    let statusView = ActivityStatusView()
    let activities = ActivityRecorder()
    var showActivities = false
    var needsLayout = false
    init() { centerBubble.addSubview(statusView); activities.view?.wantsLayer = true }

    __ACTIVITY_UPDATE__

    __ACTIVITY_ATTACHMENT__

    func refresh() {
        let centerRect = centerBubble.frame
        __ACTIVITY_REFRESH__
    }
}

func runActivityChecks() {
    let before = checks
    let fixture = ActivityFixture()
    fixture.updateInputActivities()
    check(fixture.activities.widths == [840], "initial activity width changed")
    fixture.centerBubble.frame.size.width = 220
    fixture.refresh()
    check(fixture.activities.widths == [840, 160], "activity did not reflow beside inline search")
    check(fixture.statusView.isHidden && fixture.showActivities, "typing status disappeared")
    fixture.needsLayout = false
    fixture.refresh()
    check(fixture.activities.widths.count == 2 && !fixture.needsLayout, "stable width caused a layout loop")
    for mode in [ActivityMode.scheduled, .pinned] {
        fixture.chatInteraction.mode = mode
        fixture.updateInputActivities()
        let cleans = fixture.activities.cleanCount
        fixture.needsLayout = false
        fixture.refresh()
        check(fixture.activities.cleanCount == cleans && !fixture.needsLayout, "inactive chat mode caused a layout loop")
    }
    fixture.chatInteraction.mode = .history
    fixture.inputActivities = nil
    fixture.updateInputActivities()
    check(!fixture.showActivities && !fixture.statusView.isHidden, "normal status did not return")
    print("PASS: \(checks - before) exact-source typing activity reflow and layout-loop checks")
}
