import Cocoa
import Postbox
import TelegramCore
import DateUtils
import TGUIKit
import MapKit
import CalendarUtils
import Strings
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import Localization
import SwiftSignalKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif


public func stringForTimestamp(day: Int32, month: Int32, year: Int32) -> String {
    return String(format: "%d.%02d.%02d", day, month, year - 100)
}

public func stringForTime(hours: Int32, minutes: Int32) -> String {
    return String(format: "%d:%02d", hours, minutes)
}

public enum UserPresenceDay {
    case today
    case yesterday
}

public func stringForUserPresence(day: UserPresenceDay, hours: Int32, minutes: Int32) -> String {
    let dayString: String
    switch day {
    case .today:
        dayString = strings().peerStatusToday
    case .yesterday:
        dayString = strings().peerStatusYesterday
    }
    return strings().peerStatusLastSeenAt(dayString, stringForTime(hours: hours, minutes: minutes))
}

public enum RelativeUserPresenceLastSeen {
    case justNow
    case minutesAgo(Int32)
    case hoursAgo(Int32)
    case todayAt(hours: Int32, minutes: Int32)
    case yesterdayAt(hours: Int32, minutes: Int32)
    case thisYear(month: Int32, day: Int32)
    case atDate(year: Int32, month: Int32)
}



public func userPresenceText(_ presence: TelegramUserPresence, timeDifference: TimeInterval, relativeTo timestamp: Int32, expanded: Bool = false, customTheme: UserPresenceColors? = nil) -> (String, Bool, NSColor) {

    switch presence.status {
    case .none:
        return (strings().peerStatusLongTimeAgo, false, customTheme?.grayTextColor ?? theme.colors.grayText)
    case let .present(statusTimestamp):
        let statusTimestampInt: Int = Int(statusTimestamp)
        let statusTimestamp = Int32(min(statusTimestampInt - Int(timeDifference), Int(INT32_MAX)))
        if statusTimestamp > timestamp {
            return (strings().peerStatusOnline, true, customTheme?.accentColor ?? theme.colors.accent)
        } else {
            let difference = timestamp - statusTimestamp
            if difference < 59 {
                return (strings().peerStatusJustNow, false, customTheme?.grayTextColor ?? theme.colors.grayText)
            } else if difference < 60 * 60 && !expanded {
                let minutes = max(difference / 60, 1)

                return (strings().peerStatusMinAgoOther(Int(minutes)), false, customTheme?.grayTextColor ?? theme.colors.grayText)
            } else {
                var t: time_t = time_t(statusTimestamp)
                var timeinfo: tm = tm()
                localtime_r(&t, &timeinfo)

                var now: time_t = time_t(timestamp)
                var timeinfoNow: tm = tm()
                localtime_r(&now, &timeinfoNow)

                if timeinfo.tm_year != timeinfoNow.tm_year {
                    return ("\(strings().timeLastSeen) \(stringForTimestamp(day: timeinfo.tm_mday, month: timeinfo.tm_mon + 1, year: timeinfo.tm_year))", false, customTheme?.grayTextColor ?? theme.colors.grayText)
                }

                let dayDifference = timeinfo.tm_yday - timeinfoNow.tm_yday
                if dayDifference == 0 || dayDifference == -1 {
                    let day: UserPresenceDay
                    if dayDifference == 0 {
                        if expanded {
                            day = .today
                        } else {
                            let minutes = difference / (60 * 60)

                            return (strings().lastSeenHoursAgoOther(Int(minutes)), false, customTheme?.grayTextColor ?? theme.colors.grayText)
                        }
                    } else {
                        day = .yesterday
                    }
                    return (stringForUserPresence(day: day, hours: timeinfo.tm_hour, minutes: timeinfo.tm_min), false, customTheme?.grayTextColor ?? theme.colors.grayText)
                } else {
                    return ("\(strings().timeLastSeen) \(stringForTimestamp(day: timeinfo.tm_mday, month: timeinfo.tm_mon + 1, year: timeinfo.tm_year))", false, customTheme?.grayTextColor ?? theme.colors.grayText)
                }
            }
        }
    case .recently:
        let activeUntil = presence.lastActivity - Int32(timeDifference) + 30
        if activeUntil >= timestamp {
            return (strings().peerStatusOnline, true, customTheme?.accentColor ?? theme.colors.accent)
        } else {
            return (strings().peerStatusRecently, false, customTheme?.grayTextColor ?? theme.colors.grayText)
        }
    case .lastWeek:
        return (strings().peerStatusLastWeek, false, customTheme?.grayTextColor ?? theme.colors.grayText)
    case .lastMonth:
        return (strings().peerStatusLastMonth, false, customTheme?.grayTextColor ?? theme.colors.grayText)
    }
}

