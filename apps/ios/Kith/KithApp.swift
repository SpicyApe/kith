// KithApp.swift — entry point.

import Foundation
import SwiftUI

@main
@MainActor
struct KithApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Color.kithAccent)
                .task {
                    await model.bootstrap()
                }
                .onOpenURL { url in
                    model.route(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active, model.stage == .ready else { return }
                    Task { await model.onForeground() }
                }
        }
    }
}
