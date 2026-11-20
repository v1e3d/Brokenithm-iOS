//
//  ContentView.swift
//  brokenithm-swiftui
//
//  Created by Owen Cramer on 8/27/24.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @State var connection: Listener? = nil
    @State var drawerOpen: Bool = false
    @State var sheetShowing: Bool = false
    @State var settingsShowing: Bool = false
    @AppStorage("airOn") var airOn: Bool = false
    // Layout and judging settings (edited in SettingsView)
    @AppStorage("airHeightRatio") var airHeightRatio: Double = LayoutDefaults.airHeightRatio
    @AppStorage("airGapRatio") var airGapRatio: Double = LayoutDefaults.airGapRatio
    /// Top/bottom split of every slider key, like the cabinet (16 x 2 sensors).
    @AppStorage("splitRows") var splitRows: Bool = true
    @AppStorage("splitRatio") var splitRatio: Double = LayoutDefaults.splitRatio
    /// Touches near a key edge also press the neighbouring key.
    @AppStorage("edgeAssist") var edgeAssist: Bool = true
    @AppStorage("edgeFraction") var edgeFraction: Double = LayoutDefaults.edgeFraction
    @AppStorage("insetLeft") var insetLeft: Double = LayoutDefaults.insetLeft
    @AppStorage("insetRight") var insetRight: Double = LayoutDefaults.insetRight
    @AppStorage("showTouches") var showTouches: Bool = true
    @AppStorage("showRowDivider") var showRowDivider: Bool = true
    @AppStorage("ledBrightness") var ledBrightness: Double = LayoutDefaults.ledBrightness

    private var sliderOptions: SliderMapping.Options {
        var o = SliderMapping.Options()
        o.splitRows = splitRows
        o.splitRatio = splitRatio
        o.edgeAssist = edgeAssist
        o.edgeFraction = edgeFraction
        o.insetLeft = insetLeft
        o.insetRight = insetRight
        return o
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(.black)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if connection != nil {
                        Text(connection!.status)
                            .padding(.horizontal)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    
                    Menu {
                        Toggle(isOn: $airOn.animation(.bouncy(duration: 0.3, extraBounce: 0.2))) {
                            Text("Air Input")
                        }
                        Button("Settings", systemImage: "slider.horizontal.3") {
                            settingsShowing = true
                        }
                        Button("Restart Connection", systemImage: "arrow.clockwise") {
                            try? connection?.restart()
                        }
                        Button("Tap Card", systemImage: "person.text.rectangle") {
                            connection?.tapCard()
                        }
                        Button("Insert Coin", systemImage: "dollarsign.circle") {
                            connection?.insertCoin()
                        }
                        Button("About", systemImage: "info.circle") {
                            sheetShowing.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.title2)
                            .padding(.horizontal)
                            .padding(.vertical, 5)
                            .foregroundStyle(.white)
                    }
                }
                .background(Gradient(colors: [connection?.status == "Connected" ? .green.mix(with: .white, by: 0.2).opacity(0.7) : .red.opacity(0.7), .black.opacity(0.05)]))
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .frame(height: 3)
                    .ignoresSafeArea()
                InputBoardView(connection: $connection, airOn: $airOn,
                               airHeightRatio: airHeightRatio, airGapRatio: airGapRatio,
                               sliderOptions: sliderOptions,
                               showTouches: showTouches, showRowDivider: showRowDivider,
                               ledBrightness: ledBrightness)
            }
        }
        .ignoresSafeArea(edges: [.bottom])
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                try? connection?.restart()
            }
        }
        .onChange(of: airOn) {
            connection?.enableAir(enabled: airOn)
        }
        .onAppear {
            connection = try? Listener()
            if connection != nil {
                connection?.start()
            }
        }
        .sheet(isPresented: $sheetShowing, content: { AboutView(isPresented: $sheetShowing).presentationDragIndicator(.visible) })
        .sheet(isPresented: $settingsShowing, content: { SettingsView(isPresented: $settingsShowing).presentationDragIndicator(.visible) })
        
    }
}

#Preview {
    ContentView()
}
