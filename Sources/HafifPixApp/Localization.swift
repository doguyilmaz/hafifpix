import Foundation

/// Looks a string up in this module's catalog. SwiftUI's implicit
/// LocalizedStringKey resolution targets Bundle.main, which is wrong for
/// package targets, so every user-facing string goes through here.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "HafifPixApp", bundle: .module)
}
