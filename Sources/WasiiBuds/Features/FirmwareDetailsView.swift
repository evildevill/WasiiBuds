import BudsDomain
import SwiftUI

struct FirmwareDetailsView: View {
    @ObservedObject var explorer: BluetoothExplorer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 29) {
                header
                productCard
                firmwareSection
                identitySection
                Text("Versions come directly from your earbuds. Firmware updates are managed in HeyMelody.")
                    .font(.footnote).foregroundStyle(Studio.secondary)
            }
            .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(Studio.background.ignoresSafeArea())
        .onAppear { explorer.refreshFirmware() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: explorer.firmwareDetails)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("WASII / 064414")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.4).foregroundStyle(Studio.accent)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Studio.primary)
                        .frame(width: 40, height: 40)
                        .background(Studio.surface, in: Circle())
                }
                .accessibilityLabel("Close device details")
            }
            Text("Device\ndetails")
                .font(.system(size: 43, weight: .bold, design: .rounded))
                .tracking(-1.8).foregroundStyle(Studio.primary)
            Text("The hardware and software behind your sound.")
                .font(.subheadline).foregroundStyle(Studio.secondary)
        }
    }

    private var productCard: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(explorer.controlReady ? Studio.accent : Studio.line)
                    .frame(width: 7, height: 7)
                Text(explorer.controlReady ? "CONNECTED" : "OFFLINE")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1).foregroundStyle(Studio.primary)
                Spacer()
                Text("NORD / 03")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1).foregroundStyle(Studio.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 20)
            BudsArtwork()
                .frame(width: 190, height: 185)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            HStack(alignment: .firstTextBaseline) {
                Text("Nord Buds 3 Pro")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .tracking(-0.7).foregroundStyle(Studio.primary)
                Spacer()
                Text("ONEPLUS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8).foregroundStyle(Studio.secondary)
            }
            .padding(.horizontal, 20).padding(.bottom, 21)
        }
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 25))
    }

    private var firmwareSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Firmware")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.8).foregroundStyle(Studio.primary)
                Spacer()
                Button { explorer.refreshFirmware() } label: {
                    Group {
                        if explorer.firmwareLoading { ProgressView().tint(Studio.accent) }
                        else { Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold)) }
                    }
                    .foregroundStyle(Studio.primary)
                    .frame(width: 42, height: 42)
                    .background(Studio.surface, in: Circle())
                }
                .disabled(!explorer.controlReady || explorer.accessoryCapabilities?.firmware != true || explorer.firmwareLoading)
                .accessibilityLabel("Refresh firmware versions")
            }
            HStack(spacing: 11) {
                versionCard("LEFT EARBUD", value: explorer.firmwareDetails?.left, side: 1)
                versionCard("RIGHT EARBUD", value: explorer.firmwareDetails?.right, side: 2)
            }
            HStack(spacing: 15) {
                Image(systemName: "battery.100")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Studio.accent).frame(width: 39)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHARGING CASE")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1).foregroundStyle(Studio.secondary)
                    Text(explorer.firmwareDetails?.caseVersion ?? "Not reported")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Studio.primary).textSelection(.enabled)
                }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 19))
            Text(firmwareStatus).font(.footnote).foregroundStyle(Studio.secondary)
        }
    }

    private func versionCard(_ title: String, value: String?, side: UInt8) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SingleBudArtwork(side: side).frame(width: 38, height: 48)
            Spacer(minLength: 4)
            Text(value ?? "—")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.65).lineLimit(1)
                .foregroundStyle(Studio.primary).textSelection(.enabled)
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(0.8).foregroundStyle(Studio.secondary)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 19))
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Identity")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .tracking(-0.8).foregroundStyle(Studio.primary)
            VStack(spacing: 0) {
                identityRow("Model code", value: "064414")
                Studio.line.frame(height: 1)
                identityRow("Device name", value: explorer.deviceName ?? "OnePlus Nord Buds 3 Pro")
                Studio.line.frame(height: 1)
                identityRow("Control link", value: explorer.controlReady ? "Connected" : "Disconnected")
            }
            .padding(.horizontal, 17)
            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 19))
        }
    }

    private func identityRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).foregroundStyle(Studio.secondary)
            Spacer(minLength: 10)
            Text(value).multilineTextAlignment(.trailing)
                .foregroundStyle(Studio.primary).textSelection(.enabled)
        }
        .font(.system(size: 14)).padding(.vertical, 15)
    }

    private var firmwareStatus: String {
        if !explorer.controlReady { return "Connect the earbuds to read their versions." }
        if explorer.accessoryCapabilities?.firmware != true { return "This connection does not offer a firmware reply." }
        if explorer.firmwareLoading { return "Reading versions from the earbuds…" }
        if explorer.firmwareDetails == nil { return "The earbuds have not returned a firmware version." }
        return "Only versions reported by the earbuds appear here."
    }
}
