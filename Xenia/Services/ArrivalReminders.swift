//
//  ArrivalReminders.swift
//  Xenia
//
//  Watches for the user arriving at a place they've tipped at before and, after
//  a category-dependent delay (a café is quick, a sit-down meal is not), posts a
//  local notification suggesting they open Xenia to work out the tip.
//
//  Two triggers, both work with the app closed: CoreLocation region monitoring
//  (fast — fires when you cross the geofence) and visit monitoring (iOS's own
//  "the user has settled at a place" detection, which tells "here for a visit"
//  from "driving past" better than a circle can). Either one starts the timer.
//

import Foundation
import CoreLocation
import UserNotifications
import SwiftData

@Observable
final class ArrivalReminders: NSObject {

    static let shared = ArrivalReminders()

    /// iOS caps an app at 20 monitored regions; we watch the nearest eligible places.
    static let maxRegions = 20
    /// Don't re-remind for the same place within this window.
    static let cooldown: TimeInterval = 3 * 3600

    /// How close you have to get before the reminder can fire. Region monitoring
    /// gets unreliable much below ~75 m.
    static let radiusRange: ClosedRange<CLLocationDistance> = 75...500
    static let defaultRadius: CLLocationDistance = 125

    static func clampedRadius(_ meters: CLLocationDistance) -> CLLocationDistance {
        guard meters > 0 else { return defaultRadius }
        return min(max(meters, radiusRange.lowerBound), radiusRange.upperBound)
    }

    private static let enabledKey = "arrivalRemindersEnabled"
    private static let radiusKey = "arrivalRemindersRadiusMeters"
    private static let lastFiredKey = "arrivalRemindersLastFired"
    private static let notificationPrefix = "arrival-"

    private let manager = CLLocationManager()

    /// Region identifiers we're currently inside, kept so a jittery exit→re-enter
    /// at the geofence edge doesn't let a stale `cancelReminder` callback tear
    /// down a reminder we're still owed. The CLLocationManager was created on the
    /// main thread, so its delegate callbacks — and the reads here — are all main.
    private var insideRegions: Set<String> = []

    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// Whether iOS is handing us a real fix or a deliberately fuzzed one. A
    /// geofence needs the real thing, so with Precise Location off the feature
    /// can't work no matter how the other permissions read.
    private(set) var accuracyAuthorization: CLAccuracyAuthorization

    /// Set when CoreLocation refuses to watch a place. That refusal used to be
    /// invisible — reminders simply never arrived, while every permission on the
    /// Settings screen still looked green.
    private(set) var regionMonitoringDenied = false

    /// The reminder currently queued, and when it comes due. Only ever one (see
    /// `scheduleReminder`). Holding the date is what keeps this honest: once it
    /// has passed the reminder has fired, so it stops counting as outstanding
    /// and a stale entry can't quietly mute every later nudge.
    private var pendingReminder: (placeID: String, fireDate: Date)?

    /// The queued reminder that hasn't gone off yet, if there is one.
    private var reminderAwaitingDelivery: (placeID: String, fireDate: Date)? {
        guard let pendingReminder,
              Self.isAwaitingDelivery(fireDate: pendingReminder.fireDate)
        else { return nil }
        return pendingReminder
    }

    /// Whether a scheduled reminder is still to come. Once its moment has passed
    /// it has been delivered and stops holding the single outstanding slot —
    /// without this a fired reminder would mute every later one for as long as
    /// the process lived.
    static func isAwaitingDelivery(fireDate: Date, now: Date = Date()) -> Bool {
        fireDate > now
    }

