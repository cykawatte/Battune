import AppKit
import SwiftUI

/// A short first-run tour; finishing never installs a helper or enables charging.
struct TutorialView: View {
  let finish: (Bool) -> Bool
  @ViewState private var page = 0
  private let symbols = ["slider.horizontal.3", "checkmark.shield", "menubar.rectangle"]
  var body: some View {
    VStack(spacing: 18) {
      ScrollView {
        VStack(spacing: 18) {
          Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            .accessibilityLabel("Battune")
          Text(localized("tour_title.\(page)")).font(.title.bold()).multilineTextAlignment(.center)
          Label(localized("tour_subtitle.\(page)"), systemImage: symbols[page])
            .font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
          Text(localized("tour_body.\(page)")).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 440)
          if page == 1 {
            Text(localized("tour_helper_steps")).font(.callout)
              .fixedSize(horizontal: false, vertical: true)
              .padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
          }
          Text(localized("tour_note.\(page)")).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 440)
        }.frame(maxWidth: .infinity)
      }
      HStack(spacing: 8) {
        ForEach(0..<3) { index in
          Circle().fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
            .frame(width: 7, height: 7)
        }
      }.accessibilityLabel("\(page + 1) / 3")
      HStack {
        if page > 0 {
          Button(localized("tour_back")) { page -= 1 }
        } else {
          Button(localized("tour_skip")) { _ = finish(false) }
        }
        Spacer()
        Button(localized(page == 2 ? "tour_setup" : "tour_next")) {
          if page < 2 { page += 1 } else { _ = finish(true) }
        }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
      }
    }.padding(32).frame(width: 500, height: 540)
      .interactiveDismissDisabled()
  }
}
