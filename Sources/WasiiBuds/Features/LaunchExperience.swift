import BudsDomain
import SwiftUI

struct LaunchExperience: View {
    @ObservedObject var explorer: BluetoothExplorer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingSplash = true
    @State private var revealed = false
    @State private var waveformActive = false
    @State private var requestedWidgetMode: ANCMode?

    var body: some View {
        ZStack(alignment: .top) {
            if showingSplash {
                splash.transition(.opacity)
            } else {
                HomeView(explorer: explorer)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Studio.background.ignoresSafeArea())
        .onOpenURL { url in
            guard url.scheme == "wasiibuds", url.host == "anc",
                  let modeName = url.pathComponents.dropFirst().first else { return }
            let mode: ANCMode? = switch modeName {
            case "off": .off
            case "deep": .deep
            case "transparency": .transparency
            default: nil
            }
            guard let mode else { return }
            requestedWidgetMode = mode
            applyWidgetModeIfReady()
        }
        .onChange(of: explorer.controlReady) { _, ready in
            if ready { applyWidgetModeIfReady() }
        }
        .task {
            guard showingSplash else { return }
            if reduceMotion {
                revealed = true
                try? await Task.sleep(for: .milliseconds(400))
            } else {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.78, dampingFraction: 0.76)) {
                    revealed = true
                }
                waveformActive = true
                try? await Task.sleep(for: .milliseconds(1600))
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) {
                showingSplash = false
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            explorer.start()
        }
    }

    private func applyWidgetModeIfReady() {
        guard explorer.controlReady, let mode = requestedWidgetMode else { return }
        requestedWidgetMode = nil
        explorer.setANC(mode)
    }

    private var splash: some View {
        VStack(spacing: 0) {
            Spacer()
            BudsArtwork()
                .frame(width: 390, height: 340)
                .scaleEffect(revealed ? 1 : 0.78)
                .rotationEffect(.degrees(revealed ? 0 : -7))
                .offset(y: revealed ? 0 : 34)
                .opacity(revealed ? 1 : 0)
                .shadow(color: Studio.primary.opacity(0.14),
                        radius: revealed ? 22 : 4, y: revealed ? 17 : 0)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("WASIIBUDS")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(Studio.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text("NORD BUDS 3 PRO")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(Studio.accent)
            }
            .padding(.top, 12)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 18)

            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<7) { index in
                    Capsule()
                        .fill(index == 3 ? Studio.accent : Studio.primary)
                        .frame(width: index == 3 ? 18 : 5,
                               height: waveformActive ? CGFloat(5 + (index % 3) * 5) : 5)
                        .animation(
                            reduceMotion ? nil :
                                .easeInOut(duration: 0.52)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.065),
                            value: waveformActive
                        )
                }
            }
            .frame(height: 20)
            .padding(.top, 28)
            .opacity(revealed ? 1 : 0)
            Spacer()
            Text("WasiiLabs")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(Studio.secondary)
                .opacity(revealed ? 1 : 0)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .background(Studio.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("WasiiBuds is opening")
    }
}
