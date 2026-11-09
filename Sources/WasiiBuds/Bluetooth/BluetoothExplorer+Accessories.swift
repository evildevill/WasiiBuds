import BudsDomain
import Foundation

extension BluetoothExplorer {
    func subscribeOfferedEventsIfReady() {
        guard controlReady, !didSubscribeEvents, let events = offeredEvents,
              let capabilities = accessoryCapabilities else { return }
        let desired: [UInt8] = [1, 2, 3, 4, 8, 0x0B]
        let supported = desired.filter { events.contains($0) }
        guard !supported.isEmpty else { return }
        didSubscribeEvents = true
        if capabilities.batchSubscribe {
            send(NordAccessoryControls.subscribe(supported, sequence: sequence()))
        } else {
            for event in supported {
                send(NordAccessoryControls.subscribeOne(event, sequence: sequence()))
            }
        }
    }

    func changeGesture(side: UInt8, action: UInt8, function: UInt8) {
        guard controlReady, !gestureBusy, featureOperation == nil, eqOperation == nil,
              pendingMode == nil, let table = gestureTable,
              let updated = table.changing(side: side, action: action, to: function),
              let packet = NordGesture.write(updated, sequence: sequence()) else {
            gestureError = "Read the current gesture table before changing a binding."
            showNotice("Gesture unavailable", kind: .error)
            return
        }
        gestureBusy = true
        gesturePendingSide = side
        gesturePendingAction = action
        gestureError = nil
        gestureWrite = (side, action, function, packet.sequence)
        let readSequence = sequence()
        gestureReadSequence = readSequence
        gestureReadAttempts = 0
        showNotice("Updating \(side == 1 ? "left" : "right") earbud…", kind: .progress)
        send(packet)
        scheduleGestureRead(readSequence, delay: .milliseconds(220))
        gestureTimeout?.cancel()
        gestureTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.gestureBusy else { return }
            self.finishGesture(error: "The earbuds did not confirm this gesture.")
        }
    }

    func finishGesture(error: String? = nil) {
        let side = gesturePendingSide
        gestureBusy = false
        gesturePendingSide = nil
        gesturePendingAction = nil
        gestureError = error
        gestureWrite = nil
        gestureReadSequence = nil
        gestureReadAttempts = 0
        gestureTimeout?.cancel(); gestureTimeout = nil
        showNotice(error == nil ? "\(side == 1 ? "Left" : "Right") gesture saved" : "Gesture not saved",
                   kind: error == nil ? .success : .error)
    }

    func scheduleGestureRead(_ readSequence: UInt8, delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self,
                  self.gestureReadSequence == readSequence else { return }
            self.send(NordGesture.query(sequence: readSequence))
        }
    }

    func changeHoldCycle(_ selected: UInt32) {
        guard controlReady, !holdCycleBusy, !gestureBusy, let current = holdCycleMask,
              (selected & 0x07).nonzeroBitCount >= 2,
              let packet = NordGesture.holdCycleWrite(mask: (current & ~0x07) | (selected & 0x07),
                                                     sequence: sequence()) else { return }
        holdCycleBusy = true
        gestureError = nil
        wantedHoldMask = (current & ~0x07) | (selected & 0x07)
        holdWriteSequence = packet.sequence
        let readSequence = sequence()
        holdReadSequence = readSequence
        holdReadAttempts = 0
        showNotice("Updating noise cycle…", kind: .progress)
        send(packet)
        scheduleHoldRead(readSequence, delay: .milliseconds(250))
        holdTimeout?.cancel()
        holdTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.holdCycleBusy else { return }
            self.finishHold(error: "The earbuds did not confirm the noise cycle.")
        }
    }

    func finishHold(error: String? = nil) {
        holdCycleBusy = false
        gestureError = error
        holdWriteSequence = nil
        holdReadSequence = nil
        holdReadAttempts = 0
        wantedHoldMask = nil
        holdTimeout?.cancel(); holdTimeout = nil
        showNotice(error == nil ? "Noise cycle saved" : "Noise cycle not saved",
                   kind: error == nil ? .success : .error)
    }

    func scheduleHoldRead(_ readSequence: UInt8, delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self,
                  self.holdReadSequence == readSequence else { return }
            self.send(NordGesture.holdCycleQuery(sequence: readSequence))
        }
    }

    func setFindTone(_ enabled: Bool) {
        guard controlReady, accessoryCapabilities?.find == true else { return }
        send(NordAccessoryControls.findTone(enabled, sequence: sequence()))
        findToneActive = enabled
        findTimeout?.cancel(); findTimeout = nil
        showNotice(enabled ? "Playing a sound on both earbuds" : "Sound stopped",
                   kind: enabled ? .progress : .success)
        if enabled {
            findTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.setFindTone(false)
            }
        }
    }

    func setFitTest(_ enabled: Bool) {
        guard controlReady, accessoryCapabilities?.fitTest == true else { return }
        if enabled && offeredEvents?.contains(4) != true {
            // The Classic capture for this model omitted event 04. The user's iPhone
            // firmware may still accept an explicit, session-scoped subscription.
            send(NordAccessoryControls.subscribeOne(4, sequence: sequence()))
        }
        send(NordAccessoryControls.fitTest(enabled, sequence: sequence()))
        fitTestRunning = enabled
        if enabled { fitTestResult = nil }
        fitTimeout?.cancel(); fitTimeout = nil
        showNotice(enabled ? "Checking earbud fit…" : "Fit test stopped",
                   kind: enabled ? .progress : .success)
        if enabled {
            fitTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.fitTestRunning else { return }
                self.setFitTest(false)
                self.fitTestResult = "No fit result arrived. This firmware may not send the required event."
            }
        }
    }

    func receiveAccessories(_ frame: WasiiBudsFrame) {
        if let stored = NordAccessoryControls.personalStored(from: frame) {
            personalANCStored = stored
        }
        if let table = NordGesture.table(from: frame) {
            gestureTable = table
            if let expected = gestureWrite, frame.sequence == gestureReadSequence {
                if table.confirms(side: expected.side, action: expected.action,
                                  function: expected.function) {
                    finishGesture()
                } else if gestureReadAttempts == 0 {
                    gestureReadAttempts = 1
                    let retry = sequence()
                    gestureReadSequence = retry
                    scheduleGestureRead(retry, delay: .milliseconds(350))
                } else {
                    finishGesture(error: "The earbuds kept the previous gesture.")
                }
            }
        }
        if let details = NordAccessoryControls.firmware(from: frame) {
            firmwareDetails = details
            firmwareLoading = false
            firmwareTimeout?.cancel(); firmwareTimeout = nil
        } else if frame.command == 0x8105 {
            firmwareLoading = false
            firmwareTimeout?.cancel(); firmwareTimeout = nil
        }
        if let mask = NordGesture.holdCycleMask(from: frame) {
            holdCycleMask = mask
            if frame.command == 0x810C, frame.sequence == holdReadSequence,
               let wanted = wantedHoldMask {
                if mask & 0x07 == wanted & 0x07 {
                    finishHold()
                } else if holdReadAttempts == 0 {
                    holdReadAttempts = 1
                    let retry = sequence()
                    holdReadSequence = retry
                    scheduleHoldRead(retry, delay: .milliseconds(350))
                } else {
                    finishHold(error: "The earbuds kept the previous noise cycle.")
                }
            }
        }
        if frame.command == 0x8401, let expected = gestureWrite,
           frame.sequence == expected.sequence {
            let status = frame.payload.first ?? 0xFF
            if status != 0 {
                finishGesture(error: "Earbuds refused the gesture (code \(status)).")
            }
        }
        if frame.command == 0x8404, frame.sequence == holdWriteSequence,
           let status = frame.payload.first, status != 0 {
            finishHold(error: "Earbuds refused the noise cycle (code \(status)).")
        }
        if frame.command == 0x8400 && frame.payload.first != 0 && findToneActive {
            findToneActive = false
            findTimeout?.cancel(); findTimeout = nil
            showNotice("Earbuds refused the find sound", kind: .error)
        }
        if frame.command == 0x8405 && frame.payload.first != 0 && fitTestRunning {
            fitTestRunning = false
            fitTimeout?.cancel(); fitTimeout = nil
            fitTestResult = "Earbuds refused the fit test."
            showNotice("Fit test unavailable", kind: .error)
        }
        if let result = NordAccessoryControls.fitResult(from: frame), fitTestRunning {
            func label(_ value: UInt8) -> String {
                switch value { case 1: "Good"; case 0: "Average"; case 6: "Poor"; default: "Unknown" }
            }
            fitTestResult = "Left: \(label(result.left)) · Right: \(label(result.right))"
            fitTestRunning = false
            fitTimeout?.cancel(); fitTimeout = nil
            send(NordAccessoryControls.fitTest(false, sequence: sequence()))
            showNotice("Fit test complete", kind: .success)
        }
    }
}
