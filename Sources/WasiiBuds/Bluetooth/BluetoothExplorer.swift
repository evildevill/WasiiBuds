import BudsDomain
import BudsStorage
import BudsWidgetData
import CoreBluetooth
import Foundation

struct NearbyDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let advertisedServices: [String]
}

struct AppNotice: Identifiable, Equatable {
    enum Kind { case progress, success, error }
    let id = UUID()
    let title: String
    let kind: Kind
}

enum HearingTestStage: Equatable {
    case idle, scanning, starting, testing(Int), finishing, completed, failed
}

@MainActor
final class BluetoothExplorer: NSObject, ObservableObject {
    @Published var phase: LinkPhase = .waitingForPermission
    @Published var devices: [NearbyDevice] = []
    @Published var discoveredServices: [String] = []
    @Published var battery = BudBattery()
    @Published var leftPresence: EarPresence?
    @Published var rightPresence: EarPresence?
    @Published var ancMode: ANCMode?
    @Published var pendingMode: ANCMode?
    @Published private(set) var controlReady = false
    @Published var detail = "Checking Bluetooth…"
    @Published private(set) var events: [String] = []
    @Published private(set) var deviceName: String?
    @Published var featureStates: [BudFeature: Bool] = [:]
    @Published var pendingFeature: BudFeature?
    @Published var featureError: String?
    @Published var eqCapabilities: EQCapabilities?
    @Published var eqCurrent: UInt8?
    @Published var eqCustom: [CustomEQPreset] = []
    @Published var eqCustomLoaded = false
    @Published var eqBusy = false
    @Published var eqError: String?
    @Published var bassWaveLevel: Int?
    @Published var bassLevelReported = false
    @Published var pairedAudioDevices: [PairedAudioDevice] = []
    @Published var pairedDevicesLoaded = false
    @Published var accessoryCapabilities: AccessoryCapabilities?
    @Published var offeredEvents: Set<UInt8>?
    @Published var gestureTable: GestureTable?
    @Published var firmwareDetails: FirmwareDetails?
    @Published var firmwareLoading = false
    @Published var gestureBusy = false
    @Published var gesturePendingSide: UInt8?
    @Published var gesturePendingAction: UInt8?
    @Published var gestureError: String?
    @Published var holdCycleMask: UInt32?
    @Published var holdCycleBusy = false
    @Published var personalANCStored: Bool?
    @Published var findToneActive = false
    @Published var fitTestRunning = false
    @Published var fitTestResult: String?
    @Published var hearingRecords: [HearingProfileRecord] = []
    @Published var hearingActiveID: UInt32?
    @Published var hearingLoaded = false
    @Published var hearingBusy = false
    @Published var hearingTestStage: HearingTestStage = .idle
    @Published var hearingLevelIndex = 9
    @Published var hearingToneConfirmed = false
    @Published var hearingError: String?
    @Published private(set) var notice: AppNotice?
    var didAskDevices = false
    var didSubscribeEvents = false
    var gestureWrite: (side: UInt8, action: UInt8, function: UInt8, sequence: UInt8)?
    var gestureReadSequence: UInt8?
    var gestureReadAttempts = 0
    var gestureTimeout: Task<Void, Never>?
    var firmwareTimeout: Task<Void, Never>?
    var holdWriteSequence: UInt8?
    var holdReadSequence: UInt8?
    var holdReadAttempts = 0
    var wantedHoldMask: UInt32?
    var holdTimeout: Task<Void, Never>?
    var findTimeout: Task<Void, Never>?
    var fitTimeout: Task<Void, Never>?
    var noticeTimeout: Task<Void, Never>?
    var hearingID: UInt32 = 0
    var hearingValues = [Int8](repeating: 0, count: 12)
    var hearingScanData: [UInt8] = []
    var pendingHearingRecord: HearingProfileRecord?
    var hearingWriteSequences: Set<UInt8> = []
    var hearingTimeout: Task<Void, Never>?
    var hearingToneTask: Task<Void, Never>?
    var hearingToneSendTask: Task<Void, Never>?
    var hearingToneTimeout: Task<Void, Never>?
    var hearingStartSequence: UInt8?
    var hearingToneSequence: UInt8?
    var hearingToneGeneration: UInt64 = 0
    var lastHearingTone = Date.distantPast
    var hearingTestInProgress: Bool {
        switch hearingTestStage {
        case .scanning, .starting, .testing: true
        default: false
        }
    }

