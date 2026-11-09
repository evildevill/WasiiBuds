import BudsDomain
import Foundation

extension BluetoothExplorer {
    func refreshHearingProfile() {
        guard controlReady else { return }
        send(NordHearingProfile.queryActive(sequence: sequence()))
        if accessoryCapabilities?.hearingScan == true {
            send(NordHearingProfile.queryScan(sequence: sequence()))
        }
    }

    func keepHearingRecord(_ record: HearingProfileRecord) {
        let existing = hearingRecords.first { $0.id == record.id }
        let merged = HearingProfileRecord(
            id: record.id, name: record.name, values: record.values,
            scan: record.scan.isEmpty ? (existing?.scan ?? []) : record.scan,
            descriptionID: record.descriptionID == 0 ? (existing?.descriptionID ?? 0) : record.descriptionID)
        hearingRecords = ([merged] + hearingRecords.filter { $0.id != record.id }).prefix(10).map { $0 }
        hearingProfileStore.save(hearingRecords)
    }

    func applyHearingProfile(_ record: HearingProfileRecord) {
        guard controlReady, !hearingBusy,
              hearingTestStage == .idle || hearingTestStage == .completed,
              !record.values.isEmpty else { return }
        var next = sequence()
        guard let frames = NordHearingProfile.apply(record, sequence: &next) else {
            hearingError = "This profile has data the earbuds cannot accept."
            showNotice("Profile unavailable", kind: .error)
            return
        }
        nextSequence = next
        hearingBusy = true
        hearingError = nil
        pendingHearingRecord = record
        hearingWriteSequences = Set(frames.map(\.sequence))
        showNotice("Applying hearing profile…", kind: .progress)
        frames.forEach(send)
        armHearingTimeout(seconds: 6, message: "The earbuds did not confirm this profile.")
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.controlReady, self.pendingHearingRecord?.id == record.id else { return }
            self.send(NordHearingProfile.queryActive(sequence: self.sequence()))
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.controlReady, self.pendingHearingRecord?.id == record.id else { return }
            self.send(NordHearingProfile.queryActive(sequence: self.sequence()))
        }
    }

    func deleteHearingProfile(_ record: HearingProfileRecord) {
        guard !hearingBusy, record.id != hearingActiveID else { return }
        hearingRecords.removeAll { $0.id == record.id }
        hearingProfileStore.save(hearingRecords)
    }

    func startHearingTest(skipEarScan: Bool = false) {
        guard controlReady, !hearingBusy,
              hearingTestStage == .idle || hearingTestStage == .completed ||
              hearingTestStage == .failed else { return }
        guard accessoryCapabilities?.hearingTest == true else {
            hearingTestStage = .failed
            hearingError = "These earbuds are not offering hearing-test tones to this iPhone."
            return
        }
        if leftPresence == .outOfEar || leftPresence == .inCase ||
            rightPresence == .outOfEar || rightPresence == .inCase {
            hearingError = "Put both earbuds in your ears before starting."
            return
        }
        hearingID = UInt32.random(in: 1...UInt32.max)
        hearingValues = [Int8](repeating: 0, count: 12)
        hearingScanData = []
        hearingLevelIndex = 9
        hearingToneConfirmed = false
        hearingError = nil
        send(NordAccessoryControls.subscribeOne(8, sequence: sequence()))
        if accessoryCapabilities?.hearingScan == true && !skipEarScan {
            send(NordAccessoryControls.subscribeOne(0x0E, sequence: sequence()))
            hearingTestStage = .scanning
            send(NordHearingProfile.scanCommand(true, id: hearingID, sequence: sequence()))
            let scanID = hearingID
            Task { [weak self] in
                for delay in [9, 4] {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self, self.controlReady,
                          self.hearingTestStage == .scanning, self.hearingID == scanID else { return }
                    self.send(NordHearingProfile.queryScan(sequence: self.sequence()))
                }
            }
            armHearingTimeout(seconds: 18, message: "The earbuds accepted the ear scan but did not return its result. You can retry or continue with tones only.")
        } else {
            beginHearingToneTest()
        }
    }

    func beginHearingToneTest() {
        hearingTimeout?.cancel(); hearingTimeout = nil
        let start = NordHearingProfile.testCommand(true, sequence: sequence())
        hearingStartSequence = start.sequence
        hearingTestStage = .starting
        hearingLevelIndex = 9
        send(start)
        armHearingTimeout(seconds: 4, message: "The earbuds did not confirm the hearing test start.")
    }

    func setHearingLevel(_ index: Int) {
        guard case .testing = hearingTestStage else { return }
        hearingLevelIndex = min(max(index, 0), NordHearingProfile.stops.count - 1)
        hearingToneConfirmed = false
        hearingToneSequence = nil
        hearingToneTimeout?.cancel(); hearingToneTimeout = nil
        hearingToneSendTask?.cancel(); hearingToneSendTask = nil
        hearingToneGeneration &+= 1
        hearingToneTask?.cancel()
        let remaining = max(0, 0.3 - Date().timeIntervalSince(lastHearingTone))
        hearingToneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.playHearingTone()
        }
    }

    func playHearingTone() {
        guard case .testing(let step) = hearingTestStage else { return }
        let stop = NordHearingProfile.toneStop(sequence: sequence())
        guard let tone = NordHearingProfile.tone(side: UInt8(step / 6 + 1),
                                                 frequency: UInt8(step % 6 + 1),
                                                 value: NordHearingProfile.stops[hearingLevelIndex],
                                                 sequence: sequence()) else { return }
        hearingToneSendTask?.cancel()
        hearingToneTimeout?.cancel()
        hearingToneSequence = nil
        hearingToneConfirmed = false
        hearingToneGeneration &+= 1
        let generation = hearingToneGeneration
        send(stop)
        hearingToneSendTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self,
                  self.hearingToneGeneration == generation,
                  self.hearingTestStage == .testing(step) else { return }
            self.lastHearingTone = Date()
            self.hearingToneSequence = tone.sequence
            self.send(tone)
            self.hearingToneTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self,
                      self.hearingToneSequence == tone.sequence,
                      self.hearingTestStage == .testing(step) else { return }
                self.failHearingTest("The earbuds did not confirm the hearing tone.")
            }
        }
    }

    func advanceHearingTest() {
        guard case .testing(let step) = hearingTestStage, hearingToneConfirmed else { return }
        hearingValues[step] = NordHearingProfile.snapped(NordHearingProfile.stops[hearingLevelIndex])
        hearingToneTask?.cancel(); hearingToneTask = nil
        if step < 11 {
            hearingTestStage = .testing(step + 1)
            hearingLevelIndex = 9
            playHearingTone()
        } else {
            hearingTestStage = .finishing
            send(NordHearingProfile.toneStop(sequence: sequence()))
            send(NordHearingProfile.testCommand(false, sequence: sequence()))
            if let filter = NordHearingProfile.filter(id: hearingID, values: hearingValues,
                                                      sequence: sequence()) { send(filter) }
            armHearingTimeout(seconds: 3, message: nil)
        }
    }

    func finishHearingTest(enhance: UInt8) {
        guard hearingTestStage == .finishing else { return }
        hearingTimeout?.cancel(); hearingTimeout = nil
        let group: ClosedRange<UInt8> = switch enhance {
        case 0: 1...6
        case 1: 7...12
        default: 13...20
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        let name = formatter.string(from: Date())
        let record = HearingProfileRecord(id: hearingID, name: name, values: hearingValues,
                                          scan: hearingScanData,
                                          descriptionID: UInt8.random(in: group))
        keepHearingRecord(record)
        hearingTestStage = .completed
        applyHearingProfile(record)
    }

    func stopHearingTest() {
        let stage = hearingTestStage
        hearingToneTask?.cancel(); hearingToneTask = nil
        hearingToneSendTask?.cancel(); hearingToneSendTask = nil
        hearingToneTimeout?.cancel(); hearingToneTimeout = nil
        hearingToneGeneration &+= 1
        hearingStartSequence = nil
        hearingToneSequence = nil
        hearingToneConfirmed = false
        hearingTimeout?.cancel(); hearingTimeout = nil
        guard controlReady else { hearingTestStage = .idle; return }
        switch stage {
        case .scanning:
            send(NordHearingProfile.scanCommand(false, id: hearingID, sequence: sequence()))
        case .starting:
            send(NordHearingProfile.testCommand(false, sequence: sequence()))
        case .testing:
            send(NordHearingProfile.toneStop(sequence: sequence()))
            send(NordHearingProfile.testCommand(false, sequence: sequence()))
        default: break
        }
        hearingTestStage = .idle
    }

    func failHearingTest(_ message: String) {
        stopHearingTest()
        hearingTestStage = .failed
        hearingError = message
        showNotice("Hearing test stopped", kind: .error)
    }

    func armHearingTimeout(seconds: Double, message: String?) {
        hearingTimeout?.cancel()
        hearingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            if let message {
                if self.hearingTestStage == .scanning || self.hearingTestStage == .starting {
                    self.failHearingTest(message)
                }
                else if self.hearingBusy {
                    self.hearingBusy = false
                    self.pendingHearingRecord = nil
                    self.hearingWriteSequences = []
                    self.hearingError = message
                    self.showNotice("Profile not confirmed", kind: .error)
                }
            } else if self.hearingTestStage == .finishing {
                self.failHearingTest("The earbuds did not return the hearing-test result. No profile was saved.")
            }
        }
    }

    func receiveHearingProfile(_ frame: WasiiBudsFrame) {
        if frame.command == 0x8115 {
            hearingLoaded = true
            if let record = NordHearingProfile.active(from: frame) {
                hearingActiveID = record.id
                keepHearingRecord(record)
                if let pending = pendingHearingRecord, pending.id == record.id,
                   pending.values == record.values {
                    keepHearingRecord(pending)
                    pendingHearingRecord = nil
                    hearingWriteSequences = []
                    hearingBusy = false
                    hearingTimeout?.cancel(); hearingTimeout = nil
                    showNotice("Hearing profile saved", kind: .success)
                }
            } else if pendingHearingRecord == nil {
                hearingActiveID = nil
            }
        }
        if let scan = NordHearingProfile.scan(from: frame) {
            if (frame.command == 0x0204 || frame.command == 0x811E), hearingTestStage == .scanning,
               scan.id == hearingID {
                hearingScanData = scan.data
                send(NordHearingProfile.scanCommand(false, id: hearingID, sequence: sequence()))
                beginHearingToneTest()
            } else if frame.command == 0x811E,
                      let record = hearingRecords.first(where: { $0.id == scan.id }) {
                keepHearingRecord(.init(id: record.id, name: record.name,
                                        values: record.values, scan: scan.data,
                                        descriptionID: record.descriptionID))
            }
        }
        if let status = NordHearingProfile.status(from: frame), hearingTestInProgress {
            if status.code == 1 || status.code == 3 {
                failHearingTest("Audio started playing. Pause music and try again.")
            } else if status.code == 5 {
                failHearingTest("An earbud left your ear. Put both buds in and retry.")
            } else if [7, 10, 255].contains(status.code) {
                failHearingTest("The ear scan timed out. Please retry.")
            }
        }
        if let enhance = NordHearingProfile.enhanceType(from: frame),
           hearingTestStage == .finishing, enhance.id == hearingID {
            finishHearingTest(enhance: enhance.kind)
        }
        if frame.command == 0x840D, frame.sequence == hearingStartSequence {
            hearingStartSequence = nil
            if frame.payload.first == 0 {
                hearingTimeout?.cancel(); hearingTimeout = nil
                hearingTestStage = .testing(0)
                playHearingTone()
            } else {
                failHearingTest("The earbuds refused to start the hearing tones.")
            }
        }
        if frame.command == 0x840E, frame.sequence == hearingToneSequence,
           hearingTestInProgress {
            hearingToneTimeout?.cancel(); hearingToneTimeout = nil
            hearingToneSequence = nil
            if frame.payload.first == 0 {
                hearingToneConfirmed = true
            } else {
                failHearingTest("The earbuds refused to play the hearing tone.")
            }
        }
        if hearingTestInProgress, [UInt16(0x840D), 0x840E].contains(frame.command),
           let status = frame.payload.first, status != 0 {
            failHearingTest("The earbuds refused the hearing test (code \(status)).")
        }
        if hearingBusy, hearingWriteSequences.contains(frame.sequence),
           [UInt16(0x8411), 0x840E, 0x8415, 0x8403].contains(frame.command),
           let status = frame.payload.first, status != 0 {
            hearingBusy = false
            pendingHearingRecord = nil
            hearingWriteSequences = []
            hearingTimeout?.cancel(); hearingTimeout = nil
            hearingError = "The earbuds refused this profile (code \(status))."
            showNotice("Profile not saved", kind: .error)
        }
    }
}
