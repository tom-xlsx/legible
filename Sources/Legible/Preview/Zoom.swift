import Foundation

/// App-wide page zoom for every preview. Persisted; the settings file takes over in a later milestone.
enum Zoom {
    static let didChange = Notification.Name("LegibleZoomDidChange")
    static let minimum: CGFloat = 0.7
    static let maximum: CGFloat = 2.5
    private static let key = "zoom"

    static var level: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: key)
            return stored > 0 ? CGFloat(stored) : 1
        }
        set {
            let clamped = min(max(newValue, minimum), maximum)
            UserDefaults.standard.set(Double(clamped), forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func step(_ direction: Int) {
        let stepped = (level * 10).rounded() / 10 + CGFloat(direction) * 0.1
        level = stepped
    }
}
