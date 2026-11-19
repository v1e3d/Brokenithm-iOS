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
    /// Touches this close to a key's side edge (fraction of the key width) also press the neighbouring key,
    /// like a fingertip lying across the gap between two keys on the cabinet.
    static let edgeFraction = 0.25

    struct Options: Equatable {
        /// Split every key into a top and a bottom sensor by touch height (like the cabinet).
        var splitRows: Bool = true
        /// Also press the neighbouring key when touching near a key edge.
        var edgeAssist: Bool = true
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
        let keyWidth = width / Double(keys)
        // Unsplit mode: count touches per key; the 2nd touch on a key uses the 2nd sensor.
        var touchesPerKey = [Int](repeating: 0, count: keys)

        for touch in touches {
            let position = min(max(touch.x / keyWidth, 0), Double(keys) - 0.000_001)
            let column = Int(position)            // 0 = leftmost key
            let fraction = position - Double(column)
            let top = touch.y < height / 2

            var columns = [column]
            if options.edgeAssist {
                if fraction < edgeFraction && column > 0 { columns.append(column - 1) }
                if fraction > 1 - edgeFraction && column < keys - 1 { columns.append(column + 1) }
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
