import BattuneDomain
import BattuneSystem
import SwiftUI

/// Visual language shared by the popover and the settings window: calm slate
/// surfaces from the app icon, one status colour, SF Symbols and rounded numerals.
enum Palette {
  static let charging = Color(red: 0.20, green: 0.78, blue: 0.45)
  static let holding = Color(red: 0.25, green: 0.72, blue: 0.80)
  static let discharging = Color(red: 0.98, green: 0.62, blue: 0.20)
  static let thermal = Color(red: 0.95, green: 0.33, blue: 0.30)
  static let idle = Color.secondary
}

struct StatusStyle {
  let color: Color
  let symbol: String
  let title: String
  static func of(
    _ mode: ControlMode, snapshot: BatterySnapshot, override: ChargeOverride?,
    fallback: Int? = nil
  ) -> StatusStyle {
    // Adapter mode is blocked, but macOS still enforces a confirmed ceiling.
    if mode == .unavailable, let fallback {
      return StatusStyle(
        color: Palette.holding, symbol: "lock.shield.fill",
        title: String(format: localized("protected_by_native"), fallback))
    }
    if override?.kind == .topUp {
      return StatusStyle(
        color: Palette.charging, symbol: "bolt.fill", title: localized("top_up_active"))
    }
    if override?.kind == .pause {
      return StatusStyle(color: Palette.holding, symbol: "pause.fill", title: localized("paused"))
    }
    switch mode {
    case .charging:
      return StatusStyle(color: Palette.charging, symbol: "bolt.fill", title: localized("mode.1"))
    case .holding:
      return StatusStyle(color: Palette.holding, symbol: "lock.fill", title: localized("mode.2"))
    case .thermalHold:
      return StatusStyle(
        color: Palette.thermal, symbol: "thermometer.high", title: localized("mode.3"))
    case .discharging:
      return StatusStyle(
        color: Palette.discharging, symbol: "arrow.down.circle.fill", title: localized("mode.4"))
    case .calibration:
      return StatusStyle(
        color: Palette.discharging, symbol: "arrow.triangle.2.circlepath",
        title: localized("mode.5"))
    case .unavailable:
      return StatusStyle(
        color: Palette.thermal, symbol: "exclamationmark.triangle.fill", title: localized("mode.6"))
    case .nativeLimit:
      if snapshot.charging == true {
        return StatusStyle(
          color: Palette.charging, symbol: "bolt.fill", title: localized("charging_to_limit"))
      }
      return StatusStyle(
        color: snapshot.pluggedIn == true ? Palette.holding : Palette.idle,
        symbol: snapshot.pluggedIn == true ? "lock.fill" : "battery.75percent",
        title: localized(snapshot.pluggedIn == true ? "holding_native" : "on_battery"))
    case .system:
      return StatusStyle(
        color: snapshot.charging == true ? Palette.charging : Palette.idle,
        symbol: snapshot.charging == true ? "bolt.fill" : "battery.75percent",
        title: localized("mode.0"))
    }
  }
}

/// Rounded surface used for every grouped block.
struct Card<Content: View>: View {
  var padding: CGFloat = 12
  @ViewBuilder var content: Content
  var body: some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06))
      )
  }
}

/// Charge ring with a tick at the active limit.
struct ChargeRing: View {
  let percentage: Int?
  let limit: Int?
  let color: Color
  var lineWidth: CGFloat = 9
  var body: some View {
    ZStack {
      Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: CGFloat(percentage ?? 0) / 100)
        .stroke(
          AngularGradient(
            colors: [color.opacity(0.55), color], center: .center, startAngle: .degrees(0),
            endAngle: .degrees(360 * Double(percentage ?? 0) / 100)),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      if let limit, limit < 100 {
        Capsule()
          .fill(Color.primary.opacity(0.75))
          .frame(width: 2.5, height: lineWidth + 6)
          .offset(y: -0.5)
          .frame(maxHeight: .infinity, alignment: .top)
          .rotationEffect(.degrees(360 * Double(limit) / 100))
          .padding(-3)
          .accessibilityHidden(true)
      }
      VStack(spacing: -2) {
        Text(percentage.map(String.init) ?? "—")
          .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
        Text("%").font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(localized("battery_level"))
    .accessibilityValue(percentage.map { "\($0)%" } ?? localized("unknown"))
  }
}

/// Adapter → Mac → battery, in watts, from macOS power telemetry.
struct PowerFlow: View {
  let snapshot: BatterySnapshot
  var body: some View {
    HStack(spacing: 6) {
      node(
        "powerplug.fill", localized("flow_adapter"), snapshot.adapterInput,
        active: snapshot.pluggedIn == true)
      arrow(active: (snapshot.adapterInput ?? 0) > 0.05)
      node("laptopcomputer", localized("flow_system"), snapshot.systemLoad, active: true)
      arrow(active: abs(snapshot.power ?? 0) > 0.05, reversed: (snapshot.power ?? 0) < 0)
      node(
        "battery.75percent", localized("flow_battery"), snapshot.power.map(abs),
        active: abs(snapshot.power ?? 0) > 0.05,
        tint: (snapshot.power ?? 0) < -0.05 ? Palette.discharging : Palette.charging)
    }
  }
  private func node(
    _ symbol: String, _ title: String, _ watts: Double?, active: Bool, tint: Color = .primary
  ) -> some View {
    VStack(spacing: 3) {
      Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        .foregroundStyle(active ? tint : Color.secondary)
      Text(watts.map { String(format: "%.1f W", $0) } ?? "—")
        .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
      Text(title).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
  private func arrow(active: Bool, reversed: Bool = false) -> some View {
    Image(systemName: reversed ? "arrow.left" : "arrow.right")
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(active ? Color.primary.opacity(0.6) : Color.primary.opacity(0.15))
      .accessibilityHidden(true)
  }
}

/// Native macOS steps as tappable chips; continuous slider for adapter mode.
struct LimitPicker: View {
  @Binding var limit: Int
  let supported: [Int]?
  let range: ClosedRange<Int>
  let commit: () -> Void
  var body: some View {
    if let supported, !supported.isEmpty {
      HStack(spacing: 6) {
        ForEach(supported, id: \.self) { value in
          Button {
            limit = value
            commit()
          } label: {
            Text("\(value)")
              .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
              .frame(maxWidth: .infinity, minHeight: 26)
              .background(
                Capsule().fill(value == limit ? Color.accentColor : Color.primary.opacity(0.07))
              )
              .foregroundStyle(value == limit ? Color.white : Color.primary)
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(localized("charge_limit")) \(value)%")
          .accessibilityAddTraits(value == limit ? .isSelected : [])
        }
      }
    } else {
      Slider(
        value: Binding(get: { Double(limit) }, set: { limit = Int($0.rounded()) }),
        in: Double(range.lowerBound)...Double(range.upperBound)
      ) { editing in
        if !editing { commit() }
      }
      .labelsHidden()
      .accessibilityLabel(localized("charge_limit"))
      .accessibilityValue("\(limit)%")
    }
  }
}

/// Square action tile used in the popover.
struct ActionTile: View {
  let symbol: String
  let title: String
  var active = false
  var tint: Color = .accentColor
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(spacing: 5) {
        Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
        Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity, minHeight: 50)
      .foregroundStyle(active ? Color.white : Color.primary)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(active ? tint : Color.primary.opacity(0.06))
      )
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

enum Format {
  static func duration(minutes: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
  }
  static func watts(_ value: Double?) -> String? { value.map { String(format: "%.1f W", $0) } }
}
