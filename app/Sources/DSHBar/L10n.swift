import Foundation

/// Localized string by key (en/ru/zh-Hans live in Resources/*.lproj).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string with arguments.
func Lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
