import SwiftUI

/// Whole-number settings with a continuous native track (no row of tiny ticks).
struct SettingsSlider: View {
  let titleKey: String
  @Binding private var value: Double
  private let range: ClosedRange<Double>
  private let unit: String
  private let onEditingChanged: (Bool) -> Void

  init<Value: BinaryInteger>(
    _ titleKey: String, value: Binding<Value>, in range: ClosedRange<Value>,
    unit: String = "%", onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.init(
      titleKey,
      value: Binding(
        get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Value($0.rounded()) }),
      in: Double(range.lowerBound)...Double(range.upperBound), unit: unit,
      onEditingChanged: onEditingChanged)
  }

  init(
    _ titleKey: String, value: Binding<Double>, in range: ClosedRange<Double>,
    unit: String = " °C", onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.titleKey = titleKey
    self._value = value
    self.range = range
    self.unit = unit
    self.onEditingChanged = onEditingChanged
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(localized(titleKey))
        Spacer()
        Text("\(Int(value))\(unit)").monospacedDigit().foregroundStyle(.secondary)
      }
      Slider(
        value: Binding(get: { value }, set: { value = $0.rounded() }), in: range,
        onEditingChanged: onEditingChanged
      )
      .labelsHidden()
      .accessibilityLabel(localized(titleKey))
      .accessibilityValue("\(Int(value))\(unit)")
    }.padding(.vertical, 4)
  }
}
