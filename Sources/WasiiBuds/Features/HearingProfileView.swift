import BudsDomain
import SwiftUI

struct HearingProfileView: View {
    @ObservedObject var explorer: BluetoothExplorer
    @Environment(\.dismiss) private var dismiss
    @State private var showTest = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                HStack {
                    Text("SOUND / PERSONAL")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.5).foregroundStyle(Studio.accent)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Studio.primary)
                }
                Text("Hearing profile")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .tracking(-1.5).foregroundStyle(Studio.primary)
                Text("A sound profile made from your own listening test.")
                    .font(.subheadline).foregroundStyle(Studio.secondary)

                HStack(spacing: 16) {
                    Image(systemName: "ear")
                        .font(.system(size: 22))
                        .foregroundStyle(Studio.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hearing profile")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Studio.primary)
                        Text(explorer.hearingActiveID == nil ?
                             "Take a test to create one" : "Sound tuned to your hearing")
                            .font(.footnote).foregroundStyle(Studio.secondary)
                    }
                    Spacer(minLength: 0)
                    Toggle("Hearing profile", isOn: Binding(
                        get: { explorer.featureStates[.hearingProfile] ?? false },
                        set: { explorer.setFeature(.hearingProfile, enabled: $0) }
                    ))
                    .labelsHidden()
                    .tint(Studio.accent)
                    .disabled(!explorer.controlReady || explorer.pendingFeature != nil ||
                              explorer.featureStates[.hearingProfile] == nil)
                }
                .padding(18)
                .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("Profiles")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(Studio.primary)
                        Spacer()
                        Text("\(explorer.hearingRecords.count) SAVED")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1).foregroundStyle(Studio.accent)
                    }
                    if explorer.hearingRecords.isEmpty {
                        Text(explorer.hearingLoaded ? "No profiles yet" : "Reading the earbuds…")
                            .font(.subheadline).foregroundStyle(Studio.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(spacing: 10) {
                            ForEach(explorer.hearingRecords) { record in
                                profileRow(record)
                            }
                        }
                    }
                }

                Button { showTest = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "waveform")
                            .font(.system(size: 22))
                            .foregroundStyle(Studio.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Take the hearing test")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Studio.primary)
                            Text(testAvailabilityDescription)
                                .font(.footnote).foregroundStyle(Studio.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Studio.primary)
                    }
                    .padding(19)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .disabled(!testAvailable || explorer.hearingBusy)
                .opacity(testAvailable ? 1 : 0.5)

                if explorer.controlReady, explorer.accessoryCapabilities?.hearingTest == false {
                    Text("Hearing-test tones are unavailable on this Bluetooth connection. Saved profiles can still be viewed here.")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                }

                Text("Profiles you create here stay on this iPhone. The earbuds hold the active profile, including one made in HeyMelody.")
                    .font(.footnote).foregroundStyle(Studio.secondary)
            }
            .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(Studio.background.ignoresSafeArea())
        .modifier(StatusToastPresenter(explorer: explorer))
        .onAppear { explorer.refreshHearingProfile() }
        .sheet(isPresented: $showTest) {
            HearingTestView(explorer: explorer)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(testIsRunning)
        }
    }

    private var testIsRunning: Bool {
        switch explorer.hearingTestStage {
        case .scanning, .starting, .testing, .finishing: true
        default: false
        }
    }

    private var testAvailable: Bool {
        explorer.controlReady && explorer.accessoryCapabilities?.hearingTest == true
    }

    private var testAvailabilityDescription: String {
        if !explorer.controlReady { return "Connect your earbuds to check availability" }
        guard let capabilities = explorer.accessoryCapabilities else { return "Checking availability…" }
        return capabilities.hearingTest ? "About 3 minutes · Find a quiet place" :
            "Test tones are unavailable on this connection"
    }

    private func profileRow(_ record: HearingProfileRecord) -> some View {
        let active = record.id == explorer.hearingActiveID
        return Button { explorer.applyHearingProfile(record) } label: {
            HStack(spacing: 14) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(active ? Studio.accent : Studio.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Studio.primary)
                    Text(active ? "Active on earbuds" : "Tap to apply")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                }
                Spacer()
                if explorer.hearingBusy && !active {
                    ProgressView().tint(Studio.accent)
                }
            }
            .padding(18)
            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!explorer.controlReady || explorer.hearingBusy || active)
        .contextMenu {
            if !active {
                Button("Delete from iPhone", role: .destructive) {
                    explorer.deleteHearingProfile(record)
                }
            }
        }
    }
}

