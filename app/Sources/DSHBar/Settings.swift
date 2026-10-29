import AppKit

/// Small persisted preferences. Everything defaults to the friendly option.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: "notifications") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifications") }
    }

    var animateIcon: Bool {
        get { defaults.object(forKey: "animate") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "animate") }
    }

    var showSessions: Bool {
        get { defaults.object(forKey: "showSessions") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showSessions") }
    }

    /// System Reduce Motion wins over the app preference.
    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var animates: Bool {
        animateIcon && !reduceMotion
    }
}