    /// The master on/off switch, mirrored to `UserDefaults` so the app delegate
    /// and the Settings screen agree without a shared object graph.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                requestPermissions()
                syncFromStore()
            } else {
                stopMonitoringEverything()
            }
        }
    }

    var isFullyAuthorized: Bool {
        locationStatus == .authorizedAlways
            && notificationStatus == .authorized
            && accuracyAuthorization == .fullAccuracy
    }

    /// The one thing standing between the user and a working reminder, or `nil`
    /// when nothing is. Kept next to the state it reads rather than in the view,
    /// and split into a pure function so every combination can be tested — most
    /// of them can't be talked into existing on a simulator.
    var permissionIssue: String? {
        Self.permissionIssue(
            location: locationStatus,
            notifications: notificationStatus,
            accuracy: accuracyAuthorization,
            regionMonitoringDenied: regionMonitoringDenied
        )
    }

    static func permissionIssue(
        location: CLAuthorizationStatus,
        notifications: UNAuthorizationStatus,
        accuracy: CLAccuracyAuthorization,
        regionMonitoringDenied: Bool
    ) -> String? {
        switch (location, notifications) {
        case (.denied, _), (.restricted, _):
            return String(localized: "Location is off for Xenia. Turn it on and set it to \u{201C}Always\u{201D} so reminders work in the background.")
        case (.authorizedWhenInUse, _):
            return String(localized: "Xenia needs \u{201C}Always\u{201D} location access to remind you while it's closed. It's currently \u{201C}While Using\u{201D}.")
        case (_, .denied):
            return String(localized: "Notifications are off for Xenia, so reminders can't come through.")
        default:
            break
        }
        // Everything above can be green while the feature is still dead: a
        // geofence needs a real fix to test against, and a refusal from
        // CoreLocation leaves no other trace.
        if accuracy == .reducedAccuracy {
            return String(localized: "Precise Location is off for Xenia, so it can't tell when you've arrived. Turn it on in iOS Settings.")
        }
        if regionMonitoringDenied {
            return String(localized: "iOS wouldn't let Xenia watch your saved places, so arrival reminders aren't running. Check that Location is set to \u{201C}Always\u{201D} with Precise Location on.")
        }
        return nil
    }

    /// The geofence radius, in meters. Persisted so the background launch path
    /// uses the same value. Setting it does not re-monitor — call `start()`.
    var triggerRadiusMeters: CLLocationDistance {
        get { Self.clampedRadius(UserDefaults.standard.double(forKey: Self.radiusKey)) }
        set { UserDefaults.standard.set(Self.clampedRadius(newValue), forKey: Self.radiusKey) }
    }

    override init() {
        locationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        UNUserNotificationCenter.current().delegate = self
        refreshNotificationStatus()
    }

    // MARK: - Lifecycle

    /// Call at launch (including background relaunch from a region event) and
    /// whenever the set of saved places changes.
    func start() {
        refreshNotificationStatus()
        guard isEnabled else { return }
        syncFromStore()
    }

    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in ArrivalReminders.shared.refreshNotificationStatus() }
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: - Region set

    private func syncFromStore() {
        guard isEnabled,
              locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse
        else { return }

        let context = Persistence.container.mainContext
        let saved = (try? context.fetch(FetchDescriptor<Restaurant>())) ?? []
        let wanted = Self.eligiblePlaces(
            from: saved, near: manager.location, limit: Self.maxRegions
        )
        applyRegions(for: wanted)
        manager.startMonitoringVisits()
    }

    /// The nearest reminder-worthy place a `CLVisit` could be at, or `nil`. The
    /// match window is the wider of the trigger radius and the visit's own
    /// accuracy, since a visit's coordinate can be loose.
    static func placeAtVisit(
        _ location: CLLocation,
        accuracy: CLLocationDistance,
        radius: CLLocationDistance,
        among restaurants: [Restaurant]
    ) -> Restaurant? {
        let threshold = max(radius, accuracy > 0 ? accuracy : 0)
        let eligible = eligiblePlaces(from: restaurants, near: location, limit: maxRegions)
        guard let closest = eligible.first,
              let distance = closest.distance(from: location),
              distance <= threshold
        else { return nil }
        return closest
    }

    private func handleVisit(_ visit: CLVisit) {
        guard isEnabled, CLLocationCoordinate2DIsValid(visit.coordinate) else { return }
        let location = CLLocation(latitude: visit.coordinate.latitude,
                                  longitude: visit.coordinate.longitude)
        let context = Persistence.container.mainContext
        let saved = (try? context.fetch(FetchDescriptor<Restaurant>())) ?? []
        guard let place = Self.placeAtVisit(
            location,
            accuracy: visit.horizontalAccuracy,
            radius: triggerRadiusMeters,
            among: saved
        ) else { return }

        let id = place.uuid.uuidString
        if visit.departureDate == .distantFuture {
            // Still there — count the delay from when the visit actually started,
            // not from now (visit detection can lag several minutes).
            scheduleReminder(forPlaceID: id, arrivedAt: visit.arrivalDate)
        } else {
            // The visit has ended — they've left.
            cancelReminder(forPlaceID: id)
        }
    }

    /// Places worth watching: saved, has a GPS point, tipped at before, and
    /// reminders are on for the place (its own override, else its category).
    /// Closest first when a location is known.
    static func eligiblePlaces(
        from restaurants: [Restaurant],
        near location: CLLocation?,
        limit: Int
    ) -> [Restaurant] {
        let candidates = restaurants.filter {
            $0.hasCoordinate && $0.visitCount >= 1 && $0.effectiveArrivalReminderMinutes > 0
        }
        let ordered: [Restaurant]
        if let location {
            ordered = candidates.sorted {
                ($0.distance(from: location) ?? .greatestFiniteMagnitude)
                    < ($1.distance(from: location) ?? .greatestFiniteMagnitude)
            }
        } else {
            ordered = candidates.sorted { $0.visitCount > $1.visitCount }
        }
        return Array(ordered.prefix(limit))
    }

    private func applyRegions(for places: [Restaurant]) {
        let radius = triggerRadiusMeters
        let wantedIDs = Set(places.map(\.uuid.uuidString))

        // Decide what to keep vs. stop in one pass, tracking the kept ids here —
        // `manager.monitoredRegions` is not guaranteed to reflect a stopMonitoring
        // call synchronously, so re-reading it would skip re-adding the regions
        // we just stopped for a radius change.
        var keptIDs: Set<String> = []
        for region in manager.monitoredRegions {
            let rightRadius = (region as? CLCircularRegion).map { abs($0.radius - radius) <= 1 } ?? false
            if wantedIDs.contains(region.identifier) && rightRadius {
                keptIDs.insert(region.identifier)
            } else {
                manager.stopMonitoring(for: region)
            }
        }

        for place in places where !keptIDs.contains(place.uuid.uuidString) {
            guard let coordinate = place.coordinate else { continue }
            let region = CLCircularRegion(
                center: coordinate,
                radius: radius,
                identifier: place.uuid.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func stopMonitoringEverything() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        insideRegions.removeAll()
        pendingReminder = nil
        regionMonitoringDenied = false
        manager.stopMonitoringVisits()
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.notificationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Firing

    /// A small floor so a `minutes: 1` category (or a very late visit) still gets
    /// a beat before firing. Kept short on purpose — a quick café run can be over
    /// in a couple of minutes, and the notification wording covers the rare
    /// drive-by better than a long wait would.
    static let minimumDwell: TimeInterval = 45

    /// Seconds until the reminder should fire: `minutes` after you actually got
    /// there. When `arrivedAt` is known (from a visit) the time already spent at
    /// the place is subtracted, so a slow arrival detection doesn't push the
    /// nudge past when you've already paid.
    static func notificationDelay(minutes: Int, arrivedAt: Date?, now: Date = Date()) -> TimeInterval {
        let base = TimeInterval(minutes) * 60
        var delay = base
        if let arrivedAt {
            let elapsed = now.timeIntervalSince(arrivedAt)
            if elapsed > 0, elapsed < 86_400 { delay = base - elapsed }
        }
        return max(delay, minimumDwell)
    }

    private func scheduleReminder(forPlaceID id: String, arrivedAt: Date? = nil) {
        guard isEnabled, notificationStatus == .authorized else { return }
        guard !isInCooldown(id) else { return }

        let context = Persistence.container.mainContext
        guard let uuid = UUID(uuidString: id),
              let place = (try? context.fetch(
                  FetchDescriptor<Restaurant>(predicate: #Predicate { $0.uuid == uuid })
              ))?.first
        else { return }

        let minutes = place.effectiveArrivalReminderMinutes
        guard minutes > 0 else { return }

        // Only one arrival reminder is ever outstanding. Saved places in a dense
        // block can easily share overlapping fences at the wider trigger
        // distances, and nudging once per fence turns a single arrival into a
        // pile of notifications. The closest place wins, so walking further into
        // a neighbourhood hands the reminder to wherever you actually stopped
        // rather than to whichever edge you happened to clip first.
        if let waiting = reminderAwaitingDelivery, waiting.placeID != id {
            let waitingPlace = Self.place(withID: waiting.placeID, in: context)
            let winner = Self.preferredPlace(
                incoming: place, waiting: waitingPlace, from: manager.location
            )
            guard winner?.uuid == place.uuid else { return }
            supersedeReminder(forPlaceID: waiting.placeID)
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "At \(place.name)?")
        content.body = String(localized: "Open Xenia when you're ready to work out the tip.")
        content.sound = .default
        content.userInfo = ["restaurant": id]

        let delay = Self.notificationDelay(minutes: minutes, arrivedAt: arrivedAt)
        let request = UNNotificationRequest(
            identifier: Self.notificationPrefix + id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        pendingReminder = (placeID: id, fireDate: Date().addingTimeInterval(delay))
        UNUserNotificationCenter.current().add(request)
        markFired(id)
    }

    /// The place that should own the single outstanding reminder: whichever is
    /// closer to where you are now. With no fix to compare against, the reminder
    /// already waiting keeps it — a guess isn't worth trading a good nudge for.
    static func preferredPlace(
        incoming: Restaurant,
        waiting: Restaurant?,
        from location: CLLocation?
    ) -> Restaurant? {
        guard let waiting else { return incoming }
        guard let location,
              let incomingDistance = incoming.distance(from: location),
              let waitingDistance = waiting.distance(from: location)
        else { return waiting }
        return incomingDistance < waitingDistance ? incoming : waiting
    }

    private static func place(withID id: String, in context: ModelContext) -> Restaurant? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return (try? context.fetch(
            FetchDescriptor<Restaurant>(predicate: #Predicate { $0.uuid == uuid })
        ))?.first
    }

    /// Drops a reminder a nearer place has taken over from. Unlike
    /// `cancelReminder` this doesn't consult `insideRegions` — you're standing
    /// inside both fences, which is the whole reason one has to give way — and it
    /// refunds the cooldown, since that nudge never actually arrived.
    private func supersedeReminder(forPlaceID id: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationPrefix + id])
        clearCooldown(id)
        if pendingReminder?.placeID == id { pendingReminder = nil }
    }

    private func cancelReminder(forPlaceID id: String) {
        let center = UNUserNotificationCenter.current()
        let notifID = Self.notificationPrefix + id
        center.getPendingNotificationRequests { requests in
            let wasStillPending = requests.contains { $0.identifier == notifID }
            Task { @MainActor in
                let shared = ArrivalReminders.shared
                // A re-entry beat this async callback — we're actually still
                // inside, so leave the pending reminder and its cooldown intact.
                guard !shared.insideRegions.contains(id) else { return }
                center.removePendingNotificationRequests(withIdentifiers: [notifID])
                if shared.pendingReminder?.placeID == id { shared.pendingReminder = nil }
                // A drive-by that never actually stopped shouldn't burn the 3-hour
                // cooldown — clear it so a real visit soon after still gets a nudge.
                if wasStillPending { shared.clearCooldown(id) }
                shared.rearmForSomewhereStillInside()
            }
        }
    }

    /// Overlapping fences mean leaving one circle isn't leaving. Since only one
    /// reminder is outstanding at a time, the place we just cancelled may have
    /// been standing in for somewhere we're still sitting — and no fresh entry
    /// event is coming for it, because we never crossed back in. Hand the
    /// reminder to the nearest place we're still inside.
    private func rearmForSomewhereStillInside() {
        guard isEnabled, reminderAwaitingDelivery == nil, !insideRegions.isEmpty else { return }
        let context = Persistence.container.mainContext
        let stillInside = insideRegions.compactMap { Self.place(withID: $0, in: context) }
        guard let nearest = Self.eligiblePlaces(
            from: stillInside, near: manager.location, limit: 1
        ).first else { return }
        scheduleReminder(forPlaceID: nearest.uuid.uuidString)
    }

    // MARK: - Cooldown bookkeeping

    private func isInCooldown(_ id: String) -> Bool {
        let map = UserDefaults.standard.dictionary(forKey: Self.lastFiredKey) as? [String: Double] ?? [:]
        guard let last = map[id] else { return false }
        return Date().timeIntervalSince1970 - last < Self.cooldown
    }

    private func markFired(_ id: String) {
        var map = UserDefaults.standard.dictionary(forKey: Self.lastFiredKey) as? [String: Double] ?? [:]
        map[id] = Date().timeIntervalSince1970
        UserDefaults.standard.set(map, forKey: Self.lastFiredKey)
    }

    private func clearCooldown(_ id: String) {
        var map = UserDefaults.standard.dictionary(forKey: Self.lastFiredKey) as? [String: Double] ?? [:]
        map[id] = nil
        UserDefaults.standard.set(map, forKey: Self.lastFiredKey)
    }

    // MARK: - Status

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in ArrivalReminders.shared.notificationStatus = status }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension ArrivalReminders: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
        // Precise Location can be switched on or off without the coarse status
        // changing at all, and it decides whether geofences work.
        accuracyAuthorization = manager.accuracyAuthorization
        switch locationStatus {
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            // Don't wait for a later Always upgrade that may never come — start
            // monitoring now (syncFromStore already accepts "When In Use").
            syncFromStore()
        case .authorizedAlways:
            syncFromStore()
        case .denied, .restricted:
            stopMonitoringEverything()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        insideRegions.insert(region.identifier)
        scheduleReminder(forPlaceID: region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        insideRegions.remove(region.identifier)
        cancelReminder(forPlaceID: region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        handleVisit(visit)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix is transient; nothing actionable. A refused *region* is
        // not — that arrives below.
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        // Something got through, so whatever went wrong before has cleared.
        regionMonitoringDenied = false
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        // `regionMonitoringDenied` is the failure worth surfacing: it won't clear
        // on its own, it hits every place the same way, and the feature is simply
        // dead until the user changes something. On device that usually means
        // Precise Location is off. Other errors here are per-region and
        // transient — the next `syncFromStore` retries them.
        if (error as? CLError)?.code == .regionMonitoringDenied {
            regionMonitoringDenied = true
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension ArrivalReminders: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo["restaurant"] as? String
        await MainActor.run {
            NotificationCenter.default.post(
                name: .arrivalReminderOpened,
                object: nil,
                userInfo: id.map { ["restaurant": $0] }
            )
        }
    }
}

extension Notification.Name {
    /// Posted when the user taps an arrival reminder. `userInfo["restaurant"]` is
    /// the place's `uuid` string when known.
    static let arrivalReminderOpened = Notification.Name("arrivalReminderOpened")
}
