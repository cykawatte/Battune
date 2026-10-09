import SwiftUI
import Charts
import BattuneDomain
import BattuneSystem
struct StatisticsView: View {
    @ObservedObject var coordinator: ChargeCoordinator
    let history: HistoryStore
    let loadFailed: Bool
    @ViewState private var samples: [BatterySnapshot] = []
    @ViewState private var deleteFailed = false
    @ViewState private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                row("health", coordinator.snapshot.health.map { String(format: "%.1f%%", $0) })
                row("cycles", coordinator.snapshot.cycleCount.map(String.init))
                row("capacity", coordinator.snapshot.maximumCapacity.map { "\($0) mAh" })
                row("temperature", coordinator.snapshot.temperature.map { String(format: "%.1f °C", $0) })
                row("adapter", coordinator.snapshot.adapterWatts.map { "\($0) W" })
            }
            if samples.isEmpty { Text(L("history_empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180) }
            else {
                Chart(Array(samples.enumerated()), id: \.offset) { entry in
                    if let percent = entry.element.percentage {
                        LineMark(x: .value(L("time"), entry.element.timestamp), y: .value(L("charge"), percent))
                    }
                }.chartYScale(domain: 0...100).frame(minHeight: 180).accessibilityLabel(L("history_chart"))
            }
            if loadFailed || deleteFailed { Text(L("history_error")).foregroundStyle(.red) }
            HStack {
                Text(L("history_retention")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("refresh")) { samples = history.samples }
                Button(L("clear_history"), role: .destructive) { confirmClear = true }
            }
        }.padding(20).onAppear { samples = history.samples }
            .alert(L("clear_history"), isPresented: $confirmClear) {
                Button(L("cancel"), role: .cancel) {}
                Button(L("clear_history"), role: .destructive) { do { try history.clear(); samples = [] } catch { deleteFailed = true } }
            }
    }
    private func row(_ key: String, _ value: String?) -> some View {
        GridRow { Text(L(key)).foregroundStyle(.secondary); Text(value ?? L("unknown")).monospacedDigit() }
    }
}
