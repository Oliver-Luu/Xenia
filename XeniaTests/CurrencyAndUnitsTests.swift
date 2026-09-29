//
//  CurrencyAndUnitsTests.swift
//  XeniaTests
//
//  Two settings that look alike and are meant to behave in opposite ways:
//
//    • distance units follow where the user *lives* — the device's Region
//      setting — so they never change under a traveller's feet
//    • currency is meant to follow where the user *is*, so prices read in the
//      money actually being handed over
//
//  Both rules are exercised through pure entry points, because the thing that
//  decides them (`Locale.current`) can't be changed from inside a test process.
//

import Testing
import Foundation
import CoreLocation
@testable import Xenia

@MainActor
@Suite(.serialized)
struct CurrencySwitchingTests {

    /// Restores whatever the app was set to, so a failure here doesn't leave the
    /// simulator's Xenia in a strange currency for every later suite.
    private func withCurrency(_ code: String?, _ body: () throws -> Void) rethrows {
        let saved = Preferences.shared.currencyCode
        defer { Preferences.shared.currencyCode = saved }
        Preferences.shared.currencyCode = code
        try body()
    }

    @Test func switchingCurrencyChangesWhatAmountsLookLike() throws {
        try withCurrency("USD") {
            #expect(Format.currencyCode == "USD")
            #expect(Format.currency(12).contains("12.00"))
            #expect(Format.currencySymbol() == "$")
        }
        try withCurrency("EUR") {
            #expect(Format.currencyCode == "EUR")
            #expect(Format.currencySymbol() == "€")
        }
        try withCurrency("GBP") {
            #expect(Format.currencySymbol() == "£")
        }
    }

    @Test func switchingToAWholeUnitCurrencyDropsTheDecimals() throws {
        try withCurrency("JPY") {
            #expect(Format.minorUnitDigits() == 0)
            let yen = Format.currency(1234)
            #expect(!yen.contains("."), "yen has no minor unit: \(yen)")
            // Bill entry has to follow, or typing 1234 would land on 12.34.
            #expect(Format.autoDecimal("1234", fractionDigits: Format.minorUnitDigits()) == "1234")
            #expect(Format.sanitizedAmount("12.5", fractionDigits: Format.minorUnitDigits()) == "12")
        }
    }

    @Test func switchingToAThreeDecimalCurrencyWidensEntry() throws {
        try withCurrency("KWD") {
            #expect(Format.minorUnitDigits() == 3)
            #expect(Format.autoDecimal("1234", fractionDigits: Format.minorUnitDigits()) == "1.234")
            #expect(Format.sanitizedAmount("1.2345", fractionDigits: Format.minorUnitDigits()) == "1.234")
        }
    }

    @Test func signedAmountsKeepTheCurrencyAndTheSign() throws {
        try withCurrency("USD") {
            #expect(Format.signedCurrency(5).hasPrefix("+"))
            #expect(Format.signedCurrency(-5).hasPrefix("\u{2212}"))
            #expect(Format.signedCurrency(-5).contains("5.00"))
            #expect(!Format.signedCurrency(0).hasPrefix("+"))
        }
    }

    @Test func clearingTheOverrideFallsBackToTheDevice() throws {
        try withCurrency(nil) {
            let device = Locale.current.currency?.identifier ?? "USD"
            #expect(Format.currencyCode == device,
                    "no override means follow the device, not a leftover choice")
        }
    }

    @Test func everyCurrencyThePickerOffersCanBeResolved() {
        // The picker lists `Locale.commonISOCurrencyCodes`; a code that produced
        // no symbol or a nonsense minor unit would render as broken money.
        for code in Locale.commonISOCurrencyCodes {
            #expect(!Format.currencySymbol(for: code).isEmpty, "no symbol for \(code)")
            let digits = Format.minorUnitDigits(for: code)
            #expect((0...3).contains(digits), "\(code) reported \(digits) minor digits")
        }
    }
}

// MARK: - Which currency is in effect, and why

struct CurrencyResolutionTests {

    @Test func aChosenCurrencyAlwaysWins() {
        #expect(Preferences.resolveCurrencyCode(
            override: "JPY", deviceCurrency: "USD"
        ) == "JPY", "an explicit choice must never be second-guessed")
    }

    @Test func withoutAChoiceTheDeviceDecides() {
        #expect(Preferences.resolveCurrencyCode(
            override: nil, deviceCurrency: "EUR"
        ) == "EUR")
    }

    @Test func withNothingKnownItFallsBackToDollars() {
        #expect(Preferences.resolveCurrencyCode(
            override: nil, deviceCurrency: nil
        ) == "USD")
    }
}

