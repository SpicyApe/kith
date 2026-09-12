// KithApp.swift — entry point.

import Foundation
import SwiftUI

#if DEBUG
/// Launch-argument switches the simulator UI tests use (TESTING.md §1). Debug only, so
/// nothing about them exists in a Release build.
enum UITesting {
    /// `app.launchArguments = ["-uiTesting", "-uiTestingState", "<state>"]`.
    static let isActive: Bool = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// The value after `-uiTestingState`, or nil. Defaults to `fresh` at the call site.
    static let stateName: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uiTestingState"),
              arguments.index(after: flag) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: flag)]
    }()
}
#endif

@main
@MainActor
struct KithApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = KithApp.makeModel()
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

    /// Real Supabase wiring, unless the process was launched by `KithUITests`, in which
    /// case everything is in memory and the file cache lives in a throwaway directory.
    private static func makeModel() -> AppModel {
        #if DEBUG
        if UITesting.isActive {
            let state = FakeKithAPI.State(name: UITesting.stateName)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let store = FileStore(directory: directory)
            if state != .fresh {
                // A returning player has already had the one-time second contacts ask
                // (docs/02 §2); without this the bare pre-prompt would replace the tabs
                // on a simulator whose contacts permission is still undetermined.
                store.save(Timestamp(Date()), key: StoreKey.contactsReasked)
            }
            return AppModel(
                auth: FakeAuth(signedIn: state != .fresh),
                api: FakeKithAPI(state: state),
                store: store
            )
        }
        #endif
        return AppModel()
    }
}
