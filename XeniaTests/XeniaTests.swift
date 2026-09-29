//
//  XeniaTests.swift
//  XeniaTests
//
//  Created by Oliver Luu on 8/31/26.
//

import Testing
import Foundation
import CoreLocation
@testable import Xenia

struct TipEngineTests {

    private func request(
        base: Double = 18,
        ratings: [RatingInput] = [],
        rules: [RuleSelection] = [],
        bill: Double = 100,
        party: Int = 1,
        rounding: RoundingMode = .none,
        fractionDigits: Int = 2,
        baseCash: Double? = nil
    ) -> TipRequest {
        TipRequest(
            baseTipPercent: base,
            ratings: ratings,
            ruleSelections: rules,
            bill: bill,
            partySize: party,
            rounding: rounding,
            baseTipAmount: baseCash,
            currencyFractionDigits: fractionDigits
        )
    }

    private func rating(_ name: String, _ score: Int, neutral: Int = 3, weight: Double = 2) -> RatingInput {
        RatingInput(id: UUID(), name: name, score: score, neutral: neutral, weight: weight)
    }

    @Test func baseOnlyProducesBasePercent() {
        let result = TipEngine.evaluate(request(base: 18, bill: 50))
        #expect(result.percent == 18)
        #expect(result.tipAmount == 9)
        #expect(result.total == 59)
    }

    @Test func neutralRatingsDoNotChangeTip() {
        let result = TipEngine.evaluate(request(ratings: [rating("Service", 3), rating("Food", 3)]))
        #expect(result.percent == 18)
        #expect(result.components.count == 1)
    }

    @Test func goodAndBadRatingsMoveTipByWeight() {
        let result = TipEngine.evaluate(request(ratings: [
            rating("Service", 5, weight: 2), rating("Food", 1, weight: 2),
        ]))
        // service +4, food -4 => net 0
        #expect(result.percent == 18)

        let better = TipEngine.evaluate(request(ratings: [rating("Service", 5, weight: 1.5)]))
        #expect(better.percent == 18 + 3)
    }

    @Test func ratingsUseTheirOwnNeutralAndWeight() {
        // Speed: 1-10, neutral 5, 3%/pt -> a 7 is +6%
        let result = TipEngine.evaluate(request(ratings: [rating("Speed", 7, neutral: 5, weight: 3)]))
        #expect(result.percent == 24)
        #expect(result.components.contains { $0.label == "Speed" && $0.percent == 6 })
    }

    @Test func toggleAndStepperRulesAccumulate() {
        let toggle = RuleSelection(ruleID: UUID(), title: "Great server", deltaPercent: 3, steps: 1)
        let stepper = RuleSelection(ruleID: UUID(), title: "Extra round", deltaPercent: 1, steps: 3)
        let off = RuleSelection(ruleID: UUID(), title: "Ignored", deltaPercent: 5, steps: 0)
        let result = TipEngine.evaluate(request(rules: [toggle, stepper, off]))
        #expect(result.percent == 18 + 3 + 3)
        #expect(result.components.contains { $0.label == "Extra round ×3" })
        #expect(!result.components.contains { $0.label == "Ignored" })
    }

    @Test func percentIsClampedButRawIsReported() {
        let big = RuleSelection(ruleID: UUID(), title: "Huge", deltaPercent: 200, steps: 1)
        let result = TipEngine.evaluate(request(rules: [big]))
        #expect(result.percent == 100)
        #expect(result.rawPercent == 218)

        let negative = RuleSelection(ruleID: UUID(), title: "Awful", deltaPercent: -100, steps: 1)
        let low = TipEngine.evaluate(request(rules: [negative]))
        #expect(low.percent == 0)
        #expect(low.tipAmount == 0)
    }

    @Test func roundingTipMode() {
        let result = TipEngine.evaluate(request(base: 18.5, bill: 63.4, rounding: .tip))
        // 63.4 * 0.185 = 11.729 -> 12
        #expect(result.tipAmount == 12)
        #expect(result.total == 75.4)
        #expect(result.suggestedTipAmount == 11.729)
    }

    @Test func roundingTotalMode() {
        let result = TipEngine.evaluate(request(base: 18.5, bill: 63.4, rounding: .total))
        // bill 63.4 + tip 11.729 = 75.129 -> total 75 -> tip 11.6
        #expect(result.total == 75)
        #expect((result.tipAmount - 11.6).magnitude < 0.0001)
        #expect(result.effectivePercent > 18 && result.effectivePercent < 19)
    }

