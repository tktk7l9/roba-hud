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
}
