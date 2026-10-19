import Foundation
import CoreGraphics

public enum DifficultyScale {
    /// The normal setting has a deliberate mark one fifth along the track.
    public static func position(for percent: Double) -> Double {
        let value = min(500, max(20, percent))
        return value <= 100 ? (value - 20) / 80 * 0.2 : 0.2 + (value - 100) / 400 * 0.8
    }
    public static func percent(at position: Double) -> Double {
        let value = min(1, max(0, position))
        return value <= 0.2 ? 20 + value / 0.2 * 80 : 100 + (value - 0.2) / 0.8 * 400
    }
}

public enum DesktopPetPlacement {
    /// Use full display bounds, including Dock/menu bar areas, and leave a recoverable grip.
    public static func constrain(_ frame: CGRect, to screens: [CGRect]) -> CGRect {
        guard let screen = screens.max(by: { score(frame, $0) < score(frame, $1) }) else { return frame }
        let gripX = frame.width * 0.5
        let gripY = frame.height * 0.5
        let x = min(max(frame.minX, screen.minX - frame.width + gripX), screen.maxX - gripX)
        let y = min(max(frame.minY, screen.minY - frame.height + gripY), screen.maxY - gripY)
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }
    private static func score(_ frame: CGRect, _ screen: CGRect) -> Double {
        let intersection = frame.intersection(screen)
        if !intersection.isNull { return 1_000_000 + intersection.width * intersection.height }
        let dx = max(screen.minX - frame.midX, 0, frame.midX - screen.maxX)
        let dy = max(screen.minY - frame.midY, 0, frame.midY - screen.maxY)
        return -hypot(dx, dy)
    }
}