    @Test func roundingNoneSnapsToMinorUnits() {
        let result = TipEngine.evaluate(request(base: 18.333, bill: 47.77, rounding: .none))
        // 47.77 * 0.18333 = 8.7577... -> 8.76
        #expect(result.tipAmount == 8.76)
    }

    @Test func totalRoundingLeavesAZeroedTipAtZero() {
        // Penalties cancel the base; "round the total" must not invent $0.40.
        let penalty = RuleSelection(ruleID: UUID(), title: "Terrible", deltaPercent: -100, steps: 1)
        let result = TipEngine.evaluate(request(base: 18, rules: [penalty], bill: 20.60, rounding: .total))
        #expect(result.tipAmount == 0)
        #expect(result.total == 20.60)
    }

    @Test func zeroDeltaRuleAddsNoLedgerLine() {
        let noop = RuleSelection(ruleID: UUID(), title: "Left at door", deltaPercent: 0, steps: 1)
        let result = TipEngine.evaluate(request(base: 18, rules: [noop], bill: 50))
        #expect(result.components.count == 1)   // just "Base"
        #expect(!result.components.contains { $0.label == "Left at door" })
    }

    @Test func roundingWithZeroFractionDigits() {
        // Yen: no minor unit. "none" rounds to a whole unit just like "tip".
        let none = TipEngine.evaluate(request(base: 15, bill: 3200, rounding: .none, fractionDigits: 0))
        #expect(none.tipAmount == 480)
        let odd = TipEngine.evaluate(request(base: 15.4, bill: 3210, rounding: .none, fractionDigits: 0))
        // 3210 * 0.154 = 494.34 -> 494
        #expect(odd.tipAmount == 494)
    }

    @Test func baseCashSetsTheStartingTip() {
        let result = TipEngine.evaluate(request(base: 18, bill: 50, baseCash: 12.5))
        #expect(result.tipAmount == 12.5)
        #expect(result.total == 62.5)
        #expect(result.effectivePercent == 25)
        // The "Base" component now reads as the cash amount's share of the bill.
        #expect((result.components.first!.percent - 25).magnitude < 0.0001)
    }

    @Test func baseCashStillMovedByRatingsAndRules() {
        // $10 on a $50 bill is 20%; a +4% rating and a +3% toggle lift it to 27% -> $13.50.
        let toggle = RuleSelection(ruleID: UUID(), title: "Great server", deltaPercent: 3, steps: 1)
        let result = TipEngine.evaluate(request(
            ratings: [rating("Service", 5, weight: 2)],
            rules: [toggle],
            bill: 50,
            baseCash: 10
        ))
        #expect((result.tipAmount - 13.5).magnitude < 0.0001)
        #expect((result.effectivePercent - 27).magnitude < 0.0001)
    }

    @Test func baseCashNegativeIsTreatedAsZero() {
        let result = TipEngine.evaluate(request(base: 18, bill: 50, baseCash: -5))
        #expect(result.tipAmount == 0)
        #expect(result.total == 50)
    }

    @Test func baseCashOnZeroBillStandsOnItsOwn() {
        // No bill to take a percentage of, and nothing adjusting it — the flat
        // base is the tip.
        let result = TipEngine.evaluate(request(base: 18, bill: 0, baseCash: 10))
        #expect(result.tipAmount == 10)
        #expect(result.total == 10)
    }

    @Test func baseCashOnZeroBillIsScaledByRatingsAndRules() {
        // No bill, $10 flat base. A +4% rating and a +6% toggle lift it 10% -> $11.
        let toggle = RuleSelection(ruleID: UUID(), title: "Great server", deltaPercent: 6, steps: 1)
        let result = TipEngine.evaluate(request(
            ratings: [rating("Service", 5, weight: 2)],
            rules: [toggle],
            bill: 0,
            baseCash: 10
        ))
        #expect((result.tipAmount - 11).magnitude < 0.0001)
        #expect((result.total - 11).magnitude < 0.0001)
        // The "Base" line keeps its cash value; the rating line reads in cash too.
        #expect((result.components.first!.amount - 10).magnitude < 0.0001)
        #expect(result.components.contains { $0.label == "Service" && ($0.amount - 0.4).magnitude < 0.0001 })
    }

    @Test func baseCashOnZeroBillPenaltyTrimsTheBase() {
        // A -10% penalty on a $10 flat base -> $9.
        let penalty = RuleSelection(ruleID: UUID(), title: "Slow", deltaPercent: -10, steps: 1)
        let result = TipEngine.evaluate(request(rules: [penalty], bill: 0, baseCash: 10))
        #expect((result.tipAmount - 9).magnitude < 0.0001)
    }

