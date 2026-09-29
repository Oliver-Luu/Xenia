//
//  Support.swift
//  Xenia
//
//  Value formatting. UI pieces live in Theme/Components.swift.
//

import Foundation
import CoreLocation

enum Format {
    /// Money in a specific currency. Defaults to whatever is in effect now, but
    /// anything showing a *saved* amount should pass that record's own currency —
    /// otherwise history re-labels itself the moment the user travels.
    static func currency(
        _ value: Double,
        code: String = Preferences.shared.resolvedCurrencyCode
    ) -> String {
        value.formatted(.currency(code: code))
    }

    static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return "\(rounded.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    static func signedPercent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "\u{2212}" : "")
        return "\(sign)\(abs(rounded).formatted(.number.precision(.fractionLength(0...1))))%"
    }

    static func signedCurrency(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "\u{2212}" : "")
        return sign + currency(abs(value))
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        if usesMetric {
            return meters < 1000
                ? "\(Int(meters.rounded())) m"
                : "\((meters / 1000).formatted(.number.precision(.fractionLength(1)))) km"
        } else {
            let feet = meters * feetPerMeter
            return feet < 1000
                ? "\(Int(feet.rounded())) ft"
                : "\((feet / 5280).formatted(.number.precision(.fractionLength(1)))) mi"
        }
    }

    /// Whether distances show in metric, honoring the user's units preference.
    static var usesMetric: Bool {
        usesMetric(for: Preferences.shared.distanceUnits, in: .current)
    }

    /// Units follow where the user *lives*, not where they are: `Locale.current`
    /// is the device's Region setting, so flying to Paris doesn't start quoting
    /// a Californian distances in metres. Currency is the opposite — see
    /// `Preferences.resolveCurrencyCode`. Split out so the rule can be tested
    /// against locales the test device isn't set to.
    static func usesMetric(for units: Preferences.DistanceUnits, in locale: Locale) -> Bool {
        switch units {
        case .auto:     return locale.measurementSystem == .metric
        case .metric:   return true
        case .imperial: return false
        }
    }

    private static let feetPerMeter = 3.28084

    /// The same distance expressed in the unit the user actually sees.
    static func displayDistance(_ meters: CLLocationDistance) -> Double {
        usesMetric ? meters : meters * feetPerMeter
    }

    static func metersFromDisplay(_ value: Double) -> CLLocationDistance {
        usesMetric ? value : value / feetPerMeter
    }

    /// Step for a distance stepper, in display units, so the readout lands on
    /// round numbers in the unit shown (25 m, or 50 ft) rather than round metres
    /// that read as 394 ft.
    static var distanceStep: Double { usesMetric ? 25 : 50 }

    /// Always the small unit (m / ft), never km/mi — for short spans like a
    /// geofence radius, where "0.3 mi" is useless next to a stepper.
    static func distanceFine(_ meters: CLLocationDistance) -> String {
        usesMetric
            ? "\(Int(meters.rounded())) m"
            : "\(Int((meters * feetPerMeter).rounded())) ft"
    }

    static var currencyCode: String {
        Preferences.shared.resolvedCurrencyCode
    }

    // MARK: - Currency details

    private static var minorUnitCache: [String: Int] = [:]

    /// Digits after the decimal point for a currency: 2 for USD/EUR, 0 for JPY, 3 for KWD.
    static func minorUnitDigits(for code: String = Preferences.shared.resolvedCurrencyCode) -> Int {
        if let cached = minorUnitCache[code] { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let digits = formatter.maximumFractionDigits
        minorUnitCache[code] = digits
        return digits
    }

    static func currencySymbol(for code: String = Preferences.shared.resolvedCurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? "$"
    }

    // MARK: - Amount input

    /// Cleans free-typed money input: comma → dot, drops junk characters, keeps a
    /// single decimal point, and clamps the fractional part to `fractionDigits`
    /// (0 removes the point entirely). A lone trailing "." is left so typing feels natural.
    static func sanitizedAmount(_ text: String, fractionDigits: Int) -> String {
        var s = text.replacingOccurrences(of: ",", with: ".")
        s = String(s.unicodeScalars.filter { CharacterSet(charactersIn: "0123456789.").contains($0) })
        guard let firstDot = s.firstIndex(of: ".") else { return s }
        let whole = String(s[s.startIndex..<firstDot])
        let afterDot = s[s.index(after: firstDot)...].replacingOccurrences(of: ".", with: "")
        if fractionDigits <= 0 { return whole }
        return whole + "." + String(afterDot.prefix(fractionDigits))
    }

    /// Best-effort parse of a money string to a number.
    static func amountValue(_ text: String) -> Double {
        Double(sanitizedAmount(text, fractionDigits: 9)) ?? 0
    }

    /// Cash-register entry: every digit shifts the number one place left of the
    /// decimal. "8" → "0.08", "8640" → "86.40". Empty stays empty.
    static func autoDecimal(_ input: String, fractionDigits: Int) -> String {
        let digits = input.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        guard fractionDigits > 0 else {
            return String(Int(digits) ?? 0)
        }
        let padded = digits.count > fractionDigits
            ? digits
            : String(repeating: "0", count: fractionDigits - digits.count + 1) + digits
        let cut = padded.index(padded.endIndex, offsetBy: -fractionDigits)
        let whole = String(padded[..<cut]).drop { $0 == "0" }
        let frac = String(padded[cut...])
        return (whole.isEmpty ? "0" : String(whole)) + "." + frac
    }
}
