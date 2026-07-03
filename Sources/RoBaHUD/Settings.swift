import Foundation

/// UserDefaults-backed preferences.
/// Override examples:
///   defaults write com.tktk7l9.roba-hud zmkConfigPath ~/path/to/zmk-config-roBa
///   defaults write com.tktk7l9.roba-hud opacity 0.8
enum Prefs {
    private static let defaults = UserDefaults.standard

    static let defaultZmkConfigPath =
        NSString(string: "~/src/github.com/tktk7l9/zmk-config-roBa").expandingTildeInPath

    static var zmkConfigPath: String {
        get { defaults.string(forKey: "zmkConfigPath") ?? defaultZmkConfigPath }
        set { defaults.set(newValue, forKey: "zmkConfigPath") }
    }

    static var keymapURL: URL {
        URL(fileURLWithPath: zmkConfigPath).appendingPathComponent("config/roBa.keymap")
    }
    static var layoutJSONURL: URL {
        URL(fileURLWithPath: zmkConfigPath).appendingPathComponent("config/roBa.json")
    }

    static var opacity: Double {
        get {
            let v = defaults.double(forKey: "opacity")
            return v == 0 ? 0.95 : min(max(v, 0.3), 1.0)
        }
        set { defaults.set(newValue, forKey: "opacity") }
    }

    static var batteryNotificationsEnabled: Bool {
        get { defaults.object(forKey: "batteryNotificationsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "batteryNotificationsEnabled") }
    }

    static var disconnectNotificationsEnabled: Bool {
        get { defaults.bool(forKey: "disconnectNotificationsEnabled") }
        set { defaults.set(newValue, forKey: "disconnectNotificationsEnabled") }
    }

    static var menuBarBatteryEnabled: Bool {
        get { defaults.object(forKey: "menuBarBatteryEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarBatteryEnabled") }
    }

    static var batteryNotifyThreshold: Int {
        get {
            let v = defaults.integer(forKey: "batteryNotifyThreshold")
            return v == 0 ? 20 : min(max(v, 5), 50)
        }
        set { defaults.set(newValue, forKey: "batteryNotifyThreshold") }
    }
}