    @Test func baseCashOnZeroBillCannotGoNegative() {
        let penalty = RuleSelection(ruleID: UUID(), title: "Awful", deltaPercent: -100, steps: 2)
        let result = TipEngine.evaluate(request(rules: [penalty], bill: 0, baseCash: 10))
        #expect(result.tipAmount == 0)
        #expect(result.total == 0)
    }

    @Test func baseCashPlusThreeTopRatingsScalesUp() {
        // The report scenario: $5 base, $50 bill, three 5/5 ratings (+4% each).
        // $5 is 10% of $50; +12% => 22% => $11.
        let ratings = [
            rating("Service", 5, weight: 2),
            rating("Food", 5, weight: 2),
            rating("Atmosphere", 5, weight: 2),
        ]
        let result = TipEngine.evaluate(request(ratings: ratings, bill: 50, baseCash: 5))
        #expect((result.tipAmount - 11).magnitude < 0.0001)
        #expect((result.total - 61).magnitude < 0.0001)
        #expect((result.effectivePercent - 22).magnitude < 0.0001)
    }

    @Test func baseCashWithTotalRounding() {
        let result = TipEngine.evaluate(request(base: 0, bill: 42.3, rounding: .total, baseCash: 6))
        // 6 is 14.184% of 42.3 -> ~$6.00; 42.3 + 6 = 48.3 -> 48 -> tip 5.7
        #expect(result.total == 48)
        #expect((result.tipAmount - 5.7).magnitude < 0.0001)
    }

    @Test func effectivePercentMatchesPercentWithNoOverride() {
        let result = TipEngine.evaluate(request(base: 20, bill: 80))
        #expect(result.effectivePercent == 20)
        #expect(result.percent == 20)
    }

    @Test func splittingDividesTotalAndTip() {
        let result = TipEngine.evaluate(request(base: 20, bill: 100, party: 4))
        #expect(result.tipAmount == 20)
        #expect(result.perPersonTotal == 30)
        #expect(result.perPersonTip == 5)
    }

    @Test func negativeBillIsTreatedAsZero() {
        let result = TipEngine.evaluate(request(bill: -50))
        #expect(result.tipAmount == 0)
        #expect(result.total == 0)
    }
}

@MainActor
struct TabBarPingTests {

    @Test func pingingTwoTabsLightsBoth() {
        let ping = TabBarPing()
        ping.ping(.places)
        ping.ping(.history)
        #expect(ping.isLit(.places))
        #expect(ping.isLit(.history))
        #expect(!ping.isLit(.calculate))
        #expect(ping.pinged == [.places, .history])
    }

    @Test func repingingOneTabKeepsTheOther() {
        let ping = TabBarPing()
        ping.ping(.places)
        ping.ping(.history)
        ping.ping(.history)
        #expect(ping.isLit(.places))
        #expect(ping.isLit(.history))
    }
}

struct ArrivalRemindersEligibilityTests {

