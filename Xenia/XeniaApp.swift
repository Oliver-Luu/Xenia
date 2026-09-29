//
//  XeniaApp.swift
//  Xenia
//
//  Created by Oliver Luu on 8/31/26.
//

import SwiftUI
import SwiftData

@main
struct XeniaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Persistence.container)
    }
}

/// Runs on every launch — including the background relaunches CoreLocation
/// triggers when you cross a monitored region — so the arrival monitor is wired
/// up even when there's no UI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = Persistence.container
        ArrivalReminders.shared.start()
        return true
    }
}
