import BattuneDomain
import BattuneSystem
import SwiftUI

struct ScheduleView: View {
  @ObservedObject var settings: SettingsModel
  @ObservedObject var coordinator: ChargeCoordinator
  private var nativeSteps: [Int]? {
    settings.value.advancedControl == true ? nil : coordinator.capabilities.nativeChargeLimits
  }
  var body: some View {
    Form {
      Section {
        if settings.value.schedules.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 28))
              .foregroundStyle(.secondary)
            Text(localized("schedules_empty")).foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        HStack {
          Menu {
            Button(localized("template.weekend")) { add(.weekend) }
            Button(localized("template.monday")) { add(.monday) }
          } label: {
            Label(localized("templates"), systemImage: "sparkles")
          }
          .fixedSize()
          Spacer()
          Button {
            add(.blank)
          } label: {
            Label(localized("add_schedule"), systemImage: "plus")
          }
          .disabled(settings.value.schedules.count >= 32)
        }
      } footer: {
        Text(localized("schedule_explanation")).font(.caption).foregroundStyle(.secondary)
      }
      ForEach($settings.value.schedules) { $entry in
        Section {
          editor($entry)
        } header: {
          HStack {
            Toggle(isOn: $entry.enabled) {
              Text(summary(entry)).font(.headline).textCase(nil)
            }
            .toggleStyle(.switch)
            Spacer()
            Button(role: .destructive) {
              settings.value.schedules.removeAll { $0.id == entry.id }
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(localized("delete_schedule"))
          }
        }
      }
    }.formStyle(.grouped)
  }

  @ViewBuilder private func editor(_ entry: Binding<ChargeSchedule>) -> some View {
    HStack(spacing: 4) {
      ForEach(0..<7) { day in
        let on = entry.wrappedValue.days & (1 << day) != 0
        Button {
          if on, entry.wrappedValue.days.nonzeroBitCount > 1 {
            entry.wrappedValue.days &= ~(1 << day)
          } else {
            entry.wrappedValue.days |= 1 << day
          }
        } label: {
          Text(localized("day.\(day)")).font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.07)))
            .foregroundStyle(on ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    DatePicker(
      localized("time"),
      selection: Binding(
        get: {
          Calendar.current.date(
            bySettingHour: entry.wrappedValue.minute / 60,
            minute: entry.wrappedValue.minute % 60, second: 0, of: Date()) ?? Date()
        },
        set: {
          let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
          entry.wrappedValue.minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }),
      displayedComponents: .hourAndMinute)
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(localized("charge_limit"))
        Spacer()
        Text("\(entry.wrappedValue.settings.limit)%").monospacedDigit().foregroundStyle(.secondary)
      }
      LimitPicker(
        limit: entry.settings.limit, supported: nativeSteps,
        range: (entry.wrappedValue.settings.sailing ? 21 : 20)...100
      ) {}
    }
    .onChange(of: entry.wrappedValue.settings.limit) { limit in
      entry.wrappedValue.settings.lower = min(entry.wrappedValue.settings.lower, max(20, limit - 1))
    }
    if coordinator.capabilities.forceDischarge {
      Toggle(
        localized("scheduled_discharge"),
        isOn: Binding(
          get: { entry.wrappedValue.dischargeTarget != nil },
          set: { entry.wrappedValue.dischargeTarget = $0 ? 75 : nil }))
      if entry.wrappedValue.dischargeTarget != nil {
        SettingsSlider(
          "target",
          value: Binding(
            get: { entry.wrappedValue.dischargeTarget ?? 75 },
            set: { entry.wrappedValue.dischargeTarget = $0 }), in: 20...100)
      }
    }
    Stepper(
      "\(localized("priority")): \(entry.wrappedValue.priority)", value: entry.priority,
      in: 0...100)
  }

  private func summary(_ entry: ChargeSchedule) -> String {
    let days: String
    switch entry.days {
    case 127: days = localized("every_day")
    case 31: days = localized("weekdays")
    case 96: days = localized("weekend")
    default:
      days = (0..<7).filter { entry.days & (1 << $0) != 0 }.map { localized("day.\($0)") }
        .joined(separator: " ")
    }
    return String(
      format: "%@ · %02d:%02d · %d%%", days, entry.minute / 60, entry.minute % 60,
      entry.settings.limit)
  }

  private enum Template { case blank, weekend, monday }
  /// AlDente-style presets expressed as ordinary, editable weekly schedules.
  private func add(_ template: Template) {
    guard settings.value.schedules.count < 32 else { return }
    let id = (settings.value.schedules.map(\.id).max() ?? 0) &+ 1
    var entry = ChargeSchedule(id: id)
    let base = settings.value.charge.limit
    switch template {
    case .blank:
      entry.settings.limit = base
    case .weekend:
      entry.days = 1 << 4
      entry.minute = 18 * 60
      entry.settings.limit = 100
      settings.value.schedules.append(entry)
      entry = ChargeSchedule(id: id &+ 1)
      entry.days = 1 << 6
      entry.minute = 20 * 60
      entry.settings.limit = base
    case .monday:
      entry.days = 1 << 0
      entry.minute = 5 * 60
      entry.settings.limit = 100
      settings.value.schedules.append(entry)
      entry = ChargeSchedule(id: id &+ 1)
      entry.days = 1 << 0
      entry.minute = 12 * 60
      entry.settings.limit = base
    }
    if let steps = nativeSteps, !steps.contains(entry.settings.limit) {
      entry.settings.limit = CoreBridge.nativeCeiling(entry.settings.limit, supported: steps) ?? 100
    }
    entry.settings.lower = max(20, min(entry.settings.lower, entry.settings.limit - 1))
    if settings.value.schedules.count < 32 { settings.value.schedules.append(entry) }
  }
}
