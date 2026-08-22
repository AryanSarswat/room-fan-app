import CoreBluetooth
import Foundation

/// Bluetooth probe for the fan receiver and its remote, run from a Mac.
///
///     blescan [seconds]        list what is advertising nearby
///     blescan watch <uuid>     follow one device, marking which bytes change
///     blescan dump <uuid>      connect to one device and walk its GATT tree
///
/// The question it exists to answer: does the receiver accept connections, or
/// does the remote simply broadcast? iOS can speak to the former and can never
/// impersonate the latter.
enum Mode {
    case list
    case watch(UUID)
    case dump(UUID)
}

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
    private var lastWatched: [UInt8]?
    private let started = Date()
    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
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

    /// Prints one advert against the previous one, so a button press shows up
    /// as a handful of marked byte positions rather than a wall of hex.
    private func trace(_ payload: Data) {
        let bytes = [UInt8](payload)
        defer { lastWatched = bytes }
        guard bytes != lastWatched else { return }

        let stamp = String(format: "%6.2fs", Date().timeIntervalSince(started))
        print("\(stamp)  \(payload.hex)")

        guard let previous = lastWatched else { return }
        var marks = ""
        for index in 0..<max(bytes.count, previous.count) {
            let old = index < previous.count ? previous[index] : nil
            let new = index < bytes.count ? bytes[index] : nil
            marks += (old == new) ? "   " : "^^ "
        }
        print("         \(marks)")
    }
}

extension Scanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            print("Bluetooth unavailable (state \(central.state.rawValue)).")
            return
        }
        if case .dump(let target) = mode {
            guard let peripheral = central.retrievePeripherals(withIdentifiers: [target]).first else {
                print("That device is not known to this Mac; run a plain scan first.")
                exit(1)
            }
            print("Connecting to \(peripheral.name ?? target.uuidString)…")
            central.connect(peripheral)
            return
        }
        // Duplicates are needed to notice a payload change on a button press.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let raw = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        if case .watch(let target) = mode {
            guard peripheral.identifier == target, let raw else { return }
            trace(raw)
            return
        }

        let payload = raw?.hex
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
let identifier = arguments.dropFirst().first.flatMap(UUID.init(uuidString:))

switch (arguments.first, identifier) {
case ("dump", .some(let id)):
    let scanner = Scanner(mode: .dump(id))
    RunLoop.main.run(until: .now + 15)
    _ = scanner

case ("watch", .some(let id)):
    let seconds = arguments.dropFirst(2).first.flatMap(Double.init) ?? 60
    print("Watching \(id) for \(Int(seconds))s. Press ONE button repeatedly.")
    print("Marked columns are the bytes that changed since the advert above.\n")
    let scanner = Scanner(mode: .watch(id))
    RunLoop.main.run(until: .now + seconds)
    _ = scanner

case ("dump", .none), ("watch", .none):
    print("That is not a device UUID. Copy the `id` line from a plain scan.")
    exit(2)

default:
    let seconds = arguments.first.flatMap(Double.init) ?? 15
    print("Scanning \(Int(seconds))s — press buttons on the remote now.")
    let scanner = Scanner(mode: .list)
    RunLoop.main.run(until: .now + seconds)
    scanner.report()
}