    enum EQAction {
        case builtIn(UInt8)
        case create(String)
        case save(CustomEQPreset)
        case delete(name: String, previousCount: Int)
        case bassLevel(Int)
    }
    struct EQOperation {
        let action: EQAction
        let writeCommand: UInt16
        let writeSequence: UInt8
        var readSequence: UInt8?
        var createdID: UInt8?
    }
    var eqOperation: EQOperation?
    var eqTimeout: Task<Void, Never>?

    struct FeatureOperation {
        let key: BudFeature
        let requested: Bool
        let writes: [FeatureWrite]
        var index = 0
        var writeSequence: UInt8?
        var readSequence: UInt8?
        var waitingForReconnect = false
        var didReconnect = false
        var sawConfirmingPush = false
    }
    var featureOperation: FeatureOperation?
    var featureTimeout: Task<Void, Never>?
    var reconnectingFeature = false

    var central: CBCentralManager!
    var peripherals: [UUID: CBPeripheral] = [:]
    var attemptedIDs: Set<UUID> = []
    var selected: CBPeripheral?
    var writeCharacteristic: CBCharacteristic?
    var notifyCharacteristic: CBCharacteristic?
    var streams: [String: WasiiBudsStream] = [:]
    var queuedWrites: [([UInt8], String)] = []
    var connectTimeout: Task<Void, Never>?
    var setupTask: Task<Void, Never>?
    var operationTask: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
    var recoveryTask: Task<Void, Never>?
    var pendingReadSequence: UInt8?
    var pendingWriteSequence: UInt8?
    var hasSentPendingWrite = false
    var nextSequence: UInt8 = 1
    var started = false
    let hearingProfileStore: HearingProfileStore

