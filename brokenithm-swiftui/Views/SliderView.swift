//
//  SliderView.swift
//  brokenithm-swiftui
//
//  Created by Owen Cramer on 9/11/24.
//

import SwiftUI

struct SliderView: View {
    @Binding var lanesTouching: [UInt8]
    @Binding var connection: Listener?

    var airOn: Bool
    /// Draw the top/bottom split of every key (matches SliderMapping.Options.splitRows / splitRatio).
    var splitRows: Bool = true
    var splitRatio: Double = 0.5
    var showTouches: Bool = true
    var showRowDivider: Bool = true
    /// Multiplies the LED colours sent by the game (0 = off, 1 = as sent).
    var ledBrightness: Double = 1.0

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(0 ..< 16) { i in

                    Rectangle()
                        .fill(getColor(con: connection, i: i, laneSplit: false))
                        .foregroundStyle(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            // pressed sensors: top and bottom row of the key
                            if showTouches {
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.white.opacity(isPressed(column: i, top: true) ? 0.35 : 0))
                                        .frame(height: proxy.size.height * CGFloat(splitRows ? clampedSplit : 0.5))
                                    Rectangle()
                                        .fill(Color.white.opacity(isPressed(column: i, top: false) ? 0.35 : 0))
                                }
                            }
                        }
                        .overlay(alignment: .top) {
                            if splitRows && showRowDivider {
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(height: 1)
                                    .offset(y: proxy.size.height * CGFloat(clampedSplit))
                            }
                        }
                        .overlay {
                            if i < 15 {
                                Rectangle()
                                    .fill(getColor(con: connection, i: i, laneSplit: true))
                                    .frame(width: 5)
                                    .padding(.leading, proxy.size.width / 16)
                            }
                        }
                }
            }
        }
    }

    private var clampedSplit: Double { min(max(splitRatio, 0.1), 0.9) }

    private func isPressed(column: Int, top: Bool) -> Bool {
        if splitRows {
            return lanesTouching[SliderMapping.sensorIndex(column: column, top: top)] != 0
        }
        // without rows both halves light up when the key is pressed
        return lanesTouching[SliderMapping.sensorIndex(column: column, top: true)] != 0
            || lanesTouching[SliderMapping.sensorIndex(column: column, top: false)] != 0
    }

    private func getColor(con: Listener?, i: Int, laneSplit: Bool) -> Color {
        if con == nil {
            return .black
        }

        let led = min(max(ledBrightness, 0), 1)
        if laneSplit {
            return Color(red: led * Double((con?.ledArray[(i * 2) * 3 + 4])!) / 255, green: led * Double((con?.ledArray[(i * 2) * 3 + 3])!) / 255, blue: led * Double((con?.ledArray[(i * 2) * 3 + 5])!) / 255)
        }

        return Color(red: led * Double((con?.ledArray[(i * 2) * 3 + 1])!) / 255, green: led * Double((con?.ledArray[(i * 2) * 3])!) / 255, blue: led * Double((con?.ledArray[(i * 2) * 3 + 2])!) / 255)
    }

}

#Preview {
    SliderView(lanesTouching: .constant(Array(repeating: 0, count: 32)), connection: .constant(nil), airOn: true)
}
