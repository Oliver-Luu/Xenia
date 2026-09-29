//
//  CalculatorView.swift
//  Xenia
//
//  Detect or pick a place, enter the bill, score the visit, work the rules,
//  read the tip off the panel.
//

import SwiftUI
import SwiftData
import CoreLocation

struct CalculatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) private var locationManager
    @Environment(TabBarPing.self) private var tabPing
    @Environment(Preferences.self) private var preferences

    @Query(sort: \Restaurant.name) private var restaurants: [Restaurant]
    @Query(sort: \TipCategory.sortOrder) private var categories: [TipCategory]

    @State private var selectedRestaurant: Restaurant?
    @State private var looseCategory: TipCategory?
    @State private var draftPlace: DraftPlace?
    /// A name the user typed for a category-only place, remembered so "Save to
    /// Places" / the tip log can use it without a second trip through an editor.
    @State private var looseName = ""

    @State private var billText = ""
    @State private var partySize = 1
    @State private var ratings: [UUID: Int] = [:]
    @State private var ruleSteps: [UUID: Int] = [:]
    @State private var rounding: RoundingMode = Preferences.shared.roundingDefault
    @State private var tipEntryMode: Preferences.TipEntryMode = Preferences.shared.tipEntryMode
    /// Flat cash tip the user typed; empty means "use the suggestion".
    @State private var tipAmountText = ""
    /// Base-tip override for a category-only / draft selection (a real place
    /// stores its own on `baseTipOverride`).
    @State private var sessionBase: Double?
    @State private var didSaveHistory = false

    @State private var sheet: CalcSheet?
    @State private var afterNaming: AfterNaming = .none
    @State private var donePrompt: DonePromptKind?
    @State private var autoMatchDistance: CLLocationDistance?
    @State private var didAttemptAutoMatch = false

    @FocusState private var billFocused: Bool
    @FocusState private var tipFocused: Bool

    private enum CalcSheet: Int, Identifiable {
        case picker, nameNewPlace, newRule, newRating
        var id: Int { rawValue }
    }

    /// What to do once the user finishes naming a loose-category place.
    private enum AfterNaming {
        case none, finish, historyAndFinish
    }

    private enum DonePromptKind: Identifiable {
        /// A place ready to save straight away (nearby result, or a category-only
        /// place the user already named) + unsaved tip / just the place.
        case saveBoth, saveOnly
        /// Category-only, still unnamed + unsaved tip / just the place.
        case looseBoth, loosePlaceOnly
        /// Named place, tip not in History yet.
        case historyOnly
        var id: Int { hashValue }
    }

    var body: some View {
        InstrumentScreen("Xenia") {
            if activeCategory != nil {
                HStack(alignment: .firstTextBaseline, spacing: Grid.x3) {
                    Text(tipEntryMode == .amount
                         ? Format.currency(currentResult.tipAmount)
                         : Format.percent(currentResult.effectivePercent))
                        .font(.readoutMid)
                        .monospacedDigit()
                        .foregroundStyle(Palette.accentText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HeaderButton(title: "Finish", symbol: "checkmark") { doneTapped() }
                }
            }
        } content: {
            placeBlock

            if activeCategory != nil {
                billBlock
                tipEntryBlock
                if place != nil || !ratingDimensions.isEmpty { ratingsBlock }
                if place != nil || !activeRules.isEmpty { rulesBlock }
                readoutBlock
            }
        }
        .sheet(item: $sheet, onDismiss: { afterNaming = .none }) { which in
            switch which {
            case .picker:
                PlacePickerView(
                    categories: categories,
                    savedRestaurants: restaurants,
                    onPick: applySelection
                )
            case .nameNewPlace:
                RestaurantEditView(
                    restaurant: nil,
                    categories: categories,
                    prefillCategory: looseCategory,
                    onSaved: { saved in
                        selectedRestaurant = saved
                        // Keep the name around so the tip log / readout show it even
                        // before @Query catches up with the freshly-inserted place.
                        looseName = saved.name
                        draftPlace = nil
                        switch afterNaming {
                        case .historyAndFinish: saveToHistory(); finish()
                        case .finish: finish()
                        case .none: looseCategory = nil
                        }
                        afterNaming = .none
                    }
                )
            case .newRule:
                // `selectedRestaurant`, not the render-guarded `place`: a place
                // just saved from the add row isn't in the @Query results yet.
                if let selectedRestaurant { RuleEditView(rule: nil, restaurant: selectedRestaurant) }
            case .newRating:
                if let selectedRestaurant { RatingEditView(dimension: nil, restaurant: selectedRestaurant) }
            }
        }
        .task {
            runAutoMatch()
        }
        .onChange(of: locationManager.currentLocation) { _, _ in
            runAutoMatch()
        }
        .onChange(of: restaurants.count) { _, _ in
            // A place deleted from the Places tab leaves a dead reference here.
            if let selectedRestaurant, !restaurants.contains(where: { $0 === selectedRestaurant }) {
                self.selectedRestaurant = nil
                autoMatchDistance = nil
            }
        }
        .onChange(of: billText) { _, new in
            let clean = normalizeAmountInput(new)
            if clean != new { billText = clean }
        }
        .onChange(of: tipAmountText) { _, new in
            let clean = normalizeAmountInput(new)
            if clean != new { tipAmountText = clean }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arrivalReminderOpened)) { note in
            guard let idString = note.userInfo?["restaurant"] as? String,
                  let uuid = UUID(uuidString: idString),
                  let match = restaurants.first(where: { $0.uuid == uuid })
            else { return }
            applySelection(.restaurant(match))
        }
        .alert(
            donePromptTitle,
            isPresented: Binding(get: { donePrompt != nil }, set: { if !$0 { donePrompt = nil } }),
            presenting: donePrompt
        ) { kind in
            switch kind {
            case .saveBoth:
                // History first, while the loose name/category are still set for
                // the record; saveToPlaces then consumes them.
                Button("Save to Places & History") { saveToHistory(); saveToPlaces(); finish() }
            case .saveOnly:
                Button("Save to Places") { saveToPlaces(); finish() }
            case .looseBoth:
                Button("Name & save it") { afterNaming = .historyAndFinish; sheet = .nameNewPlace }
                Button("Just log the tip") { saveToHistory(); finish() }
            case .loosePlaceOnly:
                Button("Name & save it") { afterNaming = .finish; sheet = .nameNewPlace }
            case .historyOnly:
                Button("Save to History") { saveToHistory(); finish() }
            }
            // No explicit cancel button: SwiftUI appends its own "Cancel" as the
            // last row, which is the "keep working" path.
            Button("Discard", role: .destructive) { finish() }
        } message: { kind in
            switch kind {
            case .saveBoth: Text("This tip isn't in Places or History yet.")
            case .saveOnly: Text("This place isn't saved to Places yet.")
            case .looseBoth: Text("Give this place a name to keep it, or just log the tip on its own.")
            case .loosePlaceOnly: Text("Give this place a name to keep it.")
            case .historyOnly: Text("This tip isn't in your History yet.")
            }
        }
    }

    private var donePromptTitle: String {
        switch donePrompt {
        case .saveBoth, .looseBoth: return String(localized: "Save this tip?")
        case .saveOnly, .loosePlaceOnly: return String(localized: "Save this place?")
        case .historyOnly, .none: return String(localized: "Save this tip to History?")
        }
    }

    // MARK: - Place

    private var placeBlock: some View {
        FieldGroup(label: "Where you are") {
            Panel {
                if let place {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Grid.x1) {
                            Text(place.name)
                                .font(.cardTitle)
                                .foregroundStyle(Palette.ink)
                            if !place.city.isEmpty {
                                Text(place.city)
                                    .font(.noteText)
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            CategoryTag(name: place.category?.name)
                        }
                        Spacer()
                        if let autoMatchDistance {
                            Text("\(Format.distance(autoMatchDistance)) away")
                                .font(.figureSmall)
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                } else if let draftPlace {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Grid.x1) {
                            Text(draftPlace.name)
                                .font(.cardTitle)
                                .foregroundStyle(Palette.ink)
                            CategoryTag(name: draftPlace.category.name)
                        }
                        Spacer()
                        Text("Not saved")
                            .font(.figureSmall)
                            .foregroundStyle(Palette.inkFaint)
                    }
                } else if let looseCategory {
                    VStack(alignment: .leading, spacing: Grid.x2) {
                        Text(looseCategory.name)
                            .font(.cardTitle)
                            .foregroundStyle(Palette.ink)
                        FieldWell(
                            placeholder: "Name this place (optional)",
                            text: $looseName,
                            showsClear: true
                        )
                    }
                } else {
                    Text("No place selected")
                        .font(.bodyText)
                        .foregroundStyle(Palette.inkDim)
                }

                if let hint = locationHint {
                    Text(hint)
                        .font(.noteText)
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(hasSelection ? "Change place" : "Choose a place") {
                    sheet = .picker
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private var locationHint: String? {
        switch locationManager.state {
        case .denied:
            return String(localized: "Location is off. Pick a place by hand, or turn it on in Settings.")
        case .requesting:
            return String(localized: "Checking your location.")
        case .located where place == nil && didAttemptAutoMatch:
            return String(localized: "Nothing saved nearby. Pick a place to save it here.")
        default:
            return nil
        }
    }

    // MARK: - Bill

    private var billBlock: some View {
        HStack(alignment: .top, spacing: Grid.x4) {
            FieldGroup(label: "Bill") {
                FieldWell(
                    placeholder: billPlaceholder,
                    text: $billText,
                    keyboard: amountKeyboard,
                    alignment: .trailing,
                    prefix: Format.currencySymbol(),
                    focus: $billFocused
                )
            }
            FieldGroup(label: "Split") {
                PlusMinus(
                    value: partySize,
                    range: 1...50,
                    display: partySize == 1 ? "1 way" : "\(partySize) ways"
                ) { partySize = $0 }
            }
            .frame(width: 150)
        }
    }

    /// Cash-register entry has no decimal key; literal entry keeps it.
    private var amountKeyboard: UIKeyboardType {
        preferences.autoDecimal ? .numberPad : .decimalPad
    }

    /// Zero shown to the currency's own precision ("0.00" for USD, "0" for JPY).
    private var billPlaceholder: String {
        let digits = Format.minorUnitDigits()
        return digits > 0 ? "0." + String(repeating: "0", count: digits) : "0"
    }

    // MARK: - Tip entry (percentage vs cash) + base tip

    private var tipEntryBlock: some View {
        let result = currentResult
        return FieldGroup(label: "Tip", note: baseTipNote) {
            Panel(spacing: Grid.x3) {
                HStack(spacing: Grid.x2) {
                    tipModeSegment("Percentage", mode: .percent)
                    tipModeSegment("Cash", mode: .amount)
                }

                HairRule()

                HStack(spacing: Grid.x3) {
                    Text(tipEntryMode == .amount ? "Base" : "Base tip")
                        .font(.bodyText)
                        .foregroundStyle(Palette.inkDim)
                    if isBaseOverridden {
                        Button(baseResetTitle) { resetBase() }
                            .font(.figureSmall)
                            .foregroundStyle(Palette.accentText)
                    }
                    Spacer(minLength: 0)
                    if tipEntryMode == .amount {
                        FieldWell(
                            placeholder: plainAmount(defaultBaseCash),
                            text: $tipAmountText,
                            keyboard: amountKeyboard,
                            alignment: .trailing,
                            prefix: Format.currencySymbol(),
                            focus: $tipFocused
                        )
                        .frame(width: 140)
                    } else {
                        PlusMinusDecimal(
                            value: baseTipBinding,
                            range: 0...40,
                            step: 0.5,
                            display: Format.percent(baseTipPercent)
                        )
                        .frame(width: 150)
                    }
                }

                // In cash mode the field only ever shows what you typed; the tip
                // itself moves with the ratings and adjustments, so show it here.
                if tipEntryMode == .amount {
                    let moved = baseTipCash.map { abs(result.tipAmount - $0) >= 0.005 } ?? false
                    HairRule()
                    HStack {
                        Text(moved ? "Tip, after ratings & adjustments" : "Tip")
                            .font(.noteText)
                            .foregroundStyle(Palette.inkFaint)
                        Spacer()
                        Text(Format.currency(result.tipAmount))
                            .font(.figure)
                            .monospacedDigit()
                            .foregroundStyle(Palette.accentText)
                    }
                }
            }
        }
    }

    private func tipModeSegment(_ label: LocalizedStringKey, mode: Preferences.TipEntryMode) -> some View {
        Button {
            guard tipEntryMode != mode else { return }
            tipEntryMode = mode
            if mode == .percent { tipAmountText = "" }
        } label: {
            Text(label)
                .font(.figureSmall)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Grid.x2)
                .background(tipEntryMode == mode ? Palette.accent : Palette.well)
                .foregroundStyle(tipEntryMode == mode ? Palette.onAccent : Palette.inkDim)
                .clipShape(RoundedRectangle(cornerRadius: Corner.control))
        }
        .buttonStyle(.plain)
    }

    /// A number with the currency's decimal places, no symbol — for placeholders.
    private func plainAmount(_ value: Double) -> String {
        String(format: "%.\(Format.minorUnitDigits())f", value)
    }

    // MARK: - Base tip

    private var baseTipNote: String? {
        let category = activeCategory?.name ?? String(localized: "the category")
        if tipEntryMode == .amount {
            return isBaseOverridden
                ? String(localized: "Your starting tip. Ratings and adjustments still move it up or down.")
                : String(localized: "Starts from the \(category) default. Set an amount — ratings and adjustments still apply on top.")
        }
        if place != nil {
            return isBaseOverridden
                ? String(localized: "Set just for this place. Everywhere else in \(category) is unchanged.")
                : String(localized: "Following the \(category) default. Nudge it to set one just for this place.")
        }
        return isBaseOverridden
            ? String(localized: "Adjusted for this bill only.")
            : String(localized: "The \(category) default.")
    }

    private var baseResetTitle: String {
        if tipEntryMode == .amount { return String(localized: "Use the default") }
        return place != nil ? String(localized: "Use category default") : String(localized: "Reset")
    }

    private var isBaseOverridden: Bool {
        if tipEntryMode == .amount { return !tipAmountText.isEmpty }
        return place != nil ? place?.baseTipOverride != nil : sessionBase != nil
    }

    /// The category / place default base, in cash for the current bill — the
    /// placeholder shown in cash mode until the user types their own amount.
    private var defaultBaseCash: Double {
        currentBill * baseTipPercent / 100
    }

    private var baseTipBinding: Binding<Double> {
        Binding(
            get: { baseTipPercent },
            set: { newValue in
                if let place {
                    place.baseTipOverride = newValue
                    try? modelContext.save()
                } else {
                    sessionBase = newValue
                }
            }
        )
    }

    private func resetBase() {
        if tipEntryMode == .amount {
            tipAmountText = ""
            return
        }
        if let place {
            place.baseTipOverride = nil
            try? modelContext.save()
        } else {
            sessionBase = nil
        }
    }

    /// Reformat a money field's text as it's typed — cash-register style when the
    /// preference is on, otherwise just trimming stray characters and decimals.
    private func normalizeAmountInput(_ text: String) -> String {
        let digits = Format.minorUnitDigits()
        return preferences.autoDecimal
            ? Format.autoDecimal(text, fractionDigits: digits)
            : Format.sanitizedAmount(text, fractionDigits: digits)
    }

    /// What one rating or rule contributes, in whatever unit the user is working
    /// in: percentage points, or the cash that comes to on this bill.
    private func contributionLabel(_ percentPoints: Double) -> String {
        guard tipEntryMode == .amount else { return Format.signedPercent(percentPoints) }
        // With no bill to take a percentage of, adjustments scale the cash base.
        let reference = currentBill > 0 ? currentBill : (baseTipCash ?? 0)
        return Format.signedCurrency(reference * percentPoints / 100)
    }

    // MARK: - Ratings

    private var ratingsBlock: some View {
        FieldGroup(label: TipCopy.ratingsLabel, note: TipCopy.ratingsNote) {
            Panel {
                ForEach(Array(ratingDimensions.enumerated()), id: \.element.uuid) { index, dimension in
                    if index > 0 { HairRule() }
                    let score = ratings[dimension.uuid] ?? dimension.neutralScore
                    let delta = Double(score - dimension.neutralScore) * dimension.weight
                    RatingRow(
                        name: dimension.name,
                        score: score,
                        maxScore: dimension.maxScore,
                        delta: delta,
                        deltaLabel: contributionLabel(delta)
                    ) {
                        ratings[dimension.uuid] = $0
                    }
                }

                ownAddRow(
                    saved: "Add a rating here",
                    unsaved: "Save this place & add a rating",
                    hasRows: !ratingDimensions.isEmpty
                ) { sheet = .newRating }
            }
        }
    }

    // MARK: - Rules

    private var rulesBlock: some View {
        FieldGroup(label: TipCopy.adjustmentsLabel) {
            Panel {
                ForEach(Array(activeRules.enumerated()), id: \.element.uuid) { index, rule in
                    if index > 0 { HairRule() }
                    AdjustmentRow(
                        title: rule.title,
                        detail: rule.detail,
                        deltaPercent: rule.deltaPercent,
                        isStepper: rule.isStepper,
                        maxSteps: rule.maxSteps,
                        steps: ruleSteps[rule.uuid] ?? 0,
                        format: contributionLabel
                    ) {
                        ruleSteps[rule.uuid] = $0
                    }
                }

                ownAddRow(
                    saved: "Add an adjustment here",
                    unsaved: "Save this place & add an adjustment",
                    hasRows: !activeRules.isEmpty
                ) { sheet = .newRule }
            }
        }
    }

    /// Foot-of-panel control for adding a rating / adjustment scoped to the
    /// current place, mid-calculation, so it's there next visit. For a place
    /// that isn't saved yet it saves it first (that's the only way the new
    /// rating/rule gets a home); an unnamed category-only pick needs a name
    /// first, so it points the user at the field for that.
    @ViewBuilder
    private func ownAddRow(
        saved: LocalizedStringKey,
        unsaved: LocalizedStringKey,
        hasRows: Bool,
        _ open: @escaping () -> Void
    ) -> some View {
        if place != nil {
            if hasRows { HairRule() }
            inlineAdd(saved, open)
        } else if placeReadyToSave {
            if hasRows { HairRule() }
            inlineAdd(unsaved) {
                saveToPlaces()
                open()
            }
        } else if looseCategory != nil {
            if hasRows { HairRule() }
            Text("Name this place above to add your own")
                .font(.noteText)
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Grid.x1)
        }
    }

    private func inlineAdd(_ title: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Grid.x1) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text(title).font(.system(.subheadline, weight: .semibold))
            }
            .foregroundStyle(Palette.accentText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Grid.x1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Readout

    private var readoutBlock: some View {
        let result = currentResult
        return Panel(padding: Grid.x5) {
            HStack(alignment: .lastTextBaseline) {
                Text("TIP").sectionLabelStyle()
                Spacer()
                Text(tipEntryMode == .amount
                     ? Format.currency(result.tipAmount)
                     : Format.percent(result.effectivePercent))
                    .font(.readout)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
            }

            if tipEntryMode == .amount, currentBill > 0 {
                Text("\(Format.percent(result.effectivePercent)) of the bill")
                    .font(.noteText)
                    .foregroundStyle(Palette.inkFaint)
            } else if tipEntryMode != .amount, result.rawPercent != result.percent {
                Text("Held at \(Format.percent(result.percent)) from \(Format.percent(result.rawPercent))")
                    .font(.noteText)
                    .foregroundStyle(Palette.inkFaint)
            }

            Rectangle().fill(Palette.ruleStrong).frame(height: 2)
                .padding(.vertical, Grid.x1)

            VStack(spacing: Grid.x2) {
                ForEach(result.components) { component in
                    LedgerRow(
                        label: component.label,
                        value: tipEntryMode == .amount
                            ? Format.signedCurrency(component.amount)
                            : Format.signedPercent(component.percent),
                        negative: component.percent < 0
                    )
                }
            }

            HairRule().padding(.vertical, Grid.x1)

            VStack(spacing: Grid.x2) {
                LedgerRow(label: "Bill", value: Format.currency(currentBill))
                LedgerRow(label: "Tip", value: Format.currency(result.tipAmount))
                LedgerRow(label: "Total", value: Format.currency(result.total), emphasized: true)
                if partySize > 1 {
                    HairRule().padding(.vertical, Grid.x1)
                    LedgerRow(label: "Each pays", value: Format.currency(result.perPersonTotal))
                    LedgerRow(label: "Each tips", value: Format.currency(result.perPersonTip))
                }
            }

            HairRule().padding(.vertical, Grid.x1)

            RoundingRows(selection: $rounding)

            HairRule().padding(.vertical, Grid.x1)

            HStack(spacing: Grid.x2) {
                Button { saveToPlaces() } label: {
                    Label(placesButtonTitle,
                          systemImage: place != nil ? "checkmark" : "mappin")
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(!canSaveToPlaces)

                Button { saveToHistory() } label: {
                    Label(didSaveHistory ? "In History" : "Save to History",
                          systemImage: didSaveHistory ? "checkmark" : "list.bullet.rectangle")
                }
                .buttonStyle(FilledButtonStyle())
                .disabled(currentBill <= 0 || didSaveHistory)
            }
        }
    }

    private var placesButtonTitle: String {
        if place != nil { return String(localized: "In Places") }
        return String(localized: "Save to Places")
    }

    private var canSaveToPlaces: Bool {
        place == nil && (draftPlace != nil || looseCategory != nil)
    }

    // MARK: - Derived

    /// The selected restaurant, but only while it's still a live record. Deleting
    /// it from the Places tab leaves `selectedRestaurant` pointing at a dead
    /// SwiftData object; reading it would crash, so gate every use through here.
    private var place: Restaurant? {
        guard let selectedRestaurant,
              restaurants.contains(where: { $0 === selectedRestaurant })
        else { return nil }
        return selectedRestaurant
    }

    private var typedLooseName: String? {
        let trimmed = looseName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when there's a place ready to write straight to Places — a nearby
    /// result, or a category-only place the user has already named.
    private var placeReadyToSave: Bool {
        place == nil && (draftPlace != nil || (looseCategory != nil && typedLooseName != nil))
    }

    private var hasSelection: Bool {
        place != nil || looseCategory != nil || draftPlace != nil
    }

    private var activeCategory: TipCategory? {
        place?.category ?? draftPlace?.category ?? looseCategory
    }

    private var activePlaceName: String? {
        place?.name ?? draftPlace?.name ?? typedLooseName
    }

    private var ratingDimensions: [RatingDimension] {
        if let place { return place.allRatingDimensions }
        return activeCategory?.sortedRatingDimensions ?? []
    }

    private var activeRules: [AdjustmentRule] {
        if let place { return place.activeRules }
        return activeCategory?.sortedRules ?? []
    }

    private var baseTipPercent: Double {
        if let place { return place.effectiveBaseTipPercent }
        return sessionBase ?? activeCategory?.baseTipPercent ?? 18
    }

    private var unsavedHistory: Bool { currentBill > 0 && !didSaveHistory }

    private var currentBill: Double {
        Format.amountValue(billText)
    }

    /// The flat cash base tip the user typed in cash mode, or `nil` to fall back
    /// to the percentage default.
    private var baseTipCash: Double? {
        guard tipEntryMode == .amount, !tipAmountText.isEmpty else { return nil }
        return Format.amountValue(tipAmountText)
    }

    private var ruleSelections: [RuleSelection] {
        activeRules.map { rule in
            RuleSelection(
                ruleID: rule.uuid,
                title: rule.title,
                deltaPercent: rule.deltaPercent,
                steps: ruleSteps[rule.uuid] ?? 0
            )
        }
    }

    private var ratingInputs: [RatingInput] {
        ratingDimensions.map { dimension in
            RatingInput(
                id: dimension.uuid,
                name: dimension.name,
                score: ratings[dimension.uuid] ?? dimension.neutralScore,
                neutral: dimension.neutralScore,
                weight: dimension.weight
            )
        }
    }

    private var ratingSnapshots: [RatingSnapshot] {
        ratingDimensions.map { dimension in
            RatingSnapshot(
                name: dimension.name,
                score: ratings[dimension.uuid] ?? dimension.neutralScore,
                outOf: dimension.maxScore
            )
        }
    }

    private var currentResult: TipResult {
        TipEngine.evaluate(
            TipRequest(
                baseTipPercent: baseTipPercent,
                ratings: ratingInputs,
                ruleSelections: ruleSelections,
                bill: currentBill,
                partySize: partySize,
                rounding: rounding,
                baseTipAmount: baseTipCash,
                currencyFractionDigits: Format.minorUnitDigits()
            )
        )
    }

    // MARK: - Actions

    private func applySelection(_ selection: PlaceSelection) {
        looseName = ""
        switch selection {
        case .restaurant(let restaurant):
            selectedRestaurant = restaurant
            looseCategory = nil
            draftPlace = nil
            backfillCity(restaurant)
        case .category(let category, let typedName):
            looseCategory = category
            selectedRestaurant = nil
            draftPlace = nil
            // Carry over whatever the user typed into the picker's search box.
            if let typedName { looseName = typedName }
        case .newPlace(let draft):
            draftPlace = draft
            selectedRestaurant = nil
            looseCategory = nil
        }
        autoMatchDistance = nil
        didSaveHistory = false
        billText = ""
        partySize = 1
        ratings = [:]
        ruleSteps = [:]
        rounding = Preferences.shared.roundingDefault
        tipEntryMode = Preferences.shared.tipEntryMode
        tipAmountText = ""
        sessionBase = nil
    }

    /// Reads the current fix and picks the nearest saved place. Never mutates
    /// the location manager (that is kicked off once from RootView) so it is safe
    /// to call from view lifecycle hooks without disturbing sheet presentation.
    private func runAutoMatch() {
        guard !hasSelection, let location = locationManager.currentLocation else { return }
        didAttemptAutoMatch = true
        if let match = RestaurantMatcher.closest(to: location, among: restaurants) {
            selectedRestaurant = match.restaurant
            autoMatchDistance = match.distance
            ratings = [:]
            ruleSteps = [:]
            backfillCity(match.restaurant)
        }
    }

    private func saveToHistory() {
        guard currentBill > 0, !didSaveHistory else { return }
        let result = currentResult
        let record = TipRecord(
            placeName: activePlaceName ?? activeCategory?.name ?? "Tip",
            categoryName: activeCategory?.name ?? "",
            billAmount: currentBill,
            tipPercent: result.effectivePercent,
            tipAmount: result.tipAmount,
            total: result.total,
            partySize: partySize,
            ratings: ratingSnapshots
        )
        modelContext.insert(record)
        // Bump the place's visit count. `place` is nil when a brand-new place is
        // being saved alongside this first tip — createSavedPlace() seeds the
        // count from `didSaveHistory` in that case.
        if let target = selectedRestaurant, target.modelContext != nil {
            target.visitCount += 1
        }
        try? modelContext.save()
        didSaveHistory = true
        billFocused = false
        tabPing.ping(.history)
    }

    private func saveToPlaces() {
        guard place == nil else { return }
        if let draft = draftPlace {
            createSavedPlace(
                name: draft.name,
                address: draft.streetAddress,
                coordinate: draft.coordinate,
                category: draft.category
            )
        } else if let category = looseCategory {
            if let name = typedLooseName {
                createSavedPlace(
                    name: name,
                    address: "",
                    coordinate: locationManager.currentLocation?.coordinate,
                    category: category
                )
            } else {
                afterNaming = .none
                sheet = .nameNewPlace
            }
        }
    }

    private func createSavedPlace(
        name: String,
        address: String,
        coordinate: CLLocationCoordinate2D?,
        category: TipCategory?
    ) {
        let restaurant = Restaurant(
            name: name, streetAddress: address, coordinate: coordinate, category: category
        )
        // If this tip was already logged, the place is one visit in already.
        restaurant.visitCount = didSaveHistory ? 1 : 0
        modelContext.insert(restaurant)
        try? modelContext.save()
        selectedRestaurant = restaurant
        draftPlace = nil
        looseCategory = nil
        looseName = ""
        ArrivalReminders.shared.start()
        tabPing.ping(.places)
        backfillCity(restaurant)
    }

    /// Kick off a reverse-geocode to fill in the place's city, if it has a GPS
    /// point and no city yet. Fire-and-forget — used on save and on selecting an
    /// older saved place that predates the city field.
    private func backfillCity(_ restaurant: Restaurant) {
        guard restaurant.city.isEmpty, let coordinate = restaurant.coordinate else { return }
        let id = restaurant.uuid
        Task { await PlaceGeocoder.backfillCity(placeID: id, coordinate: coordinate, in: modelContext) }
    }

    private func doneTapped() {
        billFocused = false
        if placeReadyToSave {
            donePrompt = unsavedHistory ? .saveBoth : .saveOnly
        } else if looseCategory != nil {
            donePrompt = unsavedHistory ? .looseBoth : .loosePlaceOnly
        } else if unsavedHistory {
            donePrompt = .historyOnly
        } else {
            finish()
        }
    }

    /// Clears the calculator for the next table.
    private func finish() {
        donePrompt = nil
        billText = ""
        partySize = 1
        ratings = [:]
        ruleSteps = [:]
        rounding = Preferences.shared.roundingDefault
        tipEntryMode = Preferences.shared.tipEntryMode
        tipAmountText = ""
        sessionBase = nil
        didSaveHistory = false
        selectedRestaurant = nil
        looseCategory = nil
        draftPlace = nil
        looseName = ""
        autoMatchDistance = nil
        didAttemptAutoMatch = false
        billFocused = false
        runAutoMatch()
    }
}

#Preview {
    CalculatorView()
        .environment(LocationManager())
        .environment(TabBarPing())
        .environment(Preferences.shared)
        .modelContainer(PreviewData.container)
}
