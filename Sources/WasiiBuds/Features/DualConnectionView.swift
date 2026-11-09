import BudsDomain
import SwiftUI

struct DualConnectionView: View {
    @ObservedObject var explorer: BluetoothExplorer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    Text("CONNECTION / 02")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.5).foregroundStyle(Studio.accent)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Studio.primary)
                }
                Text("Two devices.\nOne pair of buds.")
                    .font(.system(size: 35, weight: .bold, design: .rounded))
                    .tracking(-1.2).foregroundStyle(Studio.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Keep your earbuds connected to two devices and switch audio between them.")
                    .font(.subheadline).foregroundStyle(Studio.secondary)

                VStack(alignment: .leading, spacing: 9) {
                    Toggle(isOn: Binding(
                        get: { explorer.featureStates[.dualConnection] ?? false },
                        set: { explorer.setFeature(.dualConnection, enabled: $0) }
                    )) {
                        Text("Dual connection")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Studio.primary)
                    }
                    .tint(Studio.accent)
                    .disabled(!explorer.controlReady || explorer.pendingFeature != nil ||
                              explorer.featureStates[.dualConnection] == nil)
                    Text(explorer.featureStates[.dualConnection] == true ? "On" : "Off")
                        .font(.footnote).foregroundStyle(Studio.secondary)
                    if let error = explorer.featureError {
                        Text(error).font(.footnote).foregroundStyle(Studio.accent)
                    }
                }
                .padding(19)
                .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))

                HStack(alignment: .firstTextBaseline) {
                    Text("Paired devices")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Studio.primary)
                    Spacer()
                    Button { explorer.refreshPairedDevices() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Studio.primary)
                            .frame(width: 42, height: 42)
                            .background(Studio.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!explorer.controlReady)
                    .accessibilityLabel("Refresh paired devices")
                }
                if explorer.pairedAudioDevices.isEmpty {
                    Text(explorer.pairedDevicesLoaded ? "No paired devices were reported." :
                         "Reading the earbuds’ device list…")
                        .font(.subheadline).foregroundStyle(Studio.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 17))
                } else {
                    VStack(spacing: 0) {
                        ForEach(explorer.pairedAudioDevices) { device in
                            HStack(spacing: 12) {
                                Image(systemName: device.thisPhone ? "iphone" : "laptopcomputer")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Studio.accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Studio.primary)
                                    Text(device.thisPhone ? "This iPhone" :
                                         device.connected ? "Connected" : "Not connected")
                                        .font(.footnote).foregroundStyle(Studio.secondary)
                                }
                                Spacer()
                                Circle()
                                    .fill(device.connected ? Studio.accent : Studio.line)
                                    .frame(width: 8, height: 8)
                            }
                            .padding(16)
                            if device.id != explorer.pairedAudioDevices.last?.id {
                                Studio.line.frame(height: 1).padding(.leading, 55)
                            }
                        }
                    }
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 17))
                }
                Text("Pair the second phone or computer in its own Bluetooth settings. This app can turn dual connection on or off and show the earbuds’ paired list; pairing and audio routing stay with the devices.")
                    .font(.footnote).foregroundStyle(Studio.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 45)
        }
        .scrollIndicators(.hidden)
        .background(Studio.background.ignoresSafeArea())
        .modifier(StatusToastPresenter(explorer: explorer))
        .onAppear { explorer.prepareDualConnection() }
    }
}
