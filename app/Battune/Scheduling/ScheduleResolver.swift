import Foundation
import CBattuneCore
public enum ScheduleResolver {
    public static func active(_ schedules: [ChargeSchedule], at date: Date, calendar: Calendar = .current) throws -> ChargeSchedule? {
        guard schedules.count <= 32 else { throw BattuneError.invalidConfiguration }
        for entry in schedules { try entry.validate() }
        let enabled = schedules.filter(\.enabled)
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday, let hour = components.hour, let minute = components.minute else { throw BattuneError.invalidConfiguration }
        let entries = enabled.map { BattuneSchedule(id: $0.id, days: $0.days, minute: UInt32($0.minute), priority: $0.priority) }
        let index = entries.withUnsafeBufferPointer { battune_schedule($0.baseAddress, UInt32($0.count), UInt32((weekday + 5) % 7), UInt32(hour * 60 + minute)) }
        if index == -1 { return nil }
        guard index >= 0, Int(index) < enabled.count else { throw BattuneError.invalidConfiguration }
        return enabled[Int(index)]
    }
    /// Stable civil activation token: repeated DST hour must not restart discharge.
    public static func activationToken(_ schedule: ChargeSchedule, at date: Date, calendar: Calendar = .current) -> String {
        for daysBack in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: date) else { continue }
            let c = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: day)
            let weekday = ((c.weekday ?? 1) + 5) % 7
            let time = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            if schedule.days & (1 << weekday) != 0 && (daysBack > 0 || time >= schedule.minute) {
                return "\(schedule.id):\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0):\(schedule.minute)"
            }
        }
        return "\(schedule.id):unresolved"
    }
}
