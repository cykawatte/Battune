import CBattuneCore
import Foundation

public enum ScheduleResolver {
  public static func active(
    _ schedules: [ChargeSchedule], at date: Date, calendar: Calendar = .current
  ) throws -> ChargeSchedule? {
    guard schedules.count <= 32 else { throw BattuneError.invalidConfiguration }
    for entry in schedules { try entry.validate() }
    let enabled = schedules.filter(\.enabled)
    let entries = try enabled.map { entry -> BattuneSchedule in
      guard let activation = lastActivation(entry, at: date, calendar: calendar) else {
        throw BattuneError.invalidConfiguration
      }
      return BattuneSchedule(
        id: entry.id, priority: entry.priority,
        age_seconds: Int64(date.timeIntervalSince(activation)))
    }
    let index = entries.withUnsafeBufferPointer {
      battune_schedule($0.baseAddress, UInt32($0.count))
    }
    if index == -1 { return nil }
    guard index >= 0, Int(index) < enabled.count else { throw BattuneError.invalidConfiguration }
    return enabled[Int(index)]
  }
  /// Missing spring times move to the next valid local time. A repeated autumn
  /// hour activates only on its first occurrence and never rolls the plan back.
  static func lastActivation(_ entry: ChargeSchedule, at date: Date, calendar: Calendar) -> Date? {
    for daysBack in 0...7 {
      guard
        let day = calendar.date(
          byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: date))
      else { continue }
      let weekday = (calendar.component(.weekday, from: day) + 5) % 7
      guard entry.days & (1 << weekday) != 0 else { continue }
      let components = DateComponents(hour: entry.minute / 60, minute: entry.minute % 60, second: 0)
      guard
        let activation = calendar.nextDate(
          after: day.addingTimeInterval(-1), matching: components, matchingPolicy: .nextTime,
          repeatedTimePolicy: .first), activation <= date
      else { continue }
      return activation
    }
    return nil
  }
  public static func activationToken(
    _ schedule: ChargeSchedule, at date: Date, calendar: Calendar = .current
  ) -> String {
    guard let activation = lastActivation(schedule, at: date, calendar: calendar) else {
      return "\(schedule.id):unresolved"
    }
    let c = calendar.dateComponents([.year, .month, .day], from: activation)
    return "\(schedule.id):\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0):\(schedule.minute)"
  }
}
