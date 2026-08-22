import CoreBluetooth
import SwiftUI

struct BluetoothExplorerView: View {
    @State private var explorer = BluetoothExplorer()

    var body: some View {
        List {
            Section {
                ForEach(explorer.advertisers) { advertiser in
                    Button {
                        explorer.connect(advertiser.peripheral)
                    } label: {
                        row(advertiser)
                    }
                    .disabled(!advertiser.isConnectable)
                }
            } header: {
                Text(explorer.isScanning ? "Scanning…" : "Nearby")
            } footer: {
                Text("Press a button on the physical remote while this is scanning. A device whose payload changes on each press is broadcasting its commands, which an iPhone cannot reproduce.")
            }

            Section("Log") {
                ForEach(explorer.log.reversed()) { entry in
                    Text(entry.text)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .navigationTitle("Bluetooth")
        .toolbar {
            ShareLink(item: explorer.logText)
        }
        .task {
            explorer.startScanning()
        }
        .onDisappear {
            explorer.stopScanning()
            explorer.disconnect()
        }
    }

    private func row(_ advertiser: BluetoothExplorer.Advertiser) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(advertiser.name)
                Spacer()
                Text("\(advertiser.rssi) dBm").foregroundStyle(.secondary)
            }
            if !advertiser.serviceUUIDs.isEmpty {
                Text(advertiser.serviceUUIDs.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let manufacturerData = advertiser.manufacturerData {
                Text(manufacturerData)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if !advertiser.isConnectable {
                Text("broadcast only")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
