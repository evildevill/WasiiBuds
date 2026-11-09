import BudsDomain
import SwiftUI

enum Studio {
    static let background = Color.white
    static let surface = Color(red: 0.965, green: 0.965, blue: 0.955)
    static let line = Color(red: 0.86, green: 0.87, blue: 0.87)
    static let primary = Color(red: 0.055, green: 0.065, blue: 0.075)
    static let secondary = Color(red: 0.37, green: 0.39, blue: 0.41)
    static let accent = Color(red: 0.78, green: 0.22, blue: 0.08)
}

struct HomeView: View {
    @ObservedObject var explorer: BluetoothExplorer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = 0
    @State private var entered = false
    @State private var refreshFeedback = false
    @State private var showQualityNotice = false
    @State private var showEqualizer = false
    @State private var showDualConnection = false
    @Namespace private var dockNamespace

    var body: some View {
        VStack(spacing: 0) {
            if tab == 0 {
                myBudsHeader
                overview
            } else if tab == 1 {
                connectionHeader
                diagnostics
            } else {
                EarbudSettingsView(explorer: explorer)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            navigationDock
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Studio.background.ignoresSafeArea())
        .modifier(StatusToastPresenter(explorer: explorer))
        .sensoryFeedback(.selection, trigger: tab)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) { entered = true }
        }
        .alert("About high-quality audio", isPresented: $showQualityNotice) {
            Button("Cancel", role: .cancel) {}
            Button("Turn on") { explorer.setFeature(.highQuality, enabled: true) }
        } message: {
            Text("These buds offer AAC and SBC only. This switch may restart their control connection, and WasiiBuds reports no audible improvement on this model. iPhone chooses the Bluetooth codec.")
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerView(explorer: explorer)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDualConnection) {
            DualConnectionView(explorer: explorer)
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var navigationDock: some View {
        let content = HStack(spacing: 5) {
            tabButton("My buds", symbol: "earbuds", index: 0)
            tabButton("Connection", symbol: "antenna.radiowaves.left.and.right", index: 1)
            tabButton("Settings", symbol: "gearshape", index: 2)
        }
        .padding(6)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
                .shadow(color: Studio.primary.opacity(0.12), radius: 18, y: 8)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Studio.line))
                .shadow(color: Studio.primary.opacity(0.12), radius: 18, y: 8)
        }
    }

    private func tabButton(_ label: String, symbol: String, index: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.78)) {
                tab = index
            }
        } label: {
            ZStack {
                if tab == index {
                    Capsule().fill(Studio.primary)
                        .matchedGeometryEffect(id: "selection", in: dockNamespace)
                }
                HStack(spacing: 9) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolEffect(.bounce, value: tab == index)
                    Text(label).font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(tab == index ? Studio.background : Studio.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == index ? .isSelected : [])
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard
                batteryCard
                    .opacity(entered ? 1 : 0)
                    .offset(y: reduceMotion || entered ? 0 : 16)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.08), value: entered)
                noiseCard
                    .opacity(entered ? 1 : 0)
                    .offset(y: reduceMotion || entered ? 0 : 16)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.16), value: entered)
                soundSettings
                    .opacity(entered ? 1 : 0)
                    .offset(y: reduceMotion || entered ? 0 : 16)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.24), value: entered)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await MainActor.run { triggerRefresh() }
            try? await Task.sleep(for: .milliseconds(800))
        }
        .simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.08)
                .onEnded { value in
                    if value.magnification < 0.78 { triggerRefresh() }
                }
        )
    }

    private func triggerRefresh() {
        guard explorer.controlReady, !refreshFeedback else { return }
        refreshFeedback = true
        explorer.refresh()
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            refreshFeedback = false
        }
    }

    private var myBudsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Rectangle().fill(Studio.accent).frame(width: 9, height: 9)
                    Text("WASIIBUDS").font(.system(size: 11, weight: .heavy))
                        .tracking(2).foregroundStyle(Studio.primary)
                }
                Text("Nord Buds 3 Pro")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-1.3).foregroundStyle(Studio.primary)
                    .lineLimit(1).minimumScaleFactor(0.78)
            }
            Spacer()
            Button { triggerRefresh() } label: {
                Group {
                    if refreshFeedback {
                        ProgressView().tint(Studio.primary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(Studio.primary)
                .frame(width: 42, height: 42)
                .background(Studio.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!explorer.controlReady)
            .opacity(explorer.controlReady ? 1 : 0.5)
            .accessibilityLabel("Refresh earbud status")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Studio.background)
    }

    private var connectionHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CONNECTION").font(.system(size: 12, weight: .bold))
                .tracking(2).foregroundStyle(Studio.accent)
            Text("Device details")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(Studio.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Studio.background)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Studio.surface
            .frame(height: 220)
            .overlay {
                BudsArtwork()
                    .frame(width: 300, height: 300)
                    .offset(y: 8)
                    .scaleEffect(entered ? 1 : 0.88)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(explorer.controlReady ? Studio.accent : Studio.secondary)
                        .frame(width: 7, height: 7)
                    Text(explorer.controlReady ? "CONNECTED" : connectionHeading.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Studio.primary)
                .padding(.horizontal, 11)
                .frame(height: 29)
                .background(Studio.background, in: Capsule())
                .padding(16)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Text("NORD / 03")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    Spacer()
                    Text("064414").font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(Studio.primary)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 23))
            if !explorer.controlReady {
                Text(explorer.detail).font(.footnote).foregroundStyle(Studio.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { explorer.startScan() } label: {
                    HStack {
                        Text("Find my buds")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Studio.background)
                    .padding(.horizontal, 16).frame(height: 47)
                    .background(Studio.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(entered ? 1 : 0)
        .offset(y: reduceMotion || entered ? 0 : 18)
    }

    private var connectionHeading: String {
        switch explorer.phase {
        case .scanning: "Looking for your buds"
        case .connecting, .inspecting: "Connecting to controls"
        case .permissionDenied: "Bluetooth permission needed"
        case .bluetoothOff: "Bluetooth is off"
        case .connected: "Device found"
        default: "Ready to connect"
        }
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery").font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.6).foregroundStyle(Studio.primary)
                Spacer()
                Text("LIVE LEVELS").font(.system(size: 10, weight: .bold))
                    .tracking(1.4).foregroundStyle(Studio.secondary)
            }
            HStack(spacing: 0) {
                batteryPart("LEFT", value: explorer.battery.left,
                            charging: explorer.battery.leftCharging, symbol: "earbud.left",
                            presence: explorer.leftPresence, showsPresence: true)
                batteryPart("RIGHT", value: explorer.battery.right,
                            charging: explorer.battery.rightCharging, symbol: "earbud.right",
                            presence: explorer.rightPresence, showsPresence: true)
                batteryPart("CASE", value: explorer.battery.caseLevel,
                            charging: explorer.battery.caseCharging, symbol: "battery.100percent")
            }
            if explorer.battery.caseLevel == nil {
                Button { triggerRefresh() } label: {
                    Label("Open the case lid, then refresh to read its level",
                          systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Studio.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!explorer.controlReady)
            } else if explorer.battery.caseCharging {
                Label("Case is charging", systemImage: "bolt.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Studio.accent)
            }
        }
        .padding(.top, 8)
    }

    private func batteryPart(_ name: String, value: Int?, charging: Bool, symbol: String,
                             presence: EarPresence? = nil, showsPresence: Bool = false) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Studio.line, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(value ?? 0, 0), 100)) / 100)
                    .stroke(Studio.accent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: value)
                VStack(spacing: 2) {
                    Image(systemName: charging ? "bolt.fill" : symbol).font(.system(size: 15))
                        .foregroundStyle(charging ? Studio.accent : Studio.primary)
                    Text(value.map { "\($0)%" } ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Studio.primary)
            }
            .frame(width: 76, height: 76)
            Text(name).font(.system(size: 10, weight: .bold)).tracking(1.4)
                .foregroundStyle(Studio.secondary)
            Text(showsPresence ? (presence?.title ?? "Checking") : " ")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(presence == .inEar ? Studio.accent : Studio.secondary)
                .opacity(showsPresence ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var noiseCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text("Listening mode")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.6).foregroundStyle(Studio.primary)
                Spacer()
                if explorer.pendingMode != nil { ProgressView().tint(Studio.accent) }
            }
            Text(explorer.ancMode.map { "\($0.rawValue) is active" }
                 ?? "Choose how much of the world you hear")
                .font(.subheadline).foregroundStyle(Studio.secondary)
                .contentTransition(.opacity)
            HStack(spacing: 10) {
                modeButton(.off, symbol: "speaker.slash", prominent: true)
                modeButton(.transparency, symbol: "waveform", prominent: true)
            }
            HStack {
                Text("Noise cancelling")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Studio.secondary)
                Spacer()
            }
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach([ANCMode.light, .medium, .deep, .smart]) { mode in
                    modeButton(mode, symbol: "circle.grid.2x2", prominent: false)
                }
            }
            if !explorer.controlReady {
                Text("Connect the earbuds to change listening mode.")
                    .font(.footnote).foregroundStyle(Studio.secondary)
            }
        }
        .padding(18)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 21))
    }

    private func modeButton(_ mode: ANCMode, symbol: String, prominent: Bool) -> some View {
        let selected = explorer.ancMode == mode
        return Button { explorer.setANC(mode) } label: {
            HStack(spacing: 8) {
                if prominent { Image(systemName: symbol).font(.system(size: 15)) }
                Text(mode.rawValue).lineLimit(1).minimumScaleFactor(0.78)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
            }
            .font(.system(size: prominent ? 14 : 13, weight: .semibold))
            .foregroundStyle(selected ? Studio.background : Studio.primary)
            .padding(.horizontal, 13).frame(maxWidth: .infinity)
            .frame(height: prominent ? 54 : 45)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Studio.primary)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Studio.background)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!explorer.controlReady || explorer.pendingMode != nil)
        .opacity(explorer.controlReady ? 1 : 0.45)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected)
    }

    private var soundSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sound settings")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .tracking(-0.6).foregroundStyle(Studio.primary)
                .padding(.bottom, 12)
            featureRow(.lowLatency, symbol: "bolt", subtitle: "Keeps audio closer to video")
            Rectangle().fill(Studio.line).frame(height: 1)
            featureRow(.highQuality, symbol: "waveform.path", subtitle: "Switch may restart the earbuds")
            Rectangle().fill(Studio.line).frame(height: 1)
            featureRow(.spatial, symbol: "waveform.circle", subtitle: "Experimental on Nord Buds 3 Pro; effect may be silent")
            Rectangle().fill(Studio.line).frame(height: 1)
            Button { showEqualizer = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Studio.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Equalizer").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Studio.primary)
                        Text(equalizerSubtitle).font(.system(size: 11))
                            .foregroundStyle(Studio.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Studio.secondary)
                }
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .disabled(!explorer.controlReady || !equalizerAvailable)
            .opacity(explorer.controlReady && equalizerAvailable ? 1 : 0.55)
            Rectangle().fill(Studio.line).frame(height: 1)
            Button { showDualConnection = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Studio.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dual connection").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Studio.primary)
                        Text(explorer.featureStates[.dualConnection] == nil ?
                             "Waiting for device report" : "Connect to two devices")
                            .font(.system(size: 11)).foregroundStyle(Studio.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Studio.secondary)
                }
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .disabled(!explorer.controlReady || explorer.featureStates[.dualConnection] == nil)
            .opacity(explorer.controlReady && explorer.featureStates[.dualConnection] != nil ? 1 : 0.55)
            if let error = explorer.featureError {
                Text(error).font(.footnote).foregroundStyle(Studio.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .padding(18)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 21))
    }

    private var equalizerAvailable: Bool {
        explorer.eqCapabilities?.builtIn == true || explorer.eqCapabilities?.custom == true
    }

    private var equalizerSubtitle: String {
        guard explorer.controlReady else { return "Connect to open sound profiles" }
        guard let capability = explorer.eqCapabilities else { return "Checking device support" }
        guard capability.builtIn || capability.custom else { return "Unavailable on this firmware" }
        return "Presets and six-band custom sound"
    }

    private func featureRow(_ feature: BudFeature, symbol: String, subtitle: String) -> some View {
        let available = explorer.controlReady && explorer.featureStates[feature] != nil
        let busy = explorer.pendingFeature != nil
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Studio.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Studio.primary)
                Text(available ? subtitle : "Waiting for device report")
                    .font(.system(size: 11))
                    .foregroundStyle(Studio.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if explorer.pendingFeature == feature { ProgressView().tint(Studio.accent) }
            Toggle(feature.title, isOn: Binding(
                get: { explorer.featureStates[feature] ?? false },
                set: { enabled in
                    if feature == .highQuality && enabled { showQualityNotice = true }
                    else { explorer.setFeature(feature, enabled: enabled) }
                }
            ))
            .labelsHidden()
            .tint(Studio.accent)
            .disabled(!available || busy)
            .accessibilityHint(subtitle)
        }
        .padding(.vertical, 15)
        .opacity(available ? 1 : 0.55)
    }

    private var diagnostics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("STATUS", detail: explorer.phase.message)
                    Text(explorer.detail).font(.subheadline).foregroundStyle(Studio.secondary)
                    HStack(spacing: 10) {
                        actionButton("Scan again", symbol: "arrow.clockwise") { explorer.startScan() }
                        actionButton("Disconnect", symbol: "xmark") { explorer.disconnect() }
                    }
                }.studioCard()
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("GATT SERVICES", detail: "")
                    if explorer.discoveredServices.isEmpty {
                        Text("No services discovered yet").foregroundStyle(Studio.secondary)
                    } else {
                        ForEach(explorer.discoveredServices, id: \.self) { service in
                            Text(service).font(.caption.monospaced())
                                .foregroundStyle(Studio.primary).textSelection(.enabled)
                        }
                    }
                }.studioCard()
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("NEARBY DEVICES", detail: "\(explorer.devices.count) found")
                    if explorer.devices.isEmpty {
                        Text("Scan to find nearby devices").foregroundStyle(Studio.secondary)
                    }
                    ForEach(explorer.devices) { device in
                        Button { explorer.connect(to: device.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(Studio.accent).frame(width: 23)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Studio.primary)
                                    Text(String(device.id.uuidString.suffix(8)))
                                        .font(.caption.monospaced()).foregroundStyle(Studio.secondary)
                                }
                                Spacer(minLength: 0)
                                Text("\(device.rssi) dBm").font(.caption)
                                    .foregroundStyle(Studio.secondary)
                            }.padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        if device.id != explorer.devices.last?.id {
                            Rectangle().fill(Studio.line).frame(height: 1)
                        }
                    }
                }.studioCard()
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("RECENT ACTIVITY", detail: "")
                    if explorer.events.isEmpty { Text("No activity yet").foregroundStyle(Studio.secondary) }
                    ForEach(Array(explorer.events.enumerated()), id: \.offset) { _, event in
                        Text(event).font(.caption.monospaced()).foregroundStyle(Studio.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.studioCard()
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(1.7)
                .foregroundStyle(Studio.primary)
            Spacer(minLength: 0)
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(Studio.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold))
                .foregroundStyle(Studio.primary)
                .frame(maxWidth: .infinity).frame(height: 43)
                .background(Studio.surface, in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }
}

private extension View {
    func studioCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 22)
            .overlay(alignment: .top) { Studio.line.frame(height: 1) }
    }
}
