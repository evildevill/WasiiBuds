import BudsDomain
import SwiftUI

struct EqualizerView: View {
    @ObservedObject var explorer: BluetoothExplorer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editor: CustomEQPreset?
    @State private var bassDraft = 0.0
    @State private var bassDragging = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let error = explorer.eqError ?? explorer.featureError {
                    Text(error)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Studio.accent)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                if explorer.eqCapabilities?.builtIn == true { builtInSection }
                if explorer.eqCapabilities?.custom == true { customSection }
                if explorer.eqCapabilities?.bassWave == true,
                   explorer.featureStates[.bassBoost] != nil { bassSection }
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(Studio.background.ignoresSafeArea())
        .modifier(StatusToastPresenter(explorer: explorer))
        .sheet(item: $editor) { preset in
            CustomEQEditor(explorer: explorer, preset: preset)
                .id(preset.id)
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            explorer.refreshEQ()
            bassDraft = Double(explorer.bassWaveLevel ?? 0)
        }
        .onChange(of: explorer.bassWaveLevel) { _, value in
            if !bassDragging { bassDraft = Double(value ?? 0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SOUND / 01")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.5).foregroundStyle(Studio.accent)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Studio.primary)
            }
            Text("Equalizer")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .tracking(-1.5).foregroundStyle(Studio.primary)
            Text("Tune the sound on your Nord Buds 3 Pro.")
                .font(.subheadline).foregroundStyle(Studio.secondary)
        }
    }

    private var builtInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Presets", detail: "TUNED BY ONEPLUS")
            ForEach(NordEQPreset.allCases) { preset in
                let selected = explorer.eqCurrent == preset.id
                Button { explorer.selectEQ(preset) } label: {
                    HStack(spacing: 16) {
                        presetMark(preset)
                        Text(preset.title)
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Text("ACTIVE")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.1)
                            .foregroundStyle(Studio.accent)
                            .opacity(selected ? 1 : 0)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Studio.accent : Studio.secondary)
                            .contentTransition(.symbolEffect)
                    }
                    .foregroundStyle(Studio.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 66)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 17))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Studio.accent)
                            .frame(width: 3, height: 29)
                            .padding(.leading, 1)
                            .opacity(selected ? 1 : 0)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .strokeBorder(Studio.accent.opacity(selected ? 0.3 : 0), lineWidth: 1)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selected)
                }
                .buttonStyle(.plain)
                .disabled(!explorer.controlReady || explorer.eqBusy || explorer.eqCurrent == nil)
            }
            if explorer.eqCurrent == nil {
                Text("Reading the active preset from the earbuds…")
                    .font(.footnote).foregroundStyle(Studio.secondary)
            }
        }
    }

    private func presetMark(_ preset: NordEQPreset) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(preset == .balanced ? Studio.accent :
                          preset == .bass && index < 2 ? Studio.accent :
                          preset == .clearVocals && index > 1 ? Studio.accent : Studio.secondary)
                    .frame(width: 3, height: CGFloat([13, 23, 18, 11][index]))
            }
        }
        .frame(width: 35)
        .accessibilityHidden(true)
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Your sound", detail: "SIX BANDS")
            if !explorer.eqCustomLoaded {
                Text("Reading custom presets…")
                    .font(.subheadline).foregroundStyle(Studio.secondary)
            } else {
                ForEach(explorer.eqCustom) { preset in
                    HStack(spacing: 12) {
                        Button { explorer.saveCustomEQ(preset) } label: {
                            HStack {
                                Image(systemName: explorer.eqCurrent == preset.id ?
                                      "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Studio.accent)
                                Text(preset.name).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Studio.primary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!explorer.controlReady || explorer.eqBusy)
                        Button { editor = preset } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Studio.primary)
                                .frame(width: 44, height: 44)
                                .background(Studio.background, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!explorer.controlReady || explorer.eqBusy)
                        .accessibilityLabel("Edit \(preset.name)")
                    }
                    .padding(.horizontal, 16)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 17))
                }
                if explorer.eqCustom.count < 3 {
                    Button { explorer.createCustomEQ() } label: {
                        Label("Add custom preset", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Studio.primary)
                            .frame(maxWidth: .infinity, minHeight: 55)
                            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                    .disabled(!explorer.controlReady || explorer.eqBusy)
                }
            }
            Text("The earbuds store up to three custom presets. Changes save when you tap Save.")
                .font(.footnote).foregroundStyle(Studio.secondary)
        }
    }

    private var bassSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Bass boost", detail: "BASSWAVE")
            Toggle(isOn: Binding(
                get: { explorer.featureStates[.bassBoost] ?? false },
                set: { explorer.setFeature(.bassBoost, enabled: $0) }
            )) {
                Text("Bass boost").font(.subheadline.weight(.semibold))
            }
            .tint(Studio.accent)
            .disabled(!explorer.controlReady || explorer.eqBusy || explorer.pendingFeature != nil)
            if explorer.featureStates[.bassBoost] == true {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Strength").font(.footnote).foregroundStyle(Studio.secondary)
                        Spacer()
                        Text("\(Int(bassDraft))")
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Studio.primary)
                    }
                    Slider(value: $bassDraft, in: -5...5, step: 1) {
                        Text("Bass boost level")
                    } onEditingChanged: { editing in
                        bassDragging = editing
                        if !editing { explorer.setBassWaveLevel(Int(bassDraft)) }
                    }
                    .tint(Studio.accent)
                    .disabled(!explorer.controlReady || explorer.eqBusy)
                    Text(explorer.bassLevelReported ? "Level reported by earbuds" :
                         explorer.bassWaveLevel == nil ? "Set a level to tune bass" :
                         "Last accepted level; earbuds have not reported it back")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(18)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 17))
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.5).foregroundStyle(Studio.primary)
            Spacer()
            Text(detail).font(.system(size: 10, weight: .bold))
                .tracking(1.2).foregroundStyle(Studio.secondary)
        }
    }
}

