import Foundation
func L(_ key: String) -> String {
    let language = UserDefaults.standard.string(forKey: "ui.language") ?? "system"
    let bundle: Bundle
    if language != "system", let path = Bundle.module.path(forResource: language, ofType: "lproj"), let selected = Bundle(path: path) { bundle = selected }
    else { bundle = Bundle.module }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
}

// Explicit typealias avoids the SDK 27 State macro, keeping the macOS 13 property wrapper.
import SwiftUI
typealias ViewState<Value> = SwiftUI.State<Value>
