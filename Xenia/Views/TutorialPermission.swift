//
//  TutorialPermission.swift
//  Xenia
//
//  The ask-in-place half of a permission page: current state, the button that
//  triggers the real iOS prompt, and a way out to iOS Settings once the answer
//  is no. The reason lives on the page around it, so the system alert lands with
//  its explanation already on screen.
//
//  It drives the same paths the rest of the app uses — `LocationManager.refresh()`
//  and `ArrivalReminders.isEnabled` — so nothing here is a tutorial-only shortcut
//  that could drift from what Settings does.
//

import SwiftUI
import CoreLocation
import UserNotifications
import UIKit

struct TutorialPermissionPanel: View {
    let step: PermissionStep

    @Environment(LocationManager.self) private var location
    @Environment(ArrivalReminders.self) private var reminders

    /// `ArrivalReminders.isEnabled` is computed straight off `UserDefaults`, so
    /// `@Observable` can't see it change — the same reason `SettingsView` keeps
    /// its own copy. Without this the panel would keep offering the button after
    /// a tap that granted nothing new (everything already allowed on a replay).
    @State private var didAsk = false

    /// What the panel should be showing right now.
    private enum Stance {
        /// Not asked yet — offer the button.
        case ask
        /// Everything this step needs has been granted.
        case granted
        /// Asked, and got part of it (location on, "Always" or notifications not).
        case partial
        /// iOS has it switched off for Xenia; only Settings can undo that.
        case denied
    }

    var body: some View {
        Panel {
            switch stance {
            case .granted:
                grantedRow
            case .ask:
                askButton
            case .partial:
                grantedRow
                HairRule()
                note(step.partialNote)
                settingsButton
            case .denied:
                note(step.deniedNote)
                settingsButton
            }
        }
    }

    // MARK: - Pieces

    private var grantedRow: some View {
        HStack(spacing: Grid.x3) {
            MarkerBox(isOn: true)
            Text(step.grantedTitle)
                .font(.bodyText)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var askButton: some View {
        Button(step.actionTitle) { request() }
            .buttonStyle(FilledButtonStyle())
    }

    private var settingsButton: some View {
        Button("Open iOS Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        .buttonStyle(GhostButtonStyle())
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.noteText)
            .foregroundStyle(Palette.inkDim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - State

    private var stance: Stance {
        switch step {
        case .locationWhenInUse:
            switch location.authorizationStatus {
            case .notDetermined:
                return .ask
            case .authorizedWhenInUse, .authorizedAlways:
                return .granted
            default:
                return .denied
            }

        case .locationAlways:
            // Nothing has been asked for until the feature itself is switched on.
            guard reminders.isEnabled || didAsk else { return .ask }
            if reminders.locationStatus == .denied || reminders.locationStatus == .restricted {
                return .denied
            }
            if reminders.notificationStatus == .denied { return .denied }
            // "Always" is the part iOS most often defers, so granted-but-not-yet
            // -Always is its own state rather than a failure.
            return reminders.isFullyAuthorized ? .granted : .partial
        }
    }

    private func request() {
        didAsk = true
        switch step {
        case .locationWhenInUse:
            // `refresh()` asks when the status is undetermined and takes a fix
            // once it isn't — the same call the calculator relies on.
            location.refresh()
        case .locationAlways:
            // Turning the feature on is what asks: this requests notifications,
            // and escalates location to "Always" from "While Using".
            reminders.isEnabled = true
            reminders.start()
        }
    }
}