public func userPresenceStringRefreshTimeout(_ presence: TelegramUserPresence, timeDifference: Int32, relativeTo timestamp: Int32) -> Double {
    switch presence.status {
    case let .present(statusTimestamp):

        let statusTimestampInt: Int = Int(statusTimestamp)
        let statusTimestamp = Int32(min(statusTimestampInt, Int(INT32_MAX)))

        if statusTimestamp > INT32_MAX - 1 {
            return Double.infinity
        }
        if statusTimestamp >= timestamp {
            return max(1.0, Double(statusTimestamp - timestamp))
        } else {
            let difference = timestamp - statusTimestamp
            if difference < 30 {
                return Double((30 - difference) + 1)
            } else if difference < 60 * 60 {
                return Double((difference % 60) + 1)
            } else {
                return Double.infinity
            }
        }
    case .recently:
        let activeUntil = presence.lastActivity - timeDifference + 30
        if activeUntil >= timestamp {
            return Double(activeUntil - timestamp + 1)
        } else {
            return Double.infinity
        }

    case .none, .lastWeek, .lastMonth:
        return Double.infinity
    }
}


public func stringForRelativeSymbolicTimestamp(relativeTimestamp: Int32, relativeTo timestamp: Int32, medium: Bool = false) -> String {
    var t: time_t = time_t(relativeTimestamp)
    var timeinfo: tm = tm()
    localtime_r(&t, &timeinfo)

    var now: time_t = time_t(timestamp)
    var timeinfoNow: tm = tm()
    localtime_r(&now, &timeinfoNow)

    let dayDifference = timeinfo.tm_yday - timeinfoNow.tm_yday

    let hours = timeinfo.tm_hour
    let minutes = timeinfo.tm_min

    if dayDifference == 0 {
        return strings().timeTodayAt(stringForShortTimestamp(hours: hours, minutes: minutes))
    } else {
        if medium {
            return stringForMediumDate(timestamp: relativeTimestamp)
        } else {
            return stringForFullDate(timestamp: relativeTimestamp)
        }
    }
}



public func stringForShortTimestamp(hours: Int32, minutes: Int32) -> String {



    var components = DateComponents()
    components.hour = Int(hours)
    components.minute = Int(minutes)

    // Use the current calendar to ensure the components are interpreted correctly
    let calendar = Calendar.current

    // Optional: you might want to ensure you're using the current time zone
    components.timeZone = TimeZone.current

    // Create a Date from components
    guard let date = calendar.date(from: components) else {
        print("Failed to create date from components.")
        return ""
    }

    // Create a DateFormatter and set its dateStyle to .none and timeStyle to .short
    // This will ensure that the time is formatted according to the user's locale
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short

    // Format the date to a string
    let formattedTime = formatter.string(from: date)

    return formattedTime
//
}

public func stringForDuration(_ duration: Int32) -> String {
    return String.durationTransformed(elapsed: Int(duration))
}

