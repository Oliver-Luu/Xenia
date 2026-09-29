//
//  ArrivalReminderHealthTests.swift
//  XeniaTests
//
//  Arrival reminders can be switched on, fully permitted by the coarse checks,
//  and still completely dead — because iOS refused the geofences, or because
//  Precise Location is off and a fuzzed fix can't be tested against a circle.
//  Neither failure announces itself, so the app has to notice and say so.
//
//  The verdict is a pure function on purpose: a simulator can be talked into
//  roughly one of these states, and the combinations that actually strand users
//  are the ones you can't reproduce on demand.
//

import Testing
import Foundation
import CoreLocation
import UserNotifications
@testable import Xenia

struct ArrivalReminderDiagnosisTests {

    private func issue(
        location: CLAuthorizationStatus = .authorizedAlways,
        notifications: UNAuthorizationStatus = .authorized,
        accuracy: CLAccuracyAuthorization = .fullAccuracy,
        monitoringDenied: Bool = false
    ) -> String? {
        ArrivalReminders.permissionIssue(
            location: location,
            notifications: notifications,
            accuracy: accuracy,
            regionMonitoringDenied: monitoringDenied
        )
    }

    @Test func everythingGrantedReportsNothingWrong() {
        #expect(issue() == nil)
    }

    @Test func deniedLocationIsReported() {
        #expect(issue(location: .denied)?.contains("Location is off") == true)
        #expect(issue(location: .restricted)?.contains("Location is off") == true)
    }

    @Test func whileUsingOnlyIsReported() {
        #expect(issue(location: .authorizedWhenInUse)?.contains("While Using") == true)
    }

    @Test func deniedNotificationsAreReported() {
        #expect(issue(notifications: .denied)?.contains("Notifications are off") == true)
    }

    @Test func notDeterminedIsNotYetAProblem() {
        // Nothing has been refused — the tutorial or the toggle is about to ask.
        #expect(issue(location: .notDetermined, notifications: .notDetermined) == nil)
    }

    // MARK: - The two silent failures

    @Test func precisionOffIsReportedEvenThoughEveryPermissionSaysYes() {
        let message = issue(accuracy: .reducedAccuracy)
        #expect(message?.contains("Precise Location") == true,
                "Always + notifications can both be granted while geofences still can't work")
    }

    @Test func aRefusedGeofenceIsReported() {
        let message = issue(monitoringDenied: true)
        #expect(message?.contains("wouldn't let Xenia watch") == true,
                "a refusal from CoreLocation leaves no other trace for the user to find")
    }

    @Test func theFixableThingIsNamedFirst() {
        // Reduced accuracy is the likely cause of the refusal, so say that rather
        // than describing the symptom.
        #expect(issue(accuracy: .reducedAccuracy, monitoringDenied: true)?
            .contains("Precise Location") == true)
        // And a permission that's outright off outranks both.
        #expect(issue(location: .denied, accuracy: .reducedAccuracy, monitoringDenied: true)?
            .contains("Location is off") == true)
    }
}

// MARK: - Reacting to CoreLocation refusing a region

@MainActor
@Suite(.serialized)
struct RegionMonitoringFailureTests {

    private var reminders: ArrivalReminders { .shared }

