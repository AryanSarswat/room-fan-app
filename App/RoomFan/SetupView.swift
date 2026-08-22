import ModernFormsKit
import SwiftUI

/// Points the app at a fan, either by sweeping the local subnet or by typing
/// the address in. There is no vendor discovery protocol to lean on.
struct SetupView: View {
    let controller: FanController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var isScanning = false
    @State private var found: [FanDiscovery.Fan] = []

    init(controller: FanController) {
        self.controller = controller
        _draft = State(initialValue: controller.host)
    }

    var body: some View {
        Form {
            Section("Fan address") {
                TextField("192.168.1.50", text: $draft)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .onSubmit { use(draft) }
                Button("Connect") { use(draft) }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section {
                Button(isScanning ? "Scanning…" : "Scan this network") {
                    Task { await scan() }
                }
                .disabled(isScanning)

                ForEach(found) { fan in
                    Button(fan.host) { use(fan.host) }
                }
            } footer: {
                Text("Checks every address on your Wi-Fi subnet for a fan that answers.")
            }

            Section {
                NavigationLink("Bluetooth Explorer", destination: BluetoothExplorerView())
            } footer: {
                Text("Inspects what the fan receiver and remote broadcast over Bluetooth. Diagnostics only — it does not control the fan.")
            }
        }
        .navigationTitle("Setup")
    }

    private func use(_ address: String) {
        controller.host = address.trimmingCharacters(in: .whitespaces)
        dismiss()
    }

    private func scan() async {
        isScanning = true
        defer { isScanning = false }
        found = await FanDiscovery.scan()
    }
}
