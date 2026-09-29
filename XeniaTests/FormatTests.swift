//
//  FormatTests.swift
//  XeniaTests
//
//  Currency detail lookups, money-input sanitizing, and the units/currency
//  preference overrides.
//

import Testing
import Foundation
@testable import Xenia

@MainActor
@Suite(.serialized)
struct FormatTests {

    @Test func minorUnitDigitsPerCurrency() {
        #expect(Format.minorUnitDigits(for: "USD") == 2)
        #expect(Format.minorUnitDigits(for: "EUR") == 2)
        #expect(Format.minorUnitDigits(for: "JPY") == 0)
        #expect(Format.minorUnitDigits(for: "KRW") == 0)
        #expect(Format.minorUnitDigits(for: "KWD") == 3)
        #expect(Format.minorUnitDigits(for: "BHD") == 3)
    }

    @Test func currencySymbolPerCurrency() {
        #expect(Format.currencySymbol(for: "USD") == "$")
        #expect(Format.currencySymbol(for: "EUR") == "€")
        #expect(Format.currencySymbol(for: "JPY") == "¥")
    }

    @Test func sanitizedAmountCleansInput() {
        #expect(Format.sanitizedAmount("12,50", fractionDigits: 2) == "12.50")
        #expect(Format.sanitizedAmount("12.5.5", fractionDigits: 2) == "12.55")
        #expect(Format.sanitizedAmount("10.999", fractionDigits: 2) == "10.99")
        #expect(Format.sanitizedAmount("12.5", fractionDigits: 0) == "12")
        #expect(Format.sanitizedAmount("ab1c2.3d", fractionDigits: 2) == "12.3")
        #expect(Format.sanitizedAmount("", fractionDigits: 2) == "")
        #expect(Format.sanitizedAmount("12.", fractionDigits: 2) == "12.")   // trailing dot kept
        #expect(Format.sanitizedAmount("0.001", fractionDigits: 3) == "0.001")
    }

    @Test func amountValueParses() {
        #expect(Format.amountValue("12,50") == 12.5)
        #expect(Format.amountValue("abc") == 0)
        #expect(Format.amountValue("100") == 100)
    }

    @Test func autoDecimalFillsFromTheRight() {
        #expect(Format.autoDecimal("", fractionDigits: 2) == "")
        #expect(Format.autoDecimal("8", fractionDigits: 2) == "0.08")
        #expect(Format.autoDecimal("86", fractionDigits: 2) == "0.86")
        #expect(Format.autoDecimal("864", fractionDigits: 2) == "8.64")
        #expect(Format.autoDecimal("8640", fractionDigits: 2) == "86.40")
        #expect(Format.autoDecimal("0", fractionDigits: 2) == "0.00")
        #expect(Format.autoDecimal("00123", fractionDigits: 2) == "1.23")
        #expect(Format.autoDecimal("12x3", fractionDigits: 2) == "1.23")
        // Whole-unit currency (JPY): no shifting.
        #expect(Format.autoDecimal("1234", fractionDigits: 0) == "1234")
        // Three-place currency (KWD).
        #expect(Format.autoDecimal("1234", fractionDigits: 3) == "1.234")
    }

    @Test func currencyRespectsPreferenceOverride() {
        let saved = Preferences.shared.currencyCode
        defer { Preferences.shared.currencyCode = saved }

        Preferences.shared.currencyCode = "JPY"
        #expect(Format.currencyCode == "JPY")
        let yen = Format.currency(1234)
        #expect(!yen.contains("."))   // no minor unit

        Preferences.shared.currencyCode = "USD"
        #expect(Format.currency(12).contains("12.00"))
    }

    @Test func distanceRespectsUnitOverride() {
        let saved = Preferences.shared.distanceUnits
        defer { Preferences.shared.distanceUnits = saved }

        Preferences.shared.distanceUnits = .imperial
        #expect(Format.distance(100).contains("ft"))
        #expect(Format.distance(5000).contains("mi"))

        Preferences.shared.distanceUnits = .metric
        #expect(Format.distance(100).contains("m"))
        #expect(Format.distance(5000).contains("km"))
    }
}
