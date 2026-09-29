//
//  ScreenshotWalkthrough.swift
//  XeniaUITests
//
//  Drives the redesigned UI and captures screenshots as test attachments so the
//  full flow can be reviewed without a device.
//

import XCTest

final class ScreenshotWalkthrough: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// The custom tab bar sits behind the keyboard, so it can't be tapped while a
    /// keyboard is up. Screens with a keyboard toolbar have a "Done"; the plain
    /// search field doesn't, so fall back to a swipe and a tap on the title.
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.waitForExistence(timeout: 1) else { return }
        for key in ["Done", "return", "Return", "Search", "Go", "Enter"] where app.keyboards.buttons[key].exists {
            app.keyboards.buttons[key].tap()
            break
        }
        usleep(400_000)
        if app.keyboards.firstMatch.exists {
            // Tap high on the screen, well clear of both the keyboard and any row.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.11)).tap()
        }
        usleep(400_000)
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testWalkthrough() throws {
        // Dismiss the system permission prompts (location, "always", notifications).
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for label in ["Allow While Using App", "Change to Always Allow", "Allow",
                          "Don’t Allow", "OK"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }

        let app = XCUIApplication()
        // This test drives the app, not the first-run walkthrough — keep its
        // full-screen cover out of the way. `TutorialWalkthrough` covers that.
        app.launchArguments += ["-skipTutorial"]
        app.launch()
        sleep(2)
        if app.staticTexts["Xenia"].exists { app.staticTexts["Xenia"].tap() }  // nudge the interruption monitor
        sleep(1)
        snap("01-calculator-empty")

        // Open the place picker.
        let chooseBtn = app.buttons["Choose a place"].firstMatch
        XCTAssertTrue(chooseBtn.waitForExistence(timeout: 3))
        chooseBtn.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 5),
                      "place picker sheet should present")
        sleep(1)
        snap("02-place-picker")

        // Type a name in the picker's search box, then fall back to a bare
        // category — the typed name should carry through, not be asked for twice.
        let search = app.textFields["Search by name"]
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Corner Diner")
            sleep(1)
        }
        let sitDown = app.buttons["Sit-Down Restaurant"].firstMatch
        XCTAssertTrue(sitDown.waitForExistence(timeout: 3))
        sitDown.tap()
        _ = app.staticTexts["HOW WAS IT"].waitForExistence(timeout: 5)
        sleep(1)

        // A category-only place shows an optional "name this place" field up top,
        // pre-filled from the picker search. Typing a name there means Finish can
        // save it without a trip through the editor — and it must not be mistaken
        // for the bill field.
        let looseNameField = app.textFields["Name this place (optional)"]
        XCTAssertTrue(looseNameField.waitForExistence(timeout: 3),
                      "a category-only place should offer to name itself")
        XCTAssertEqual(looseNameField.value as? String, "Corner Diner",
                       "the picker's search text should pre-fill the place name")

        // Enter a bill. Target the bill well by its placeholder, not firstMatch —
        // the loose-name field sits above it.
        let billField = app.textFields["0.00"]
        if billField.waitForExistence(timeout: 3) {
            billField.tap()
            // Auto-decimal is on by default — digits fill in from the right, no ".".
            billField.typeText("8640")
            // The tab bar must stay pinned to the bottom, not ride up with the keyboard.
            snap("03a-bill-keyboard")
            let rulesTab = app.buttons["RULES"].firstMatch
            let windowBottom = app.windows.firstMatch.frame.maxY
            XCTAssertTrue(!rulesTab.exists || rulesTab.frame.minY >= windowBottom - 140,
                          "the tab bar should stay at the bottom, not rise with the keyboard")
            if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        }
        sleep(1)

        // Hold the split "+" — it should auto-repeat and race past several values,
        // not step once like a tap.
        let splitPlus = app.buttons["plus"].firstMatch
        if splitPlus.waitForExistence(timeout: 2) {
            splitPlus.press(forDuration: 2.0)
            sleep(1)
            XCTAssertFalse(app.staticTexts["1 way"].exists,
                           "holding + should advance the split well past 1")
            let readout = app.staticTexts.matching(
                NSPredicate(format: "label ENDSWITH ' ways'")
            ).firstMatch
            if readout.exists {
                let count = Int(readout.label.split(separator: " ").first ?? "0") ?? 0
                XCTAssertGreaterThan(count, 3, "a ~2s hold should auto-repeat, not step once")
            }
        }
        sleep(1)
        snap("03-calculator-filled")

        // Cash tip mode — you set a starting amount in the base-tip field;
        // ratings and adjustments still move the tip from there.
        if app.buttons["Cash"].firstMatch.waitForExistence(timeout: 2) {
            app.buttons["Cash"].firstMatch.tap()
            sleep(1)
            snap("03b-cash-tip")
            app.buttons["Percentage"].firstMatch.tap()
            sleep(1)
        }

        // Score the visit and toggle a rule.
        let stars = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Set to'"))
        if stars.count >= 5 { stars.element(boundBy: 4).tap() }
        sleep(1)
        app.swipeUp()
        sleep(1)
        snap("04-readout")

        XCTAssertTrue(app.buttons["Save to History"].firstMatch.waitForExistence(timeout: 3),
                      "the split save buttons should exist")
        let saveHistory = app.buttons["Save to History"].firstMatch
        var scrolls = 0
        while !saveHistory.isHittable && scrolls < 8 {
            app.staticTexts["TIP"].firstMatch.swipeUp(velocity: .slow)
            usleep(350_000)
            scrolls += 1
        }
        snap("04b-save-buttons")

        // Rounding is a 3-way choice now.
        let roundTotal = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Round the total'")
        ).firstMatch
        if roundTotal.waitForExistence(timeout: 2) {
            roundTotal.tap()
            sleep(1)
            snap("04e-rounding")
        }

        // Finish. This is a category-only place that already has a name (carried
        // over from the picker search), so it can be saved straight away — no
        // second trip through the editor.
        var savedARecord = false
        XCTAssertTrue(app.buttons["Finish"].firstMatch.waitForExistence(timeout: 2))
        app.buttons["Finish"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.alerts["Save this tip?"].waitForExistence(timeout: 3),
                      "Finish on a named category-only place should offer to save it")
        snap("04c-finish-prompt")
        app.alerts.buttons["Save to Places & History"].firstMatch.tap()
        savedARecord = true
        sleep(1)
        snap("04d-after-finish")
        // Back on the calculator, tip cleared for the next table (it may auto-match
        // the place we just saved, since we haven't moved).
        XCTAssertTrue(app.staticTexts["Xenia"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists, "the save flow should be done")
        // Cleared for the next table. Which shape that takes depends on whether
        // the auto-match found anything: with a fix it re-selects the place we
        // just saved and the bill well is back at its empty "0.00" placeholder
        // (the well draws its currency prefix separately, so that's the text
        // field, not one label); with no fix — a simulator with no location —
        // nothing is selected and the calculator collapses to the place block.
        let emptyBill = app.textFields["0.00"].firstMatch
        let noSelection = app.staticTexts["No place selected"].firstMatch
        XCTAssertTrue(emptyBill.waitForExistence(timeout: 3) || noSelection.exists,
                      "the bill resets after saving")

        // Deleting that just-made place from Places must not crash the calculator,
        // which may still be holding it as the selected restaurant.
        app.buttons["PLACES"].firstMatch.tap()
        let dinerRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Corner Diner'")).firstMatch
        if dinerRow.waitForExistence(timeout: 3) {
            dinerRow.swipeLeft()
            sleep(1)
            if app.buttons["Delete"].firstMatch.waitForExistence(timeout: 2) {
                app.buttons["Delete"].firstMatch.tap()   // deletes straight away (undoable via Recently deleted)
                sleep(1)
            }
        }
        app.buttons["TIP"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Xenia"].waitForExistence(timeout: 3),
                      "the calculator survives its selected place being deleted")
        XCTAssertTrue(app.buttons["Choose a place"].firstMatch.waitForExistence(timeout: 3),
                      "with its place gone, the calculator falls back to no selection")

        // Rules tab and a category editor.
        app.buttons["RULES"].firstMatch.tap()
        _ = app.staticTexts["Rules"].waitForExistence(timeout: 3)
        sleep(1)
        snap("05-rules-list")

        // Swipe a row to reveal delete, then back out without deleting.
        let deliveryRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delivery'")).firstMatch
        XCTAssertTrue(deliveryRow.waitForExistence(timeout: 3))
        deliveryRow.swipeLeft()
        sleep(1)
        snap("05b-swipe-revealed")
        XCTAssertFalse(app.staticTexts["Edit category"].exists,
                       "swiping a row must not also open its editor")
        XCTAssertTrue(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 2), "swipe should reveal Delete")
        // Swipe back the other way to dismiss without deleting.
        deliveryRow.swipeRight()
        sleep(1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delivery'")).firstMatch.exists,
                      "dismissing the swipe keeps the row")

        // Leave a row swiped open, switch tabs, come back — it should be closed.
        deliveryRow.swipeLeft()
        sleep(1)
        XCTAssertTrue(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 2))
        app.buttons["TIP"].firstMatch.tap()
        sleep(1)
        app.buttons["RULES"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 1),
                       "a swiped-open row should reset when you leave and return to the tab")

        let cat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sit-Down'")).firstMatch
        XCTAssertTrue(cat.waitForExistence(timeout: 3))
        cat.tap()
        sleep(2)
        snap("06-category-edit")

        // Ratings + rules management.
        app.swipeUp()
        sleep(1)
        snap("06b-ratings-and-rules")

        // Add a custom rating.
        XCTAssertTrue(app.buttons["Add a rating"].firstMatch.waitForExistence(timeout: 2))
        app.buttons["Add a rating"].firstMatch.tap()
        let nameField = app.textFields["e.g. Cleanliness"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "rating editor should open")
        sleep(1)
        nameField.typeText("Cleanliness")
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        sleep(1)
        snap("06c-rating-editor")
        XCTAssertTrue(app.buttons["Save"].firstMatch.waitForExistence(timeout: 2))
        app.buttons["Save"].firstMatch.tap()
        sleep(1)
        snap("06d-rating-added")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cleanliness'")).firstMatch
            .waitForExistence(timeout: 2), "the new rating should appear in the list")

        // Reorder something.
        let moveDown = app.buttons["Move down"].firstMatch
        if moveDown.waitForExistence(timeout: 2) {
            moveDown.tap()
            sleep(1)
        }
        if app.buttons["Cancel"].firstMatch.exists { app.buttons["Cancel"].firstMatch.tap() }
        sleep(1)

        // Places tab.
        app.buttons["PLACES"].firstMatch.tap()
        _ = app.staticTexts["Places"].waitForExistence(timeout: 3)
        sleep(1)
        snap("07-places-empty")

        // Add and save a place (favorited, in a new group).
        XCTAssertTrue(app.buttons["Add"].firstMatch.waitForExistence(timeout: 2))
        app.buttons["Add"].firstMatch.tap()
        let placeName = app.textFields["Place name"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 3))
        sleep(1)
        placeName.tap()
        placeName.typeText("Lucia's")
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        if app.buttons["Pin to the top of Places"].firstMatch.exists {
            app.buttons["Pin to the top of Places"].firstMatch.tap()
        }
        snap("08-place-edit")
        app.buttons["Save"].firstMatch.tap()
        sleep(1)
        snap("08b-places-list")
        XCTAssertTrue(app.staticTexts["Lucia's"].waitForExistence(timeout: 3), "the place should appear in the list")

        // Re-open Lucia's and give it an adjustment that only applies there.
        app.staticTexts["Lucia's"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Adjustments only here"].waitForExistence(timeout: 3),
                      "an existing place should offer per-place adjustments")

        // Per-place arrival-reminder override.
        let remindHere = app.buttons["Don't remind me here"].firstMatch
        for _ in 0..<6 where !remindHere.isHittable {
            app.swipeUp(velocity: .slow)
            usleep(250_000)
        }
        if remindHere.isHittable { remindHere.tap(); usleep(300_000) }
        var addedCustomRule = false
        let addAdjustment = app.buttons["Add an adjustment"].firstMatch
        for _ in 0..<8 where !addAdjustment.isHittable {
            app.swipeUp(velocity: .slow)
            usleep(300_000)
        }
        if addAdjustment.isHittable {
            addAdjustment.tap()
            let ruleTitle = app.textFields["Title"]
            if ruleTitle.waitForExistence(timeout: 3) {
                ruleTitle.tap()
                ruleTitle.typeText("Regulars' thank-you")
                if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
                snap("08e-custom-adjustment")
                app.buttons["Save"].firstMatch.tap()
                sleep(1)
                addedCustomRule = app.staticTexts["Regulars' thank-you"].waitForExistence(timeout: 3)
                XCTAssertTrue(addedCustomRule, "the per-place adjustment should show in the editor")
            }
        }
        snap("08f-place-with-custom")
        if app.buttons["Cancel"].firstMatch.exists { app.buttons["Cancel"].firstMatch.tap() }
        sleep(1)

        // Search.
        let placeSearch = app.textFields["Search places"]
        if placeSearch.waitForExistence(timeout: 2) {
            placeSearch.tap()
            placeSearch.typeText("luc")
            sleep(1)
            snap("08c-places-search")
            if app.buttons["Clear text"].firstMatch.exists { app.buttons["Clear text"].firstMatch.tap() }
        }
        // Dismiss the keyboard — the tab bar sits behind it and isn't tappable while it's up.
        dismissKeyboard(app)

        // History tab.
        app.buttons["HISTORY"].firstMatch.tap()
        _ = app.staticTexts["History"].waitForExistence(timeout: 3)
        sleep(1)
        snap("09-history")

        // Settings tab: arrival reminders + the "start over" actions.
        app.buttons["SETTINGS"].firstMatch.tap()
        let reminderToggle = app.buttons["Suggest a tip when I arrive"].firstMatch
        XCTAssertTrue(reminderToggle.waitForExistence(timeout: 3),
                      "Settings should show the arrival-reminders controls")
        snap("12-settings")

        // Turn reminders on (this prompts for notifications + location).
        reminderToggle.tap()
        sleep(1)
        app.staticTexts["Settings"].firstMatch.tap()  // nudge the interruption monitor
        sleep(1)
        XCTAssertTrue(app.staticTexts["Café / Coffee Shop"].waitForExistence(timeout: 3),
                      "the per-category timing list appears once reminders are on")
        XCTAssertTrue(app.staticTexts["Trigger distance"].exists,
                      "the trigger-distance control appears once reminders are on")
        snap("12b-settings-reminders-on")

        // Scroll to the new display/currency/units/trash sections.
        app.swipeUp()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Tip display defaults"].waitForExistence(timeout: 3),
                      "Settings should carry the tip-display defaults")
        snap("12c-settings-display")

        // Currency picker sheet.
        if app.buttons.matching(NSPredicate(format: "label CONTAINS 'region default' OR label CONTAINS 'USD'")).firstMatch.waitForExistence(timeout: 2) {
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'region default' OR label CONTAINS 'USD'")).firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Follow my region"].waitForExistence(timeout: 3),
                          "the currency picker should open")
            snap("12d-currency")
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }

        // Recently deleted — restore the place we deleted earlier.
        let trashRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Open recently deleted'")
        ).firstMatch
        if trashRow.waitForExistence(timeout: 2) {
            trashRow.tap()
            XCTAssertTrue(app.staticTexts["Recently deleted"].waitForExistence(timeout: 3),
                          "the trash screen should open")
            snap("12e-recently-deleted")
            let dinerTrash = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Corner Diner'")).firstMatch
            if dinerTrash.waitForExistence(timeout: 2) {
                dinerTrash.tap()
                if app.buttons["Restore"].firstMatch.waitForExistence(timeout: 2) {
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Restore'")).firstMatch.exists,
                                  "restoring should ask for confirmation")
                    app.buttons["Restore"].firstMatch.tap()
                }
                sleep(1)
            }
            if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
            sleep(1)
        }

        // Exercise a destructive action's confirmation, then back out.
        var settingsScrolls = 0
        let clearHistory = app.buttons["Reset tip history"].firstMatch
        while !clearHistory.waitForExistence(timeout: 1) && settingsScrolls < 6 {
            app.swipeUp()
            usleep(300_000)
            settingsScrolls += 1
        }
        if clearHistory.exists {
            clearHistory.tap()
            XCTAssertTrue(app.staticTexts["Reset tip history?"].waitForExistence(timeout: 2),
                          "resetting history should ask first")
            snap("12f-settings-confirm")
            app.buttons["Cancel"].firstMatch.tap()
            sleep(1)
        }

        app.buttons["HISTORY"].firstMatch.tap()
        _ = app.staticTexts["History"].waitForExistence(timeout: 3)
        sleep(1)

        // If the calculator's Save button couldn't be reached in the harness,
        // there is nothing to exercise here — the swipe-to-delete path is
        // covered by the Places and Rules assertions above.
        guard savedARecord, app.staticTexts["Total tipped"].waitForExistence(timeout: 3) else { return }

        // Swipe a history row to delete it — no confirmation, it slides away.
        let visitRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Corner Diner'")).firstMatch
        if visitRow.waitForExistence(timeout: 2) {
            visitRow.swipeLeft()
            sleep(1)
            snap("10-history-swipe")
            let del = app.buttons["Delete"].firstMatch
            if del.waitForExistence(timeout: 2) {
                del.tap()
                sleep(1)
                snap("11-history-after-delete")
            }
        }
    }
}
