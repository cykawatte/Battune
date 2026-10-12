import Foundation
// Explicit typealias avoids the SDK 27 State macro, keeping the macOS 13 property wrapper.
import SwiftUI

func localized(_ key: String) -> String {
  let language = UserDefaults.standard.string(forKey: "ui.language") ?? "system"
  let resources: Bundle
  if let url = Bundle.main.url(forResource: "Battune_Battune", withExtension: "bundle"),
    let embedded = Bundle(url: url)
  {
    resources = embedded
  } else {
    resources = Bundle.module
  }
  let bundle: Bundle
  if language != "system", let path = resources.path(forResource: language, ofType: "lproj"),
    let selected = Bundle(path: path)
  {
    bundle = selected
  } else {
    bundle = resources
  }
  return bundle.localizedString(forKey: key, value: nil, table: nil)
}

typealias ViewState<Value> = SwiftUI.State<Value>
