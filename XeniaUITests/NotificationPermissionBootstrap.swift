//
//  NotificationPermissionBootstrap.swift
//  XeniaUITests
//
//  `xcrun simctl privacy` can grant location (including "Always"), but there is
//  no equivalent for notifications — that alert has to be tapped. This test taps
//  it, once, so the location-driven suite in `ArrivalRemindersLocationTests` has
//  a simulator where reminders can actually be scheduled.
//
//  Notification and location grants persist on a simulator until the app is
//  deleted or the device is erased, so this only needs to run when a simulator
//  is fresh. `scripts/test-location-notifications.sh` runs it first every time.
//

import XCTest

final class NotificationPermissionBootstrap: XCTestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// System alerts are flaky through `addUIInterruptionMonitor` alone, so also
    /// reach into SpringBoard and tap whatever permission alert is up.
    @discardableResult
    private func tapSystemAlert(timeout: TimeInterval = 8) -> Bool {
        let labels = [
            "Allow",                    // notifications
            "Allow While Using App",    // location, when-in-use
            "Change to Always Allow",   // location, escalated to always
            "Keep While Using",
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let button = springboard.buttons[label]
                if button.exists, button.isHittable {
                    button.tap()
                    return true
                }
            }
            usleep(300_000)
        }
        return false
    }

    @MainActor
    func testGrantNotificationAndLocationPermissions() throws {
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for label in ["Allow", "Allow While Using App", "Change to Always Allow"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }

        let app = XCUIApplication()
        app.launch()
        sleep(2)

        // A fresh install opens on the tutorial; Skip always works.
        let skip = app.buttons["Skip"].firstMatch
        if skip.waitForExistence(timeout: 6) {
            skip.tap()
            sleep(1)
        }

        let settingsTab = app.buttons["SETTINGS"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10),
                      "should land on the main app with its tab bar")
        settingsTab.tap()
        sleep(1)

        let toggle = app.buttons["Suggest a tip when I arrive"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8),
                      "the arrival-reminder switch should be on the Settings screen")

        // Already on from an earlier bootstrap? Nothing to grant.
        let trigger = app.staticTexts["Trigger distance"].firstMatch
        if !trigger.exists {
            toggle.tap()
            // Notifications are asked for first, then location.
            tapSystemAlert()
            sleep(1)
            tapSystemAlert()
            sleep(1)
            tapSystemAlert()   // the "Always" escalation, if it comes separately
            sleep(2)
        }

        XCTAssertTrue(app.staticTexts["Trigger distance"].waitForExistence(timeout: 8),
                      "reminders should be switched on after the grants")

        // The Settings screen calls out any missing permission — the bootstrap
        // has only really worked if there's nothing left to complain about.
        let complaints = [
            "Location is off for Xenia. Turn it on and set it to \u{201C}Always\u{201D} so reminders work in the background.",
            "Notifications are off for Xenia, so reminders can't come through.",
        ]
        for complaint in complaints {
            XCTAssertFalse(
                app.staticTexts[complaint].exists,
                "permission not granted — the location suite will not be able to schedule anything: \(complaint)"
            )
        }

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "permissions-granted"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
