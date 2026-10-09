import AppKit
import SwiftUI
import BattuneDomain
import BattuneSystem
struct PopoverView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var coordinator: ChargeCoordinator
    let openSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Battune").font(.headline); Spacer(); Text("0.1.0-dev").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .firstTextBaseline) {
                Text(coordinator.snapshot.percentage.map { "\($0)%" } ?? "—").font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
                Spacer()
                Label(L(coordinator.snapshot.pluggedIn == true ? "ac_power" : coordinator.snapshot.pluggedIn == false ? "battery_power" : "unknown"), systemImage: coordinator.snapshot.pluggedIn == true ? "powerplug" : "battery.50percent")
                    .foregroundStyle(.secondary)
            }
            Text(L(coordinator.mode.localizationKey)).font(.headline)
            if !coordinator.capabilities.canControl { Label(L("unsupported"), systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack { Text(L("charge_limit")); Spacer(); Text("\(settings.value.charge.limit)%").monospacedDigit() }
            Slider(value: Binding(get: { Double(settings.value.charge.limit) }, set: { settings.value.charge.limit = Int($0) }), in: 20...100, step: 1) { editing in
                if !editing, settings.save() { coordinator.updateSettings(settings.value) }
            }.accessibilityLabel(L("charge_limit"))
            HStack { Text(L("sailing")); Spacer(); Text(L(settings.value.charge.sailing ? "on" : "off")) }
            HStack { Text(L("thermal")); Spacer(); Text(L(settings.value.charge.thermal ? "on" : "off")) }
            if let error = coordinator.lastError ?? settings.error { Text(L("error.\(error.rawValue)")).font(.caption).foregroundStyle(.red) }
            Divider()
            HStack {
                Button(L("settings"), action: openSettings).keyboardShortcut(",")
                Spacer()
                Button(L("quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }.padding(20).frame(width: 320)
    }
}
