@preconcurrency import CoreBluetooth
import Foundation
import Observation

/// A Bluetooth probe for working out how the fan receiver and its remote talk.
///
/// It answers the question that decides whether an iPhone can ever replace the
/// remote: does the receiver accept GATT connections, or does the remote just
/// broadcast? iOS apps can do the former and cannot do the latter, so the
/// advertisement dump below is the important part.
@MainActor
@Observable
final class BluetoothExplorer: NSObject {
    struct Advertiser: Identifiable {
        let peripheral: CBPeripheral
        var name: String
        var rssi: Int
        var isConnectable: Bool
        var serviceUUIDs: [String]
        /// Hex of the manufacturer-specific advertisement payload. If this
        /// changes each time a remote button is pressed, the remote is
        /// broadcasting commands rather than connecting.
        var manufacturerData: String?
        var id: UUID { peripheral.identifier }
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
    }

    private(set) var advertisers: [Advertiser] = []
    private(set) var log: [LogEntry] = []
    private(set) var isScanning = false
    private(set) var connected: CBPeripheral?

    private var central: CBCentralManager?

    var logText: String {
        let formatter = Date.FormatStyle(date: .omitted, time: .standard)
        return log.map { "\($0.time.formatted(formatter))  \($0.text)" }.joined(separator: "\n")
    }

    func startScanning() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            return  // Scanning begins once the radio reports it is powered on.
        }
        beginScan()
    }

    func stopScanning() {
        central?.stopScan()
        isScanning = false
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScanning()
        note("Connecting to \(peripheral.name ?? peripheral.identifier.uuidString)")
        central?.connect(peripheral)
    }

    func disconnect() {
        guard let connected else { return }
        central?.cancelPeripheralConnection(connected)
    }

    private func beginScan() {
        guard central?.state == .poweredOn else { return }
        advertisers.removeAll()
        isScanning = true
        // Duplicates are required: a broadcast-style remote shows up as a
        // stream of identical-looking adverts whose payload changes on a press.
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func note(_ text: String) {
        log.append(LogEntry(text: text))
    }
}

// CoreBluetooth calls these back on the queue the central was created with,
// which is `.main` above, so assuming main-actor isolation is sound. The
// alternative — hopping through a Task — would reorder callbacks.
extension BluetoothExplorer: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            note("Bluetooth state: \(central.state.rawValue)")
            if central.state == .poweredOn { beginScan() }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Read the advertisement out here: the dictionary itself cannot cross
        // into the main actor, but the plain values pulled from it can.
        let manufacturerData = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hex
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        let rssi = RSSI.intValue

        MainActor.assumeIsolated {
            let advertiser = Advertiser(
                peripheral: peripheral,
                name: peripheral.name ?? localName ?? "Unnamed",
                rssi: rssi,
                isConnectable: isConnectable,
                serviceUUIDs: serviceUUIDs,
                manufacturerData: manufacturerData
            )

            if let index = advertisers.firstIndex(where: { $0.id == advertiser.id }) {
                if let manufacturerData, advertisers[index].manufacturerData != manufacturerData {
                    note("\(advertiser.name) payload changed: \(manufacturerData)")
                }
                advertisers[index] = advertiser
            } else {
                advertisers.append(advertiser)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connected = peripheral
            note("Connected. Discovering services…")
            peripheral.delegate = self
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            note("Connect failed: \(error?.localizedDescription ?? "unknown")")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            connected = nil
            note("Disconnected" + (error.map { ": \($0.localizedDescription)" } ?? ""))
        }
    }
}

extension BluetoothExplorer: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        MainActor.assumeIsolated {
            for service in peripheral.services ?? [] {
                note("Service \(service.uuid)")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            for characteristic in service.characteristics ?? [] {
                note("  Char \(characteristic.uuid) [\(characteristic.properties.names)]")
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            guard let value = characteristic.value else { return }
            note("  \(characteristic.uuid) = \(value.hex)")
        }
    }
}

private extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

private extension CBCharacteristicProperties {
    var names: String {
        let all: [(CBCharacteristicProperties, String)] = [
            (.read, "read"), (.write, "write"),
            (.writeWithoutResponse, "writeNoResp"),
            (.notify, "notify"), (.indicate, "indicate"),
        ]
        return all.filter { contains($0.0) }.map(\.1).joined(separator: ",")
    }
}