    private func place(
        _ name: String,
        lat: Double,
        visits: Int,
        reminderMinutes: Int
    ) -> Restaurant {
        let category = TipCategory(name: "\(name) cat")
        category.arrivalReminderMinutes = reminderMinutes
        let r = Restaurant(
            name: name,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: 0),
            category: category
        )
        r.visitCount = visits
        return r
    }

    @Test func filtersOutPlacesThatArentReminderWorthy() {
        let good = place("Good", lat: 1, visits: 2, reminderMinutes: 30)
        let neverVisited = place("New", lat: 1, visits: 0, reminderMinutes: 30)
        let reminderOff = place("Off", lat: 1, visits: 5, reminderMinutes: 0)
        let noGPS = Restaurant(name: "No GPS", category: {
            let c = TipCategory(name: "c"); c.arrivalReminderMinutes = 30; return c
        }())
        noGPS.visitCount = 5

        let result = ArrivalReminders.eligiblePlaces(
            from: [good, neverVisited, reminderOff, noGPS], near: nil, limit: 20
        )
        #expect(result.map(\.name) == ["Good"])
    }

    @Test func perPlaceOverrideDecidesWhetherItsWatched() {
        let followsCategory = place("Follows", lat: 1, visits: 2, reminderMinutes: 30)
        let forcedOff = place("ForcedOff", lat: 1, visits: 2, reminderMinutes: 30)
        forcedOff.arrivalRemindersOn = false
        let forcedOn = place("ForcedOn", lat: 1, visits: 2, reminderMinutes: 0)  // category off
        forcedOn.arrivalRemindersOn = true

        #expect(followsCategory.effectiveArrivalReminderMinutes == 30)
        #expect(forcedOff.effectiveArrivalReminderMinutes == 0)
        #expect(forcedOn.effectiveArrivalReminderMinutes == ArrivalDefaults.fallbackMinutes)

        let watched = ArrivalReminders.eligiblePlaces(
            from: [followsCategory, forcedOff, forcedOn], near: nil, limit: 20
        ).map(\.name)
        #expect(watched.contains("Follows"))
        #expect(!watched.contains("ForcedOff"))
        #expect(watched.contains("ForcedOn"))
    }

    @Test func keepsTheNearestWhenOverTheRegionLimit() {
        let here = CLLocation(latitude: 0, longitude: 0)
        let places = (1...25).map { place("P\($0)", lat: Double($0) / 1000, visits: 1, reminderMinutes: 20) }

        let result = ArrivalReminders.eligiblePlaces(from: places.shuffled(), near: here, limit: 20)
        #expect(result.count == 20)
        #expect(result.first?.name == "P1")   // closest
        #expect(!result.contains { $0.name == "P25" })  // farthest dropped
    }

    @Test func clampsTriggerRadiusIntoTheValidRange() {
        #expect(ArrivalReminders.clampedRadius(0) == ArrivalReminders.defaultRadius)
        #expect(ArrivalReminders.clampedRadius(10) == ArrivalReminders.radiusRange.lowerBound)
        #expect(ArrivalReminders.clampedRadius(99_999) == ArrivalReminders.radiusRange.upperBound)
        #expect(ArrivalReminders.clampedRadius(200) == 200)
    }

    @Test func aVisitMatchesTheNearestReminderWorthyPlace() {
        // ~55 m north of (0,0); a couple hundred m north for the far one.
        let near = place("Near", lat: 0.0005, visits: 2, reminderMinutes: 30)
        let far = place("Far", lat: 0.003, visits: 2, reminderMinutes: 30)
        let visitHere = CLLocation(latitude: 0, longitude: 0)

        let matched = ArrivalReminders.placeAtVisit(
            visitHere, accuracy: 20, radius: 120, among: [far, near]
        )
        #expect(matched?.name == "Near")

        // Too far for any place.
        let elsewhere = CLLocation(latitude: 0.02, longitude: 0)
        #expect(ArrivalReminders.placeAtVisit(
            elsewhere, accuracy: 20, radius: 120, among: [far, near]
        ) == nil)
    }

    @Test func aLooseVisitStillMatchesWhenAccuracyIsWide() {
        let spot = place("Spot", lat: 0.0018, visits: 3, reminderMinutes: 40)  // ~200 m off
        let visit = CLLocation(latitude: 0, longitude: 0)

        // Tight radius, but the visit itself is only accurate to 300 m.
        let matched = ArrivalReminders.placeAtVisit(
            visit, accuracy: 300, radius: 100, among: [spot]
        )
        #expect(matched?.name == "Spot")
    }

    @Test func notificationDelayCountsFromRealArrivalNotDetection() {
        let now = Date()

        // No arrival time (a geofence trigger): the full category delay.
        #expect(ArrivalReminders.notificationDelay(minutes: 55, arrivedAt: nil, now: now) == 55 * 60)

        // A visit detected 10 min after arriving: 10 min already served.
        #expect(ArrivalReminders.notificationDelay(
            minutes: 55, arrivedAt: now.addingTimeInterval(-600), now: now
        ) == 55 * 60 - 600)

        // Detected so late the delay is already spent → the minimum dwell, not never.
        #expect(ArrivalReminders.notificationDelay(
            minutes: 3, arrivedAt: now.addingTimeInterval(-600), now: now
        ) == ArrivalReminders.minimumDwell)
        // The floor is kept short so a quick café run still catches you.
        #expect(ArrivalReminders.minimumDwell <= 60)

        // Garbage arrival dates are ignored.
        #expect(ArrivalReminders.notificationDelay(minutes: 55, arrivedAt: .distantPast, now: now) == 55 * 60)
        #expect(ArrivalReminders.notificationDelay(
            minutes: 55, arrivedAt: now.addingTimeInterval(120), now: now
        ) == 55 * 60)
    }
}
