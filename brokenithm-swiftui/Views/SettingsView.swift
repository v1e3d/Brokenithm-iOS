//
//  SettingsView.swift
//  brokenithm-swiftui
//
//  Layout and judging customization. Every value is stored with @AppStorage, so it survives restarts.
//

import SwiftUI

/// Keys and defaults shared by ContentView and SettingsView.
enum LayoutDefaults {
    static let airHeightRatio = 1.0 / 3.0
    static let airGapRatio = 0.0
    static let splitRatio = 0.5
    static let edgeFraction = SliderMapping.defaultEdgeFraction
    static let insetLeft = 0.0
    static let insetRight = 0.0
    static let ledBrightness = 1.0
}

struct SettingsView: View {
    @Binding var isPresented: Bool

    @AppStorage("airOn") var airOn: Bool = false
    @AppStorage("airHeightRatio") var airHeightRatio: Double = LayoutDefaults.airHeightRatio
    @AppStorage("airGapRatio") var airGapRatio: Double = LayoutDefaults.airGapRatio
    @AppStorage("splitRows") var splitRows: Bool = true
    @AppStorage("splitRatio") var splitRatio: Double = LayoutDefaults.splitRatio
    @AppStorage("edgeAssist") var edgeAssist: Bool = true
    @AppStorage("edgeFraction") var edgeFraction: Double = LayoutDefaults.edgeFraction
    @AppStorage("insetLeft") var insetLeft: Double = LayoutDefaults.insetLeft
    @AppStorage("insetRight") var insetRight: Double = LayoutDefaults.insetRight
    @AppStorage("showTouches") var showTouches: Bool = true
    @AppStorage("showRowDivider") var showRowDivider: Bool = true
    @AppStorage("ledBrightness") var ledBrightness: Double = LayoutDefaults.ledBrightness

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("위/아래 칸 분할 (실기체 16×2)", isOn: $splitRows)
                    if splitRows {
                        percentSlider("위 칸 높이", value: $splitRatio, range: 0.2 ... 0.8)
                    }
                    Toggle("가장자리 보정", isOn: $edgeAssist)
                    if edgeAssist {
                        percentSlider("보정 폭 (키 너비 대비)", value: $edgeFraction, range: 0.05 ... 0.45)
                    }
                    percentSlider("왼쪽 여백", value: $insetLeft, range: 0 ... 0.2)
                    percentSlider("오른쪽 여백", value: $insetRight, range: 0 ... 0.2)
                } header: {
                    Text("슬라이더")
                } footer: {
                    Text("여백을 주면 16개 키가 안쪽 영역에만 배치되고, 여백을 누르면 가장 바깥 키로 처리됩니다. 가장자리 보정은 키 경계 근처를 누르면 옆 키도 함께 누릅니다.")
                }

                Section {
                    Toggle("에어 영역 사용", isOn: $airOn)
                    if airOn {
                        percentSlider("에어 영역 높이 (화면 대비)", value: $airHeightRatio, range: 0.15 ... 0.6)
                        percentSlider("에어와 슬라이더 사이 데드존", value: $airGapRatio, range: 0 ... 0.15)
                    }
                } header: {
                    Text("에어")
                } footer: {
                    Text("데드존은 어떤 입력도 보내지 않는 띠입니다. 슬라이더를 치다가 에어가 잘못 들어갈 때 늘리세요.")
                }

                Section("표시") {
                    Toggle("누른 칸 강조", isOn: $showTouches)
                    Toggle("위/아래 경계선", isOn: $showRowDivider)
                    percentSlider("LED 밝기", value: $ledBrightness, range: 0 ... 1)
                }

                Section {
                    Button("기본값으로 되돌리기", role: .destructive) {
                        airHeightRatio = LayoutDefaults.airHeightRatio
                        airGapRatio = LayoutDefaults.airGapRatio
                        splitRows = true
                        splitRatio = LayoutDefaults.splitRatio
                        edgeAssist = true
                        edgeFraction = LayoutDefaults.edgeFraction
                        insetLeft = LayoutDefaults.insetLeft
                        insetRight = LayoutDefaults.insetRight
                        showTouches = true
                        showRowDivider = true
                        ledBrightness = LayoutDefaults.ledBrightness
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { isPresented = false }
                }
            }
        }
    }

    private func percentSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

#Preview {
    SettingsView(isPresented: .constant(true))
}
