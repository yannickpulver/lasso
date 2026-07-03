import Foundation

public enum ShapeMath {
    /// Bounding box of a freeform drawn path, padded and clamped.
    /// Returns nil for accidental clicks (too few points) or tiny shapes (<10x10 pre-padding).
    public static func boundingBox(of points: [CGPoint], padding: CGFloat, clampedTo bounds: CGRect) -> CGRect? {
        guard points.count >= 6 else { return nil }

        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }

        guard maxX - minX >= 10, maxY - minY >= 10 else { return nil }

        let rect = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + 2 * padding,
            height: (maxY - minY) + 2 * padding
        ).intersection(bounds)

        return rect.isEmpty ? nil : rect
    }
}
