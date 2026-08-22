import ModernFormsKit
import SwiftUI

/// The four things the physical remote does, and nothing else.
struct ControlView: View {
    @Bindable var controller: FanController
    /// Held locally while dragging so the fan is only told the final value.
    @State private var draggingBrightness: Double?

    var body: some View {
        Form {
            if let state = controller.state {
                lightSection(state)
                fanSection(state)
                if state.supportsBreeze {
                    breezeSection(state)
                }
            } else if controller.host.isEmpty {
                ContentUnavailableView {
                    Label("No fan yet", systemImage: "fan")
                } description: {
                    Text("Point the app at the fan on your Wi-Fi network.")
                } actions: {
                    NavigationLink("Choose a fan", destination: SetupView(controller: controller))
                }
            } else {
                ContentUnavailableView(
                    "Connecting",
                    systemImage: "wifi",
                    description: Text(controller.host)
                )
            }

            if let errorMessage = controller.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Room Fan")
        .toolbar {
            NavigationLink("Settings", destination: SetupView(controller: controller))
        }
        .task { await controller.pollWhileVisible() }
    }

    private func lightSection(_ state: FanState) -> some View {
        Section("Light") {
            Toggle("Light", isOn: binding(state.lightOn) { isOn in
                await controller.send(.light(on: isOn)) { $0.lightOn = isOn }
            })

            LabeledContent("Brightness") {
                Slider(
                    value: Binding(
                        get: { draggingBrightness ?? Double(state.brightness) },
                        set: { draggingBrightness = $0 }
                    ),
                    in: Double(FanLimits.brightness.lowerBound)...Double(FanLimits.brightness.upperBound),
                    step: 1
                ) { isDragging in
                    guard !isDragging, let value = draggingBrightness.map({ Int($0) }) else { return }
                    draggingBrightness = nil
                    Task {
                        await controller.send(.brightness(value)) {
                            $0.brightness = value
                            $0.lightOn = true
                        }
                    }
                }
            }
            .disabled(!state.lightOn)
        }
    }

    private func fanSection(_ state: FanState) -> some View {
        Section("Fan") {
            Toggle("Fan", isOn: binding(state.fanOn) { isOn in
                await controller.send(.fan(on: isOn)) { $0.fanOn = isOn }
            })

            Picker("Speed", selection: binding(state.fanSpeed) { speed in
                await controller.send(.speed(speed)) {
                    $0.fanSpeed = speed
                    $0.fanOn = true
                }
            }) {
                ForEach(FanLimits.speed, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Direction", selection: binding(state.direction) { direction in
                await controller.send(.direction(direction)) { $0.direction = direction }
            }) {
                Text("Summer").tag(FanDirection.forward)
                Text("Winter").tag(FanDirection.reverse)
            }
            .pickerStyle(.segmented)
        }
    }

    private func breezeSection(_ state: FanState) -> some View {
        Section("Breeze") {
            Toggle("Breeze Mode", isOn: binding(state.breezeOn ?? false) { isOn in
                await controller.send(.breeze(on: isOn)) { $0.breezeOn = isOn }
            })
        }
    }

    /// Reads from the fan's last known state and writes by sending a command.
    private func binding<Value: Sendable>(
        _ value: Value,
        set: @escaping @MainActor (Value) async -> Void
    ) -> Binding<Value> {
        Binding(get: { value }, set: { newValue in Task { @MainActor in await set(newValue) } })
    }
}
