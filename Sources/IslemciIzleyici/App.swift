import SwiftUI

@main
struct IslemciIzleyiciApp: App {
    @StateObject private var monitor = Monitor()

    init() {
        Dump.runIfRequested()
        LoginItem.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
        } label: {
            Text(monitor.menuTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
