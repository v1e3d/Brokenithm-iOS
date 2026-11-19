// Standalone tests for SliderMapping (no XCTest needed, runs on macOS and Linux):
//   swiftc -o slider-tests brokenithm-swiftui/Input/SliderMapping.swift Tests/SliderMappingTests/main.swift && ./slider-tests
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition { failures += 1; print("FAIL (line \(line)): \(message)") }
}
func pressedIndices(_ s: [UInt8]) -> [Int] { s.indices.filter { s[$0] != 0 } }

let W = 1600.0, H = 400.0, key = W / 16
let split = SliderMapping.Options(splitRows: true, edgeAssist: false)
let unsplit = SliderMapping.Options(splitRows: false, edgeAssist: false)
func touch(column: Int, top: Bool, at fraction: Double = 0.5) -> SliderMapping.Touch {
    SliderMapping.Touch(x: (Double(column) + fraction) * key, y: top ? H * 0.25 : H * 0.75)
}

// Official numbering: sensor 1 (index 0) = top of the rightmost key, 2 = its bottom, 31/32 = top/bottom of the leftmost key.
check(pressedIndices(SliderMapping.sensors(for: [touch(column: 15, top: true)], width: W, height: H, options: split)) == [0], "rightmost top = index 0")
check(pressedIndices(SliderMapping.sensors(for: [touch(column: 15, top: false)], width: W, height: H, options: split)) == [1], "rightmost bottom = index 1")
check(pressedIndices(SliderMapping.sensors(for: [touch(column: 0, top: true)], width: W, height: H, options: split)) == [30], "leftmost top = index 30")
check(pressedIndices(SliderMapping.sensors(for: [touch(column: 0, top: false)], width: W, height: H, options: split)) == [31], "leftmost bottom = index 31")
for c in 0 ..< 16 {
    check(SliderMapping.sensorIndex(column: c, top: true) == 2 * (15 - c), "sensorIndex top column \(c)")
    check(SliderMapping.sensorIndex(column: c, top: false) == 2 * (15 - c) + 1, "sensorIndex bottom column \(c)")
}

// TAP on top of a HOLD in the same lane: hold the bottom row, tap the top row -> the top sensor is a new press.
let hold = SliderMapping.sensors(for: [touch(column: 7, top: false)], width: W, height: H, options: split)
let holdAndTap = SliderMapping.sensors(for: [touch(column: 7, top: false), touch(column: 7, top: true)], width: W, height: H, options: split)
check(pressedIndices(hold) == [17], "hold on column 7 bottom")
check(pressedIndices(holdAndTap) == [16, 17], "tap on top while holding bottom adds the top sensor")
check(holdAndTap[17] != 0, "hold sensor stays pressed while tapping")

// Order of touches never changes the result (no flicker between frames).
let many = [touch(column: 2, top: true), touch(column: 2, top: false), touch(column: 9, top: true, at: 0.1), touch(column: 13, top: false, at: 0.9)]
for options in [split, unsplit, SliderMapping.Options(splitRows: true, edgeAssist: true), SliderMapping.Options(splitRows: false, edgeAssist: true)] {
    let a = SliderMapping.sensors(for: many, width: W, height: H, options: options)
    let b = SliderMapping.sensors(for: many.reversed(), width: W, height: H, options: options)
    let c = SliderMapping.sensors(for: [many[2], many[0], many[3], many[1]], width: W, height: H, options: options)
    check(a == b && a == c, "order independent for \(options)")
}

// Edge assist is symmetric across the whole slider (the old code skipped the right edge on the right half).
let edge = SliderMapping.Options(splitRows: true, edgeAssist: true)
for c in 0 ..< 16 {
    let right = pressedIndices(SliderMapping.sensors(for: [touch(column: c, top: true, at: 0.9)], width: W, height: H, options: edge))
    let expectRight = c < 15 ? [SliderMapping.sensorIndex(column: c + 1, top: true), SliderMapping.sensorIndex(column: c, top: true)].sorted() : [SliderMapping.sensorIndex(column: c, top: true)]
    check(right == expectRight, "right edge of column \(c) -> \(right)")
    let left = pressedIndices(SliderMapping.sensors(for: [touch(column: c, top: false, at: 0.1)], width: W, height: H, options: edge))
    let expectLeft = c > 0 ? [SliderMapping.sensorIndex(column: c, top: false), SliderMapping.sensorIndex(column: c - 1, top: false)].sorted() : [SliderMapping.sensorIndex(column: c, top: false)]
    check(left == expectLeft, "left edge of column \(c) -> \(left)")
    let middle = pressedIndices(SliderMapping.sensors(for: [touch(column: c, top: true, at: 0.5)], width: W, height: H, options: edge))
    check(middle == [SliderMapping.sensorIndex(column: c, top: true)], "middle of column \(c) presses one sensor")
}

// Unsplit mode: one finger = one sensor, a 2nd finger on the same key = the other sensor (still a new press).
check(pressedIndices(SliderMapping.sensors(for: [touch(column: 4, top: true)], width: W, height: H, options: unsplit)) == [22], "unsplit single touch uses 2k")
check(pressedIndices(SliderMapping.sensors(for: [touch(column: 4, top: true), touch(column: 4, top: true, at: 0.8)], width: W, height: H, options: unsplit)) == [22, 23], "unsplit two fingers use both sensors")

// Out-of-range positions clamp instead of crashing.
check(pressedIndices(SliderMapping.sensors(for: [SliderMapping.Touch(x: -50, y: 10)], width: W, height: H, options: split)) == [30], "x < 0 clamps to leftmost")
check(pressedIndices(SliderMapping.sensors(for: [SliderMapping.Touch(x: W + 50, y: H + 10)], width: W, height: H, options: split)) == [1], "x > width clamps to rightmost")
check(pressedIndices(SliderMapping.sensors(for: [touch(column: 3, top: true)], width: 0, height: H, options: split)).isEmpty, "zero width yields nothing")
check(SliderMapping.sensors(for: [], width: W, height: H, options: split).count == 32, "always 32 sensors")

if failures == 0 { print("All SliderMapping tests passed.") } else { print("\(failures) failure(s)."); exit(1) }
