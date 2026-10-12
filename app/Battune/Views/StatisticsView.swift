import AppKit
import BattuneDomain
import BattuneSystem
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct StatisticsView: View {
  @ObservedObject var coordinator: ChargeCoordinator
  @ObservedObject var history: HistoryStore
  let loadFailed: Bool
  @ViewState private var days = 1
  @ViewState private var metric = "charge"
  @ViewState private var operationFailed = false
  @ViewState private var confirmClear = false
  private var since: Date { Date().addingTimeInterval(-Double(days) * 86400) }
  private var samples: [BatterySnapshot] { history.samples.filter { $0.timestamp >= since } }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 8) {
          row("health", coordinator.snapshot.health.map { String(format: "%.1f%%", $0) })
          row("cycles", coordinator.snapshot.cycleCount.map(String.init))
          row("capacity", coordinator.snapshot.maximumCapacity.map { "\($0) mAh" })
          row("design_capacity", coordinator.snapshot.designCapacity.map { "\($0) mAh" })
          row("temperature", coordinator.snapshot.temperature.map { String(format: "%.1f °C", $0) })
          row("voltage", coordinator.snapshot.voltage.map { String(format: "%.2f V", $0) })
          row("current", coordinator.snapshot.current.map { String(format: "%.2f A", $0) })
          row("power", coordinator.snapshot.power.map { String(format: "%.1f W", $0) })
          row("adapter", coordinator.snapshot.adapterWatts.map { "\($0) W" })
        }
        Text(localized("health_ratio_note")).font(.caption).foregroundStyle(.secondary)
        HStack {
          Picker(localized("period"), selection: $days) {
            Text("24 h").tag(1)
            Text("7 d").tag(7)
            Text("30 d").tag(30)
          }.pickerStyle(.segmented)
          Picker(localized("metric"), selection: $metric) {
            Text(localized("charge")).tag("charge")
            Text(localized("temperature")).tag("temperature")
            Text(localized("power")).tag("power")
          }
        }
        if samples.compactMap(reading).isEmpty {
          Text(localized("history_empty")).foregroundStyle(.secondary).frame(
            maxWidth: .infinity, minHeight: 160)
        } else {
          Chart(Array(samples.enumerated()), id: \.offset) { entry in
            if let value = reading(entry.element) {
              LineMark(
                x: .value(localized("time"), entry.element.timestamp),
                y: .value(localized(metric), value))
              PointMark(
                x: .value(localized("time"), entry.element.timestamp),
                y: .value(localized(metric), value)
              ).symbolSize(8)
            }
          }.chartXScale(domain: since...Date()).frame(height: 180)
            .accessibilityLabel(localized("history_chart"))
          HStack {
            Text("\(localized("samples")): \(samples.compactMap(reading).count)")
            Spacer()
            if let minimum = samples.compactMap(reading).min(),
              let maximum = samples.compactMap(reading).max()
            {
              Text(String(format: "Min %.1f · Max %.1f", minimum, maximum)).monospacedDigit()
            }
          }.font(.caption).foregroundStyle(.secondary)
        }
        Text(localized("power_sign_note")).font(.caption).foregroundStyle(.secondary)
        if loadFailed || operationFailed || coordinator.historyError {
          Text(localized("history_error")).foregroundStyle(.red)
        }
        HStack {
          Text(localized("history_retention")).font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button(localized("export_csv"), action: export)
          Button(localized("clear_history"), role: .destructive) { confirmClear = true }
        }
      }.padding(20)
    }.alert(localized("clear_history"), isPresented: $confirmClear) {
      Button(localized("cancel"), role: .cancel) {}
      Button(localized("clear_history"), role: .destructive) {
        do {
          try history.clear()
          operationFailed = false
        } catch { operationFailed = true }
      }
    }
  }
  private func reading(_ sample: BatterySnapshot) -> Double? {
    switch metric {
    case "temperature": return sample.temperature
    case "power": return sample.power
    default: return sample.percentage.map(Double.init)
    }
  }
  private func export() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "Battune-\(days)d.csv"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try history.exportCSV(since: since).write(to: url, atomically: true, encoding: .utf8)
        operationFailed = false
      } catch { operationFailed = true }
    }
  }
  private func row(_ key: String, _ value: String?) -> some View {
    GridRow {
      Text(localized(key)).foregroundStyle(.secondary)
      Text(value ?? localized("unknown")).monospacedDigit()
    }
  }
}