    init(hearingProfileStore: HearingProfileStore = HearingProfileStore()) {
        self.hearingProfileStore = hearingProfileStore
        hearingRecords = hearingProfileStore.load()
        super.init()
        WidgetStatusPublisher.publish(battery: BudBattery(), mode: nil, connected: false)
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func start() {
        started = true
        guard central.state == .poweredOn else { updateAvailability(); return }
        guard selected == nil, !central.isScanning else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: NordBudsProtocol.service)])
        if let match = connected.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains("Nord Buds 3 Pro") }) {
            peripherals[match.identifier] = match
            connect(to: match.identifier)
        } else {
            startScan()
        }
    }

    func startScan() {
        guard central.state == .poweredOn else { updateAvailability(); return }
        disconnect()
        devices = []
        peripherals = [:]
        attemptedIDs = []
        central.scanForPeripherals(withServices: nil)
        phase = .scanning
        detail = "Looking for OnePlus Nord Buds 3 Pro"
    }

    func stopScan() {
        central.stopScan()
        if phase == .scanning {
            phase = .ready
            detail = "Scan stopped"
        }
    }

    func connect(to id: UUID) {
        guard central.state == .poweredOn, let peripheral = peripherals[id] else {
            phase = .failed("Device not available. Scan again.")
            return
        }
        if reconnectingFeature {
            resetSession(preserveFeature: true)
            reconnectingFeature = false
        } else {
            disconnect()
        }
        central.stopScan()
        attemptedIDs.insert(id)
        selected = peripheral
        peripheral.delegate = self
        deviceName = peripheral.name
        phase = .connecting(id)
        detail = "Opening the device control connection"
        log("Connecting to \(peripheral.name ?? "device")")
        central.connect(peripheral)
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.selected?.identifier == id else { return }
            if case .connecting = self.phase {
                self.central.cancelPeripheralConnection(peripheral)
                self.resetSession()
                self.phase = .failed("Connection timed out")
                self.detail = "Try opening the case, then scan again."
            }
        }
    }

    func disconnect() {
        recoveryTask?.cancel(); recoveryTask = nil
        if let selected { central?.cancelPeripheralConnection(selected) }
        resetSession()
        if central?.state == .poweredOn { phase = .ready; detail = "Ready to connect" }
    }

    func refresh() {
        guard controlReady else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            self.send(NordBudsProtocol.batteryQuery(sequence: self.sequence()))
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, self.controlReady else { return }
            self.send(NordWear.query(sequence: self.sequence()))
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, self.controlReady else { return }
            self.send(NordBudsProtocol.ancQuery(sequence: self.sequence()))
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, self.controlReady else { return }
            self.send(NordBudsProtocol.featureQuery(sequence: self.sequence()))
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, self.controlReady else { return }
            self.refreshEQ()
        }
    }

    func refreshEQ() {
        guard controlReady, eqOperation == nil, let capabilities = eqCapabilities else { return }
        Task { [weak self] in
            guard let self else { return }
            if capabilities.builtIn {
                self.send(NordEqualizer.queryCurrent(sequence: self.sequence()))
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, self.controlReady else { return }
            if capabilities.custom {
                self.send(NordEqualizer.queryCustom(sequence: self.sequence()))
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, self.controlReady else { return }
            if capabilities.bassWave {
                self.send(NordEqualizer.bassLevelQuery(sequence: self.sequence()))
            }
        }
    }

    func refreshPairedDevices() {
        guard controlReady, featureStates[.dualConnection] != nil else { return }
        didAskDevices = true
        send(NordDualConnection.queryDevices(sequence: sequence()))
    }

    func prepareDualConnection() {
        guard controlReady, let enabled = featureStates[.dualConnection] else { return }
        send(NordDualConnection.followup(enabled: enabled, sequence: sequence()))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, self.controlReady else { return }
            self.refreshPairedDevices()
        }
    }

    func showNotice(_ title: String, kind: AppNotice.Kind) {
        noticeTimeout?.cancel()
        notice = AppNotice(title: title, kind: kind)
        if kind != .progress {
            let id = notice?.id
            noticeTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, self.notice?.id == id else { return }
                self.notice = nil
            }
        }
    }

    func dismissNotice() {
        noticeTimeout?.cancel(); noticeTimeout = nil
        notice = nil
    }

    func refreshAccessorySettings() {
        guard controlReady else { return }
        if accessoryCapabilities?.gestures == true {
            send(NordGesture.query(sequence: sequence()))
            send(NordGesture.holdCycleQuery(sequence: sequence()))
        }
        if accessoryCapabilities?.personalANC == true {
            send(NordAccessoryControls.personalStoredQuery(sequence: sequence()))
        }
        refreshHearingProfile()
        if featureStates[.autoPlayPause] == nil || featureStates[.personalANC] == nil {
            send(NordBudsProtocol.featureQuery(sequence: sequence()))
        }
    }

    func refreshGestures() {
        guard controlReady, accessoryCapabilities?.gestures == true else { return }
        send(NordGesture.query(sequence: sequence()))
        send(NordGesture.holdCycleQuery(sequence: sequence()))
    }

    func refreshFirmware() {
        guard controlReady, accessoryCapabilities?.firmware == true else { return }
        firmwareLoading = true
        send(NordAccessoryControls.firmwareQuery(sequence: sequence()))
        firmwareTimeout?.cancel()
        firmwareTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.firmwareLoading = false
        }
    }

    func sequence() -> UInt8 {
        let value = nextSequence
        nextSequence = nextSequence == 0xBF ? 1 : nextSequence + 1
        return value
    }

    func resetSession(preserveFeature: Bool = false) {
        publishWidgetSnapshot(connected: false)
        if hearingTestStage != .idle { stopHearingTest() }
        hearingTimeout?.cancel(); hearingTimeout = nil
        hearingToneTask?.cancel(); hearingToneTask = nil
        hearingBusy = false
        hearingTestStage = .idle
        pendingHearingRecord = nil
        hearingWriteSequences = []
        hearingActiveID = nil
        hearingLoaded = false
        if controlReady && findToneActive {
            send(NordAccessoryControls.findTone(false, sequence: sequence()))
        }
        if controlReady && fitTestRunning {
            send(NordAccessoryControls.fitTest(false, sequence: sequence()))
        }
        findTimeout?.cancel(); findTimeout = nil
        fitTimeout?.cancel(); fitTimeout = nil
        gestureTimeout?.cancel(); gestureTimeout = nil
        holdTimeout?.cancel(); holdTimeout = nil
        noticeTimeout?.cancel(); noticeTimeout = nil
        connectTimeout?.cancel(); connectTimeout = nil
        setupTask?.cancel(); setupTask = nil
        operationTask?.cancel(); operationTask = nil
        refreshTask?.cancel(); refreshTask = nil
        recoveryTask?.cancel(); recoveryTask = nil
        selected = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        streams = [:]
        queuedWrites = []
        discoveredServices = []
        battery = BudBattery()
        leftPresence = nil
        rightPresence = nil
        ancMode = nil
        pendingMode = nil
        pendingReadSequence = nil
        pendingWriteSequence = nil
        hasSentPendingWrite = false
        controlReady = false
        deviceName = nil
        eqCapabilities = nil
        eqCurrent = nil
        eqCustom = []
        eqCustomLoaded = false
        eqBusy = false
        eqOperation = nil
        eqError = nil
        bassWaveLevel = nil
        bassLevelReported = false
        pairedAudioDevices = []
        pairedDevicesLoaded = false
        didAskDevices = false
        didSubscribeEvents = false
        accessoryCapabilities = nil
        offeredEvents = nil
        gestureTable = nil
        firmwareDetails = nil
        firmwareLoading = false
        firmwareTimeout?.cancel(); firmwareTimeout = nil
        gestureBusy = false
        gesturePendingSide = nil
        gesturePendingAction = nil
        gestureError = nil
        gestureWrite = nil
        gestureReadSequence = nil
        gestureReadAttempts = 0
        holdCycleMask = nil
        holdCycleBusy = false
        holdWriteSequence = nil
        holdReadSequence = nil
        holdReadAttempts = 0
        wantedHoldMask = nil
        personalANCStored = nil
        findToneActive = false
        fitTestRunning = false
        fitTestResult = nil
        notice = nil
        eqTimeout?.cancel(); eqTimeout = nil
        if !preserveFeature {
            featureStates = [:]
            featureOperation = nil
            pendingFeature = nil
            featureError = nil
            featureTimeout?.cancel(); featureTimeout = nil
            reconnectingFeature = false
        }
    }

    func updateAvailability() {
        switch central.state {
        case .poweredOn: phase = .ready; detail = "Bluetooth is ready"
        case .poweredOff: phase = .bluetoothOff; detail = "Turn on Bluetooth in Control Center"
        case .unauthorized: phase = .permissionDenied; detail = "Allow Bluetooth in iPhone Settings"
        case .unsupported: phase = .failed("Bluetooth is unsupported")
        case .resetting, .unknown: phase = .waitingForPermission
        @unknown default: phase = .failed("Bluetooth is unavailable")
        }
    }

    func failControlDiscovery(_ message: String, peripheral: CBPeripheral) {
        resetSession()
        central.cancelPeripheralConnection(peripheral)
        phase = .failed(message)
        detail = message
        log(message)
    }

    func log(_ message: String) {
        events.insert(message, at: 0)
        if events.count > 12 { events.removeLast() }
    }

    func publishWidgetSnapshot(connected: Bool? = nil) {
        WidgetStatusPublisher.publish(battery: battery, mode: ancMode,
                                      connected: connected ?? controlReady)
    }

    func send(_ frame: WasiiBudsFrame) {
        sendRaw(frame.encoded(), label: String(format: "%04X (seq %02X)", frame.command, frame.sequence))
    }

    func sendRaw(_ bytes: [UInt8], label: String) {
        guard selected != nil, let characteristic = writeCharacteristic,
              characteristic.properties.contains(.writeWithoutResponse) else {
            log("Write characteristic unavailable")
            return
        }
        guard let selected, selected.maximumWriteValueLength(for: .withoutResponse) > 0 else {
            log("Device write limit unavailable")
            return
        }
        let maximum = selected.maximumWriteValueLength(for: .withoutResponse)
        for offset in stride(from: 0, to: bytes.count, by: maximum) {
            queuedWrites.append((Array(bytes[offset..<min(offset + maximum, bytes.count)]), label))
        }
        flushWrites()
    }

    func flushWrites() {
        guard let peripheral = selected, let characteristic = writeCharacteristic else { return }
        while peripheral.canSendWriteWithoutResponse && !queuedWrites.isEmpty {
            let next = queuedWrites.removeFirst()
            peripheral.writeValue(Data(next.0), for: characteristic, type: .withoutResponse)
            log("Sent \(next.1)")
        }
    }

    func beginProtocol() {
        guard let selected, writeCharacteristic != nil, notifyCharacteristic?.isNotifying == true else { return }
        if featureOperation?.waitingForReconnect == true { featureOperation?.didReconnect = true }
        controlReady = true
        recoveryTask?.cancel(); recoveryTask = nil
        publishWidgetSnapshot()
        phase = .connected(selected.identifier)
        detail = "Control channel found; waiting for device reports"
        log("Control service and notifications ready")
        setupTask?.cancel()
        setupTask = Task { [weak self] in
            guard let self else { return }
            self.send(NordBudsProtocol.hello(sequence: self.sequence()))
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, self.controlReady else { return }
            self.send(NordBudsProtocol.register())
            self.send(NordAccessoryControls.offeredEventsQuery(sequence: self.sequence()))
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, self.controlReady else { return }
            self.refresh()
        }
    }

}

