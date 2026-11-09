import BudsDomain
import SwiftUI

struct EarbudSettingsView: View {
    @ObservedObject var explorer: BluetoothExplorer
    @State private var showGestures = false
    @State private var showHearingProfile = false
    @State private var showFirmware = false
    @State private var selectedGestureSide: UInt8 = 1

    private var hearingAvailable: Bool {
        explorer.controlReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 31) {
                HStack {
                    Text("WASII / DEVICE")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.5).foregroundStyle(Studio.accent)
                    Spacer()
                    Text("03")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Studio.secondary)
                }
                Text("Settings")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(-1.8).foregroundStyle(Studio.primary)
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Studio.background)
            ScrollView {
                VStack(alignment: .leading, spacing: 31) {
                deviceIdentity
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("GESTURE CONTROLS")
                    HStack(spacing: 12) {
                        gestureShortcut(side: 1)
                        gestureShortcut(side: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel("FIND & FIT")
                    HStack(alignment: .top, spacing: 12) {
                        actionCard(title: "Find my\nearbuds", symbol: "location.north.circle",
                                   detail: "Play a tone on both buds",
                                   button: explorer.findToneActive ? "Stop" : "Play sound",
                                   enabled: explorer.controlReady && explorer.accessoryCapabilities?.find == true) {
                            explorer.setFindTone(!explorer.findToneActive)
                        }
                        actionCard(title: "Earbud\nfit test", symbol: "ear",
                                   detail: "Check the seal in each ear",
                                   button: explorer.fitTestRunning ? "Stop" : "Start test",
                                   enabled: explorer.controlReady && explorer.accessoryCapabilities?.fitTest == true) {
                            explorer.setFitTest(!explorer.fitTestRunning)
                        }
                    }
                    if let result = explorer.fitTestResult {
                        Text(result).font(.footnote).foregroundStyle(Studio.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel("PREFERENCES")
                    Toggle(isOn: Binding(
                        get: { explorer.featureStates[.autoPlayPause] ?? false },
                        set: { explorer.setFeature(.autoPlayPause, enabled: $0) }
                    )) {
                        preferenceLabel("Auto play / pause", subtitle: "Pause when a bud leaves your ear")
                    }
                    .tint(Studio.accent)
                    .disabled(!explorer.controlReady || explorer.pendingFeature != nil ||
                              explorer.featureStates[.autoPlayPause] == nil)
                    Studio.line.frame(height: 1)
                    Toggle(isOn: Binding(
                        get: { explorer.featureStates[.personalANC] ?? false },
                        set: { explorer.setFeature(.personalANC, enabled: $0) }
                    )) {
                        preferenceLabel("Personalized noise cancellation", subtitle: personalSubtitle)
                    }
                    .tint(Studio.accent)
                    .disabled(!explorer.controlReady || explorer.pendingFeature != nil ||
                              explorer.featureStates[.personalANC] == nil ||
                              explorer.accessoryCapabilities?.personalANC != true ||
                              (explorer.featureStates[.personalANC] == false && explorer.personalANCStored != true))
                    Text("Personalized ANC requires a profile saved on the buds.")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("PERSONAL SOUND")
                    Button { showHearingProfile = true } label: {
                        HStack(spacing: 17) {
                            Image(systemName: "ear")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(Studio.accent)
                                .frame(width: 48, height: 48)
                                .background(Studio.background, in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Hearing profile")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(Studio.primary)
                                Text(explorer.accessoryCapabilities?.hearingTest == false ?
                                     "Test tones unavailable on this connection" :
                                     (explorer.hearingActiveID == nil ?
                                      "Create sound tuned to your hearing" : "Profile on your earbuds"))
                                    .font(.footnote).foregroundStyle(Studio.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Studio.primary)
                        }
                        .padding(18)
                        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hearingAvailable)
                    .opacity(hearingAvailable ? 1 : 0.5)
                }
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("ABOUT YOUR EARBUDS")
                    Button { showFirmware = true } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 21, weight: .medium))
                                .foregroundStyle(Studio.accent)
                                .frame(width: 46, height: 46)
                                .background(Studio.background, in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Device details")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Studio.primary)
                                Text("Model and firmware versions")
                                    .font(.footnote).foregroundStyle(Studio.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Studio.primary)
                        }
                        .padding(18)
                        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .background(Studio.background.ignoresSafeArea())
        .onAppear { explorer.refreshAccessorySettings() }
        .onDisappear {
            if explorer.findToneActive { explorer.setFindTone(false) }
            if explorer.fitTestRunning { explorer.setFitTest(false) }
        }
        .sheet(isPresented: $showGestures) {
            EarbudGesturesView(explorer: explorer, selectedSide: $selectedGestureSide)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHearingProfile) {
            HearingProfileView(explorer: explorer)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFirmware) {
            FirmwareDetailsView(explorer: explorer)
                .presentationDragIndicator(.visible)
        }
    }

    private var personalSubtitle: String {
        if explorer.personalANCStored == true { return "Use the profile saved on your earbuds" }
        if explorer.personalANCStored == false { return "Set up a profile in HeyMelody first" }
        return "Checking for a saved profile"
    }

    private var deviceIdentity: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("ONEPLUS / 064414")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.3).foregroundStyle(Studio.secondary)
                Spacer()
                Circle().fill(explorer.controlReady ? Studio.accent : Studio.line)
                    .frame(width: 7, height: 7)
                Text(explorer.controlReady ? "CONNECTED" : "OFFLINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1).foregroundStyle(Studio.primary)
            }
            Text("Nord Buds 3 Pro")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .tracking(-0.7).foregroundStyle(Studio.primary)
            Studio.line.frame(height: 1)
            HStack {
                Text("LEFT  ·  \(explorer.leftPresence?.title ?? "Checking")")
                Spacer()
                Text("RIGHT  ·  \(explorer.rightPresence?.title ?? "Checking")")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Studio.secondary)
        }
        .padding(20)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .heavy, design: .monospaced))
            .tracking(1.5).foregroundStyle(Studio.accent)
    }

    private func gestureShortcut(side: UInt8) -> some View {
        let isLeft = side == 1
        let presence = isLeft ? explorer.leftPresence : explorer.rightPresence
        let binding = explorer.gestureTable?.function(side: side, action: 2)
        let bindingTitle = NordGesture.availableActions(for: 2)
            .first(where: { $0.function == binding })?.title ?? "Reading controls"
        return Button {
            selectedGestureSide = side
            showGestures = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    SingleBudArtwork(side: side)
                        .frame(width: 82, height: 94)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Studio.secondary)
                }
                Text(isLeft ? "Left bud" : "Right bud")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Studio.primary)
                Text(presence?.title ?? "Status unknown")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Studio.accent)
                Text("Double tap · \(bindingTitle)")
                    .font(.system(size: 11))
                    .foregroundStyle(Studio.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 215, alignment: .topLeading)
            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(!explorer.controlReady || explorer.accessoryCapabilities?.gestures != true)
        .opacity(explorer.controlReady && explorer.accessoryCapabilities?.gestures == true ? 1 : 0.5)
        .accessibilityLabel("\(isLeft ? "Left" : "Right") earbud gestures, \(bindingTitle)")
    }

    private func preferenceLabel(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Studio.primary)
            Text(subtitle).font(.footnote).foregroundStyle(Studio.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionCard(title: String, symbol: String, detail: String, button: String,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Studio.accent)
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Studio.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 11)).foregroundStyle(Studio.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(button, action: action)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Studio.background)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Studio.primary, in: Capsule())
                .buttonStyle(.plain)
                .disabled(!enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
        .opacity(enabled ? 1 : 0.55)
    }
}