// MARK: - Units follow home, not the traveller

struct DistanceUnitsTests {

    private func metric(_ units: Preferences.DistanceUnits, _ localeID: String) -> Bool {
        Format.usesMetric(for: units, in: Locale(identifier: localeID))
    }

    @Test func automaticUnitsComeFromTheDevicesRegion() {
        #expect(metric(.auto, "en_US") == false)
        #expect(metric(.auto, "fr_FR") == true)
        #expect(metric(.auto, "de_DE") == true)
        #expect(metric(.auto, "ja_JP") == true)
        // The UK measures distance in miles, and `Locale` models that as its own
        // measurement system rather than metric.
        #expect(metric(.auto, "en_GB") == false)
    }

    @Test func anExplicitChoiceIgnoresTheRegionEntirely() {
        for localeID in ["en_US", "fr_FR", "en_GB", "ja_JP"] {
            #expect(metric(.metric, localeID) == true)
            #expect(metric(.imperial, localeID) == false)
        }
    }

    @Test func unitsDoNotFollowTheUserAround() {
        // The whole point of the split: a Californian in Paris still reads feet,
        // because units are a property of the person, not the pavement. There is
        // deliberately no location input to this decision — if one ever appears,
        // this test is the place that should have to change.
        let atHome = metric(.auto, "en_US")
        let abroad = metric(.auto, "en_US")   // same device, different country
        #expect(atHome == abroad)
        #expect(atHome == false)
    }
}

// MARK: - Rendering distances in the chosen unit

@MainActor
@Suite(.serialized)
struct DistanceFormattingTests {

    private func withUnits(_ units: Preferences.DistanceUnits, _ body: () throws -> Void) rethrows {
        let saved = Preferences.shared.distanceUnits
        defer { Preferences.shared.distanceUnits = saved }
        Preferences.shared.distanceUnits = units
        try body()
    }

    @Test func metricSwitchesToKilometresPastAThousandMetres() throws {
        try withUnits(.metric) {
            #expect(Format.distance(100) == "100 m")
            #expect(Format.distance(999).hasSuffix(" m"))
            #expect(Format.distance(1500).hasSuffix(" km"))
        }
    }

    @Test func imperialSwitchesToMilesPastAThousandFeet() throws {
        try withUnits(.imperial) {
            #expect(Format.distance(10).hasSuffix(" ft"))
            #expect(Format.distance(5000).hasSuffix(" mi"))
        }
    }

    @Test func theFineFormatterNeverGoesUpAUnit() throws {
        // Used next to the geofence stepper, where "0.3 mi" would be useless.
        try withUnits(.imperial) {
            #expect(Format.distanceFine(5000).hasSuffix(" ft"))
        }
        try withUnits(.metric) {
            #expect(Format.distanceFine(5000).hasSuffix(" m"))
        }
    }

    @Test func aRadiusSurvivesTheRoundTripThroughDisplayUnits() throws {
        // The trigger-distance stepper works in display units and converts back
        // to metres to store. Drift here would quietly move every geofence.
        for units in [Preferences.DistanceUnits.metric, .imperial] {
            try withUnits(units) {
                for meters in [75.0, 125.0, 200.0, 350.0, 500.0] {
                    let round = Format.metersFromDisplay(Format.displayDistance(meters))
                    #expect(abs(round - meters) < 0.001,
                            "\(meters) m drifted to \(round) m in \(units)")
                }
            }
        }
    }

    @Test func theStepperStepIsRoundInWhicheverUnitIsShown() throws {
        try withUnits(.metric) { #expect(Format.distanceStep == 25) }
        try withUnits(.imperial) { #expect(Format.distanceStep == 50) }
    }

    @Test func everyAllowedTriggerRadiusRendersSensibly() throws {
        for units in [Preferences.DistanceUnits.metric, .imperial] {
            try withUnits(units) {
                for meters in [ArrivalReminders.radiusRange.lowerBound,
                               ArrivalReminders.defaultRadius,
                               ArrivalReminders.radiusRange.upperBound] {
                    let shown = Format.distanceFine(meters)
                    #expect(!shown.hasPrefix("0 "), "\(meters) m rendered as \(shown)")
                }
            }
        }
    }
}
