import BattuneDomain
import BattuneSystem
import SwiftUI

struct ScheduleView: View {
  @ObservedObject var settings: SettingsModel
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(localized("schedule_explanation")).font(.callout).foregroundStyle(.secondary)
      ScrollView {
        ForEach($settings.value.schedules) { $entry in
          GroupBox {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Toggle("\(localized("schedule")) \(entry.id)", isOn: $entry.enabled)
                Spacer()
                Button(role: .destructive) {
                  settings.value.schedules.removeAll { $0.id == entry.id }
                } label: {
                  Image(systemName: "trash")
                }.accessibilityLabel(localized("delete_schedule"))
              }
              HStack {
                ForEach(0..<7) { day in
                  Toggle(
                    localized("day.\(day)"),
                    isOn: Binding(
                      get: { entry.days & (1 << day) != 0 },
                      set: { on in
                        if on { entry.days |= 1 << day } else { entry.days &= ~(1 << day) }
                      })
                  ).toggleStyle(.button)
                }
              }
              SettingsSlider(
                "hour",
                value: Binding(
                  get: { entry.minute / 60 }, set: { entry.minute = $0 * 60 + entry.minute % 60 }),
                in: 0...23, unit: "")
              SettingsSlider(
                "minute",
                value: Binding(
                  get: { entry.minute % 60 }, set: { entry.minute = entry.minute / 60 * 60 + $0 }),
                in: 0...59, unit: "")
              SettingsSlider(
                "charge_limit", value: $entry.settings.limit,
                in: (entry.settings.sailing ? 21 : 20)...100
              )
              .onChange(of: entry.settings.limit) { limit in
                entry.settings.lower = min(entry.settings.lower, max(20, limit - 1))
              }
              Toggle(localized("sailing"), isOn: $entry.settings.sailing).disabled(
                entry.settings.limit <= 20)
              if entry.settings.sailing {
                SettingsSlider(
                  "lower_limit", value: $entry.settings.lower,
                  in: 20...max(21, entry.settings.limit - 1)
                ).disabled(entry.settings.limit <= 21)
              }
              Toggle(
                localized("scheduled_discharge"),
                isOn: Binding(
                  get: { entry.dischargeTarget != nil },
                  set: { entry.dischargeTarget = $0 ? 75 : nil }))
              if entry.dischargeTarget != nil {
                SettingsSlider(
                  "target",
                  value: Binding(
                    get: { entry.dischargeTarget ?? 75 }, set: { entry.dischargeTarget = $0 }),
                  in: 20...100)
              }
              SettingsSlider("priority", value: $entry.priority, in: 0...100, unit: "")
            }.padding(6)
          }
        }
      }
      Button(localized("add_schedule")) {
        let id = (settings.value.schedules.map(\.id).max() ?? 0) &+ 1
        settings.value.schedules.append(ChargeSchedule(id: id))
      }.disabled(settings.value.schedules.count >= 32)
    }.padding(12)
  }
}
