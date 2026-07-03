import CoreBluetooth
import Foundation

/// Reads the roBa's per-half battery levels over BLE GATT.
///
/// The split central (right half) exposes the standard Battery Service
/// (0x180F): its own Battery Level (0x2A19) plus one proxied characteristic
/// per peripheral, labeled by a Characteristic User Description (0x2901) of
/// "Peripheral N" (enabled in firmware via
/// CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY / _FETCHING).
///
/// CoreBluetooth piggybacks on the existing HID bond — connecting from this
/// app shares the system's BLE link and does not disturb typing. Requires
/// the Bluetooth TCC permission (NSBluetoothAlwaysUsageDescription).
final class BatteryMonitor: NSObject {
    enum State: Equatable {
        case idle
        case bluetoothOff
        case unauthorized
        case searching
        case connected
        case disconnected
    }

    var onUpdate: ((BatteryRole, Int) -> Void)?
    var onState: ((State) -> Void)?

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let userDescription = CBUUID(string: "2901")

    private let deviceName = "roBa"
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var roles: [CBCharacteristic: BatteryRole] = [:]
    private var retryTimer: Timer?

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    /// Re-read all known characteristics (e.g. after wake from sleep).
    func refresh() {
        guard let peripheral else { return }
        for characteristic in roles.keys {
            peripheral.readValue(for: characteristic)
        }
    }

    private func findAndConnect() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        if let target = connected.first(where: { ($0.name ?? "").hasPrefix(deviceName) }) {
            retryTimer?.invalidate()
            retryTimer = nil
            peripheral = target
            target.delegate = self
            central.connect(target)
        } else {
            onState?(.searching)
            scheduleRetry()
        }
    }

    /// The keyboard may be asleep or out of range: poll the system's
    /// connected-peripherals list until it shows up.
    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.findAndConnect()
        }
    }
}

/// CLI: print battery readings until Ctrl-C (Bluetooth TCC must be granted
/// to the invoking context).
///   /Applications/RoBaHUD.app/Contents/MacOS/RoBaHUD --battery-dump
enum BatteryDump {
    static func run() -> Int32 {
        let monitor = BatteryMonitor()
        monitor.onUpdate = { role, level in
            print("battery  \(role.displayName) (\(role.key))  \(level)%")
        }
        monitor.onState = { state in
            print("state    \(state)")
        }
        monitor.start()
        CFRunLoopRun()
        return 0
    }
}

extension BatteryMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            findAndConnect()
        case .poweredOff:
            onState?(.bluetoothOff)
        case .unauthorized:
            onState?(.unauthorized)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onState?(.connected)
        roles.removeAll()
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        onState?(.disconnected)
        roles.removeAll()
        // A pending connect re-establishes as soon as the device returns.
        central.connect(peripheral)
        scheduleRetry()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        scheduleRetry()
    }
}

extension BatteryMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.batteryService {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.batteryLevel {
            // Role is decided by the CUD descriptor (absent → central).
            peripheral.discoverDescriptors(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic,
                    error: Error?) {
        let cud = characteristic.descriptors?.first { $0.uuid == Self.userDescription }
        if let cud {
            peripheral.readValue(for: cud)     // role assigned in didUpdateValueFor descriptor
        } else {
            assign(role: .central, to: characteristic, on: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor,
                    error: Error?) {
        guard descriptor.uuid == Self.userDescription,
              let characteristic = descriptor.characteristic else { return }
        assign(role: BatteryRole.from(cud: descriptor.value as? String),
               to: characteristic, on: peripheral)
    }

    private func assign(role: BatteryRole, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        roles[characteristic] = role
        peripheral.readValue(for: characteristic)
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let role = roles[characteristic],
              let byte = characteristic.value?.first else { return }
        onUpdate?(role, Int(byte))
    }
}
