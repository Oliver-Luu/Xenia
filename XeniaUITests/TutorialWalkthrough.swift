//
//  TutorialWalkthrough.swift
//  XeniaUITests
//
//  Walks the first-run tutorial end to end — including the practice tip — and
//  captures each page as a test attachment, so the whole script can be reviewed
//  without a device. Also checks the two things that are easy to break when the
//  script is edited: a required goal really does gate "Next", and finishing the
//  tutorial leaves the user on the real tip screen.
//
//  Pull the shots with:
//    xcrun xcresulttool export attachments --path <result.xcresult> --output-path <dir>
//

import XCTest

final class TutorialWalkthrough: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTutorial() throws {
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for label in ["Allow While Using App", "Allow", "Don’t Allow", "OK"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }

        let app = XCUIApplication()
        app.launch()
        sleep(2)

        let next = app.buttons["Next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 8),
                      "the tutorial should present itself on a first launch")
        snap("01-welcome")

        // Pages 2 and 3: the feature tours.
        next.tap(); sleep(1); snap("02-categories")
        next.tap(); sleep(1); snap("03-places")

        // Page 4: the practice bill. Next is gated until a bill is entered.
        next.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["The Blue Fig"].waitForExistence(timeout: 5),
                      "the practice calculator should appear on the first practice page")
        snap("04-practice-bill-locked")
        XCTAssertFalse(next.isEnabled,
                       "a required goal should hold Next until it's done")

        // Opening the number pad must neither hide the bill field nor trap the
        // user: the field scrolls clear of the keyboard and an explicit Done
        // dismisses it (the pad has no return key).
        let billField = app.textFields["0.00"].firstMatch
        XCTAssertTrue(billField.waitForExistence(timeout: 3), "the practice bill field")
        billField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "tapping the bill well should raise the number pad")
        sleep(1)
        snap("04b-practice-bill-keyboard")
        XCTAssertTrue(billField.isHittable,
                      "the bill field must stay clear of the keyboard while typing")

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 2),
                      "a Done button must offer a way out of the number pad")
        done.tap()
        sleep(1)

        let useSuggested = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Use '")
        ).firstMatch
        XCTAssertTrue(useSuggested.waitForExistence(timeout: 3),
                      "the practice bill should offer its suggested amount")
        useSuggested.tap()
        sleep(1)
        snap("05-practice-bill-filled")
        XCTAssertTrue(next.isEnabled, "entering a bill should unlock Next")

        // Page 5: ratings. Gated until a track moves off neutral.
        next.tap()
        sleep(1)
        // `.textCase(.uppercase)` only changes how a section label draws — the
        // accessibility string keeps the original casing.
        XCTAssertTrue(app.staticTexts["How was it"].waitForExistence(timeout: 5),
                      "the ratings panel should unlock on the ratings page")
        snap("06-practice-ratings-locked")
        XCTAssertFalse(next.isEnabled)

        // Top of the first rating's 1...5 track.
        let topMark = app.buttons["Set to 5"].firstMatch
        XCTAssertTrue(topMark.waitForExistence(timeout: 3))
        topMark.tap()
        sleep(1)
        snap("07-practice-ratings-scored")
        XCTAssertTrue(next.isEnabled, "scoring a rating should unlock Next")

        // Page 6: adjustments — offered, not required.
        next.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Adjustments"].waitForExistence(timeout: 5),
                      "the adjustments panel should unlock on the adjustments page")
        XCTAssertFalse(app.staticTexts["How was it"].exists,
                       "the ratings panel is hidden on the adjustments page")
        XCTAssertTrue(next.isEnabled, "an optional goal must not gate Next")
        let rule = app.staticTexts["Server went above and beyond"].firstMatch
        if rule.waitForExistence(timeout: 3) {
            rule.tap()
            sleep(1)
        }
        snap("08-practice-adjustments")

        // Page 7: the full readout, with the ledger of everything applied.
        next.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Total"].waitForExistence(timeout: 5),
                      "the readout ledger should unlock on the readout page")
        snap("09-practice-readout")

        // The permission pages explain themselves and ask in place. Neither may
        // gate Next — a declined permission must not trap anyone in the tutorial.
        next.tap()
        sleep(1)
        let allowWhileUsing = app.buttons["Allow while using Xenia"].firstMatch
        XCTAssertTrue(allowWhileUsing.waitForExistence(timeout: 5),
                      "the while-using page should offer the request in place")
        XCTAssertTrue(next.isEnabled, "a permission page must never gate Next")
        snap("10-permission-while-using")
        allowWhileUsing.tap()
        sleep(2)
        app.staticTexts["Permission"].firstMatch.tap()  // nudge the interruption monitor
        sleep(1)
        snap("11-permission-while-using-answered")

        next.tap()
        sleep(1)
        let turnOnReminders = app.buttons["Turn on arrival reminders"].firstMatch
        XCTAssertTrue(turnOnReminders.waitForExistence(timeout: 5),
                      "the always page should offer to turn reminders on")
        XCTAssertTrue(next.isEnabled, "a permission page must never gate Next")
        snap("12-permission-always")
        turnOnReminders.tap()
        sleep(2)
        app.staticTexts["Permission"].firstMatch.tap()  // nudge the interruption monitor
        sleep(2)
        snap("13-permission-always-answered")

        // Walk out whatever pages remain after the permissions.
        var guardrail = 0
        while next.exists, next.isEnabled, guardrail < 12 {
            next.tap()
            sleep(1)
            guardrail += 1
            snap("14-page-\(guardrail + 13)")
        }

        // The last page's button finishes rather than advancing.
        let finish = app.buttons["Start tipping"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 5),
                      "the final page should offer to finish")
        finish.tap()
        sleep(2)
        snap("15-app-after-tutorial")
        XCTAssertTrue(app.buttons["Choose a place"].firstMatch.waitForExistence(timeout: 5),
                      "finishing should land on the real tip screen")

        // And it should stay gone: Settings offers it again on demand.
        app.buttons["SETTINGS"].firstMatch.tap()
        sleep(1)
        let replay = app.buttons["Replay the tutorial"].firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout: 5),
                      "Settings should offer a replay")
        app.swipeUp()
        sleep(1)
        snap("16-settings-replay")
        replay.tap()
        sleep(2)
        XCTAssertTrue(app.buttons["Next"].firstMatch.waitForExistence(timeout: 5),
                      "the replay button should bring the tutorial back")
        snap("17-replayed")
    }
}
