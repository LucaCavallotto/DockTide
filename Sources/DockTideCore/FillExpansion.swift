import CoreGraphics

public enum FillExpansion {
    public static func target(window: CGRect, liveWorkArea: CGRect, reservedWorkArea: CGRect?, screen: CGRect) -> CGRect? {
        let area = screen.maxY - liveWorkArea.maxY > 20 ? liveWorkArea : reservedWorkArea
        guard let area else { return nil }
        return target(window: window, workArea: area, screen: screen)
    }

    /// A geometry heuristic: macOS does not supply a public "Fill was clicked" event.
    /// Match the entire work area (optionally with uniform system tiling margins).
    /// Only extend downward, retaining the menu bar and the user's tiling margins.
    public static func target(window: CGRect, workArea: CGRect, screen: CGRect) -> CGRect? {
        guard window.width > 0, window.height > 0,
              screen.maxY - workArea.maxY > 20,
              abs(workArea.minX - screen.minX) <= 2,
              abs(workArea.maxX - screen.maxX) <= 2 else { return nil }
        let insets = [window.minX - workArea.minX, workArea.maxX - window.maxX,
                      window.minY - workArea.minY, workArea.maxY - window.maxY]
        guard let margin = insets.first, margin >= -2, margin <= 16,
              insets.allSatisfy({ abs($0 - margin) <= 2 }) else { return nil }
        return CGRect(x: window.minX, y: window.minY, width: window.width,
                      height: screen.maxY - max(0, margin) - window.minY)
    }
}
