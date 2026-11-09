import BudsDomain
import Foundation

extension BluetoothExplorer {
    func selectEQ(_ preset: NordEQPreset) {
        guard controlReady, eqCapabilities?.builtIn == true, eqCurrent != preset.id else { return }
        beginEQWrite(NordEqualizer.selectBuiltIn(preset, sequence: sequence()), action: .builtIn(preset.id))
    }

    func createCustomEQ() {
        guard controlReady, eqCapabilities?.custom == true, eqCustomLoaded, eqCustom.count < 3 else { return }
        let used = Set(eqCustom.map(\.name))
        let name = (1...9).map { "Custom \($0)" }.first { !used.contains($0) } ?? "Custom"
        let preset = CustomEQPreset.new(name: name)
        guard let packet = NordEqualizer.custom(.create, preset: preset, sequence: sequence()) else { return }
        beginEQWrite(packet, action: .create(name))
    }

    func saveCustomEQ(_ preset: CustomEQPreset) {
        guard controlReady, eqCapabilities?.custom == true,
              eqCustom.contains(where: { $0.id == preset.id }) else { return }
        guard let packet = NordEqualizer.custom(.save, preset: preset, sequence: sequence()) else {
            eqError = "Use a name of at most 20 bytes and gains from −6 to +6 dB."
            return
        }
        beginEQWrite(packet, action: .save(preset))
    }

    func deleteCustomEQ(_ preset: CustomEQPreset) {
        guard controlReady, eqCapabilities?.custom == true,
              eqCustom.contains(where: { $0.id == preset.id }) else { return }
        guard eqCurrent != preset.id else {
            eqError = "Select another preset before deleting this one."
            return
        }
        guard let packet = NordEqualizer.custom(.delete, preset: preset, sequence: sequence()) else { return }
        beginEQWrite(packet, action: .delete(name: preset.name, previousCount: eqCustom.count))
    }

    func setBassWaveLevel(_ level: Int) {
        guard controlReady, eqCapabilities?.bassWave == true, bassWaveLevel != level,
              let packet = NordEqualizer.bassLevel(level, sequence: sequence()) else { return }
        beginEQWrite(packet, action: .bassLevel(level))
    }

    func beginEQWrite(_ packet: WasiiBudsFrame, action: EQAction) {
        guard controlReady, eqOperation == nil, featureOperation == nil, pendingMode == nil else { return }
        eqOperation = EQOperation(action: action, writeCommand: packet.command,
                                writeSequence: packet.sequence)
        eqBusy = true
        eqError = nil
        showNotice("Updating sound…", kind: .progress)
        send(packet)
        armEQTimeout()
    }