public func stringForFullDate(timestamp: Int32) -> String {
    var t: time_t = Int(timestamp)
    var timeinfo = tm()
    localtime_r(&t, &timeinfo);

    switch timeinfo.tm_mon + 1 {
    case 1:
        return strings().timePreciseDateM1("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 2:
        return strings().timePreciseDateM2("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 3:
        return strings().timePreciseDateM3("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 4:
        return strings().timePreciseDateM4("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 5:
        return strings().timePreciseDateM5("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 6:
        return strings().timePreciseDateM6("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 7:
        return strings().timePreciseDateM7("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 8:
        return strings().timePreciseDateM8("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 9:
        return strings().timePreciseDateM9("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 10:
        return strings().timePreciseDateM10("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 11:
        return strings().timePreciseDateM11("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 12:
        return strings().timePreciseDateM12("\(timeinfo.tm_mday)", "\(2000 + timeinfo.tm_year - 100)", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    default:
        return ""
    }
}

public func stringForDate(timestamp: Int32) -> String {
    var t: time_t = Int(timestamp)
    var timeinfo = tm()
    localtime_r(&t, &timeinfo);

    switch timeinfo.tm_mon + 1 {
    case 1:
        return strings().timePreciseDateM1("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 2:
        return strings().timePreciseDateM2("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 3:
        return strings().timePreciseDateM3("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 4:
        return strings().timePreciseDateM4("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 5:
        return strings().timePreciseDateM5("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 6:
        return strings().timePreciseDateM6("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 7:
        return strings().timePreciseDateM7("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 8:
        return strings().timePreciseDateM8("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 9:
        return strings().timePreciseDateM9("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 10:
        return strings().timePreciseDateM10("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 11:
        return strings().timePreciseDateM11("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    case 12:
        return strings().timePreciseDateM12("\(timeinfo.tm_mday)", "", stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min)))
    default:
        return ""
    }
}

public extension Date {

    var isToday: Bool {
        return CalendarUtils.isSameDate(self, date: Date(), checkDay: true)
    }
    var isTomorrow: Bool {
        return Calendar.current.isDateInTomorrow(self)
    }
}


public func stringForMediumDate(timestamp: Int32) -> String {
    var t: time_t = Int(timestamp)
    var timeinfo = tm()
    localtime_r(&t, &timeinfo);

    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))

    if date.isToday || date.timeIntervalSince1970 < Date().timeIntervalSince1970 {
        return DateUtils.string(forLastSeen: timestamp)
    }

    let formatter = DateFormatter()
    formatter.timeStyle = .short
    let time = formatter.string(from: date)

    if date.isTomorrow {
        return strings().timeTomorrowAt(time)
    }



    switch timeinfo.tm_mon + 1 {
    case 1:
        return strings().timePreciseMediumDateM1("\(timeinfo.tm_mday)", time)
    case 2:
        return strings().timePreciseMediumDateM2("\(timeinfo.tm_mday)", time)
    case 3:
        return strings().timePreciseMediumDateM3("\(timeinfo.tm_mday)", time)
    case 4:
        return strings().timePreciseMediumDateM4("\(timeinfo.tm_mday)", time)
    case 5:
        return strings().timePreciseMediumDateM5("\(timeinfo.tm_mday)", time)
    case 6:
        return strings().timePreciseMediumDateM6("\(timeinfo.tm_mday)", time)
    case 7:
        return strings().timePreciseMediumDateM7("\(timeinfo.tm_mday)", time)
    case 8:
        return strings().timePreciseMediumDateM8("\(timeinfo.tm_mday)", time)
    case 9:
        return strings().timePreciseMediumDateM9("\(timeinfo.tm_mday)", time)
    case 10:
        return strings().timePreciseMediumDateM10("\(timeinfo.tm_mday)", time)
    case 11:
        return strings().timePreciseMediumDateM11("\(timeinfo.tm_mday)", time)
    case 12:
        return strings().timePreciseMediumDateM12("\(timeinfo.tm_mday)", time)
    default:
        return ""
    }
}

private var sharedDistanceFormatter: MKDistanceFormatter?
public func stringForDistance(distance: CLLocationDistance) -> String {
    let distanceFormatter: MKDistanceFormatter
    if let currentDistanceFormatter = sharedDistanceFormatter {
        distanceFormatter = currentDistanceFormatter
    } else {
        distanceFormatter = MKDistanceFormatter()
        distanceFormatter.unitStyle = .full
        sharedDistanceFormatter = distanceFormatter
    }

    return distanceFormatter.string(fromDistance: distance)
}



public func formatBirthdayToString(day: Int, month: Int, year: Int?) -> String? {
    let calendar = Calendar(identifier: .gregorian)
    let dateYear = year ?? CalendarUtils.yearForNoYear
    guard let date = calendar.date(from: DateComponents(year: dateYear, month: month, day: day)) else { return nil }
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard components.year == dateYear, components.month == month, components.day == day else { return nil }

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale.current
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = TimeZone.current
    if year == nil {
        dateFormatter.dateFormat = "MMM d"
    } else {
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
    }
    return dateFormatter.string(from: date)
}


public func formatDHm(from seconds: Int32) -> String {
    let d = seconds / 86_400
    let h = (seconds % 86_400) / 3_600
    let m = (seconds % 3_600) / 60

    var parts: [String] = []

    let ds = strings().formatTimeoutShortDay
    let hs = strings().formatTimeoutShortHour
    let ms = strings().formatTimeoutShortMinute

    if d > 0 { parts.append("\(d)\(ds)") }
    if h > 0 || d > 0 { parts.append("\(h)\(hs)") }
    parts.append("\(m)\(ms)")

    return parts.joined(separator: " ")
}

public struct UserPresenceColors {
    public let grayTextColor: NSColor
    public let accentColor: NSColor

    public init(grayTextColor: NSColor, accentColor: NSColor) {
        self.grayTextColor = grayTextColor
        self.accentColor = accentColor
    }
}
