//
//  InputBoardView.swift
//  brokenithm-swiftui
//
//  Created by Owen Cramer on 9/11/24.
//

import SwiftUI

struct InputBoardView: View {
    /// Slider sensor states in game order (see SliderMapping): index 2k = top row, 2k+1 = bottom row
    /// of the k-th key from the right.
    @State var lanesTouching: [UInt8] = Array(repeating: 0, count: 32)
    @State var airTouching: [UInt8] = Array(repeating: 0, count: 6)
    @Binding var connection: Listener?
    @Binding var airOn: Bool
    @Binding var airOption: String
    var splitRows: Bool = true
    var edgeAssist: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let airHeight = proxy.size.height / (airOption == "Normal" ? 3 : airOption == "Small" ? 4.5 : 2)
            let airBlockHeight = airHeight / 6
            let sliderTop: CGFloat = airOn ? airHeight : 0
            VStack(spacing: 0) {
                if airOn {
                    AirInputView(size: airHeight, airTouching: $airTouching, connection: $connection)
                }
                SliderView(lanesTouching: $lanesTouching, connection: $connection, airOn: airOn, splitRows: splitRows)
            }
            .sensoryFeedback(.success, trigger: airOption)
            .gesture(
                SpatialEventGesture()
                    .onChanged { events in
                        // Rebuild the whole state from every finger that is down, then send it once.
                        // (Sending after each finger, or clearing lanes when one finger lifts or touches
                        // the air area, made other held fingers flicker off/on: broken HOLDs and ghost TAPs.)
                        var sliderTouches: [SliderMapping.Touch] = []
                        var air = [UInt8](repeating: 0, count: 6)
                        for event in events where event.phase == .active {
                            let x = event.location.x
                            let y = event.location.y
                            if (y < airHeight && airOn) || y < 0 {
                                if airOn, y > 0 {
                                    setAir(&air, block: Int(y / airBlockHeight))
                                }
                            } else {
                                sliderTouches.append(SliderMapping.Touch(x: Double(x), y: Double(y - sliderTop)))
                            }
                        }
                        let options = SliderMapping.Options(splitRows: splitRows, edgeAssist: edgeAssist)
                        let lanes = SliderMapping.sensors(for: sliderTouches,
                                                          width: Double(proxy.size.width),
                                                          height: Double(proxy.size.height - sliderTop),
                                                          options: options)
                        update(lanes: lanes, air: air)
                    }
                    .onEnded { _ in
                        update(lanes: Array(repeating: 0, count: 32), air: Array(repeating: 0, count: 6))
                    }
            )
        }
    }

    /// Sends the new state only when something changed.
    private func update(lanes: [UInt8], air: [UInt8]) {
        if lanes == lanesTouching && air == airTouching { return }
        lanesTouching = lanes
        airTouching = air
        connection?.sendInput(arrayLane: lanes, arrayAir: air)
    }

    /// Air blocks from the top of the air area; unchanged from the original mapping.
    private func setAir(_ air: inout [UInt8], block: Int) {
        let airLanes = [4, 5, 2, 3, 0, 1]
        let index = min(max(block, 0), 5)
        air[airLanes[index]] = 128
    }
}

#Preview {
    InputBoardView(connection: .constant(nil), airOn: .constant(true), airOption: .constant("Normal"))
}
