import SwiftUI

@main
struct RoomFanApp: App {
    @State private var controller = FanController()

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller)
        }
    }
}

struct RootView: View {
    @Bindable var controller: FanController

    var body: some View {
        NavigationStack {
            ControlView(controller: controller)
        }
    }
}
