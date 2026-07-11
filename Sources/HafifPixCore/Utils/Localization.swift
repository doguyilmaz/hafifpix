import Foundation

/// Core-module string lookup (settings names, statuses, error messages).
func LC(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "HafifPixCore", bundle: .module)
}
