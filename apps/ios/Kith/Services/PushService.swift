// PushService.swift — notification permission, APNs registration, deep links.
//
// The OS prompt is only ever fired from the pre-prompt screen (docs/02 §7). On a
// free-team sideload `registerForRemoteNotifications` fails with an entitlement
// error; that is reported through `onRegistrationError` and otherwise ignored.

import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushService {
    static let shared = PushService()
    private init() {}

    /// Hex APNs token, set by the app delegate.
    var onToken: ((String) -> Void)?
    /// A tapped notification carrying a `url` key in its payload.
    var onDeepLink: ((URL) -> Void)?
    /// Registration failed (usually a missing `aps-environment` entitlement).
    var onRegistrationError: ((String) -> Void)?

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    var isAuthorized: Bool {
        get async { await authorizationStatus() == .authorized }
    }

    /// Fires the OS prompt and, on grant, asks for an APNs token.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            onRegistrationError?(error.localizedDescription)
            return false
        }
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    /// Re-registers on launch when the user has already granted permission.
    func registerIfAuthorized() async {
        if await isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func handle(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        onToken?(hex)
    }

    func handle(registrationError error: Error) {
        onRegistrationError?(error.localizedDescription)
    }

    func handle(notificationURL string: String?) {
        guard let string, let url = URL(string: string) else { return }
        onDeepLink?(url)
    }
}

/// UIKit hooks SwiftUI does not expose. Attached with `@UIApplicationDelegateAdaptor`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushService.shared.handle(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushService.shared.handle(registrationError: error)
    }

    // The async (completion-handler-free) spellings, so no non-Sendable completion
    // closure escapes. The class is `@MainActor`, so these inherit that isolation and
    // can touch `PushService.shared` (also `@MainActor`) without a hop.

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let link = response.notification.request.content.userInfo["url"] as? String
        PushService.shared.handle(notificationURL: link)
    }
}
