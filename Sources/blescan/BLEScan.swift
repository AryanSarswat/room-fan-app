import CoreBluetooth
import Foundation

/// Bluetooth probe for the fan receiver and its remote, run from a Mac.
///
///     blescan [seconds]        list what is advertising nearby
///     blescan dump <uuid>      connect to one device and walk its GATT tree
///
/// The question it exists to answer: does the receiver accept connections, or
/// does the remote simply broadcast? iOS can speak to the former and can never
/// impersonate the latter.
final class Scanner: NSObject, @unchecked Sendable {
    private struct Seen {
        var name: String
        var rssi: Int
        var connectable: Bool
        var services: [String]
        var manufacturerData: String?
        var payloadChanges: Int
        var count: Int
    }

    /// Every property below is touched only on this queue.
    private let queue = DispatchQueue(label: "blescan")
    private var central: CBCentralManager!
    private var seen: [UUID: Seen] = [:]
    private let target: UUID?

    init(connectTo target: UUID?) {
        self.target = target
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    func report() {
        queue.sync {
            guard !seen.isEmpty else {
                print("Nothing advertising nearby.")
                return
            }
            print("\n\(seen.count) device(s), strongest first:\n")
            for (id, device) in seen.sorted(by: { $0.value.rssi > $1.value.rssi }) {
                let kind = device.connectable ? "connectable" : "broadcast-only"
                print("\(device.name)  \(device.rssi) dBm  \(kind)  \(device.count) adverts")
                print("  id \(id.uuidString)")
                if !device.services.isEmpty {
                    print("  services \(device.services.joined(separator: ", "))")
                }
                if let payload = device.manufacturerData {
                    print("  mfg data \(payload)")
                }
                if device.payloadChanges > 0 {
                    print("  ** payload changed \(device.payloadChanges)x while scanning **")
                }
                print("")
            }
        }
    }
}

extension Scanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            print("Bluetooth unavailable (state \(central.state.rawValue)).")
            return
        }
        if let target {
            let known = central.retrievePeripherals(withIdentifiers: [target])
            guard let peripheral = known.first else {
                print("That device is not known to this Mac; run a plain scan first.")
                exit(1)
            }
            print("Connecting to \(peripheral.name ?? target.uuidString)…")
            central.connect(peripheral)
        } else {
            // Duplicates are needed to notice a payload change on a button press.
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let payload = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hex
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "(unnamed)"
        var device = seen[peripheral.identifier] ?? Seen(
            name: name, rssi: RSSI.intValue, connectable: false,
            services: [], manufacturerData: nil, payloadChanges: 0, count: 0
        )
        if let payload, let previous = device.manufacturerData, previous != payload {
            device.payloadChanges += 1
            print("payload change on \(name): \(payload)")
        }
        device.name = name
        device.rssi = max(device.rssi, RSSI.intValue)
        device.connectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? device.connectable
        device.services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        device.manufacturerData = payload ?? device.manufacturerData
        device.count += 1
        seen[peripheral.identifier] = device
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected. Discovering services…")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        print("Connect failed: \(error?.localizedDescription ?? "unknown")")
        exit(1)
    }
}

extension Scanner: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        for service in peripheral.services ?? [] {
            print("service \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        for characteristic in service.characteristics ?? [] {
            print("  char \(characteristic.uuid) [\(characteristic.properties.names)]")
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard let value = characteristic.value else { return }
        print("  \(characteristic.uuid) = \(value.hex)")
    }
}

extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

extension CBCharacteristicProperties {
    var names: String {
        let all: [(CBCharacteristicProperties, String)] = [
            (.read, "read"), (.write, "write"), (.writeWithoutResponse, "writeNoResp"),
            (.notify, "notify"), (.indicate, "indicate"),
        ]
        return all.filter { contains($0.0) }.map(\.1).joined(separator: ",")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "dump", let id = arguments.dropFirst().first.flatMap(UUID.init(uuidString:)) {
    let scanner = Scanner(connectTo: id)
    RunLoop.main.run(until: .now + 15)
    _ = scanner
} else {
    let seconds = arguments.first.flatMap(Double.init) ?? 15
    print("Scanning \(Int(seconds))s — press buttons on the remote now.")
    let scanner = Scanner(connectTo: nil)
    RunLoop.main.run(until: .now + seconds)
    scanner.report()
}