extension BluetoothExplorer: @preconcurrency CBCentralManagerDelegate {
    @objc func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn { resetSession() }
        updateAvailability()
        if central.state == .poweredOn && started { start() }
    }

    @objc func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Unnamed device"
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString).sorted()
        let device = NearbyDevice(id: peripheral.identifier, name: name,
                                  rssi: RSSI.intValue, advertisedServices: advertised)
        peripherals[device.id] = peripheral
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
        devices.sort { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
        if selected == nil && !attemptedIDs.contains(peripheral.identifier)
            && name.localizedCaseInsensitiveContains("Nord Buds 3 Pro") {
            connect(to: peripheral.identifier)
        }
    }

    @objc func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard selected?.identifier == peripheral.identifier else { return }
        connectTimeout?.cancel(); connectTimeout = nil
        phase = .inspecting(peripheral.identifier)
        detail = "Discovering control service"
        peripheral.discoverServices(nil)
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.selected?.identifier == peripheral.identifier else { return }
            if case .inspecting = self.phase {
                self.detail = "Service discovery timed out"
                self.phase = .failed("Service discovery timed out")
                self.central.cancelPeripheralConnection(peripheral)
                self.resetSession()
            }
        }
    }

    @objc func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        let interruptedSetting = pendingFeature?.title
        let interruptedEQ = eqBusy
        resetSession()
        phase = .failed("Could not connect")
        detail = error?.localizedDescription ?? "Open the case and try again"
        if let interruptedSetting { featureError = "Could not reconnect to confirm \(interruptedSetting)." }
        if interruptedEQ { eqError = "Could not reconnect to confirm the equalizer change." }
    }

    @objc func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if featureOperation?.waitingForReconnect == true {
            let id = peripheral.identifier
            resetSession(preserveFeature: true)
            peripherals[id] = peripheral
            phase = .ready
            detail = "Earbuds restarting; reconnecting…"
            reconnectingFeature = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.reconnectingFeature else { return }
                self.connect(to: id)
            }
            return
        }
        let interruptedSetting = pendingFeature?.title
        let interruptedEQ = eqBusy
        resetSession()
        phase = .ready
        detail = error.map { "Connection lost: \($0.localizedDescription)" } ?? "Disconnected"
        if let interruptedSetting { featureError = "Connection lost while changing \(interruptedSetting)." }
        if interruptedEQ { eqError = "Connection lost while changing the equalizer." }
        guard started, central.state == .poweredOn else { return }
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.selected == nil,
                  self.central.state == .poweredOn else { return }
            self.start()
        }
    }
}

