import BudsDomain
import Foundation

extension BluetoothExplorer {
    func receive(_ frame: WasiiBudsFrame) {
        // The gesture reply is small and its final entries can contain call bindings.
        // Keep the complete reply visible in Connection diagnostics.
        let previewBytes = frame.command == 0x8108 ? frame.payload[...] : frame.payload.prefix(16)
        let preview = previewBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        log(String(format: "Received %04X (seq %02X): %@", frame.command, frame.sequence, preview))
        if let answer = NordBudsProtocol.answerTimeRequest(
            frame, unixSeconds: UInt32(Date().timeIntervalSince1970)) {
            send(answer)
        }
        receiveCapabilities(frame)
        receiveAccessories(frame)
        receiveHearingProfile(frame)
        receiveEqualizer(frame)
        receiveFeatures(frame)
        receiveLiveStatus(frame)
    }

    private func receiveCapabilities(_ frame: WasiiBudsFrame) {
        if let capabilities = NordEqualizer.capabilities(from: frame) {
            eqCapabilities = capabilities
            log("EQ capability: built-in \(capabilities.builtIn), custom \(capabilities.custom), bass \(capabilities.bassWave)")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.controlReady else { return }
                self.refreshEQ()
            }
        }
        if let capabilities = NordAccessoryControls.capabilities(from: frame) {
            accessoryCapabilities = capabilities
            subscribeOfferedEventsIfReady()
            if capabilities.firmware { refreshFirmware() }
            if capabilities.gestures || capabilities.personalANC {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled else { return }
                    self?.refreshAccessorySettings()
                }
            }
        }
        if let events = NordAccessoryControls.offeredEvents(from: frame) {
            offeredEvents = events
            subscribeOfferedEventsIfReady()
        }
    }

    private func receiveLiveStatus(_ frame: WasiiBudsFrame) {
        if frame.command == 0x8404, pendingMode != nil,
           frame.sequence == pendingWriteSequence,
           let status = frame.payload.first, status != 0 {
            pendingMode = nil
            pendingReadSequence = nil
            pendingWriteSequence = nil
            hasSentPendingWrite = false
            operationTask?.cancel()
            detail = status == 0x0E ? "Put a bud in your ear and try again" : "Earbuds refused this change (code \(status))"
            showNotice("Noise control change failed", kind: .error)
            return
        }
        if let update = NordBudsProtocol.battery(from: frame) {
            if let left = update.left {
                battery.left = left
                battery.leftCharging = update.leftCharging
            }
            if let right = update.right {
                battery.right = right
                battery.rightCharging = update.rightCharging
            }
            if let caseLevel = update.caseLevel {
                battery.caseLevel = caseLevel
                battery.caseCharging = update.caseCharging
            }
            if pendingMode == nil { detail = "Battery report received" }
            publishWidgetSnapshot()
        }
        if let report = NordWear.report(from: frame) {
            if let left = report.left { leftPresence = left }
            if let right = report.right { rightPresence = right }
        }
        if let mode = NordBudsProtocol.anc(from: frame) {
            ancMode = mode
            publishWidgetSnapshot()
            if pendingMode == nil { detail = "Noise mode report received" }
            if let desired = pendingMode {
                let isMatchingRead = frame.command == 0x810C && frame.sequence == pendingReadSequence
                let isPush = frame.command == 0x0204 && hasSentPendingWrite
                if isMatchingRead || isPush {
                    pendingMode = nil
                    pendingReadSequence = nil
                    pendingWriteSequence = nil
                    hasSentPendingWrite = false
                    operationTask?.cancel()
                    detail = desired == mode ? "Noise control updated" : "Earbuds reported \(mode.rawValue) instead"
                    showNotice(desired == mode ? "Noise control updated" : "Noise mode differs from request",
                               kind: desired == mode ? .success : .error)
                }
            }
        }
    }
}
