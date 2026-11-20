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
    /// Air area height as a fraction of the board height.
    var airHeightRatio: Double = LayoutDefaults.airHeightRatio
    /// Dead band between the air area and the slider (fraction of the board height); touches there send nothing.
    var airGapRatio: Double = LayoutDefaults.airGapRatio
    var sliderOptions = SliderMapping.Options()
    var showTouches: Bool = true
    var showRowDivider: Bool = true
    var ledBrightness: Double = LayoutDefaults.ledBrightness

    var body: some View {
        GeometryReader { proxy in
            let airHeight: CGFloat = airOn ? proxy.size.height * CGFloat(min(max(airHeightRatio, 0.05), 0.8)) : 0
            let gap: CGFloat = airOn ? proxy.size.height * CGFloat(min(max(airGapRatio, 0), 0.3)) : 0
            let airBlockHeight = max(airHeight / 6, 1)
            let sliderTop = airHeight + gap
            let sliderHeight = max(proxy.size.height - sliderTop, 1)
            VStack(spacing: 0) {
                if airOn {
                    AirInputView(size: airHeight, airTouching: $airTouching, connection: $connection)
                    if gap > 0 {
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: gap)
                            .overlay(alignment: .center) {
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                            }
                    }
                }
                HStack(spacing: 0) {
                    Color.black.frame(width: proxy.size.width * CGFloat(min(max(sliderOptions.insetLeft, 0), 0.4)))
                    SliderView(lanesTouching: $lanesTouching, connection: $connection, airOn: airOn,
                               splitRows: sliderOptions.splitRows, splitRatio: sliderOptions.splitRatio,
                               showTouches: showTouches, showRowDivider: showRowDivider, ledBrightness: ledBrightness)
                    Color.black.frame(width: proxy.size.width * CGFloat(min(max(sliderOptions.insetRight, 0), 0.4)))
                }
            }
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
                            if y < 0 { continue }
                            if airOn && y < airHeight {
                                setAir(&air, block: Int(y / airBlockHeight))
                            } else if y >= sliderTop {
                                sliderTouches.append(SliderMapping.Touch(x: Double(x), y: Double(y - sliderTop)))
                            }
                            // touches in the dead band are ignored
                        }
                        let lanes = SliderMapping.sensors(for: sliderTouches,
                                                          width: Double(proxy.size.width),
                                                          height: Double(sliderHeight),
                                                          options: sliderOptions)
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
    InputBoardView(connection: .constant(nil), airOn: .constant(true))
}