struct HearingTestView: View {
    @ObservedObject var explorer: BluetoothExplorer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("HEARING / TEST")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.5).foregroundStyle(Studio.accent)
                Spacer()
                Button("Close") {
                    explorer.stopHearingTest()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Studio.primary)
            }
            Text(title)
                .font(.system(size: 37, weight: .bold, design: .rounded))
                .tracking(-1.3).foregroundStyle(Studio.primary)
            Text(detail)
                .font(.subheadline).foregroundStyle(Studio.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .testing(let step) = explorer.hearingTestStage {
                HStack {
                    Text(step < 6 ? "LEFT EARBUD" : "RIGHT EARBUD")
                    Spacer()
                    Text("\(step + 1) / 12")
                }
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1).foregroundStyle(Studio.accent)
                ProgressView(value: Double(step + 1), total: 12)
                    .tint(Studio.accent)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Adjust until the tone is barely audible.")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Studio.primary)
                    Slider(value: Binding(
                        get: { Double(explorer.hearingLevelIndex) },
                        set: { explorer.setHearingLevel(Int($0.rounded())) }
                    ), in: 0...24, step: 1)
                    .tint(Studio.accent)
                    HStack {
                        Text("Softer")
                        Spacer()
                        Text("Louder")
                    }
                    .font(.footnote).foregroundStyle(Studio.secondary)
                    if explorer.hearingLevelIndex >= 21 {
                        Text("This level may be loud. Lower it before continuing if uncomfortable.")
                            .font(.footnote).foregroundStyle(Studio.accent)
                    }
                    Text(explorer.hearingToneConfirmed ?
                         "If no tone is audible as you adjust the slider, close the test instead of saving a profile." :
                         "Waiting for the earbuds to accept this tone…")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                }
                .padding(20)
                .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
            }
            if explorer.hearingTestStage == .scanning || explorer.hearingTestStage == .starting ||
                explorer.hearingTestStage == .finishing ||
                explorer.hearingBusy {
                ProgressView().tint(Studio.accent)
            }
            if let error = explorer.hearingError {
                Text(error).font(.footnote).foregroundStyle(Studio.accent)
            }
            Spacer(minLength: 0)
            Button(actionTitle) { primaryAction() }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Studio.background)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Studio.primary, in: Capsule())
                .buttonStyle(.plain)
                .disabled(explorer.hearingTestStage == .scanning ||
                          explorer.hearingTestStage == .starting ||
                          explorer.hearingTestStage == .finishing || explorer.hearingBusy ||
                          toneIsPending)
            if explorer.hearingTestStage == .idle || explorer.hearingTestStage == .failed,
               explorer.accessoryCapabilities?.hearingScan == true,
               explorer.accessoryCapabilities?.hearingTest == true {
                Button("Continue with tones only") {
                    explorer.startHearingTest(skipEarScan: true)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Studio.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .buttonStyle(.plain)
                Text("Skips the ear-fit scan. Your profile will use the 12 listening tones without ear-fit calibration.")
                    .font(.footnote)
                    .foregroundStyle(Studio.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 23).padding(.top, 30).padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Studio.background.ignoresSafeArea())
        .onDisappear { explorer.stopHearingTest() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { explorer.stopHearingTest() }
        }
    }

    private var title: String {
        switch explorer.hearingTestStage {
        case .idle, .failed: "Your hearing test"
        case .scanning: "Checking the fit"
        case .starting: "Starting the tones"
        case .testing(let step): step < 6 ? "Left earbud" : "Right earbud"
        case .finishing: "Creating your profile"
        case .completed: "Profile created"
        }
    }

    private var detail: String {
        switch explorer.hearingTestStage {
        case .idle, .failed: "Wear both earbuds, pause music and find a quiet place. You’ll set the softest tone you can hear at each step."
        case .scanning: "The earbuds are measuring the fit in each ear. Keep them in place."
        case .starting: "Waiting for the earbuds to confirm the listening test."
        case .testing(let step): "Tone \(step % 6 + 1) of 6. Move the slider, then continue when the tone is barely audible."
        case .finishing: "The earbuds are building your sound profile."
        case .completed: explorer.hearingBusy ? "Applying the profile to your earbuds…" :
            (explorer.hearingError == nil ? "Your profile is saved on this iPhone and active on the earbuds." :
                "The profile could not be confirmed on the earbuds.")
        }
    }

    private var actionTitle: String {
        switch explorer.hearingTestStage {
        case .idle: explorer.accessoryCapabilities?.hearingScan == true ? "Start with ear scan" : "Start test"
        case .failed: explorer.accessoryCapabilities?.hearingScan == true ? "Retry ear scan" : "Try again"
        case .testing(let step): !explorer.hearingToneConfirmed ? "Waiting for tone" :
            (step == 11 ? "Save profile" : "Next tone")
        case .completed: "Done"
        case .scanning, .starting, .finishing: "Please wait"
        }
    }

    private func primaryAction() {
        switch explorer.hearingTestStage {
        case .idle, .failed: explorer.startHearingTest()
        case .testing: explorer.advanceHearingTest()
        case .completed: dismiss()
        case .scanning, .starting, .finishing: break
        }
    }

    private var toneIsPending: Bool {
        if case .testing = explorer.hearingTestStage { return !explorer.hearingToneConfirmed }
        return false
    }
}