private struct CustomEQEditor: View {
    @ObservedObject var explorer: BluetoothExplorer
    let preset: CustomEQPreset
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var gains: [Int8]
    @State private var confirmDelete = false

    init(explorer: BluetoothExplorer, preset: CustomEQPreset) {
        self.explorer = explorer
        self.preset = preset
        _name = State(initialValue: preset.name)
        _gains = State(initialValue: preset.gains)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Studio.secondary)
                    Spacer()
                    Text("CUSTOM SOUND")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.5).foregroundStyle(Studio.accent)
                    Spacer()
                    Button("Save") {
                        var edited = preset
                        edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        edited.gains = gains
                        explorer.saveCustomEQ(edited)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Studio.accent)
                    .disabled(!valid || explorer.eqBusy)
                }
                TextField("Preset name", text: $name)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(Studio.primary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Text("Drag each band, then tap Save. The earbuds confirm the full preset before the list updates.")
                    .font(.subheadline).foregroundStyle(Studio.secondary)
                EQBandGraph(frequencies: preset.frequencies, gains: $gains)
                    .frame(height: 300)
                Button("Reset bands") { gains = Array(repeating: 0, count: gains.count) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Studio.primary)
                    .padding(.top, 4)
                Button("Delete preset", role: .destructive) { confirmDelete = true }
                    .font(.subheadline.weight(.medium))
                    .disabled(explorer.eqBusy || explorer.eqCurrent == preset.id)
                    .padding(.top, 15)
                if explorer.eqCurrent == preset.id {
                    Text("Select a different preset before deleting this one.")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                }
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
        .background(Studio.background.ignoresSafeArea())
        .confirmationDialog("Delete \(preset.name)?", isPresented: $confirmDelete) {
            Button("Delete preset", role: .destructive) {
                explorer.deleteCustomEQ(preset)
                dismiss()
            }
        } message: {
            Text(explorer.eqCurrent == preset.id ?
                 "Select another preset first. The earbuds cannot delete the active preset." :
                 "This removes the preset from the earbuds.")
        }
    }

    private var valid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf8.count <= 20
    }

}

