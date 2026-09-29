//
//  TabBarPing.swift
//  Xenia
//
//  Lets a deep view (the calculator) flash a short amber marker over one or more
//  tabs in the custom tab bar — used to confirm "saved to Places" / "saved to
//  History" right where the user would go to look.
//

import SwiftUI

@Observable
final class TabBarPing {
    /// Tabs currently showing their confirmation marker.
    private(set) var pinged: Set<AppTab> = []

    private var generation: [AppTab: Int] = [:]

    /// Whether `tab`'s marker is lit right now.
    func isLit(_ tab: AppTab) -> Bool { pinged.contains(tab) }

    /// Light up `tab`'s marker, then clear it after a beat. Independent per tab,
    /// so pinging Places and History back to back lights both. Call from an
    /// action, never synchronously during a view's body.
    func ping(_ tab: AppTab) {
        pinged.insert(tab)
        let mine = (generation[tab] ?? 0) + 1
        generation[tab] = mine
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if generation[tab] == mine { pinged.remove(tab) }
        }
    }
}
