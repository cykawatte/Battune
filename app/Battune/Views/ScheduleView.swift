import SwiftUI
import BattuneDomain
import BattuneSystem
struct ScheduleView: View {
    @ObservedObject var settings: SettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("schedule_explanation")).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                ForEach($settings.value.schedules) { $entry in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Toggle("\(L("schedule")) \(entry.id)", isOn: $entry.enabled)
                                Spacer()
                                Button(role: .destructive) { settings.value.schedules.removeAll { $0.id == entry.id } } label: { Image(systemName: "trash") }.accessibilityLabel(L("delete_schedule"))
                            }
                            HStack {
                                ForEach(0..<7) { day in
                                    Toggle(L("day.\(day)"), isOn: Binding(get: { entry.days & (1 << day) != 0 }, set: { on in
                                        if on { entry.days |= 1 << day } else { entry.days &= ~(1 << day) }
                                    })).toggleStyle(.button)
                                }
                            }
                            HStack {
                                Stepper("\(L("hour")): \(entry.minute / 60)", value: Binding(get: { entry.minute / 60 }, set: { entry.minute = $0 * 60 + entry.minute % 60 }), in: 0...23)
                                Stepper("\(L("minute")): \(entry.minute % 60)", value: Binding(get: { entry.minute % 60 }, set: { entry.minute = entry.minute / 60 * 60 + $0 }), in: 0...59)
                            }
                            Stepper("\(L("charge_limit")): \(entry.settings.limit)%", value: $entry.settings.limit, in: 20...100)
                            Toggle(L("sailing"), isOn: $entry.settings.sailing)
                            if entry.settings.sailing { Stepper("\(L("lower_limit")): \(entry.settings.lower)%", value: $entry.settings.lower, in: 20...99) }
                            Toggle(L("scheduled_discharge"), isOn: Binding(get: { entry.dischargeTarget != nil }, set: { entry.dischargeTarget = $0 ? 75 : nil }))
                            if entry.dischargeTarget != nil {
                                Stepper("\(L("target")): \(entry.dischargeTarget ?? 75)%", value: Binding(get: { entry.dischargeTarget ?? 75 }, set: { entry.dischargeTarget = $0 }), in: 20...100)
                            }
                            Stepper("\(L("priority")): \(entry.priority)", value: $entry.priority, in: 0...100)
                        }.padding(6)
                    }
                }
            }
            Button(L("add_schedule")) {
                let id = (settings.value.schedules.map(\.id).max() ?? 0) &+ 1
                settings.value.schedules.append(ChargeSchedule(id: id))
            }.disabled(settings.value.schedules.count >= 32)
        }.padding(12)
    }
}
