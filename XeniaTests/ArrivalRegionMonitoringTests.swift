//
//  ArrivalRegionMonitoringTests.swift
//  XeniaTests
//
//  The other half of location testing: not "what happens when an event arrives"
//  but "did we actually ask CoreLocation to watch the right circles". These run
//  in the app process, so `CLLocationManager.monitoredRegions` reports the real
//  set the app has registered with the system — the same set a background
//  relaunch would fire against.
//
//  `applyRegions` is the fiddliest code in the feature (it diffs what's already
//  monitored against what should be, and CoreLocation doesn't update that set
//  synchronously), so it's worth checking against the real API rather than a
//  stand-in.
//

import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import Xenia

@MainActor
@Suite(.serialized)
struct ArrivalRegionMonitoringTests {

    private let enabledKey = "arrivalRemindersEnabled"
    private let radiusKey = "arrivalRemindersRadiusMeters"

    private var reminders: ArrivalReminders { .shared }

    /// Fixtures are laid out on a line from here. A real coordinate on purpose:
    /// CoreLocation will not monitor a region centred on (0, 0), so a fixture
    /// built around the origin silently never registers.
    private static let baseLatitude = 37.33182
    private static let baseLongitude = -122.03118

    /// Fixture places reuse a fixed set of ids so the geofences they register
    /// are replaced run over run rather than piling up.
    private static func fixtureUUID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
    }

    /// Regions the app currently has registered with CoreLocation. Any manager
    /// instance reports the app-wide set.
    private var monitored: Set<CLCircularRegion> {
        Set(CLLocationManager().monitoredRegions.compactMap { $0 as? CLCircularRegion })
    }

    private func monitoredRegion(for place: Restaurant) -> CLCircularRegion? {
        monitored.first { $0.identifier == place.uuid.uuidString }
    }

    /// `startMonitoring(for:)` lands asynchronously, so poll.
    private func waitForRegion(
        _ place: Restaurant,
        toExist shouldExist: Bool,
        timeout: TimeInterval = 3
    ) async -> CLCircularRegion? {
        let deadline = Date().addingTimeInterval(timeout)
        var found = monitoredRegion(for: place)
        while (found != nil) != shouldExist, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            found = monitoredRegion(for: place)
        }
        return found
    }

    // MARK: - Fixture

    /// Builds `count` places in the real store, runs `body`, then removes them
    /// and stops monitoring. Places are laid out on a line so distance ordering
    /// is predictable; `visitCount` descends so the ordering is deterministic
    /// even when the simulator has no location fix.
    private func withPlaces(
        count: Int,
        categoryMinutes: Int = 30,
        _ body: ([Restaurant]) async throws -> Void
    ) async throws {
        // A geofence left behind by an earlier run is invisible to this one but
        // still counts against the app's 20-region allowance, and once that's
        // used up CoreLocation denies every new registration with
        // kCLErrorDomain 5. Every test below would then fail as though the app
        // were broken, so name the real problem instead.
        let alreadyMonitored = CLLocationManager().monitoredRegions
        try #require(
            alreadyMonitored.isEmpty,
            """
            \(alreadyMonitored.count) geofence(s) were already registered before \
            this test ran, leaked by an earlier run. iOS allows 20 per app and \
            then refuses the rest, which would make these tests fail misleadingly. \
            Erase the simulator and try again: xcrun simctl erase <udid>
            """
        )

        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: enabledKey)
        let previousRadius = defaults.object(forKey: radiusKey)

        let context = Persistence.container.mainContext

        // A previous run that crashed mid-test may have left its fixtures behind.
        let staleIDs = Set((0..<count).map { Self.fixtureUUID($0) })
        for place in (try? context.fetch(FetchDescriptor<Restaurant>())) ?? []
        where staleIDs.contains(place.uuid) {
            context.delete(place)
        }

        let category = TipCategory(name: "Region fixture \(UUID().uuidString)")
        category.arrivalReminderMinutes = categoryMinutes
        context.insert(category)

        // Stable identifiers, not fresh UUIDs. A geofence is keyed by its
        // identifier, so reusing these means each run re-registers the same few
        // circles instead of adding new ones. With random ids the fixtures
        // accumulate across runs until the app hits the 20-region ceiling, after
        // which CoreLocation refuses everything and the suite fails on a
        // simulator that looks clean (see the note on the region limit below).
        let places: [Restaurant] = (0..<count).map { index in
            let place = Restaurant(
                name: "Region fixture \(index)",
                coordinate: CLLocationCoordinate2D(
                    latitude: Self.baseLatitude + Double(index) / 1000,
                    longitude: Self.baseLongitude
                ),
                category: category
            )
            place.uuid = Self.fixtureUUID(index)
            place.visitCount = count - index
            context.insert(place)
            return place
        }
        try context.save()

        defaults.set(true, forKey: enabledKey)

        var thrown: Error?
        do { try await body(places) } catch { thrown = error }

        reminders.isEnabled = false          // stops monitoring everything

        // Belt and braces. `stopMonitoring` matches on identifier, so this
        // reclaims the fixture's slots even if the app's own teardown missed
        // one — a leaked geofence can't be seen or removed by the next run.
        let sweeper = CLLocationManager()
        for place in places {
            sweeper.stopMonitoring(for: CLCircularRegion(
                center: place.coordinate ?? CLLocationCoordinate2D(
                    latitude: Self.baseLatitude, longitude: Self.baseLongitude
                ),
                radius: 100,
                identifier: place.uuid.uuidString
            ))
        }

        for place in places { context.delete(place) }
        context.delete(category)
        try? context.save()
        defaults.set(previousEnabled ?? false, forKey: enabledKey)
        if let previousRadius {
            defaults.set(previousRadius, forKey: radiusKey)
        } else {
            defaults.removeObject(forKey: radiusKey)
        }

        if let thrown { throw thrown }
    }

    // MARK: - Tests

    @Test func everyEligiblePlaceGetsAGeofenceAtTheChosenRadius() async throws {
        try await withPlaces(count: 3) { places in
            reminders.triggerRadiusMeters = 200
            reminders.start()

            for place in places {
                let region = try #require(
                    await waitForRegion(place, toExist: true),
                    "\(place.name) should be monitored"
                )
                #expect(region.radius == 200)
                #expect(abs(region.center.latitude - place.latitude) < 0.000001)
                #expect(abs(region.center.longitude - place.longitude) < 0.000001)
                #expect(region.notifyOnEntry)
                #expect(region.notifyOnExit)
            }
        }
    }

    @Test func aPlaceWithRemindersOffIsNotWatched() async throws {
        try await withPlaces(count: 2, categoryMinutes: 0) { places in
            reminders.start()
            try? await Task.sleep(for: .milliseconds(800))
            for place in places {
                #expect(monitoredRegion(for: place) == nil,
                        "a category with reminders off shouldn't cost a geofence slot")
            }
        }
    }

    @Test func aPlaceYouveNeverTippedAtIsNotWatched() async throws {
        try await withPlaces(count: 2) { places in
            places[0].visitCount = 0
            try Persistence.container.mainContext.save()

            reminders.start()
            #expect(await waitForRegion(places[1], toExist: true) != nil)
            #expect(monitoredRegion(for: places[0]) == nil)
        }
    }

    @Test func changingTheTriggerDistanceRebuildsTheFences() async throws {
        try await withPlaces(count: 2) { places in
            reminders.triggerRadiusMeters = 100
            reminders.start()
            let first = try #require(await waitForRegion(places[0], toExist: true))
            #expect(first.radius == 100)

            // The Settings stepper does exactly this: new radius, then re-monitor.
            reminders.triggerRadiusMeters = 350
            reminders.start()

            // Poll for the radius to actually change — CoreLocation's monitored
            // set doesn't update the moment stopMonitoring returns, which is what
            // makes this easy to get wrong.
            let deadline = Date().addingTimeInterval(3)
            var region = monitoredRegion(for: places[0])
            while region?.radius != 350, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
                region = monitoredRegion(for: places[0])
            }
            #expect(region?.radius == 350,
                    "a radius change must re-create the fence, not silently drop it")
            #expect(monitoredRegion(for: places[1])?.radius == 350)
        }
    }

    // The 20-region cap is deliberately NOT exercised against live CoreLocation
    // here. Registering 21+ fences wedges the simulator permanently: iOS starts
    // refusing registrations with kCLErrorDomain 5, `monitoredRegions` then
    // reports an empty set even though the system is still holding 20, and
    // because both `applyRegions` and `stopMonitoringEverything` iterate that
    // set, nothing can release them again — `stopMonitoring(for:)` by identifier
    // doesn't recover it either. Only erasing the simulator does.
    //
    // The app's actual contract — never ask for more than `maxRegions`, nearest
    // first — is a pure function, covered by
    // `ArrivalRemindersEligibilityTests.keepsTheNearestWhenOverTheRegionLimit`.

    @Test func turningRemindersOffReleasesEveryFence() async throws {
        try await withPlaces(count: 3) { places in
            reminders.start()
            try #require(await waitForRegion(places[0], toExist: true) != nil)

            reminders.isEnabled = false

            for place in places {
                #expect(await waitForRegion(place, toExist: false) == nil,
                        "switching off should hand back the geofence slots")
            }
        }
    }

    @Test func aPlaceThatBecomesIneligibleLosesItsFence() async throws {
        try await withPlaces(count: 2) { places in
            reminders.start()
            try #require(await waitForRegion(places[0], toExist: true) != nil)

            // The user turns reminders off for just this place.
            places[0].arrivalRemindersOn = false
            try Persistence.container.mainContext.save()
            reminders.start()

            #expect(await waitForRegion(places[0], toExist: false) == nil)
            #expect(monitoredRegion(for: places[1]) != nil,
                    "the other places should keep their fences")
        }
    }
}
