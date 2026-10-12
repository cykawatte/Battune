import SwiftUI

/// Whole-number settings with a continuous native track (no row of tiny ticks).
struct SettingsSlider: View {
  let titleKey: String
  @Binding private var value: Double
  private let range: ClosedRange<Double>
  private let unit: String
  private let supportedValues: [Double]?
  private let onEditingChanged: (Bool) -> Void

  init<Value: BinaryInteger>(
    _ titleKey: String, value: Binding<Value>, in range: ClosedRange<Value>,
    unit: String = "%", supportedValues: [Int]? = nil,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.init(
      titleKey,
      value: Binding(
        get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Value($0.rounded()) }),
      in: Double(range.lowerBound)...Double(range.upperBound), unit: unit,
      supportedValues: supportedValues?.map(Double.init),
      onEditingChanged: onEditingChanged)
  }

  init(
    _ titleKey: String, value: Binding<Double>, in range: ClosedRange<Double>,
    unit: String = " °C", supportedValues: [Double]? = nil,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.titleKey = titleKey
    self._value = value
    self.range = range
    self.unit = unit
    self.supportedValues = supportedValues
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
        value: Binding(
          get: { value },
          set: { proposed in
            value =
              supportedValues?.min(by: { abs($0 - proposed) < abs($1 - proposed) })
              ?? proposed.rounded()
          }), in: range,
        onEditingChanged: onEditingChanged
      )
      .labelsHidden()
      .accessibilityLabel(localized(titleKey))
      .accessibilityValue("\(Int(value))\(unit)")
    }.padding(.vertical, 4)
  }
}