struct EarbudGesturesView: View {
    @ObservedObject var explorer: BluetoothExplorer
    @Binding var selectedSide: UInt8
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                HStack {
                    Text("WASII / CONTROLS")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.5).foregroundStyle(Studio.accent)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Studio.primary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gestures")
                        .font(.system(size: 43, weight: .bold, design: .rounded))
                        .tracking(-1.7).foregroundStyle(Studio.primary)
                    Text("Choose an earbud, then set what each touch does.")
                        .font(.subheadline).foregroundStyle(Studio.secondary)
                }

                HStack(spacing: 11) {
                    sideCard(1)
                    sideCard(2)
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("During calls")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(Studio.primary)
                        Spacer()
                        Text("BOTH BUDS")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.2).foregroundStyle(Studio.accent)
                    }
                    Text("The model lists these call actions for both earbuds. They are not editable on Nord Buds 3 Pro.")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                    VStack(spacing: 0) {
                        callRow("Double tap", detail: "Answer or end a call", action: 2, enabledFunction: 0x1D)
                        Studio.line.frame(height: 1)
                        callRow("Extended hold", detail: "Decline a ringing call · model-listed", action: 6, enabledFunction: 0x1C)
                    }
                    .padding(.horizontal, 17)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
                    Text("Single tap is not a call action on this model. A regular hold changes noise control; the decline action uses a separate, longer hold and has not been confirmed on this iPhone.")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(selectedSide == 1 ? "Left earbud" : "Right earbud")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(Studio.primary)
                        Spacer()
                        Text("TOUCH MAP")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.2).foregroundStyle(Studio.accent)
                    }
                    VStack(spacing: 0) {
                        gestureRow("Single tap", action: 1, index: "01")
                        Studio.line.frame(height: 1)
                        gestureRow("Double tap", action: 2, index: "02")
                        Studio.line.frame(height: 1)
                        gestureRow("Triple tap", action: 3, index: "03")
                        Studio.line.frame(height: 1)
                        gestureRow("Long hold", action: 6, index: "04")
                    }
                    .padding(.horizontal, 17)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
                    if explorer.gestureTable == nil {
                        Label("Reading controls from the earbuds", systemImage: "waveform")
                            .font(.footnote).foregroundStyle(Studio.secondary)
                    }
                    if let error = explorer.gestureError {
                        Text(error).font(.footnote).foregroundStyle(Studio.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Noise cycle")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(Studio.primary)
                        Spacer()
                        Text("BOTH BUDS")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.2).foregroundStyle(Studio.accent)
                    }
                    Text("Choose at least two modes for the hold gesture.")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                    VStack(spacing: 0) {
                        cycleRow("Off", bit: 0)
                        Studio.line.frame(height: 1)
                        cycleRow("Noise cancellation", bit: 1)
                        Studio.line.frame(height: 1)
                        cycleRow("Transparency", bit: 2)
                    }
                    .padding(.horizontal, 17)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                Text("The earbuds confirm each change before it appears here.")
                    .font(.footnote).foregroundStyle(Studio.secondary)
            }
            .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(Studio.background.ignoresSafeArea())
        .modifier(StatusToastPresenter(explorer: explorer))
        .onAppear { explorer.refreshGestures() }
    }

    private func sideCard(_ side: UInt8) -> some View {
        let active = selectedSide == side
        let pending = explorer.gesturePendingSide == side
        let presence = side == 1 ? explorer.leftPresence : explorer.rightPresence
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.83)) {
                selectedSide = side
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    SingleBudArtwork(side: side)
                        .frame(width: 82, height: 96)
                    Spacer()
                    if pending {
                        ProgressView().tint(Studio.accent)
                    } else {
                        Circle().fill(active ? Studio.accent : Studio.line)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(side == 1 ? "LEFT EARBUD" : "RIGHT EARBUD")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1)
                Text(pending ? "Saving change…" : (presence?.title ?? "Status unknown"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Studio.primary)
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 186, alignment: .topLeading)
            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21)
                .strokeBorder(active ? Studio.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(side == 1 ? "Left" : "Right") earbud, \(presence?.title ?? "status unknown")")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func callRow(_ title: String, detail: String, action: UInt8,
                         enabledFunction: UInt8) -> some View {
        let current = explorer.gestureTable?.callFunction(action: action)
        return HStack(spacing: 15) {
            Image(systemName: action == 2 ? "hand.tap" : "hand.point.up.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Studio.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Studio.primary)
                Text(detail).font(.footnote).foregroundStyle(Studio.secondary)
                Text(current == enabledFunction ? "Reported by both earbuds" :
                     current == 0 ? "Off in the earbuds' gesture table" :
                     "Not reported in the gesture table")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(current == enabledFunction ? Studio.accent : Studio.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
    }

    private func gestureRow(_ title: String, action: UInt8, index: String) -> some View {
        let side = selectedSide
        let value = explorer.gestureTable?.function(side: side, action: action)
        let choices = NordGesture.availableActions(for: action)
        let isPending = explorer.gesturePendingSide == side && explorer.gesturePendingAction == action
        return Menu {
            ForEach(choices) { choice in
                Button(choice.title) {
                    explorer.changeGesture(side: side, action: action, function: choice.function)
                }
            }
        } label: {
            HStack(spacing: 15) {
                Text(index)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Studio.accent)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Studio.primary)
                    Text(isPending ? "Saving to \(side == 1 ? "left" : "right") earbud…" :
                         choices.first(where: { $0.function == value })?.title ??
                         value.map { String(format: "Current 0x%02X", $0) } ?? "Unavailable")
                        .font(.footnote)
                        .foregroundStyle(isPending ? Studio.accent : Studio.secondary)
                }
                Spacer(minLength: 0)
                if isPending {
                    ProgressView().tint(Studio.accent)
                } else {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Studio.secondary)
                    }
            }
            .frame(minHeight: 69)
            .contentShape(Rectangle())
        }
        .disabled(value == nil || explorer.gestureBusy || !explorer.controlReady)
        .accessibilityLabel("\(title), \(side == 1 ? "left" : "right") earbud")
    }

    private func cycleRow(_ title: String, bit: UInt32) -> some View {
        let current = explorer.holdCycleMask
        let selected = current.map { $0 & (1 << bit) != 0 } ?? false
        return Button {
            guard let current else { return }
            explorer.changeHoldCycle(current ^ (1 << bit))
        } label: {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Studio.primary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Studio.accent : Studio.secondary)
            }
            .padding(.vertical, 17)
        }
        .buttonStyle(.plain)
        .disabled(current == nil || explorer.holdCycleBusy || explorer.gestureBusy ||
                  (selected && ((current ?? 0) & 0x07).nonzeroBitCount <= 2))
    }
}