private struct EQBandGraph: View {
    let frequencies: [UInt16]
    @Binding var gains: [Int8]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Studio.surface)
                ForEach([-6, 0, 6], id: \.self) { level in
                    Path { path in
                        let y = yPosition(for: level, height: height)
                        path.move(to: CGPoint(x: 28, y: y))
                        path.addLine(to: CGPoint(x: width - 28, y: y))
                    }
                    .stroke(Studio.line, style: StrokeStyle(lineWidth: level == 0 ? 1.5 : 1,
                                                            dash: level == 0 ? [] : [3, 4]))
                }
                areaPath(width: width, height: height)
                    .fill(Studio.accent.opacity(0.09))
                curvePath(width: width, height: height)
                    .stroke(Studio.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round,
                                                               lineJoin: .round))
                ForEach(frequencies.indices, id: \.self) { index in
                    let point = point(at: index, width: width, height: height)
                    Circle()
                        .fill(Studio.background)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Studio.accent, lineWidth: 3))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .position(point)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("eqGraph"))
                                .onChanged { value in
                                    let raw = 6 - (value.location.y - 25) / max(height - 80, 1) * 12
                                    gains[index] = Int8(min(6, max(-6, Int(raw.rounded()))))
                                }
                        )
                        .accessibilityElement()
                        .accessibilityLabel("\(frequencyLabel(frequencies[index])) band")
                        .accessibilityValue("\(gains[index]) decibels")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: gains[index] = min(6, gains[index] + 1)
                            case .decrement: gains[index] = max(-6, gains[index] - 1)
                            @unknown default: break
                            }
                        }
                    Text(frequencyLabel(frequencies[index]))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Studio.secondary)
                        .position(x: point.x, y: height - 21)
                        .accessibilityHidden(true)
                }
                Text("+6")
                    .position(x: width / 2, y: 14)
                Text("−6")
                    .position(x: width / 2, y: height - 52)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Studio.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .coordinateSpace(name: "eqGraph")
        }
        .sensoryFeedback(.selection, trigger: gains)
    }

    private func point(at index: Int, width: CGFloat, height: CGFloat) -> CGPoint {
        let x = 28 + CGFloat(index) * (width - 56) / CGFloat(max(frequencies.count - 1, 1))
        return CGPoint(x: x, y: yPosition(for: Int(gains[index]), height: height))
    }

    private func yPosition(for level: Int, height: CGFloat) -> CGFloat {
        25 + CGFloat(6 - level) / 12 * max(height - 80, 1)
    }

    private func curvePath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            guard !frequencies.isEmpty else { return }
            path.move(to: point(at: 0, width: width, height: height))
            for index in 1..<frequencies.count {
                let previous = point(at: index - 1, width: width, height: height)
                let current = point(at: index, width: width, height: height)
                let middle = (previous.x + current.x) / 2
                path.addCurve(to: current,
                              control1: CGPoint(x: middle, y: previous.y),
                              control2: CGPoint(x: middle, y: current.y))
            }
        }
    }

    private func areaPath(width: CGFloat, height: CGFloat) -> Path {
        var path = curvePath(width: width, height: height)
        guard !frequencies.isEmpty else { return path }
        path.addLine(to: CGPoint(x: width - 28, y: yPosition(for: 0, height: height)))
        path.addLine(to: CGPoint(x: 28, y: yPosition(for: 0, height: height)))
        path.closeSubpath()
        return path
    }

    private func frequencyLabel(_ frequency: UInt16) -> String {
        frequency >= 1000 ? "\(Int(frequency) / 1000)k" : "\(frequency)"
    }
}
