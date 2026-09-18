import Foundation
import EventKit

/// A date-only deadline stays date-only in EventKit. Notification dates are
/// explicit so an early alert doesn't change the actual deadline.
struct ReminderTiming: Codable, Equatable {
    var due: DateComponents?
    var notificationDate: Date?

    static func normalized(_ components: DateComponents?) -> DateComponents? {
        guard let components else { return nil }
        return DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: components.timeZone,
                              year: components.year, month: components.month, day: components.day,
                              hour: components.hour, minute: components.hour == nil ? nil : (components.minute ?? 0))
    }

    var date: Date? {
        guard let due else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = due.timeZone ?? .current
        return calendar.date(from: due)
    }

    var hasTime: Bool { due?.hour != nil }

    var notificationAnchor: Date? {
        guard let date else { return nil }
        if hasTime { return date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = due?.timeZone ?? .current
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
    }

    var leadMinutes: Int? {
        guard let anchor = notificationAnchor, let notificationDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = due?.timeZone ?? .current
        let days = calendar.dateComponents([.day], from: notificationDate, to: anchor).day ?? 0
        if days != 0, calendar.date(byAdding: .day, value: -days, to: anchor) == notificationDate { return days * 1440 }
        return Int((anchor.timeIntervalSince(notificationDate) / 60).rounded())
    }

    static func make(date: Date, hasTime: Bool, leadMinutes: Int?, calendar input: Calendar = .current) -> ReminderTiming {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.timeZone
        let fields: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        var components = calendar.dateComponents(fields, from: date)
        // Date-only deadlines float with the local calendar; timed ones keep their zone.
        components.timeZone = hasTime ? calendar.timeZone : nil
        var timing = ReminderTiming(due: normalized(components))
        if let leadMinutes, let anchor = timing.notificationAnchor {
            // "One day before" keeps the same wall-clock time across DST changes.
            timing.notificationDate = leadMinutes != 0 && leadMinutes % 1440 == 0
                ? calendar.date(byAdding: .day, value: -(leadMinutes / 1440), to: anchor)
                : calendar.date(byAdding: .minute, value: -leadMinutes, to: anchor)
        }
        return timing
    }

    static func read(_ reminder: EKReminder) -> ReminderTiming? {
        let due = normalized(reminder.dueDateComponents)
        let start = reminder.startDateComponents.flatMap { components -> Date? in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = components.timeZone ?? .current
            return calendar.date(from: components)
        }
        let dates = (reminder.alarms ?? []).filter { $0.structuredLocation == nil }.compactMap { alarm in
            alarm.absoluteDate ?? start?.addingTimeInterval(alarm.relativeOffset)
        }
        let notification = dates.min()
        return due == nil && notification == nil ? nil : ReminderTiming(due: due, notificationDate: notification)
    }

    /// Preserve unrelated alarms/metadata when only a checkbox or title changes.
    static func apply(_ timing: ReminderTiming?, to reminder: EKReminder) {
        let previous = read(reminder)
        if previous?.due != timing?.due {
            reminder.dueDateComponents = timing?.due
            reminder.startDateComponents = timing?.due
        }
        if previous?.notificationDate != timing?.notificationDate || previous?.due != timing?.due {
            for alarm in reminder.alarms ?? [] where alarm.structuredLocation == nil {
                reminder.removeAlarm(alarm)
            }
            if let date = timing?.notificationDate { reminder.addAlarm(EKAlarm(absoluteDate: date)) }
        }
    }
}