    private func region() -> CLCircularRegion {
        CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 37.33182, longitude: -122.03118),
            radius: 125,
            identifier: UUID().uuidString
        )
    }

    /// Leaves the shared singleton as it was found — a stuck flag here would show
    /// up as a phantom warning on the Settings screen in every later test.
    private func withCleanFlag(_ body: () throws -> Void) rethrows {
        defer {
            reminders.locationManager(CLLocationManager(), didStartMonitoringFor: region())
        }
        try body()
    }

    @Test func aRefusedRegionIsRecordedAndExplained() throws {
        try withCleanFlag {
            #expect(!reminders.regionMonitoringDenied)

            reminders.locationManager(
                CLLocationManager(),
                monitoringDidFailFor: region(),
                withError: CLError(.regionMonitoringDenied)
            )

            #expect(reminders.regionMonitoringDenied)
            #expect(reminders.permissionIssue != nil,
                    "a refusal has to reach the user — nothing else would tell them")
        }
    }

    @Test func aTransientFailureIsNotTreatedAsAStandingProblem() throws {
        try withCleanFlag {
            reminders.locationManager(
                CLLocationManager(),
                monitoringDidFailFor: region(),
                withError: CLError(.network)
            )
            #expect(!reminders.regionMonitoringDenied,
                    "the next syncFromStore retries these; don't nag about them")
        }
    }

    @Test func aRegionGettingThroughClearsTheWarning() throws {
        reminders.locationManager(
            CLLocationManager(),
            monitoringDidFailFor: region(),
            withError: CLError(.regionMonitoringDenied)
        )
        #expect(reminders.regionMonitoringDenied)

        reminders.locationManager(CLLocationManager(), didStartMonitoringFor: region())
        #expect(!reminders.regionMonitoringDenied)
    }
}

// MARK: - Which place owns the single outstanding reminder

struct PreferredPlaceTests {

    private func place(_ name: String, lat: Double) -> Restaurant {
        let category = TipCategory(name: "\(name) cat")
        category.arrivalReminderMinutes = 30
        let place = Restaurant(
            name: name,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -122.03118),
            category: category
        )
        place.visitCount = 2
        return place
    }

    private let here = CLLocation(latitude: 37.33182, longitude: -122.03118)

    @Test func withNothingWaitingTheArrivalTakesIt() {
        let arriving = place("Arriving", lat: 37.33182)
        #expect(ArrivalReminders.preferredPlace(
            incoming: arriving, waiting: nil, from: here
        )?.name == "Arriving")
    }

    @Test func theCloserPlaceWins() {
        let near = place("Near", lat: 37.33185)     // ~3 m away
        let far = place("Far", lat: 37.33500)       // ~350 m away

        #expect(ArrivalReminders.preferredPlace(
            incoming: near, waiting: far, from: here
        )?.name == "Near", "walking up to a place should move the reminder to it")

        #expect(ArrivalReminders.preferredPlace(
            incoming: far, waiting: near, from: here
        )?.name == "Near", "clipping a distant fence shouldn't steal it back")
    }

    @Test func withoutAFixTheReminderAlreadyWaitingKeepsIt() {
        let near = place("Near", lat: 37.33185)
        let far = place("Far", lat: 37.33500)
        #expect(ArrivalReminders.preferredPlace(
            incoming: near, waiting: far, from: nil
        )?.name == "Far", "a guess isn't worth trading a good nudge for")
    }

    @Test func aPlaceWithNoCoordinateNeverDisplacesOne() {
        let waiting = place("Waiting", lat: 37.33185)
        let noGPS = Restaurant(name: "No GPS", category: TipCategory(name: "c"))
        #expect(ArrivalReminders.preferredPlace(
            incoming: noGPS, waiting: waiting, from: here
        )?.name == "Waiting")
    }
}

// MARK: - The single outstanding reminder must not get stuck

struct OutstandingReminderSlotTests {

    @Test func areminderStillToComeHoldsTheSlot() {
        let now = Date()
        #expect(ArrivalReminders.isAwaitingDelivery(
            fireDate: now.addingTimeInterval(600), now: now
        ))
    }

    @Test func areminderThatHasFiredReleasesTheSlot() {
        let now = Date()
        #expect(!ArrivalReminders.isAwaitingDelivery(
            fireDate: now.addingTimeInterval(-1), now: now
        ), "a delivered reminder that kept the slot would mute every later one")
        #expect(!ArrivalReminders.isAwaitingDelivery(
            fireDate: now.addingTimeInterval(-86_400), now: now
        ))
    }
}
