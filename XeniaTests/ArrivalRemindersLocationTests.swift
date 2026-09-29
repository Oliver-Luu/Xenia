//
//  ArrivalRemindersLocationTests.swift
//  XeniaTests
//
//  Location-driven tests for the arrival-reminder notification system. These run
//  in the app process (XeniaTests sets TEST_HOST), so they drive the real
//  `ArrivalReminders.shared` — its CoreLocation delegate callbacks, the real
//  `UNUserNotificationCenter`, the real cooldown in `UserDefaults`, and the real
//  SwiftData store — rather than a stand-in. What's simulated is only the thing
//  a test can't physically do: crossing a geofence and being detected as a visit.
//
//  `XeniaTests.ArrivalRemindersEligibilityTests` already covers the pure math
//  (which places are watched, radius clamping, delay arithmetic). This file
//  covers what happens when a location event actually arrives.
//
//  Requires, on the simulator/device under test:
//    • Location "Always" granted   — `xcrun simctl privacy <dev> grant location-always OliverLuu.Xenia`
//    • Notifications granted       — no simctl equivalent; run the
//      `NotificationPermissionBootstrap` UI test once per simulator.
//  `scripts/test-location-notifications.sh` does both, then runs this suite.
//

import Testing
import Foundation
import CoreLocation
import UserNotifications
import SwiftData
@testable import Xenia

/// A `CLVisit` the test can build. CoreLocation never vends one publicly, and
/// visit detection can't be provoked in a simulator, so we subclass and override
/// the four properties `handleVisit` reads.
private final class StubVisit: CLVisit {
    private let stubCoordinate: CLLocationCoordinate2D
    private let stubArrival: Date
    private let stubDeparture: Date
    private let stubAccuracy: CLLocationDistance

    init(
        coordinate: CLLocationCoordinate2D,
        arrival: Date,
        departure: Date,
        accuracy: CLLocationDistance
    ) {
        stubCoordinate = coordinate
        stubArrival = arrival
        stubDeparture = departure
        stubAccuracy = accuracy
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var coordinate: CLLocationCoordinate2D { stubCoordinate }
    override var arrivalDate: Date { stubArrival }
    override var departureDate: Date { stubDeparture }
    override var horizontalAccuracy: CLLocationDistance { stubAccuracy }
}

@MainActor
@Suite(.serialized)
struct ArrivalRemindersLocationTests {

    // Mirrors of `ArrivalReminders`' private constants — kept here so the tests
    // observe the same storage the app writes. Update both together.
    private let enabledKey = "arrivalRemindersEnabled"
    private let lastFiredKey = "arrivalRemindersLastFired"
    private let notificationPrefix = "arrival-"

    /// Somewhere no real saved place will be, so a visit lands on the fixture and
    /// nothing else in the store.
    private let nowhere = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    private var reminders: ArrivalReminders { .shared }
    private var center: UNUserNotificationCenter { .current() }

    // MARK: - Fixture

    /// Puts one eligible place in the real store with reminders switched on, runs
    /// `body`, then removes the place and restores the reminder defaults.
    private func withPlace(
        named name: String = "Test Diner",
        categoryMinutes: Int = 30,
        overrideOn: Bool? = nil,
        visits: Int = 3,
        at coordinate: CLLocationCoordinate2D? = nil,
        _ body: (Restaurant) async throws -> Void
    ) async throws {
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: enabledKey)
        let previousFired = defaults.object(forKey: lastFiredKey)

        // These tests hand the delegate its own region objects, so they need no
        // real geofences — and must not register any. `start()` (below, to read
        // the live notification settings) would register one per eligible place,
        // and a fixture place deleted afterwards would leave its geofence behind.
        // iOS only allows 20 per app, so leaking one per test eventually wedges
        // the simulator: every later registration fails with
        // kCLErrorDomain 5 (regionMonitoringDenied). Keeping the master switch
        // off across `start()` makes `syncFromStore` return before it monitors.
        defaults.set(false, forKey: enabledKey)
        try await requireNotificationsAuthorized()