extension BluetoothExplorer: @preconcurrency CBPeripheralDelegate {
    @objc func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard selected?.identifier == peripheral.identifier else { return }
        flushWrites()
    }

    @objc func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if let error {
            failControlDiscovery("Service discovery failed: \(error.localizedDescription)", peripheral: peripheral)
            return
        }
        let services = peripheral.services ?? []
        discoveredServices = services.map { $0.uuid.uuidString }.sorted()
        log("Found \(services.count) GATT services")
        let target = services.first { $0.uuid.uuidString.uppercased() == NordBudsProtocol.service }
        if let target {
            peripheral.discoverCharacteristics(nil, for: target)
            for service in services where service.uuid == CBUUID(string: "FE2C") {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        } else {
            connectTimeout?.cancel(); connectTimeout = nil
            central.cancelPeripheralConnection(peripheral)
            selected = nil
            phase = .scanning
            detail = "Checking the other Nord Buds connection"
            log(detail)
            central.scanForPeripherals(withServices: nil)
        }
    }

    @objc func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if let error {
            if service.uuid == CBUUID(string: "FE2C") {
                log("Optional FE2C discovery failed: \(error.localizedDescription)")
            } else {
                failControlDiscovery("Characteristic discovery failed: \(error.localizedDescription)",
                                     peripheral: peripheral)
            }
            return
        }
        if service.uuid == CBUUID(string: "FE2C") {
            for characteristic in service.characteristics ?? [] {
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    log("Subscribed to \(characteristic.uuid.uuidString)")
                }
            }
            return
        }
        connectTimeout?.cancel(); connectTimeout = nil
        for characteristic in service.characteristics ?? [] {
            let id = characteristic.uuid.uuidString.uppercased()
            log("Characteristic \(id)")
            if id == NordBudsProtocol.write { writeCharacteristic = characteristic }
            if id == NordBudsProtocol.notify { notifyCharacteristic = characteristic }
        }
        if let notifyCharacteristic, writeCharacteristic != nil,
           notifyCharacteristic.properties.contains(.notify) || notifyCharacteristic.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: notifyCharacteristic)
            detail = "Enabling device reports"
        } else {
            failControlDiscovery("Control characteristics are missing or unavailable", peripheral: peripheral)
        }
    }

    @objc func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        guard characteristic.uuid.uuidString.uppercased() == NordBudsProtocol.notify else {
            if let error { log("Optional notification failed: \(error.localizedDescription)") }
            return
        }
        if let error {
            failControlDiscovery("Control notifications failed: \(error.localizedDescription)",
                                 peripheral: peripheral)
        } else if characteristic.isNotifying {
            beginProtocol()
        } else {
            failControlDiscovery("Control notifications were not enabled", peripheral: peripheral)
        }
    }

    @objc func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if let error { log("Notification error: \(error.localizedDescription)"); return }
        guard let value = characteristic.value else { return }
        let id = characteristic.uuid.uuidString
        var stream = streams[id] ?? WasiiBudsStream()
        let frames = stream.append(Array(value))
        streams[id] = stream
        for frame in frames { receive(frame) }
    }
}
