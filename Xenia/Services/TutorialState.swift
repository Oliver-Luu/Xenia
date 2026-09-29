//
//  TutorialState.swift
//  Xenia
//
//  Whether the first-run walkthrough still needs showing, and the switch that
//  presents it. Backed by `UserDefaults` and injected as an `@Observable` so the
//  Settings replay button and the root cover stay in step.
//

import Foundation

@Observable
final class TutorialState {

    static let shared = TutorialState()

    private enum Key {
        static let seenVersion = "tutorialSeenVersion"
    }

    /// UI tests that drive the app itself launch with `-skipTutorial` so the
    /// first-run cover doesn't sit over everything they're trying to tap.
    private static var isSuppressed: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipTutorial")
    }

    /// The highest `TutorialScript.version` this user has been through. `0` means
    /// they have never seen it. Storing the version rather than a bool means a
    /// rewritten tutorial can be shown again by bumping the script version.
    private(set) var seenVersion: Int

    /// Drives the full-screen cover on `RootView`.
    var isPresented = false

    private init() {
        seenVersion = UserDefaults.standard.integer(forKey: Key.seenVersion)
    }

    var hasSeenCurrentVersion: Bool { seenVersion >= TutorialScript.version }

    /// First-launch entry point. Does nothing once the user has been offered the
    /// current script.
    func presentIfUnseen() {
        guard !Self.isSuppressed, !hasSeenCurrentVersion else { return }
        isPresented = true
    }

    /// The Settings button: always shows, whatever has been seen before.
    func replay() {
        isPresented = true
    }

    /// Called when the tutorial closes — finished or skipped. Either way the user
    /// has now been offered it and shouldn't be interrupted by it again.
    func markSeen() {
        guard !hasSeenCurrentVersion else { return }
        seenVersion = TutorialScript.version
        UserDefaults.standard.set(seenVersion, forKey: Key.seenVersion)
    }
}
