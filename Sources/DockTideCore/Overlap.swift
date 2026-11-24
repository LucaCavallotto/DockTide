import CoreGraphics
import Foundation

public enum Overlap {
    /// Ignore edge contact and tiny discrepancies between coordinate systems.
    public static func requiresHiding(dock: CGRect, windows: [CGRect]) -> Bool {
        guard dock.width > 0, dock.height > 0 else { return false }
        return windows.contains {
            let intersection = dock.intersection($0)
            return !intersection.isNull && intersection.width > 2 && intersection.height > 2
        }
    }
}