    func armEQTimeout() {
        eqTimeout?.cancel()
        eqTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, let operation = self.eqOperation else { return }
            if case .bassLevel = operation.action, operation.readSequence != nil {
                self.finishEQ(error: "The earbuds accepted the bass level but did not report it back. Refresh to verify.")
                return
            }
            self.finishEQ(error: "The earbuds did not confirm the equalizer change. Refresh and try again.")
        }
    }

    func finishEQ(error: String? = nil) {
        eqError = error
        if let error { log(error); detail = error }
        else { detail = "Equalizer confirmed by earbuds" }
        showNotice(error == nil ? "Sound updated" : "Sound change failed",
                   kind: error == nil ? .success : .error)
        eqOperation = nil
        eqBusy = false
        eqTimeout?.cancel(); eqTimeout = nil
    }

    func setFeature(_ feature: BudFeature, enabled: Bool) {
        guard controlReady, featureOperation == nil, pendingMode == nil, eqOperation == nil,
              featureStates[feature] != nil,
              featureStates[feature] != enabled else { return }
        if feature == .personalANC && enabled && personalANCStored != true {
            featureError = "No personalized ANC result is stored on the earbuds. Complete the fit setup in HeyMelody first."
            showNotice("No saved ANC profile", kind: .error)
            return
        }
        let writes = NordBudsProtocol.featureWrites(for: feature, enabled: enabled,
                                                    current: featureStates)
        featureOperation = FeatureOperation(key: feature, requested: enabled, writes: writes)
        pendingFeature = feature
        featureError = nil
        showNotice("Updating \(feature.title)…", kind: .progress)
        sendNextFeatureWrite()
    }

    func sendNextFeatureWrite() {
        guard var operation = featureOperation, operation.index < operation.writes.count,
              controlReady else { return }
        let write = operation.writes[operation.index]
        let seq = sequence()
        operation.writeSequence = seq
        operation.readSequence = nil
        featureOperation = operation
        detail = "Applying \(operation.key.title)…"
        if write.feature == .personalANC && write.enabled {
            send(NordAccessoryControls.applyPersonalANC(sequence: seq))
        } else {
            send(NordBudsProtocol.setFeature(write.feature, enabled: write.enabled, sequence: seq))
        }
        armFeatureTimeout(seconds: 3)
    }

    func armFeatureTimeout(seconds: Double) {
        featureTimeout?.cancel()
        featureTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, let operation = self.featureOperation else { return }
            self.finishFeatureOperation(error: "No confirmation for \(operation.key.title). Refresh and try again.")
        }
    }

    func finishFeatureOperation(error: String? = nil) {
        if error == nil, let operation = featureOperation,
           operation.key == .dualConnection, controlReady {
            send(NordDualConnection.followup(enabled: operation.requested,
                                             sequence: sequence()))
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.controlReady else { return }
                self.refreshPairedDevices()
            }
        }
        if let error { log(error); detail = error }
        else { detail = "Setting confirmed by earbuds" }
        showNotice(error == nil ? "\(featureOperation?.key.title ?? "Setting") updated" :
                   "Setting change failed", kind: error == nil ? .success : .error)
        featureError = error
        featureOperation = nil
        pendingFeature = nil
        featureTimeout?.cancel()
        featureTimeout = nil
    }

    func setANC(_ mode: ANCMode) {
        guard controlReady, pendingMode == nil, featureOperation == nil, eqOperation == nil,
              let packet = NordBudsProtocol.setANC(mode, sequence: sequence()) else { return }
        pendingMode = mode
        showNotice("Updating noise control…", kind: .progress)
        pendingWriteSequence = packet.sequence
        hasSentPendingWrite = true
        detail = "Applying \(mode.rawValue)…"
        send(packet)
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, self.pendingMode == mode, self.controlReady else { return }
            let readSequence = self.sequence()
            self.pendingReadSequence = readSequence
            self.send(NordBudsProtocol.ancQuery(sequence: readSequence))
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self.pendingMode == mode else { return }
            self.pendingMode = nil
            self.pendingReadSequence = nil
            self.pendingWriteSequence = nil
            self.hasSentPendingWrite = false
            self.detail = "No confirmed response for \(mode.rawValue). Try Refresh."
            self.showNotice("Noise control not confirmed", kind: .error)
            self.log("ANC confirmation timed out")
        }
    }

    func receiveEqualizer(_ frame: WasiiBudsFrame) {
        if var operation = eqOperation,
           frame.command == (operation.writeCommand | 0x8000),
           frame.sequence == operation.writeSequence {
            let status = frame.payload.first ?? 0xFF
            if status != 0 {
                finishEQ(error: "Earbuds refused the equalizer change (code \(status)).")
                refreshEQ()
            } else {
                if case .bassLevel(let accepted) = operation.action {
                    bassWaveLevel = accepted
                    bassLevelReported = false
                }
                if case .create = operation.action { operation.createdID = frame.payload.dropFirst().first }
                let readSequence = sequence()
                operation.readSequence = readSequence
                eqOperation = operation
                armEQTimeout()
                Task { [weak self] in
                    // WasiiBuds waits for the preset to settle before reading it back.
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self, self.controlReady,
                          self.eqOperation?.readSequence == readSequence else { return }
                    switch operation.action {
                    case .builtIn:
                        self.send(NordEqualizer.queryCurrent(sequence: readSequence))
                    case .create, .save, .delete:
                        self.send(NordEqualizer.queryCustom(sequence: readSequence))
                    case .bassLevel:
                        self.send(NordEqualizer.bassLevelQuery(sequence: readSequence))
                    }
                }
            }
        }
        if let current = NordEqualizer.current(from: frame) {
            eqCurrent = current
            if let operation = eqOperation, frame.command == 0x810F,
               frame.sequence == operation.readSequence,
               case .builtIn(let wanted) = operation.action {
                finishEQ(error: current == wanted ? nil : "Earbuds kept the previous equalizer preset.")
            }
        }
        if let list = NordEqualizer.customList(from: frame) {
            eqCustom = list
            eqCustomLoaded = true
            if eqCurrent == nil, let selected = list.first(where: { $0.selected }) {
                eqCurrent = selected.id
            }
            if let operation = eqOperation, frame.sequence == operation.readSequence {
                switch operation.action {
                case .create(let name):
                    let found = list.contains { $0.id == operation.createdID || $0.name == name }
                    finishEQ(error: found ? nil : "The new preset was not returned by the earbuds.")
                case .save(let wanted):
                    let found = list.contains { $0.id == wanted.id && $0.name == wanted.name &&
                        $0.gains == wanted.gains && $0.selected }
                    if found { eqCurrent = wanted.id }
                    finishEQ(error: found ? nil : "The earbuds did not confirm this custom preset.")
                case .delete(_, let previousCount):
                    finishEQ(error: list.count < previousCount ? nil : "The earbuds kept this custom preset.")
                default: break
                }
            }
        }
        if let level = NordEqualizer.bassLevel(from: frame) {
            bassWaveLevel = level
            bassLevelReported = true
            if let operation = eqOperation, frame.sequence == operation.readSequence,
               case .bassLevel(let wanted) = operation.action {
                finishEQ(error: level == wanted ? nil : "Earbuds reported a different bass level.")
            }
        }
    }

    func receiveFeatures(_ frame: WasiiBudsFrame) {
        if (frame.command == 0x8403 || frame.command == 0x8412), var operation = featureOperation,
           (frame.command == 0x8412) == (operation.key == .personalANC && operation.requested),
           frame.sequence == operation.writeSequence {
            let status = frame.payload.first ?? 0xFF
            if status != 0 {
                finishFeatureOperation(error: status == 1
                    ? "\(operation.key.title) is unavailable on these earbuds."
                    : "Earbuds refused \(operation.key.title) right now (code \(status)).")
                refresh()
            } else {
                operation.index += 1
                operation.writeSequence = nil
                featureOperation = operation
                if operation.index < operation.writes.count {
                    sendNextFeatureWrite()
                } else if operation.writes.contains(where: { $0.feature == .highQuality }) {
                    operation.waitingForReconnect = true
                    featureOperation = operation
                    armFeatureTimeout(seconds: 15)
                    // Some firmware stays connected. Ask again if no link restart arrives.
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(5))
                        guard let self, self.controlReady, self.featureOperation?.waitingForReconnect == true else { return }
                        let seq = self.sequence()
                        self.featureOperation?.readSequence = seq
                        self.send(NordBudsProtocol.featureQuery(sequence: seq))
                    }
                } else if operation.key == .lowLatency {
                    if operation.sawConfirmingPush {
                        finishFeatureOperation(error: featureStates[.lowLatency] == operation.requested ? nil
                            : "Earbuds did not change Low latency mode.")
                    } else { armFeatureTimeout(seconds: 3) }
                } else {
                    let seq = sequence()
                    featureOperation?.readSequence = seq
                    if operation.key == .personalANC && operation.requested {
                        Task { [weak self] in
                            try? await Task.sleep(for: .milliseconds(900))
                            guard !Task.isCancelled, let self,
                                  self.featureOperation?.readSequence == seq else { return }
                            self.send(NordBudsProtocol.featureQuery(sequence: seq))
                        }
                    } else {
                        send(NordBudsProtocol.featureQuery(sequence: seq))
                    }
                    armFeatureTimeout(seconds: 3)
                }
            }
        }
        if let states = NordBudsProtocol.features(from: frame) {
            if frame.command == 0x810D { featureStates = states }
            else { featureStates.merge(states) { _, new in new } }
            if frame.command == 0x810D, states[.hearingProfile] != nil,
               !hearingLoaded { refreshHearingProfile() }
            if frame.command == 0x810D, states[.dualConnection] != nil, !didAskDevices {
                refreshPairedDevices()
            }
            if let operation = featureOperation {
                let matchingRead = frame.command == 0x810D &&
                    (frame.sequence == operation.readSequence || operation.didReconnect)
                let matchingPush = frame.command == 0x0503 && operation.key == .lowLatency &&
                    states[operation.key] != nil
                if matchingRead, let reported = states[operation.key] {
                    finishFeatureOperation(error: reported == operation.requested ? nil
                        : "Earbuds did not change \(operation.key.title).")
                } else if matchingPush {
                    if operation.writeSequence == nil {
                        finishFeatureOperation(error: states[operation.key] == operation.requested ? nil
                            : "Earbuds did not change \(operation.key.title).")
                    } else {
                        featureOperation?.sawConfirmingPush = true
                    }
                }
            }
        }
        if let devices = NordDualConnection.devices(from: frame) {
            pairedAudioDevices = devices
            pairedDevicesLoaded = true
        }
        if let gameMode = NordBudsProtocol.gameMode(from: frame) {
            featureStates[.lowLatency] = gameMode
            if let operation = featureOperation, operation.key == .lowLatency {
                if operation.writeSequence == nil {
                    finishFeatureOperation(error: gameMode == operation.requested ? nil
                        : "Earbuds did not change Low latency mode.")
                } else { featureOperation?.sawConfirmingPush = true }
            }
        }
    }
}
