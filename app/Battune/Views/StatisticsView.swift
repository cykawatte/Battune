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
  private var snapshot: BatterySnapshot { coordinator.snapshot }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading,
          spacing: 10
        ) {
          tile("heart.fill", "health", snapshot.health.map { String(format: "%.1f %%", $0) })
          tile("arrow.triangle.2.circlepath", "cycles", snapshot.cycleCount.map(String.init))
          tile("battery.100", "capacity", snapshot.maximumCapacity.map { "\($0) mAh" })
          tile("ruler", "design_capacity", snapshot.designCapacity.map { "\($0) mAh" })
          tile(
            "thermometer.medium", "temperature",
            snapshot.temperature.map { String(format: "%.1f °C", $0) })
          tile("bolt", "voltage", snapshot.voltage.map { String(format: "%.2f V", $0) })
          tile(
            "waveform.path.ecg", "current", snapshot.current.map { String(format: "%.2f A", $0) })
          tile("powerplug", "adapter", snapshot.adapterWatts.map { "\($0) W" })
        }
        if snapshot.systemLoad != nil || snapshot.power != nil {
          Card {
            VStack(alignment: .leading, spacing: 10) {
              Text(localized("power_flow")).font(.headline)
              PowerFlow(snapshot: snapshot)
            }
          }
        }
        Text(localized("health_ratio_note")).font(.caption).foregroundStyle(.secondary)
        Card {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Picker(localized("metric"), selection: $metric) {
                Text(localized("charge")).tag("charge")
                Text(localized("temperature")).tag("temperature")
                Text(localized("power")).tag("power")
              }
              .labelsHidden().fixedSize()
              Spacer()
              Picker(localized("period"), selection: $days) {
                Text("24 h").tag(1)
                Text("7 d").tag(7)
                Text("30 d").tag(30)
              }
              .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            chart
          }
        }
        Text(localized("power_sign_note")).font(.caption).foregroundStyle(.secondary)
        if loadFailed || operationFailed || coordinator.historyError {
          Label(localized("history_error"), systemImage: "exclamationmark.triangle")
            .foregroundStyle(Palette.thermal)
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
  private var tint: Color {
    switch metric {
    case "temperature": return Palette.thermal
    case "power": return Palette.discharging
    default: return Palette.holding
    }
  }
  @ViewBuilder private var chart: some View {
    let points = samples.compactMap { sample in reading(sample).map { (sample.timestamp, $0) } }
    if points.isEmpty {
      Text(localized("history_empty")).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 180)
    } else {
      Chart(points, id: \.0) { point in
        AreaMark(x: .value(localized("time"), point.0), y: .value(localized(metric), point.1))
          .foregroundStyle(
            LinearGradient(
              colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top,
              endPoint: .bottom)
          )
          .interpolationMethod(.monotone)
        LineMark(x: .value(localized("time"), point.0), y: .value(localized(metric), point.1))
          .foregroundStyle(tint)
          .lineStyle(StrokeStyle(lineWidth: 2))
          .interpolationMethod(.monotone)
      }
      .chartXScale(domain: since...Date())
      .chartYScale(domain: metric == "charge" ? 0...100 : yDomain(points.map(\.1)))
      .frame(height: 200)
      .accessibilityLabel(localized("history_chart"))
      HStack {
        Text("\(localized("samples")): \(points.count)")
        Spacer()
        if let minimum = points.map(\.1).min(), let maximum = points.map(\.1).max() {
          Text(String(format: "Min %.1f · Max %.1f", minimum, maximum)).monospacedDigit()
        }
      }.font(.caption).foregroundStyle(.secondary)
    }
  }
  private func yDomain(_ values: [Double]) -> ClosedRange<Double> {
    let low = values.min() ?? 0
    let high = values.max() ?? 1
    let pad = max(1, (high - low) * 0.15)
    return (low - pad)...(high + pad)
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
  private func tile(_ symbol: String, _ key: String, _ value: String?) -> some View {
    Card(padding: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Label(localized(key), systemImage: symbol)
          .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        Text(value ?? localized("unknown"))
          .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
      }
    }
  }
}