        let context = Persistence.container.mainContext
        let category = TipCategory(name: "Fixture \(UUID().uuidString)")
        category.arrivalReminderMinutes = categoryMinutes
        let place = Restaurant(
            name: name,
            coordinate: coordinate ?? nowhere,
            category: category
        )
        place.visitCount = visits
        place.arrivalRemindersOn = overrideOn
        context.insert(category)
        context.insert(place)
        try context.save()

        defaults.set(true, forKey: enabledKey)
        defaults.removeObject(forKey: lastFiredKey)
        await removeAllArrivalNotifications()

        var thrown: Error?
        do { try await body(place) } catch { thrown = error }

        await removeAllArrivalNotifications()
        context.delete(place)
        context.delete(category)
        try? context.save()
        defaults.set(previousEnabled ?? false, forKey: enabledKey)
        if let previousFired {
            defaults.set(previousFired, forKey: lastFiredKey)
        } else {
            defaults.removeObject(forKey: lastFiredKey)
        }

        if let thrown { throw thrown }
    }

    /// The reminder pipeline bails silently without notification permission, so a
    /// missing grant would read as "every scenario passes with no notification".
    private func requireNotificationsAuthorized() async throws {
        reminders.start()  // re-reads the live notification settings
        let deadline = Date().addingTimeInterval(5)
        while reminders.notificationStatus == .notDetermined, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try #require(
            reminders.notificationStatus == .authorized,
            """
            Notifications are not authorized on this simulator, so no reminder can \
            ever be scheduled. Run the NotificationPermissionBootstrap UI test once \
            (or scripts/test-location-notifications.sh, which does it for you).
            """
        )
    }

    // MARK: - Driving location events

    private func region(for place: Restaurant) -> CLCircularRegion {
        CLCircularRegion(
            center: place.coordinate ?? nowhere,
            radius: reminders.triggerRadiusMeters,
            identifier: place.uuid.uuidString
        )
    }

    private func enter(_ place: Restaurant) {
        reminders.locationManager(CLLocationManager(), didEnterRegion: region(for: place))
    }

    private func leave(_ place: Restaurant) {
        reminders.locationManager(CLLocationManager(), didExitRegion: region(for: place))
    }

    private func visit(
        at coordinate: CLLocationCoordinate2D,
        arrivedMinutesAgo: Double,
        departed: Date = .distantFuture,
        accuracy: CLLocationDistance = 20
    ) {
        let visit = StubVisit(
            coordinate: coordinate,
            arrival: Date().addingTimeInterval(-arrivedMinutesAgo * 60),
            departure: departed,
            accuracy: accuracy
        )
        reminders.locationManager(CLLocationManager(), didVisit: visit)
    }

    // MARK: - Observing notifications

    private func pending(for place: Restaurant) async -> UNNotificationRequest? {
        let id = notificationPrefix + place.uuid.uuidString
        return await center.pendingNotificationRequests().first { $0.identifier == id }
    }

    /// Scheduling and cancelling both hop through async callbacks, so poll rather
    /// than sampling once.
    @discardableResult
    private func waitForReminder(
        _ place: Restaurant,
        toExist shouldExist: Bool,
        timeout: TimeInterval = 3
    ) async -> UNNotificationRequest? {
        let deadline = Date().addingTimeInterval(timeout)
        var found = await pending(for: place)
        while (found != nil) != shouldExist, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            found = await pending(for: place)
        }
        return found
    }

    /// For "nothing should happen" assertions: give the pipeline time to have
    /// scheduled something, then confirm it didn't.
    private func expectNoReminderSettles(_ place: Restaurant) async -> Bool {
        try? await Task.sleep(for: .milliseconds(600))
        return await pending(for: place) == nil
    }

    private func removeAllArrivalNotifications() async {
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(notificationPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func delay(of request: UNNotificationRequest) throws -> TimeInterval {
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        return trigger.timeInterval
    }

    // MARK: - Arriving

    @Test func crossingIntoTheGeofenceSchedulesTheCategoryDelay() async throws {
        try await withPlace(categoryMinutes: 30) { place in
            enter(place)

            let request = try #require(
                await waitForReminder(place, toExist: true),
                "entering a saved place's region should schedule its reminder"
            )
            #expect(try delay(of: request) == 30 * 60)
        }
    }

    @Test func theReminderNamesThePlaceAndCarriesItsIDForTheDeepLink() async throws {
        try await withPlace(named: "Bistro Verde", categoryMinutes: 45) { place in
            enter(place)
            let request = try #require(await waitForReminder(place, toExist: true))

            #expect(request.content.title == "At Bistro Verde?")
            #expect(request.content.body == "Open Xenia when you're ready to work out the tip.")
            // The user asked that the tip never be pre-empted in the notification.
            #expect(!request.content.body.contains("%"))
            #expect(request.content.userInfo["restaurant"] as? String == place.uuid.uuidString)
            #expect(request.content.sound == .default)
        }
    }

    @Test func aCafeStyleShortDelayStillClearsTheMinimumDwell() async throws {
        try await withPlace(categoryMinutes: 1) { place in
            enter(place)
            let request = try #require(await waitForReminder(place, toExist: true))
            #expect(try delay(of: request) >= ArrivalReminders.minimumDwell)
        }
    }

    // MARK: - Places that shouldn't nudge

    @Test func aCategoryWithRemindersOffNeverSchedules() async throws {
        try await withPlace(categoryMinutes: 0) { place in
            enter(place)
            #expect(await expectNoReminderSettles(place))
        }
    }

    @Test func aPlaceThatOptedOutNeverSchedules() async throws {
        try await withPlace(categoryMinutes: 30, overrideOn: false) { place in
            enter(place)
            #expect(await expectNoReminderSettles(place))
        }
    }

    @Test func aPlaceThatOptedInUsesTheFallbackWhenItsCategoryIsOff() async throws {
        try await withPlace(categoryMinutes: 0, overrideOn: true) { place in
            enter(place)
            let request = try #require(await waitForReminder(place, toExist: true))
            #expect(try delay(of: request) == Double(ArrivalDefaults.fallbackMinutes) * 60)
        }
    }

    @Test func aRegionForAPlaceThatNoLongerExistsIsIgnored() async throws {
        try await withPlace { _ in
            let ghost = CLCircularRegion(
                center: nowhere,
                radius: 125,
                identifier: UUID().uuidString
            )
            reminders.locationManager(CLLocationManager(), didEnterRegion: ghost)

            try? await Task.sleep(for: .milliseconds(600))
            let ids = await center.pendingNotificationRequests().map(\.identifier)
            #expect(!ids.contains(notificationPrefix + ghost.identifier))
        }
    }

    @Test func remindersStayOffWhileTheMasterSwitchIsOff() async throws {
        try await withPlace(categoryMinutes: 30) { place in
            UserDefaults.standard.set(false, forKey: enabledKey)
            enter(place)
            #expect(await expectNoReminderSettles(place))
            UserDefaults.standard.set(true, forKey: enabledKey)
        }
    }

    // MARK: - Leaving

    @Test func leavingBeforeItFiresCancelsTheReminder() async throws {
        try await withPlace(categoryMinutes: 45) { place in
            enter(place)
            try #require(await waitForReminder(place, toExist: true) != nil)

            leave(place)
            #expect(
                await waitForReminder(place, toExist: false) == nil,
                "walking back out should take the pending nudge with it"
            )
        }
    }

    @Test func aDriveByDoesNotBurnTheCooldownForALaterRealVisit() async throws {
        try await withPlace(categoryMinutes: 45) { place in
            // Clipped the corner of the geofence and kept going.
            enter(place)
            try #require(await waitForReminder(place, toExist: true) != nil)
            leave(place)
            try #require(await waitForReminder(place, toExist: false) == nil)

            // Came back for real a few minutes later — still inside the 3-hour
            // cooldown window, but the drive-by shouldn't have spent it.
            enter(place)
            #expect(
                await waitForReminder(place, toExist: true) != nil,
                "a cancelled drive-by must not suppress the next real arrival"
            )
        }
    }

    @Test func aJitteryExitAndReEntryKeepsTheReminderStanding() async throws {
        try await withPlace(categoryMinutes: 45) { place in
            // Start it from a visit that began 10 minutes ago, so the reminder
            // carries a distinctive 35-minute delay. Surviving the wobble has to
            // mean *this* reminder survived — a cancel followed by a fresh one
            // would look identical at 45 minutes, and would quietly have restarted
            // the countdown the user is already partway through.
            visit(at: nowhere, arrivedMinutesAgo: 10)
            let original = try #require(await waitForReminder(place, toExist: true))
            let originalDelay = try delay(of: original)
            #expect(abs(originalDelay - 35 * 60) < 5)

            // Now stand inside the fence, then wobble across its edge: out and
            // straight back in, before the cancel's async lookup gets to run.
            enter(place)
            leave(place)
            enter(place)

            try? await Task.sleep(for: .milliseconds(800))
            let still = try #require(
                await pending(for: place),
                "an edge-of-fence wobble must not drop the reminder"
            )
            #expect(abs(try delay(of: still) - originalDelay) < 5,
                    "the wobble must not restart a countdown that's already running")
        }
    }

    // MARK: - Cooldown

    @Test func aSecondArrivalWithinTheCooldownDoesNotNudgeAgain() async throws {
        try await withPlace(categoryMinutes: 30) { place in
            enter(place)
            try #require(await waitForReminder(place, toExist: true) != nil)

            // Stand in for the notification having fired: it's no longer pending,
            // but the cooldown it set is still running.
            await removeAllArrivalNotifications()

            enter(place)
            #expect(
                await expectNoReminderSettles(place),
                "a re-entry inside the 3-hour cooldown should stay quiet"
            )
        }
    }

    @Test func anExpiredCooldownAllowsANewNudge() async throws {
        try await withPlace(categoryMinutes: 30) { place in
            enter(place)
            try #require(await waitForReminder(place, toExist: true) != nil)
            await removeAllArrivalNotifications()

            // Wind the last-fired stamp back past the 3-hour window.
            var map = UserDefaults.standard.dictionary(forKey: lastFiredKey) as? [String: Double] ?? [:]
            map[place.uuid.uuidString] = Date()
                .addingTimeInterval(-ArrivalReminders.cooldown - 60)
                .timeIntervalSince1970
            UserDefaults.standard.set(map, forKey: lastFiredKey)

            enter(place)
            #expect(await waitForReminder(place, toExist: true) != nil)
        }
    }

    // MARK: - Visits (the second, slower trigger)

    @Test func aVisitInProgressSchedulesFromWhenYouActuallySatDown() async throws {
        try await withPlace(categoryMinutes: 55) { place in
            // iOS noticed the visit 10 minutes late; 45 of the 55 should remain.
            visit(at: nowhere, arrivedMinutesAgo: 10)

            let request = try #require(
                await waitForReminder(place, toExist: true),
                "a visit at a saved place should schedule the reminder on its own"
            )
            let remaining = try delay(of: request)
            #expect(abs(remaining - 45 * 60) < 5)
        }
    }

    @Test func aVisitThatHasEndedCancelsTheReminder() async throws {
        try await withPlace(categoryMinutes: 55) { place in
            visit(at: nowhere, arrivedMinutesAgo: 10)
            try #require(await waitForReminder(place, toExist: true) != nil)

            // The same visit, now reported with a departure — they've left.
            visit(at: nowhere, arrivedMinutesAgo: 40, departed: Date())
            #expect(await waitForReminder(place, toExist: false) == nil)
        }
    }

    @Test func aLooseVisitStillMatchesWhenItsAccuracyIsWide() async throws {
        try await withPlace(categoryMinutes: 30) { place in
            // ~200 m off the saved point, but the fix is only good to 400 m.
            let offset = CLLocationCoordinate2D(latitude: 0.0018, longitude: 0)
            visit(at: offset, arrivedMinutesAgo: 1, accuracy: 400)
            #expect(await waitForReminder(place, toExist: true) != nil)
        }
    }

    @Test func aVisitSomewhereElseEntirelyIsIgnored() async throws {
        try await withPlace(categoryMinutes: 30) { place in
            // ~5 km away — outside both the radius and the accuracy window.
            let elsewhere = CLLocationCoordinate2D(latitude: 0.045, longitude: 0)
            visit(at: elsewhere, arrivedMinutesAgo: 5, accuracy: 30)
            #expect(await expectNoReminderSettles(place))
        }
    }

    @Test func aVisitWithAnInvalidCoordinateIsIgnored() async throws {
        try await withPlace(categoryMinutes: 30) { place in
            let broken = CLLocationCoordinate2D(latitude: 91, longitude: 181)
            visit(at: broken, arrivedMinutesAgo: 5)
            #expect(await expectNoReminderSettles(place))
        }
    }

    // MARK: - Turning the whole thing off

    @Test func switchingRemindersOffTearsDownWhatWasPending() async throws {
        try await withPlace(categoryMinutes: 45) { place in
            enter(place)
            try #require(await waitForReminder(place, toExist: true) != nil)

            reminders.isEnabled = false
            #expect(
                await waitForReminder(place, toExist: false) == nil,
                "turning reminders off should clear reminders already queued up"
            )

            enter(place)
            #expect(await expectNoReminderSettles(place))
        }
    }
}

