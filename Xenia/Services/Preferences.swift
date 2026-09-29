//
//  Preferences.swift
//  Xenia
//
//  App-wide display choices: currency, whether tips are entered as a percentage
//  or a flat amount, the default rounding, and distance units. Backed by
//  `UserDefaults` and injected as an `@Observable` so `Format` and the views
//  refresh the moment a setting changes.
//

import Foundation

@Observable
final class Preferences {

    static let shared = Preferences()

    enum TipEntryMode: String, CaseIterable, Codable {
        case percent, amount
    }

    enum DistanceUnits: String, CaseIterable, Codable {
        /// Follow the device's Region setting (does not change when travelling).
        case auto
        case metric
        case imperial
    }

    private enum Key {
        static let currency = "prefCurrencyCode"
        static let tipEntry = "prefTipEntryMode"
        static let rounding = "prefRoundingDefault"
        static let distance = "prefDistanceUnits"
        static let autoDecimal = "prefAutoDecimal"
        static let travelCurrency = "prefTravelCurrencyCode"
        static let declinedRegions = "prefDeclinedCurrencyRegions"
    }

    /// What to do about the currency where the user currently is.
    enum CurrencySuggestion: Equatable {
        /// Nothing to say — already right, already answered, or overridden.
        case none
        /// Back in the home country: drop the travel currency without asking.
        /// Returning to the default the user never opted into isn't news.
        case revertToHome
        /// Somewhere new whose money differs: worth one prompt.
        case ask(region: String, currency: String)
    }

    /// `nil` means "follow the device locale".
    var currencyCode: String? {
        didSet {
            if let currencyCode {
                UserDefaults.standard.set(currencyCode, forKey: Key.currency)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.currency)
            }
        }
    }

    var tipEntryMode: TipEntryMode {
        didSet { UserDefaults.standard.set(tipEntryMode.rawValue, forKey: Key.tipEntry) }
    }

    var roundingDefault: RoundingMode {
        didSet { UserDefaults.standard.set(roundingDefault.rawValue, forKey: Key.rounding) }
    }

    var distanceUnits: DistanceUnits {
        didSet { UserDefaults.standard.set(distanceUnits.rawValue, forKey: Key.distance) }
    }

    /// Cash-register bill entry: digits fill in from the right of the decimal.
    var autoDecimal: Bool {
        didSet { UserDefaults.standard.set(autoDecimal, forKey: Key.autoDecimal) }
    }

    private init() {
        let defaults = UserDefaults.standard
        currencyCode = defaults.string(forKey: Key.currency)
        tipEntryMode = defaults.string(forKey: Key.tipEntry)
            .flatMap(TipEntryMode.init(rawValue:)) ?? .percent
        roundingDefault = defaults.string(forKey: Key.rounding)
            .flatMap(RoundingMode.init(rawValue:)) ?? .none
        distanceUnits = defaults.string(forKey: Key.distance)
            .flatMap(DistanceUnits.init(rawValue:)) ?? .auto
        autoDecimal = defaults.object(forKey: Key.autoDecimal) as? Bool ?? true
        travelCurrencyCode = defaults.string(forKey: Key.travelCurrency)
        declinedCurrencyRegions = Set(defaults.stringArray(forKey: Key.declinedRegions) ?? [])
    }

    /// The currency the user accepted for where they are now, if they're away
    /// from home. Persisted — you're still abroad tomorrow morning.
    var travelCurrencyCode: String? {
        didSet {
            if let travelCurrencyCode {
                UserDefaults.standard.set(travelCurrencyCode, forKey: Key.travelCurrency)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.travelCurrency)
            }
        }
    }

    /// Countries where the user said "not now". Remembered so a decline is
    /// answered once, not at every glance at the app for a fortnight.
    var declinedCurrencyRegions: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(declinedCurrencyRegions).sorted(), forKey: Key.declinedRegions
            )
        }
    }

    /// The ISO code actually in effect: an explicit choice, else the currency
    /// accepted for where they're travelling, else the device locale, else USD.
    var resolvedCurrencyCode: String {
        Self.resolveCurrencyCode(
            override: currencyCode,
            travelCurrency: travelCurrencyCode,
            deviceCurrency: Locale.current.currency?.identifier
        )
    }

    /// Split out so the precedence can be tested without changing the device's
    /// region. Distance units deliberately resolve the other way round — they
    /// follow where the user lives, never where they are (`Format.usesMetric`).
    static func resolveCurrencyCode(
        override: String?,
        travelCurrency: String? = nil,
        deviceCurrency: String?
    ) -> String {
        override ?? travelCurrency ?? deviceCurrency ?? "USD"
    }

    /// The currency spent in a country, e.g. `"JP"` → `"JPY"`, or `nil` where
    /// there isn't one.
    static func currencyCode(forRegion region: String) -> String? {
        var components = Locale.Components(identifier: "en_US")
        components.region = Locale.Region(region)
        guard let code = Locale(components: components).currency?.identifier,
              !code.isEmpty,
              // "XXX" is ISO 4217 for "no currency here". Antarctica resolves to
              // it, and so does any region code Locale doesn't recognise —
              // offering to switch someone to XXX would be nonsense.
              code != "XXX"
        else { return nil }
        return code
    }

    /// Whether arriving in `region` should change anything, and whether to ask.
    /// Pure, because the interesting cases — landing somewhere, declining, then
    /// flying home — are ones you can't stage on a desk.
    static func currencySuggestion(
        forRegion region: String?,
        override: String?,
        travelCurrency: String?,
        deviceCurrency: String?,
        declinedRegions: Set<String>
    ) -> CurrencySuggestion {
        // An explicit pick from the currency screen is a standing instruction;
        // it outranks anything geography has to say.
        guard override == nil else { return .none }
        guard let region, let candidate = currencyCode(forRegion: region) else { return .none }

        let home = deviceCurrency ?? "USD"
        if candidate == home {
            return travelCurrency == nil ? .none : .revertToHome
        }
        if candidate == travelCurrency { return .none }
        if declinedRegions.contains(region) { return .none }
        return .ask(region: region, currency: candidate)
    }

    /// Applies the outcome of a suggestion the user has answered.
    func acceptTravelCurrency(_ code: String, forRegion region: String) {
        travelCurrencyCode = code
        declinedCurrencyRegions.remove(region)
    }

    func declineTravelCurrency(forRegion region: String) {
        declinedCurrencyRegions.insert(region)
    }

    func revertToHomeCurrency() {
        travelCurrencyCode = nil
    }
}
