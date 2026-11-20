//
//  SliderMapping.swift
//  brokenithm-swiftui
//
//  Maps touches on the slider area to CHUNITHM's 32 slider sensors.
//  Foundation only (no SwiftUI) so it can be unit tested on any platform.
//

import Foundation

/// CHUNITHM's ground slider is 16 keys wide and 2 rows tall: 32 sensors.
///
/// Official sensor numbering (operator manual): 1 = top row of the rightmost key, 2 = bottom row of the
/// rightmost key, 3 = top row of the 2nd key from the right, ... 31 = top-left, 32 = bottom-left.
/// The array sent to the game is 0-based, so index `2k` is the top row and `2k + 1` the bottom row of
/// the k-th key counted from the right.
///
/// The two rows matter for real charts: a TAP that falls on top of a HOLD in the same lane is played by
/// keeping one row pressed and tapping the other, and a second finger on the same key only counts as a
/// new press if it lands on the sensor that is not already pressed.
enum SliderMapping {
    static let keys = 16
    static let sensors = 32
    static let pressed: UInt8 = 128
    /// Default edge assist width: touches this close to a key's side edge (fraction of the key width) also
    /// press the neighbouring key, like a fingertip lying across the gap between two keys on the cabinet.
    static let defaultEdgeFraction = 0.25

    struct Options: Equatable {
        /// Split every key into a top and a bottom sensor by touch height (like the cabinet).
        var splitRows: Bool = true
        /// Also press the neighbouring key when touching near a key edge.
        var edgeAssist: Bool = true
        /// Edge assist width as a fraction of the key width (0...0.45).
        var edgeFraction: Double = SliderMapping.defaultEdgeFraction
        /// Height of the top row as a fraction of the slider height (0.1...0.9); the rest is the bottom row.
        var splitRatio: Double = 0.5
        /// Fractions of the slider width left and right that are not keys (touches there count as the edge key).
        var insetLeft: Double = 0
        var insetRight: Double = 0
    }

    struct Touch: Equatable {
        /// Position relative to the slider area: x in 0...width, y in 0...height (0 = top).
        var x: Double
        var y: Double
    }

    /// Sensor states (game order, 0 or `pressed`) for all touches currently on the slider area.
    /// The result depends only on the set of touches, never on their order, so an unchanged hand never
    /// produces a release/press flicker that the game would read as an extra tap.
    static func sensors(for touches: [Touch], width: Double, height: Double, options: Options) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: sensors)
        guard width > 0, height > 0 else { return out }
        let left = width * min(max(options.insetLeft, 0), 0.4)
        let usable = max(width * (1 - min(max(options.insetLeft, 0), 0.4) - min(max(options.insetRight, 0), 0.4)), 1)
        let keyWidth = usable / Double(keys)
        let edge = min(max(options.edgeFraction, 0), 0.45)
        let splitY = height * min(max(options.splitRatio, 0.1), 0.9)
        // Unsplit mode: count touches per key; the 2nd touch on a key uses the 2nd sensor.
        var touchesPerKey = [Int](repeating: 0, count: keys)

        for touch in touches {
            let position = min(max((touch.x - left) / keyWidth, 0), Double(keys) - 0.000_001)
            let column = Int(position)            // 0 = leftmost key
            let fraction = position - Double(column)
            let top = touch.y < splitY

            var columns = [column]
            if options.edgeAssist && edge > 0 {
                if fraction < edge && column > 0 { columns.append(column - 1) }
                if fraction > 1 - edge && column < keys - 1 { columns.append(column + 1) }
            }
            for c in columns {
                let key = keys - 1 - c            // counted from the right, as the game numbers sensors
                if options.splitRows {
                    out[2 * key + (top ? 0 : 1)] = pressed
                } else {
                    touchesPerKey[key] += 1
                }
            }
        }

        if !options.splitRows {
            for key in 0 ..< keys {
                if touchesPerKey[key] >= 1 { out[2 * key] = pressed }
                if touchesPerKey[key] >= 2 { out[2 * key + 1] = pressed }
            }
        }
        return out
    }

    /// Sensor index (game order) of the top or bottom row of a key given as a column from the left.
    static func sensorIndex(column: Int, top: Bool) -> Int {
        2 * (keys - 1 - column) + (top ? 0 : 1)
    }
}