// MARK: - Places close enough to share a fence

@MainActor
@Suite(.serialized)
struct OverlappingArrivalRemindersTests {

    // Two saved places close enough that their trigger circles overlap — likely
    // in a city at the 500 m maximum. Only one reminder may be outstanding, so
    // arriving in the shared area nudges once rather than once per fence.

    private let enabledKey = "arrivalRemindersEnabled"
    private let lastFiredKey = "arrivalRemindersLastFired"
    private let notificationPrefix = "arrival-"

    @Test func twoPlacesInTheSameBlockNudgeOnceBetweenThem() async throws {
        let reminders = ArrivalReminders.shared
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: enabledKey)
        let previousFired = defaults.object(forKey: lastFiredKey)

        defaults.set(false, forKey: enabledKey)
        reminders.start()                       // refresh notification status only
        try #require(reminders.notificationStatus == .authorized,
                     "run the NotificationPermissionBootstrap UI test first")

        let context = Persistence.container.mainContext
        let category = TipCategory(name: "Overlap \(UUID().uuidString)")
        category.arrivalReminderMinutes = 30
        context.insert(category)

        // ~30 m apart: well inside one another's trigger radius.
        let cafe = Restaurant(
            name: "Corner Cafe",
            coordinate: CLLocationCoordinate2D(latitude: 37.33182, longitude: -122.03118),
            category: category
        )
        let bar = Restaurant(
            name: "Corner Bar",
            coordinate: CLLocationCoordinate2D(latitude: 37.33209, longitude: -122.03118),
            category: category
        )
        for place in [cafe, bar] {
            place.visitCount = 2
            context.insert(place)
        }
        try context.save()

        defaults.set(true, forKey: enabledKey)
        defaults.removeObject(forKey: lastFiredKey)

        // `ArrivalReminders`' own manager never asks for a fix, so without this
        // `manager.location` is nil and the closest-wins comparison can't run —
        // it would fall back to "whatever is already waiting keeps it" and the
        // interesting branch would go untested. `location` is cached per app, so
        // a fix fetched here is the one it sees.
        await Self.primeLocationFix()

        // Order matters: the simulated position sits on the café, so entering the
        // bar's fence first and the café's second is what makes the second
        // arrival the closer one and forces the swap. Entering the café first
        // would only ever exercise the cheaper "keep what's waiting" branch.
        let center = UNUserNotificationCenter.current()
        for place in [bar, cafe] {
            let region = CLCircularRegion(
                center: place.coordinate!,
                radius: reminders.triggerRadiusMeters,
                identifier: place.uuid.uuidString
            )
            reminders.locationManager(CLLocationManager(), didEnterRegion: region)
        }

        try? await Task.sleep(for: .milliseconds(800))
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let ours = pending.filter {
            $0 == notificationPrefix + cafe.uuid.uuidString
                || $0 == notificationPrefix + bar.uuid.uuidString
        }
        #expect(ours.count == 1,
                "overlapping fences should nudge once between them, not once each")

        // Whichever gave way never fired, so its cooldown must have been refunded
        // — otherwise arriving there properly later would be met with silence.
        // (Only bites when a fix is available to compare distances with; without
        // one the loser is skipped rather than superseded and never marked.)
        let lastFired = UserDefaults.standard.dictionary(forKey: lastFiredKey) as? [String: Double] ?? [:]
        let loser = ours.contains(notificationPrefix + cafe.uuid.uuidString) ? bar : cafe
        #expect(lastFired[loser.uuid.uuidString] == nil,
                "the superseded place shouldn't burn its 3-hour cooldown")

        center.removePendingNotificationRequests(withIdentifiers: [
            notificationPrefix + cafe.uuid.uuidString,
            notificationPrefix + bar.uuid.uuidString,
        ])
        context.delete(cafe)
        context.delete(bar)
        context.delete(category)
        try? context.save()
        defaults.set(previousEnabled ?? false, forKey: enabledKey)
        if let previousFired {
            defaults.set(previousFired, forKey: lastFiredKey)
        } else {
            defaults.removeObject(forKey: lastFiredKey)
        }
    }
    @Test func leavingOneOverlappingFenceHandsTheNudgeToTheOneStillAround() async throws {
        // The cost of "only one reminder at a time": the place that gave way has
        // no pending nudge left, and no fresh entry event is coming for it —
        // you never left its circle. Walking out of the closer fence has to hand
        // the reminder back rather than leaving you with nothing.
        let reminders = ArrivalReminders.shared
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: enabledKey)
        let previousFired = defaults.object(forKey: lastFiredKey)

        defaults.set(false, forKey: enabledKey)
        reminders.start()
        try #require(reminders.notificationStatus == .authorized,
                     "run the NotificationPermissionBootstrap UI test first")

        let context = Persistence.container.mainContext
        let category = TipCategory(name: "Overlap exit \(UUID().uuidString)")
        category.arrivalReminderMinutes = 30
        context.insert(category)

        let outer = Restaurant(
            name: "Outer Place",
            coordinate: CLLocationCoordinate2D(latitude: 37.33182, longitude: -122.03118),
            category: category
        )
        let inner = Restaurant(
            name: "Inner Place",
            coordinate: CLLocationCoordinate2D(latitude: 37.33209, longitude: -122.03118),
            category: category
        )
        for place in [outer, inner] {
            place.visitCount = 2
            context.insert(place)
        }
        try context.save()

        defaults.set(true, forKey: enabledKey)
        defaults.removeObject(forKey: lastFiredKey)

        let center = UNUserNotificationCenter.current()
        func fence(_ place: Restaurant) -> CLCircularRegion {
            CLCircularRegion(
                center: place.coordinate!,
                radius: reminders.triggerRadiusMeters,
                identifier: place.uuid.uuidString
            )
        }
        func ourPending() async -> [String] {
            await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter {
                    $0 == notificationPrefix + outer.uuid.uuidString
                        || $0 == notificationPrefix + inner.uuid.uuidString
                }
        }

        // Into both fences: one reminder between them.
        reminders.locationManager(CLLocationManager(), didEnterRegion: fence(outer))
        reminders.locationManager(CLLocationManager(), didEnterRegion: fence(inner))
        try? await Task.sleep(for: .milliseconds(800))
        let afterArriving = await ourPending()
        #expect(afterArriving.count == 1)

        // Walk out of whichever one is holding it, still inside the other.
        let holder = afterArriving[0] == notificationPrefix + inner.uuid.uuidString ? inner : outer
        let stillInside = holder === inner ? outer : inner
        reminders.locationManager(CLLocationManager(), didExitRegion: fence(holder))

        try? await Task.sleep(for: .milliseconds(1200))
        let afterLeaving = await ourPending()
        #expect(afterLeaving == [notificationPrefix + stillInside.uuid.uuidString],
                "still standing in \(stillInside.name)'s circle — it should hold the nudge now")

        center.removePendingNotificationRequests(withIdentifiers: [
            notificationPrefix + outer.uuid.uuidString,
            notificationPrefix + inner.uuid.uuidString,
        ])
        reminders.locationManager(CLLocationManager(), didExitRegion: fence(stillInside))
        context.delete(outer)
        context.delete(inner)
        context.delete(category)
        try? context.save()
        defaults.set(previousEnabled ?? false, forKey: enabledKey)
        if let previousFired {
            defaults.set(previousFired, forKey: lastFiredKey)
        } else {
            defaults.removeObject(forKey: lastFiredKey)
        }
    }

    /// Asks for one location fix and waits for it to land, so `CLLocationManager
    /// .location` is populated app-wide. Best effort — the tests that use it
    /// still assert something meaningful if no fix arrives.
    static func primeLocationFix() async {
        let prime = LocationManager()
        prime.refresh()
        let deadline = Date().addingTimeInterval(3)
        while prime.currentLocation == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
