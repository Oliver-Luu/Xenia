//
//  ArrivalLiveGeofenceTests.swift
//  XeniaTests
//
//  The one thing the rest of the suite can't do: cross a geofence for real.
//  Every other test calls the delegate methods directly, which proves the app
//  reacts correctly to a location event but not that iOS ever sends one.
//
//  These three run either side of a simulated drive:
//
//    1. seedAPlaceAndRegisterItsGeofence      — leaves a place in the store
//       …  scripts/test-location-notifications.sh walks `simctl location`
//          from outside the fence to inside it  …
//    2. theReminderArrivedAfterTheRealCrossing — the notification landed
//    3. removeTheSeededPlace                   — tidy up
//
//  They're skipped unless the app's `xeniaLiveGeofence` default is set, since on
//  their own — without the drive in between — they mean nothing. The script sets
//  it from outside the simulator with `simctl spawn <dev> defaults write`; an
//  environment variable would not do, because xcodebuild's TEST_RUNNER_ prefix
//  passes variables to a UI test runner, not to the app hosting a unit test.
//  Run them with:
//
//      scripts/test-location-notifications.sh --live
//

import Testing
import Foundation
import CoreLocation
import UserNotifications
import SwiftData
@testable import Xenia

@MainActor
@Suite(.serialized, .enabled(if: UserDefaults.standard.bool(forKey: "xeniaLiveGeofence"),
                             "live geofence drive — run scripts/test-location-notifications.sh --live"))
struct ArrivalLiveGeofenceTests {

    /// Matches the coordinate the script drives to.
    private static let target = CLLocationCoordinate2D(latitude: 37.33182, longitude: -122.03118)
    private static let placeIDKey = "xeniaLiveGeofencePlaceID"
    private static let placeName = "Live Geofence Diner"

    private var reminders: ArrivalReminders { .shared }

    @Test func seedAPlaceAndRegisterItsGeofence() async throws {
        try #require(reminders.notificationStatus == .authorized || {
            reminders.start(); return true
        }())

        let context = Persistence.container.mainContext
        // Clear anything a previous run left behind.
        try removeSeededPlace(in: context)

        let category = TipCategory(name: "Live Geofence")
        // The shortest timing the UI offers; the 45 s minimum dwell still applies,
        // so the reminder is due about a minute after the crossing.
        category.arrivalReminderMinutes = 1
        let place = Restaurant(name: Self.placeName, coordinate: Self.target, category: category)
        place.visitCount = 1
        context.insert(category)
        context.insert(place)
        try context.save()

        UserDefaults.standard.set(place.uuid.uuidString, forKey: Self.placeIDKey)
        // The widest fence the app allows — a simulated jump is easier to catch.
        reminders.triggerRadiusMeters = ArrivalReminders.radiusRange.upperBound
        reminders.isEnabled = true

        // The fence has to be live with CoreLocation before the drive starts,
        // or the crossing has nothing to trigger.
        let deadline = Date().addingTimeInterval(5)
        var registered = false
        while !registered, Date() < deadline {
            registered = CLLocationManager().monitoredRegions
                .contains { $0.identifier == place.uuid.uuidString }
            if !registered { try? await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(registered, "the seeded place's geofence should be registered with CoreLocation")

        // Nothing should be queued yet — the crossing hasn't happened.
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        #expect(!pending.contains { $0.identifier == "arrival-" + place.uuid.uuidString })
    }

    @Test func theReminderArrivedAfterTheRealCrossing() async throws {
        let id = try #require(
            UserDefaults.standard.string(forKey: Self.placeIDKey),
            "no seeded place — run the seed step first"
        )
        let notificationID = "arrival-" + id

        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let match = delivered.first { $0.request.identifier == notificationID }

        #expect(
            match != nil,
            """
            No arrival reminder was delivered after the simulated drive into the \
            geofence. Either CoreLocation never reported the region entry, or the \
            reminder was scheduled and never fired.
            """
        )
        if let match {
            #expect(match.request.content.title == "At \(Self.placeName)?")
            #expect(match.request.content.userInfo["restaurant"] as? String == id)
        }
    }

    @Test func removeTheSeededPlace() throws {
        try removeSeededPlace(in: Persistence.container.mainContext)
        UserDefaults.standard.removeObject(forKey: Self.placeIDKey)
        if let id = UserDefaults.standard.string(forKey: Self.placeIDKey) {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: ["arrival-" + id])
        }
    }

    private func removeSeededPlace(in context: ModelContext) throws {
        let name = Self.placeName
        for place in try context.fetch(
            FetchDescriptor<Restaurant>(predicate: #Predicate { $0.name == name })
        ) {
            context.delete(place)
        }
        let categoryName = "Live Geofence"
        for category in try context.fetch(
            FetchDescriptor<TipCategory>(predicate: #Predicate { $0.name == categoryName })
        ) {
            context.delete(category)
        }
        try context.save()
    }
}
