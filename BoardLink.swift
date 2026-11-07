import CoreBluetooth
import Foundation

/// Finds the "Bike Dash" board over Bluetooth and sends it navigation packets.
final class BoardLink: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: "6E5A0001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let charUUID    = CBUUID(string: "6E5A0002-B5A3-F393-E0A9-E50E24DCCA9E")

    @Published var status = "Looking for Bike Dash..."
    @Published var connected = false

    private var central: CBCentralManager!
    private var board: CBPeripheral?
    private var navChar: CBCharacteristic?
    private var lastPayload: String?
    private var retryTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: Finding the board

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn {
            findBoard()
        } else {
            status = "Bluetooth is off"
            connected = false
        }
    }

    private func findBoard() {
        guard central.state == .poweredOn else { return }
        if let b = board, b.state == .connected || b.state == .connecting { return }

        // The board is usually already connected to the iPhone (for calls & music)
        if let p = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]).first {
            attach(p)
            return
        }
        status = "Looking for Bike Dash..."
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
        scheduleRetry()
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.findBoard()
        }
    }

    private func attach(_ p: CBPeripheral) {
        central.stopScan()
        board = p
        p.delegate = self
        status = "Connecting..."
        central.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        attach(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = "Setting up..."
        p.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        lost()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        lost()
    }

    private func lost() {
        board = nil
        navChar = nil
        connected = false
        status = "Bike Dash disconnected"
        scheduleRetry()
    }

    // MARK: Services

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            status = "Board firmware too old - upload bike_dashboard_nav"
            return
        }
        p.discoverCharacteristics([Self.charUUID], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == Self.charUUID }) else { return }
        navChar = ch
        connected = true
        status = "Connected to Bike Dash"
        if let last = lastPayload { send(last) }
    }

    // MARK: Sending

    /// Builds the board packet and shortens only the text fields if Bluetooth can't carry it all,
    /// so the arrow and the numbers always arrive intact.
    func sendNav(code: Int, meters: Int, instruction: String, street: String,
                 eta: String, remainingM: Int, remainingMin: Int) {
        func pack(_ ins: String, _ st: String) -> String {
            [String(code), String(meters), ins, st, eta, String(remainingM), String(remainingMin)].joined(separator: "|")
        }
        var ins = instruction, st = street
        let maxLen = board.map { $0.maximumWriteValueLength(for: .withoutResponse) } ?? 180
        while pack(ins, st).utf8.count > maxLen && (!ins.isEmpty || !st.isEmpty) {
            if ins.count >= st.count { ins = String(ins.dropLast()) } else { st = String(st.dropLast()) }
        }
        send(pack(ins, st))
    }

    func send(_ text: String) {
        lastPayload = text
        guard let p = board, let ch = navChar, p.state == .connected else { return }
        guard p.canSendWriteWithoutResponse else { pending = true; return }   // radio busy: send when ready
        pending = false
        var data = Data(text.utf8)
        let maxLen = p.maximumWriteValueLength(for: .withoutResponse)
        if data.count > maxLen { data = data.prefix(maxLen) }
        p.writeValue(data, for: ch, type: .withoutResponse)
    }

    private var pending = false
    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        if pending, let last = lastPayload { send(last) }
    }
}
